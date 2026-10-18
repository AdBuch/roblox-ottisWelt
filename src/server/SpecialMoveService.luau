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
}

-- Per execution: damage already dealt to each player (whole-move PvP cap).
type Execution = { move: MoveDefinition, attacker: Attacker, dealtTo: { [Player]: number }, landedAny: boolean }

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
	return {
		damage = damage * attacker.comboMultiplier,
		pvpMultiplier = move.PvPMultiplier,
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

local function apply(execution: Execution, target: Target, damage: number, hitPosition: Vector3?): (number, boolean)
	if target.kind == "Player" and target.player then
		local info = hitInfo(execution, damage, target)
		if info.pvpCap and info.pvpCap <= 0 then
			return 0, false -- this move already took its maximum from this player
		end
		info.hitPosition = hitPosition
		local dealt, blocked = CombatTargets.applyHit(execution.attacker.player, target, info)
		execution.dealtTo[target.player] = (execution.dealtTo[target.player] or 0) + dealt
		execution.landedAny = execution.landedAny or dealt > 0 or blocked
		return dealt, blocked
	end
	local info = hitInfo(execution, damage, nil)
	info.hitPosition = hitPosition
	local dealt, blocked = CombatTargets.applyHit(execution.attacker.player, target, info)
	execution.landedAny = execution.landedAny or dealt > 0 or blocked
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
		strike(execution, step.Multiplier, index == 1, step.Range, if step.Spin then -1 else step.ArcDot)
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
