--!strict
-- Executes player moves from SpecialMoveDefinitions generically by Kind: basic attacks, aerial
-- attacks and combination moves. Every move: short fixed wind-up (never charged) -> re-validation
-- (attacker alive and still allowed to fight) -> server-side target search (range, arc, line of
-- sight, legal target for the attacker's context/team) -> damage through CombatTargets.
--   Melee      hit steps with their own animation, lunge, range, arc or full spin; one hit per
--              target per step
--   Projectile arrows, falloff beyond 100 studs, pierce only through zombies
--   Aerial     needs a real jump (combo aerials started on the ground do one controlled hop),
--              optional air strike, controlled descent (no repeated acceleration), landing strike
--              plus optional shockwave, landing recovery by weapon weight
--   Volley     ARROW RAIN into a marked circle; impacts checked from above (roofs block them)
-- PvP: per-move multiplier and target cap; PvPBalanceConfig caps every hit and the whole move per
-- target; PlayerCombatService additionally handles shields, counters and protection.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local InputDefinitions = require(ReplicatedStorage.Shared.InputDefinitions)
local ProjectileDefinitions = require(ReplicatedStorage.Shared.ProjectileDefinitions)
local PvPBalanceConfig = require(ReplicatedStorage.Shared.PvPBalanceConfig)
local WeaponBalanceConfig = require(ReplicatedStorage.Shared.WeaponBalanceConfig)
local SpecialMoveDefinitions = require(ReplicatedStorage.Shared.SpecialMoveDefinitions)
local Arena = require(script.Parent.Arena)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatRules = require(script.Parent.CombatRules)
local CombatTargets = require(script.Parent.CombatTargets)
local CombatUtil = require(script.Parent.CombatUtil)
local JumpAttackService = require(script.Parent.JumpAttackService)
local ProjectileService = require(script.Parent.ProjectileService)
local Remotes = require(script.Parent.Remotes)

type MoveDefinition = SpecialMoveDefinitions.MoveDefinition
type HitStep = SpecialMoveDefinitions.HitStep
type Anim = SpecialMoveDefinitions.Anim
type Target = CombatTargets.Target
type CombatContext = CombatRules.CombatContext

export type Attacker = {
	player: Player,
	context: CombatContext,
	weaponId: string,
	character: Model,
	root: BasePart,
	aimPoint: Vector3,
	comboMultiplier: number,
	bonusStagger: number,
	bashMultiplier: number,
	basicDamage: number, -- universal combos scale with the equipped basic attack
	basicRange: number,
	fromCombo: boolean,
	weaponModel: Model?,
	animate: (anim: Anim, windUp: number, duration: number) -> (),
	extendBusy: (seconds: number) -> (), -- landing recovery
	stillValid: () -> boolean,
	reject: (reason: string) -> (),
	pvpScale: number?, -- PvP damage scale (Special tiers use flatter PvP multipliers)
	onLanded: ((target: Target, dealt: number, blocked: boolean, killed: boolean) -> ())?,
}

-- Per execution: damage already dealt to each player (whole-move PvP cap).
type Execution = { move: MoveDefinition, attacker: Attacker, dealtTo: { [Player]: number }, landedAny: boolean }

local SWEEP_TOLERANCE = 14 -- degrees added on each side of a sweep slice (plus the target's own width)
local MAX_AIM_TURN = math.rad(45) -- the aim may bend a swing at most this far from the body's facing

local SpecialMoveService = {}

local function maxTargets(move: MoveDefinition, context: CombatContext): number
	return if context == "PvP" then move.PvPMaxTargets else move.MaxTargets
end

local function moveDamage(move: MoveDefinition, attacker: Attacker): number
	return if move.BasicMultiplier then attacker.basicDamage * move.BasicMultiplier else move.Damage
end

local function moveRange(move: MoveDefinition, attacker: Attacker, override: number?): number
	if override then
		return override
	end
	if move.BasicMultiplier and move.Kind ~= "Projectile" then
		return math.clamp(attacker.basicRange, move.Range, 10) -- long weapons reach a bit farther
	end
	return move.Range
end

local function hitInfo(execution: Execution, damage: number, target: Target?): CombatTargets.HitInfo
	local move, attacker = execution.move, execution.attacker
	local bash = if move.ShieldBash then attacker.bashMultiplier else 1
	local cap: number? = nil
	if target and target.kind == "Player" and target.player then
		local humanoid = target.model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			cap = math.max(0, humanoid.MaxHealth * PvPBalanceConfig.MaxMoveFraction - (execution.dealtTo[target.player] or 0))
		end
	end
	-- PvE and PvP values are separate (WeaponBalanceConfig): `damage` carries the PvE multiplier,
	-- `pvpMultiplier` (used only against players) removes it again and applies the normalization
	local pve = WeaponBalanceConfig.pveFactor(attacker.weaponId)
	local pvp = WeaponBalanceConfig.pvpFactor(attacker.weaponId)
	return {
		damage = damage * attacker.comboMultiplier * pve,
		pvpMultiplier = move.PvPMultiplier * pvp * (attacker.pvpScale or attacker.comboMultiplier) / math.max(0.01, attacker.comboMultiplier * pve),
		height = move.Height,
		heavy = move.Impact ~= nil or move.Ultimate == true or move.Stagger >= 0.45,
		label = move.Name,
		direction = if move.Sweep and math.abs(move.Sweep[2] - move.Sweep[1]) >= 300 then "SPIN"
			elseif move.Sweep and move.Height == "High" then "DOWN"
			elseif move.Sweep then (if move.Sweep[2] < move.Sweep[1] then "LEFT" else "RIGHT")
			elseif move.Line then "THRUST"
			else nil,
		fromPosition = attacker.root.Position,
		stagger = (move.Stagger + attacker.bonusStagger) * bash,
		knockback = move.Knockback * bash,
		isProjectile = move.Kind == "Projectile" or move.Kind == "Volley",
		executeThreshold = move.ExecuteThreshold,
		executeMultiplier = move.ExecuteMultiplier,
		weaponId = attacker.weaponId,
		isSpecial = string.sub(move.Id, -6) ~= "_Basic",
		spin = move.Anim == "Spin",
		guardBreak = move.GuardBreak == true,
		fromCombo = attacker.fromCombo,
		pvpCap = cap,
	}
end

local function landed(execution: Execution, target: Target, dealt: number, blocked: boolean)
	execution.landedAny = execution.landedAny or dealt > 0 or blocked
	local callback = execution.attacker.onLanded
	if callback and (dealt > 0 or blocked) then
		callback(target, dealt, blocked, dealt > 0 and not CombatTargets.isAlive(target))
	end
end

local function apply(execution: Execution, target: Target, damage: number, hitPosition: Vector3?): (number, boolean)
	if target.kind == "Player" and target.player then
		local info = hitInfo(execution, damage, target)
		if info.pvpCap and info.pvpCap <= 0 then
			return 0, false -- this move already took its maximum from this player
		end
		info.hitPosition = hitPosition
		local dealt, blocked = CombatTargets.applyHit(execution.attacker.player, target, info)
		execution.dealtTo[target.player] = (execution.dealtTo[target.player] or 0) + dealt
		landed(execution, target, dealt, blocked)
		return dealt, blocked
	end
	local info = hitInfo(execution, damage, nil)
	info.hitPosition = hitPosition
	local dealt, blocked = CombatTargets.applyHit(execution.attacker.player, target, info)
	landed(execution, target, dealt, blocked)
	return dealt, blocked
end

-- Current root/character (the attacker may have moved during the wind-up).
local function refresh(attacker: Attacker): boolean
	if not attacker.stillValid() then
		return false
	end
	local character, _, root = CombatUtil.getLivingCharacter(attacker.player)
	if not character or not root then
		return false
	end
	attacker.character = character
	attacker.root = root
	return true
end

local function aimDirection(attacker: Attacker): Vector3
	local offset = attacker.aimPoint - attacker.root.Position
	local flat = CombatUtil.flat(offset)
	if flat.Magnitude < 0.5 then
		return CombatUtil.flat(attacker.root.CFrame.LookVector).Unit
	end
	return flat.Unit
end

-- The swing direction: the aim, bent at most MAX_AIM_TURN away from the body's facing (a client
-- can't swing behind itself by sending a backward aim point).
local function swingDirection(attacker: Attacker): Vector3
	local look = CombatUtil.flat(attacker.root.CFrame.LookVector)
	local aim = aimDirection(attacker)
	if look.Magnitude < 0.1 then
		return aim
	end
	look = look.Unit
	local angle = math.acos(math.clamp(look:Dot(aim), -1, 1))
	if angle <= MAX_AIM_TURN then
		return aim
	end
	local sign = if look:Cross(aim).Y >= 0 then 1 else -1
	return CFrame.fromAxisAngle(Vector3.yAxis, sign * MAX_AIM_TURN):VectorToWorldSpace(look)
end

type Geometry = { sweep: { number }?, line: number?, range: number }

-- One hit phase along the ANIMATED path: a sweep is checked in time slices from its start angle to
-- its end angle (so a right-to-left slash hits right-side targets first and never hits behind),
-- a thrust is a narrow line. Every target is hit at most once; walls block (line of sight).
local function sweepStrike(execution: Execution, multiplier: number, isFirst: boolean, geometry: Geometry, exclude: { [Model]: boolean }?): { [Model]: boolean }
	local move, attacker = execution.move, execution.attacker
	local hit: { [Model]: boolean } = {}
	if multiplier <= 0 then
		return hit
	end
	local limit = maxTargets(move, attacker.context)
	local count = 0
	local sweep = geometry.sweep
	local slices = if sweep then math.clamp(math.ceil(math.abs(sweep[2] - sweep[1]) / 45), 2, 8) else 1
	local active = move.ActiveTime or 0.1
	for slice = 1, slices do
		if slice > 1 then
			task.wait(active / slices)
			if not refresh(attacker) then
				return hit
			end
		end
		local origin = attacker.root.Position
		local forward = swingDirection(attacker)
		local right = Vector3.new(-forward.Z, 0, forward.X)
		local lo, hi = 0, 0
		if sweep then
			local a0 = sweep[1] + (sweep[2] - sweep[1]) * (slice - 1) / slices
			local a1 = sweep[1] + (sweep[2] - sweep[1]) * slice / slices
			lo, hi = math.min(a0, a1) - SWEEP_TOLERANCE, math.max(a0, a1) + SWEEP_TOLERANCE
		end
		local ignore = CombatTargets.losIgnoreList(attacker.character)
		for _, target in CombatTargets.list(attacker.player, attacker.context) do
			if count >= limit then
				break
			end
			if hit[target.model] or (exclude and exclude[target.model]) then
				continue
			end
			local position = target.root.Position
			local offset = CombatUtil.flat(position - origin)
			local distance = offset.Magnitude
			if distance - target.radius > geometry.range or math.abs(origin.Y - position.Y) > 7 then
				continue
			end
			local along, across = offset:Dot(forward), offset:Dot(right)
			local inside: boolean
			if geometry.line then
				inside = along >= -target.radius and math.abs(across) <= (geometry.line :: number) + target.radius
			elseif sweep then
				local angle = math.deg(math.atan2(across, along)) -- + = right of the swing direction
				local margin = if distance > 0.1 then math.deg(math.atan(target.radius / distance)) else 180
				inside = distance <= target.radius + 1 or (angle + margin >= lo and angle - margin <= hi)
			else
				inside = true
			end
			if inside and CombatUtil.hasLineOfSight(origin, position, ignore) then
				hit[target.model] = true
				count += 1
				apply(execution, target, moveDamage(move, attacker) * multiplier, nil)
			end
		end
	end
	if isFirst and count == 0 then
		attacker.reject("nothing inside the swing")
	end
	return hit
end

-- One hit phase: every legal target in range/arc/sight is hit at most once.
local function strike(execution: Execution, multiplier: number, isFirst: boolean, range: number?, arcDot: number?, exclude: { [Model]: boolean }?): { [Model]: boolean }
	local move, attacker = execution.move, execution.attacker
	local hit: { [Model]: boolean } = {}
	if multiplier <= 0 then
		return hit
	end
	local result = CombatTargets.findInArc(attacker.player, attacker.context, attacker.character, attacker.root, moveRange(move, attacker, range), arcDot or move.ArcDot, maxTargets(move, attacker.context) + (if exclude then 2 else 0))
	if #result.targets == 0 then
		if isFirst then
			attacker.reject(result.reason or "invalid target")
		end
		return hit
	end
	local count = 0
	for _, target in result.targets do
		if not (exclude and exclude[target.model]) and count < maxTargets(move, attacker.context) then
			count += 1
			hit[target.model] = true
			apply(execution, target, moveDamage(move, attacker) * multiplier, nil)
		end
	end
	return hit
end

local function lunge(attacker: Attacker, distance: number)
	if distance ~= 0 then
		local direction = aimDirection(attacker) * (if distance < 0 then -1 else 1)
		Remotes.CombatFeedback:FireClient(attacker.player, CombatConfig.Feedback.Dash, direction, math.abs(distance))
	end
end

------------------------------------------------------------------------------------------
-- Kinds
------------------------------------------------------------------------------------------

local function executeMelee(execution: Execution)
	local move, attacker = execution.move, execution.attacker
	if move.Anim == "Spin" then
		CombatEffects.ring(attacker.root.Position - Vector3.new(0, 2.5, 0), move.Range, Color3.fromRGB(255, 220, 140))
	end
	local steps: { HitStep } = move.Hits or { { Delay = 0, Multiplier = 1 } }
	local elapsed = 0
	local allHit: { [Model]: boolean } = {}
	for index, step in steps do
		if step.Delay > elapsed then
			task.wait(step.Delay - elapsed)
			elapsed = step.Delay
		end
		if not refresh(attacker) then
			return
		end
		if index > 1 or step.Anim then
			attacker.animate(step.Anim or move.Anim, 0.04, 0.3)
		end
		if step.Lunge then
			lunge(attacker, step.Lunge)
		end
		if step.Spin then
			CombatEffects.ring(attacker.root.Position - Vector3.new(0, 2.5, 0), step.Range or move.Range, Color3.fromRGB(255, 220, 140))
		end
		local sweep = step.Sweep or (if not move.Hits then move.Sweep else nil)
		local line = step.Line or (if not move.Hits then move.Line else nil)
		local struck: { [Model]: boolean }
		if sweep or line then
			struck = sweepStrike(execution, step.Multiplier, index == 1, { sweep = sweep, line = line, range = moveRange(move, attacker, step.Range) }, nil)
		else
			struck = strike(execution, step.Multiplier, index == 1, step.Range, if step.Spin then -1 else step.ArcDot)
		end
		for model in struck do
			allHit[model] = true
		end
	end
	-- Heavy ground impact (e.g. HEAVY DESCENT): sand burst + a weaker hit around the impact point
	if move.Impact and refresh(attacker) then
		local point = attacker.root.Position + swingDirection(attacker) * math.min(move.Range * 0.6, 4)
		CombatEffects.sandBurst(Vector3.new(point.X, Arena.Layout.FloorTop, point.Z), move.Impact, 1)
		strike(execution, move.ImpactMultiplier or 0.35, false, move.Impact, -1, allHit)
	end
	if not execution.landedAny and move.MissRecovery then
		attacker.extendBusy(move.MissRecovery) -- a missed heavy move is punishable
	end
end

local function fireArrows(execution: Execution, origin: Vector3, direction: Vector3)
	local move, attacker = execution.move, execution.attacker
	local count = move.ProjectileCount or 1
	local spread = math.rad(move.Spread or 0)
	local extra = math.rad(move.ExtraSpread or 0)
	local hitTargets: { [Model]: boolean } = {}
	local pierceSteps = ProjectileDefinitions.PlayerArrow.PierceDamageSteps
	local rng = Random.new()
	for i = 1, count do
		local pierced = 0
		local angle = (i - (count + 1) / 2) * spread + rng:NextNumber(-extra, extra)
		local rotated = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(direction)
		ProjectileService.fireArrow({
			attacker = attacker.player,
			context = attacker.context,
			origin = origin,
			direction = rotated,
			speed = move.ProjectileSpeed or 145,
			range = move.Range,
			pierce = move.Pierce or 1,
			onHit = function(target: Target, position: Vector3, distance: number): boolean?
				if hitTargets[target.model] or not CombatTargets.isAlive(target) then
					return target.kind == "Zombie"
				end
				hitTargets[target.model] = true
				pierced += 1
				local multiplier = ProjectileDefinitions.falloff(distance) * (pierceSteps[pierced] or pierceSteps[#pierceSteps])
				local _, blocked = apply(execution, target, moveDamage(move, attacker) * multiplier, position)
				return target.kind == "Zombie" and not blocked
			end,
		})
	end
end

local function executeProjectile(execution: Execution)
	local attacker = execution.attacker
	local head = attacker.character:FindFirstChild("Head")
	local origin = if head and head:IsA("BasePart") then head.Position else attacker.root.Position + Vector3.new(0, 1.5, 0)
	local toAim = attacker.aimPoint - origin
	local direction = if toAim.Magnitude > 2 then toAim.Unit else attacker.root.CFrame.LookVector
	local flat = CombatUtil.flat(direction)
	if flat.Magnitude > 0.05 then
		origin += flat.Unit * 1.2
	end
	fireArrows(execution, origin, direction)
end

-- Aerial: needs a real jump; one controlled hop for combo aerials started on the ground.
local function executeAerial(execution: Execution)
	local move, attacker = execution.move, execution.attacker
	local player = attacker.player
	if not JumpAttackService.isAirborne(player) then
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Leap, InputDefinitions.LeapUpVelocity, aimDirection(attacker), (move.Forward or 0) * 0.5)
		task.wait(0.28)
		if not refresh(attacker) then
			return
		end
	end
	JumpAttackService.consume(player)
	local alreadyHit: { [Model]: boolean } = {}
	if move.AirHit and move.AirHit > 0 then
		alreadyHit = strike(execution, move.AirHit, false, nil, nil)
	end
	-- Controlled descent (one velocity change, never repeated: no flying)
	attacker.animate(move.Anim, 0.05, 0.5)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Dive, aimDirection(attacker), move.Forward or 0, InputDefinitions.DiveVelocity)
	JumpAttackService.waitForLanding(player, InputDefinitions.MaxAirSeconds)
	if not refresh(attacker) then
		return
	end
	attacker.character:SetAttribute("SpecialLandingStart", Workspace:GetServerTimeNow())
	local feet = attacker.root.Position - Vector3.new(0, 2.8, 0)
	local landed = strike(execution, 1, false, nil, nil, alreadyHit)
	if move.Shockwave and move.Shockwave > 0 then
		CombatEffects.sandBurst(Vector3.new(feet.X, math.max(feet.Y, Arena.Layout.FloorTop), feet.Z), move.Shockwave, 1)
		for model in landed do
			alreadyHit[model] = true
		end
		strike(execution, move.ShockwaveMultiplier or 0.4, false, move.Shockwave, -1, alreadyHit)
	else
		CombatEffects.sandBurst(Vector3.new(feet.X, math.max(feet.Y, Arena.Layout.FloorTop), feet.Z), 2.5, 0.4)
	end
	local recovery = (move.LandingRecovery or 0) + (if not execution.landedAny then move.MissRecovery or 0 else 0)
	if recovery > 0 then
		attacker.extendBusy(recovery)
	end
end

-- ARROW RAIN: a marked circle, arrows fall in after a short delay, impacts checked from above.
local function executeVolley(execution: Execution)
	local move, attacker = execution.move, execution.attacker
	local toAim = CombatUtil.flat(attacker.aimPoint - attacker.root.Position)
	local distance = math.min(toAim.Magnitude, move.Range)
	local center = attacker.root.Position + (if toAim.Magnitude > 0.1 then toAim.Unit else aimDirection(attacker)) * distance
	center = Vector3.new(center.X, Arena.Layout.FloorTop, center.Z)
	if Arena.isInside(attacker.root.Position) and not Arena.isInside(center, -2) then
		center = Arena.getSafePoint(center)
	end
	local radius = move.Radius or 6
	if move.Lunge then
		lunge(attacker, move.Lunge) -- quick evasive step back
	end
	CombatEffects.groundMarker(center, radius, 0.9, Color3.fromRGB(255, 200, 90))
	CombatEffects.arrowRain(center, radius, 0.9)
	task.wait(0.9)
	if not refresh(attacker) then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = CombatTargets.losIgnoreList(attacker.character)
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local count = 0
	for _, target in CombatTargets.list(attacker.player, attacker.context) do
		if count >= maxTargets(move, attacker.context) then
			break
		end
		local position = target.root.Position
		if CombatUtil.flatDistance(position, center) <= radius + target.radius then
			-- Arrows come from above: a roof or solid geometry over the target protects it
			if Workspace:Raycast(position + Vector3.new(0, 40, 0), Vector3.new(0, -38, 0), params) == nil then
				count += 1
				apply(execution, target, moveDamage(move, attacker), position)
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- Entry point
------------------------------------------------------------------------------------------

-- Runs a move (yields through its wind-up and hits). Callers handle cooldowns and busy time.
-- Returns true if anything was hit (or blocked).
function SpecialMoveService.execute(move: MoveDefinition, attacker: Attacker): boolean
	local execution: Execution = { move = move, attacker = attacker, dealtTo = {}, landedAny = false }
	attacker.animate(move.Anim, move.WindUp, move.Duration)
	if move.WindUp >= 0.2 and attacker.weaponModel then
		CombatEffects.glow(attacker.weaponModel, Color3.fromRGB(255, 210, 90), move.WindUp)
	end
	if move.Lunge and move.Lunge > 0 and move.Kind == "Melee" then
		lunge(attacker, move.Lunge)
	end
	task.wait(move.WindUp)
	if not refresh(attacker) then
		return false
	end
	if move.Kind == "Melee" then
		executeMelee(execution)
	elseif move.Kind == "Projectile" then
		if move.Advanced and not JumpAttackService.isAirborne(attacker.player) and move.Id == "EagleShot" then
			-- EAGLE SHOT: a short jump, then the shot from the air
			Remotes.CombatFeedback:FireClient(attacker.player, CombatConfig.Feedback.Leap, InputDefinitions.LeapUpVelocity, aimDirection(attacker), 0)
			task.wait(0.3)
			if not refresh(attacker) then
				return false
			end
		end
		executeProjectile(execution)
	elseif move.Kind == "Aerial" then
		executeAerial(execution)
	elseif move.Kind == "Volley" then
		executeVolley(execution)
	end
	return execution.landedAny
end

return SpecialMoveService
