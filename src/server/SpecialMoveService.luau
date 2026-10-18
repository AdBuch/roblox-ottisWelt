--!strict
-- Executes weapon moves (basic attacks and specials) from SpecialMoveDefinitions, generically by
-- Kind. Every move: visible wind-up -> re-validation (attacker still alive and allowed to fight)
-- -> server-side target search (range, arc, line of sight) -> damage through CombatTargets.
-- PvP: per-move multiplier and target cap; PlayerCombatService additionally caps each hit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local SpecialMoveDefinitions = require(ReplicatedStorage.Shared.SpecialMoveDefinitions)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatRules = require(script.Parent.CombatRules)
local CombatTargets = require(script.Parent.CombatTargets)
local CombatUtil = require(script.Parent.CombatUtil)
local ProjectileService = require(script.Parent.ProjectileService)
local Remotes = require(script.Parent.Remotes)

type MoveDefinition = SpecialMoveDefinitions.MoveDefinition
type Anim = SpecialMoveDefinitions.Anim
type Target = CombatTargets.Target
type CombatContext = CombatRules.CombatContext

export type Attacker = {
	player: Player,
	context: CombatContext,
	character: Model,
	root: BasePart,
	aimPoint: Vector3,
	comboMultiplier: number,
	bonusStagger: number,
	bashMultiplier: number,
	weaponModel: Model?,
	animate: (anim: Anim, windUp: number, duration: number) -> (),
	stillValid: () -> boolean,
	reject: (reason: string) -> (),
}

local SpecialMoveService = {}

local function maxTargets(move: MoveDefinition, context: CombatContext): number
	return if context == "PvP" then move.PvPMaxTargets else move.MaxTargets
end

local function hitInfo(move: MoveDefinition, attacker: Attacker, damage: number): CombatTargets.HitInfo
	local bash = if move.ShieldBash then attacker.bashMultiplier else 1
	return {
		damage = damage * attacker.comboMultiplier,
		pvpMultiplier = move.PvPMultiplier,
		fromPosition = attacker.root.Position,
		stagger = (move.Stagger + attacker.bonusStagger) * bash,
		knockback = move.Knockback * bash,
		isProjectile = move.Kind == "Projectile",
		executeThreshold = move.ExecuteThreshold,
		executeMultiplier = move.ExecuteMultiplier,
	}
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

local function strike(move: MoveDefinition, attacker: Attacker, multiplier: number, isFirst: boolean): boolean
	local result = CombatTargets.findInArc(attacker.player, attacker.context, attacker.character, attacker.root, move.Range, move.ArcDot, maxTargets(move, attacker.context))
	if #result.targets == 0 then
		if isFirst then
			attacker.reject(result.reason or "invalid target")
		end
		return false
	end
	for _, target in result.targets do
		CombatTargets.applyHit(attacker.player, target, hitInfo(move, attacker, move.Damage * multiplier))
	end
	return true
end

local function executeMelee(move: MoveDefinition, attacker: Attacker)
	if move.Anim == "Spin" then
		CombatEffects.ring(attacker.root.Position - Vector3.new(0, 2.5, 0), move.Range, Color3.fromRGB(255, 220, 140))
	end
	local hits: { SpecialMoveDefinitions.HitStep } = move.Hits or { { Delay = 0, Multiplier = 1 } }
	local elapsed = 0
	for index, step in hits do
		if step.Delay > elapsed then
			task.wait(step.Delay - elapsed)
			elapsed = step.Delay
		end
		if not refresh(attacker) then
			return
		end
		-- Later strikes only happen while a valid target is still in range
		if not strike(move, attacker, step.Multiplier, index == 1) and index > 1 then
			return
		end
	end
end

local function executeProjectile(move: MoveDefinition, attacker: Attacker)
	local head = attacker.character:FindFirstChild("Head")
	local origin = if head and head:IsA("BasePart") then head.Position else attacker.root.Position + Vector3.new(0, 1.5, 0)
	local toAim = attacker.aimPoint - origin
	local direction = if toAim.Magnitude > 2 then toAim.Unit else attacker.root.CFrame.LookVector
	local flat = CombatUtil.flat(direction)
	if flat.Magnitude > 0.05 then
		origin += flat.Unit * 1.2
	end
	local count = move.ProjectileCount or 1
	local spread = math.rad(move.Spread or 0)
	local hitTargets: { [Model]: boolean } = {}
	for i = 1, count do
		local angle = (i - (count + 1) / 2) * spread
		local rotated = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(direction)
		ProjectileService.fireArrow({
			attacker = attacker.player,
			context = attacker.context,
			origin = origin,
			direction = rotated,
			speed = move.ProjectileSpeed or 110,
			range = move.Range,
			pierce = move.Pierce or 1,
			onHit = function(target: Target)
				-- One arrow volley may hit each target only once (no triple-shot stacking on one body)
				if hitTargets[target.model] or not CombatTargets.isAlive(target) then
					return
				end
				hitTargets[target.model] = true
				CombatTargets.applyHit(attacker.player, target, hitInfo(move, attacker, move.Damage))
			end,
		})
	end
end

local function executeNet(move: MoveDefinition, attacker: Attacker)
	local result = CombatTargets.findInArc(attacker.player, attacker.context, attacker.character, attacker.root, move.Range, move.ArcDot, 1)
	local target = result.targets[1]
	local from = attacker.root.Position + Vector3.new(0, 1.5, 0)
	if not target then
		CombatEffects.netThrow(from, from + aimDirection(attacker) * 8)
		attacker.reject(result.reason or "invalid target")
		return
	end
	CombatEffects.netThrow(from, target.root.Position + Vector3.new(0, 1, 0))
	task.wait(0.25)
	if not CombatTargets.isAlive(target) then
		return
	end
	CombatTargets.applySlow(target, move.SlowFactor or 0.6, move.SlowSeconds or 1.5)
	task.wait(0.35)
	if not refresh(attacker) or not CombatTargets.isAlive(target) then
		return
	end
	-- Automatic follow-up thrust only if the netted target is still in range
	local distance = CombatUtil.flatDistance(attacker.root.Position, target.root.Position) - target.radius
	if distance <= (move.FollowUpRange or 10) then
		attacker.animate("Thrust", 0.05, 0.3)
		CombatTargets.applyHit(attacker.player, target, hitInfo(move, attacker, move.FollowUpDamage or 20))
	end
end

local function executeDash(move: MoveDefinition, attacker: Attacker)
	local direction = aimDirection(attacker)
	local wanted = move.DashDistance or 8
	-- Never through walls: stop short of the first solid obstacle
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = CombatTargets.losIgnoreList(attacker.character)
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(attacker.root.Position, direction * wanted, params)
	local distance = if hit then math.max(0, (hit.Position - attacker.root.Position).Magnitude - 2) else wanted
	if distance > 0.5 then
		-- The client owns its character's physics, so it performs the movement
		Remotes.CombatFeedback:FireClient(attacker.player, CombatConfig.Feedback.Dash, direction, distance)
	end
	task.wait(0.22)
	if not refresh(attacker) then
		return
	end
	strike(move, attacker, 1, true)
end

-- Runs a move (yields for its wind-up and hits). Callers handle cooldowns and busy time.
function SpecialMoveService.execute(move: MoveDefinition, attacker: Attacker)
	attacker.animate(move.Anim, move.WindUp, move.Duration)
	if move.WindUp >= 0.3 and attacker.weaponModel then
		CombatEffects.glow(attacker.weaponModel, Color3.fromRGB(255, 210, 90), move.WindUp)
	end
	if move.Lunge and move.Lunge > 0 then
		Remotes.CombatFeedback:FireClient(attacker.player, CombatConfig.Feedback.Dash, aimDirection(attacker), move.Lunge)
	end
	task.wait(move.WindUp)
	if not refresh(attacker) then
		return
	end

	if move.Kind == "Melee" then
		executeMelee(move, attacker)
	elseif move.Kind == "Projectile" then
		executeProjectile(move, attacker)
	elseif move.Kind == "Net" then
		executeNet(move, attacker)
	elseif move.Kind == "Dash" then
		executeDash(move, attacker)
	end
end

return SpecialMoveService
