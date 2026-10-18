--!strict
-- One interface for everything a player can hit: arena zombies, Otti (the Round 7 boss), enemy
-- players (Team Battle) and training dummies. Which targets are valid depends on the attacker's CombatContext
-- (CombatRules). All damage goes through applyHit(), which also sends the Hit feedback.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatRules = require(script.Parent.CombatRules)
local CombatUtil = require(script.Parent.CombatUtil)
local OttiBossService = require(script.Parent.OttiBossService)
local Remotes = require(script.Parent.Remotes)
local TrainingService = require(script.Parent.TrainingService)
local ZombieService = require(script.Parent.ZombieService)

type CombatContext = CombatRules.CombatContext

export type TargetKind = "Zombie" | "Player" | "Dummy" | "Boss"

export type Target = {
	kind: TargetKind,
	model: Model,
	root: BasePart,
	radius: number,
	player: Player?,
	zombie: ZombieService.Zombie?,
	dummy: TrainingService.Dummy?,
}

export type HitInfo = {
	damage: number, -- already includes combo bonuses (PvP scaling happens here)
	pvpMultiplier: number,
	fromPosition: Vector3,
	stagger: number,
	knockback: number,
	isProjectile: boolean,
	executeThreshold: number?,
	executeMultiplier: number?,
	weaponId: string?, -- zombie limb-loss chances depend on the weapon
	isSpecial: boolean?,
	spin: boolean?,
	hitPosition: Vector3?, -- projectiles: exact impact point
	guardBreak: boolean?, -- combo: breaks a raised guard instead of being stopped by it
	fromCombo: boolean?, -- combo / aerial move (PvP stagger lock)
	pvpCap: number?, -- PvP: the most this hit may still deal (whole-move cap)
}

-- Handles damage to players (installed by PlayerCombatService: blocking, caps, deaths).
type PlayerDamageHandler = (victim: Player, attacker: Player, damage: number, info: HitInfo) -> (number, boolean)
type PlayerSlowHandler = (victim: Player, factor: number, seconds: number) -> ()

local CombatTargets = {}

local damagePlayer: PlayerDamageHandler = function()
	return 0, false
end
local slowPlayer: PlayerSlowHandler = function() end

function CombatTargets.setPlayerHandlers(onDamage: PlayerDamageHandler, onSlow: PlayerSlowHandler)
	damagePlayer = onDamage
	slowPlayer = onSlow
end

local function zombieTarget(model: Instance): Target?
	local zombie = ZombieService.getByModel(model)
	if zombie then
		return { kind = "Zombie", model = zombie.model, root = zombie.root, radius = zombie.root.Size.X / 2, zombie = zombie }
	end
	return nil
end

local function bossTarget(): Target?
	local model, root = OttiBossService.getHittable()
	if model and root then
		return { kind = "Boss", model = model, root = root, radius = 2.2 }
	end
	return nil
end

local function playerTarget(attacker: Player, victim: Player): Target?
	if not CombatRules.isEnemy(attacker, victim) then
		return nil
	end
	local character, _, root = CombatUtil.getLivingCharacter(victim)
	if character and root then
		return { kind = "Player", model = character, root = root, radius = 1, player = victim }
	end
	return nil
end

-- All currently valid targets for this attacker.
function CombatTargets.list(attacker: Player, context: CombatContext): { Target }
	local targets: { Target } = {}
	if context == "Zombies" then
		for _, model in CollectionService:GetTagged(CombatConfig.ZombieTag) do
			local target = zombieTarget(model)
			if target then
				table.insert(targets, target)
			end
		end
		local boss = bossTarget()
		if boss then
			table.insert(targets, boss)
		end
	elseif context == "PvP" then
		for _, other in Players:GetPlayers() do
			local target = playerTarget(attacker, other)
			if target then
				table.insert(targets, target)
			end
		end
	elseif context == "Training" then
		for _, dummy in TrainingService.getDummies() do
			table.insert(targets, { kind = "Dummy", model = dummy.model, root = dummy.root, radius = 1.2, dummy = dummy })
		end
	end
	return targets
end

-- The target a raycast hit belongs to (for projectiles), if it is valid for this attacker.
function CombatTargets.resolve(attacker: Player, context: CombatContext, instance: Instance): Target?
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		if context == "Zombies" and CollectionService:HasTag(model, CombatConfig.ZombieTag) then
			return zombieTarget(model)
		elseif context == "Zombies" and CollectionService:HasTag(model, Config.OttiTag) then
			return bossTarget()
		elseif context == "PvP" then
			local victim = Players:GetPlayerFromCharacter(model)
			if victim then
				return playerTarget(attacker, victim)
			end
		elseif context == "Training" and CollectionService:HasTag(model, Config.TrainingDummyTag) then
			local dummy = TrainingService.getByModel(model)
			if dummy then
				return { kind = "Dummy", model = dummy.model, root = dummy.root, radius = 1.2, dummy = dummy }
			end
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Instances that never block a line of sight between fighters.
function CombatTargets.losIgnoreList(attackerCharacter: Model): { Instance }
	local list: { Instance } = { attackerCharacter }
	local arena = Workspace:FindFirstChild(Config.ArenaFolderName)
	local zombies = arena and arena:FindFirstChild(Config.ZombiesFolderName)
	if zombies then
		table.insert(list, zombies)
	end
	for _, boss in CollectionService:GetTagged(Config.OttiTag) do
		table.insert(list, boss)
	end
	for _, other in Players:GetPlayers() do
		if other.Character and other.Character ~= attackerCharacter then
			table.insert(list, other.Character)
		end
	end
	for _, dummy in TrainingService.getDummies() do
		table.insert(list, dummy.model)
	end
	return list
end

export type ArcResult = { targets: { Target }, reason: string? }

-- Targets in range and arc with line of sight, closest first (at most maxTargets).
function CombatTargets.findInArc(attacker: Player, context: CombatContext, character: Model, root: BasePart, range: number, arcDot: number, maxTargets: number): ArcResult
	local candidates: { { target: Target, distance: number } } = {}
	local closestReason, closestDistance = "invalid target (nothing to hit)", math.huge
	local ignore = CombatTargets.losIgnoreList(character)
	for _, target in CombatTargets.list(attacker, context) do
		local position = target.root.Position
		local distance = math.max(0, CombatUtil.flatDistance(root.Position, position) - target.radius)
		local reason: string? = nil
		if distance > range or math.abs(root.Position.Y - position.Y) > 7 then
			reason = ("out of range (%.1f studs)"):format(distance)
		elseif arcDot > -1 and not CombatUtil.isFacing(root.CFrame, position, arcDot) then
			reason = "invalid facing direction"
		elseif not CombatUtil.hasLineOfSight(root.Position, position, ignore) then
			reason = "blocked line of sight"
		end
		if reason == nil then
			table.insert(candidates, { target = target, distance = distance })
		elseif distance < closestDistance then
			closestReason, closestDistance = reason, distance
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	local result: { Target } = {}
	for i = 1, math.min(maxTargets, #candidates) do
		table.insert(result, candidates[i].target)
	end
	return { targets = result, reason = if #result == 0 then closestReason else nil }
end

function CombatTargets.isAlive(target: Target): boolean
	if target.kind == "Zombie" then
		return target.zombie ~= nil and ZombieService.getByModel(target.model) ~= nil
	elseif target.kind == "Player" then
		local player = target.player
		return player ~= nil and CombatUtil.getLivingCharacter(player) ~= nil
	elseif target.kind == "Boss" then
		return OttiBossService.getHittable() ~= nil
	end
	return target.model.Parent ~= nil
end

-- Applies one hit. Returns the damage dealt and whether it was blocked.
function CombatTargets.applyHit(attacker: Player, target: Target, info: HitInfo): (number, boolean)
	local dealt, blocked = 0, false
	if target.kind == "Zombie" then
		local zombie = target.zombie
		if not zombie then
			return 0, false
		end
		if info.guardBreak and ZombieService.breakGuard(zombie) then
			-- the raised guard is broken: the hit goes through and the zombie staggers
			ZombieService.applyDamage(zombie, attacker, math.floor(info.damage * ZombieService.damageMultiplier(zombie) + 0.5), info.fromPosition, 1.2, info.knockback, { weaponId = info.weaponId, isSpecial = true })
			dealt = math.floor(info.damage + 0.5)
		elseif ZombieService.tryGuardBlock(zombie, info.fromPosition) then
			blocked = true
		else
			local damage = info.damage
			if info.executeThreshold and info.executeMultiplier and ZombieService.healthFraction(zombie) < info.executeThreshold then
				damage *= info.executeMultiplier -- bonus vs weakened zombies only
			end
			damage *= ZombieService.damageMultiplier(zombie) -- lost armor
			damage = math.floor(damage + 0.5)
			if ZombieService.applyDamage(zombie, attacker, damage, info.fromPosition, info.stagger, info.knockback, {
				weaponId = info.weaponId,
				isSpecial = info.isSpecial,
				spin = info.spin,
				hitPosition = info.hitPosition,
			}) then
				dealt = damage
			end
		end
	elseif target.kind == "Player" then
		local victim = target.player
		if victim then
			dealt, blocked = damagePlayer(victim, attacker, info.damage * info.pvpMultiplier, info)
		end
	elseif target.kind == "Boss" then
		dealt, blocked = OttiBossService.applyPlayerHit(attacker, info.damage, info.fromPosition, info.isProjectile, info.stagger, info.hitPosition, info.guardBreak == true)
	elseif target.kind == "Dummy" then
		local dummy = target.dummy
		if dummy then
			dealt = math.floor(info.damage + 0.5)
			TrainingService.hit(dummy, dealt)
		end
	end
	if dealt > 0 or blocked then
		CombatEffects.burst(target.root.Position, if blocked then Color3.fromRGB(255, 220, 120) else Color3.fromRGB(255, 240, 180), 0.6)
	end
	Remotes.CombatFeedback:FireClient(attacker, CombatConfig.Feedback.Hit, target.model, dealt, blocked)
	return dealt, blocked
end

function CombatTargets.applySlow(target: Target, factor: number, seconds: number)
	if target.kind == "Zombie" and target.zombie then
		ZombieService.applySlow(target.zombie, factor, seconds)
	elseif target.kind == "Player" and target.player then
		slowPlayer(target.player, factor, seconds)
	end
end

return CombatTargets
