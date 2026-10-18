--!strict
-- Ranged AI for the Undead Sagittarius (zombie archer). Runs inside ZombieService's think loop and
-- uses its movement helpers (passed in as a toolkit, so there is no require cycle).
--   target    living arena fighters within DetectRange; prefers players few other archers aim at,
--             with a clear line of sight near its preferred range (individual targeting)
--   position  keeps 55-85 studs: picks reachable firing spots with line of sight, near the arena
--             edge, away from melee crowds and other archers; relocates when a player gets closer
--             than 25 studs; a cornered archer strikes weakly once and retreats
--   shooting  visible bow draw + aim line, then a server-simulated arrow (ProjectileService) with
--             slight lead, limited accuracy (worse when wounded/critical) and no wall/floor/shield
--             penetration. Only a few archers may draw at the same time.
-- A dead archer never deals delayed damage: its arrows check that the shooter is still alive.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local ProjectileDefinitions = require(ReplicatedStorage.Shared.ProjectileDefinitions)
local Arena = require(script.Parent.Arena)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatRules = require(script.Parent.CombatRules)
local CombatUtil = require(script.Parent.CombatUtil)

type ArcherState = {
	target: Player?,
	nextRetarget: number,
	nextShotAt: number,
	goal: Vector3?,
	nextReposition: number,
}

local ZombieArcherAI = {}

local targetOf: { [any]: Player? } = {}
local drawing = 0

local function archersOn(player: Player, except: any): number
	local count = 0
	for z, target in targetOf do
		if target == player and z ~= except then
			count += 1
		end
	end
	return count
end

local function maxSimultaneousDraws(): number
	local living = 0
	for _, player in CombatRules.zombieTargets() do
		if CombatUtil.getLivingCharacter(player) then
			living += 1
		end
	end
	return math.clamp(1 + living, 2, 4)
end

local function eyeOf(position: Vector3): Vector3
	return position + Vector3.new(0, 1.5, 0)
end

local function pickTarget(z: any, kit: any, state: ArcherState, now: number): (Player?, BasePart?)
	local current = state.target
	if current and now < state.nextRetarget then
		local root = kit.isValidTarget(current)
		if root then
			return current, root
		end
	end
	state.nextRetarget = now + 1.2 + z.rng:NextNumber() * 0.4
	local def = z.definition
	local detect = def.DetectRange or CombatConfig.ArcherDetectRadius
	local preferred = ((def.PreferredRangeMin or 55) + (def.PreferredRangeMax or 85)) / 2
	local best: Player?, bestRoot: BasePart?, bestScore = nil, nil, -math.huge
	for _, player in CombatRules.zombieTargets() do
		local root = kit.isValidTarget(player)
		if root then
			local distance = CombatUtil.flatDistance(root.Position, z.root.Position)
			if distance <= detect then
				local canSee = CombatUtil.hasLineOfSight(eyeOf(z.root.Position), root.Position, kit.ignoreList(player.Character))
				local score = -math.abs(distance - preferred) / 40
					+ (if canSee then 0.8 else 0)
					- 0.6 * archersOn(player, z)
					+ (if player == current then 0.3 else 0)
				if score > bestScore then
					best, bestRoot, bestScore = player, root, score
				end
			end
		end
	end
	state.target = best
	targetOf[z] = best
	return best, bestRoot
end

-- A reachable firing position with line of sight, near the edge, away from crowds and other archers.
local function pickFiringSpot(z: any, kit: any, targetRoot: BasePart, character: Model?): Vector3?
	local def = z.definition
	local minRange, maxRange = def.PreferredRangeMin or 55, def.PreferredRangeMax or 85
	local ignore = kit.ignoreList(character)
	local best, bestScore = nil, -math.huge
	local base = math.atan2(z.root.Position.Z - targetRoot.Position.Z, z.root.Position.X - targetRoot.Position.X)
	for i = 0, 9 do
		local angle = base + (i - 4.5) * 0.35
		for _, radius in { minRange + 5, (minRange + maxRange) / 2 } do
			local candidate = Vector3.new(targetRoot.Position.X + math.cos(angle) * radius, Arena.Layout.FloorTop, targetRoot.Position.Z + math.sin(angle) * radius)
			if Arena.isInside(candidate, -8) then
				local x, zz = candidate.X / Arena.Layout.SemiAxisX, candidate.Z / Arena.Layout.SemiAxisZ
				local edge = math.sqrt(x * x + zz * zz)
				local score = (if CombatUtil.hasLineOfSight(eyeOf(candidate + Vector3.new(0, 2.5, 0)), targetRoot.Position, ignore) then 3 else 0)
					+ (if edge > 0.7 then 0.8 else 0) -- edge positions: clear lanes, out of the melee
					- kit.zombiesNear(candidate, 8, z) * 0.4
					- (candidate - z.root.Position).Magnitude / 60
				for other, _ in targetOf do
					if other ~= z and other.alive and CombatUtil.flatDistance(other.root.Position, candidate) < 14 then
						score -= 0.8 -- spread the archers out
					end
				end
				if score > bestScore then
					best, bestScore = candidate, score
				end
			end
		end
	end
	return best
end

local function shoot(z: any, kit: any, state: ArcherState, player: Player)
	local def = z.definition
	local rig = z.rig
	z.busy = true
	drawing += 1
	local drawSeconds = def.DrawSeconds or 0.75
	-- Telegraph: bow raised, string drawn, glowing outline and a faint aim line
	kit.setPose(rig.leftShoulder, rig.leftShoulderRest, 90, drawSeconds * 0.4)
	kit.setPose(rig.rightShoulder, rig.rightShoulderRest, 95, drawSeconds * 0.6)
	CombatEffects.glow(z.model, Color3.fromRGB(255, 190, 90), drawSeconds)
	local _, _, startRoot = CombatUtil.getLivingCharacter(player)
	if startRoot then
		kit.faceTowards(z, startRoot.Position)
		CombatEffects.aimLine(eyeOf(z.root.Position), startRoot.Position, drawSeconds)
	end
	task.wait(drawSeconds)
	drawing = math.max(0, drawing - 1)

	local fired = false
	local character, _, targetRoot = CombatUtil.getLivingCharacter(player)
	if z.alive and not z.unarmed and character and targetRoot and kit.isValidTarget(player) then
		kit.faceTowards(z, targetRoot.Position)
		local origin = eyeOf(z.root.Position) + CombatUtil.flat(z.root.CFrame.LookVector) * 1.2
		if CombatUtil.hasLineOfSight(origin, targetRoot.Position, kit.ignoreList(character)) then
			local arrowDef = ProjectileDefinitions.EnemyArrow
			local distance = (targetRoot.Position - origin).Magnitude
			-- Slight lead on moving targets, limited accuracy (more error when wounded)
			local velocity = CombatUtil.flat(targetRoot.AssemblyLinearVelocity)
			local lead = velocity * (distance / arrowDef.Speed) * (def.LeadFactor or 0.35)
			local aim = targetRoot.Position + lead + Vector3.new(0, 0.4, 0)
			local errorRad = math.rad((def.AimErrorDegrees or 2.2) * z.mods.AimErrorMultiplier)
			local direction = (aim - origin).Unit
			direction = (CFrame.fromAxisAngle(Vector3.yAxis, z.rng:NextNumber(-1, 1) * errorRad)
				* CFrame.fromAxisAngle(CombatUtil.flat(direction).Unit:Cross(Vector3.yAxis), z.rng:NextNumber(-0.6, 0.6) * errorRad)):VectorToWorldSpace(direction)
			kit.handlers().fireArrow({
				origin = origin,
				direction = direction,
				speed = arrowDef.Speed,
				range = math.min(arrowDef.MaxRange, (def.DetectRange or 140) + 20),
				damage = math.max(1, math.floor((def.ArrowDamage or 8) * CombatConfig.ZombieDamageMultiplier + 0.5)),
				isShooterAlive = function()
					return z.alive
				end,
			})
			fired = true
		end
	end
	if z.alive then
		kit.setPose(rig.rightShoulder, rig.rightShoulderRest, if fired then 60 else 0, 0.1)
		task.wait(0.25)
		kit.setPose(rig.rightShoulder, rig.rightShoulderRest, 0, 0.3)
		kit.setPose(rig.leftShoulder, rig.leftShoulderRest, 0, 0.3)
	end
	local cooldown = (def.FireCooldown or 2.2) * z.mods.FireCooldownMultiplier * (0.85 + z.rng:NextNumber() * 0.3)
	state.nextShotAt = os.clock() + (if fired then cooldown else 0.6)
	z.busy = false
end

function ZombieArcherAI.think(z: any, kit: any, now: number)
	local state: ArcherState = z.archer
	if not state then
		state = { target = nil, nextRetarget = 0, nextShotAt = now + 1.2 + z.rng:NextNumber(), goal = nil, nextReposition = 0 }
		z.archer = state
	end
	local def = z.definition
	local player, targetRoot = pickTarget(z, kit, state, now)
	if not player or not targetRoot then
		state.goal = nil
		if CombatUtil.flatDistance(z.root.Position, Arena.Layout.Center) > 30 then
			kit.moveTowards(z, Arena.Layout.Center, now)
		else
			z.humanoid:MoveTo(z.root.Position)
		end
		kit.checkStuck(z, now, false)
		return
	end

	local character = player.Character
	local position = z.root.Position
	local distance = CombatUtil.flatDistance(position, targetRoot.Position)
	local canSee = CombatUtil.hasLineOfSight(eyeOf(position), targetRoot.Position, kit.ignoreList(character))
	local minComfort = def.MinComfortRange or 25

	-- Cornered: weak strike, then retreat (profile RetreatAfterAttack)
	if distance <= def.AttackRange and now >= z.retreatUntil and now - z.lastAttack >= def.AttackCooldown then
		local away = CombatUtil.flat(position - targetRoot.Position)
		local escape = position + (if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis) * 10
		if not Arena.isInside(escape, -6) or z.rng:NextNumber() < 0.5 then
			kit.faceTowards(z, targetRoot.Position)
			if kit.melee(z, player) then
				state.goal = nil
				return
			end
		end
	end

	-- Shoot when lined up (individual cooldown + global draw limit)
	if canSee and distance >= 8 and now >= state.nextShotAt and drawing < maxSimultaneousDraws() and now >= z.retreatUntil - 1 then
		z.humanoid:MoveTo(position)
		task.spawn(shoot, z, kit, state, player)
		return
	end

	-- Positioning
	local goal: Vector3
	if distance < minComfort then
		-- Too close: back away, sliding along the wall when there is no room behind
		local away = CombatUtil.flat(position - targetRoot.Position)
		local direction = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
		goal = position + direction * 18
		if not Arena.isInside(goal, -6) then
			goal = position + CFrame.fromAxisAngle(Vector3.yAxis, z.drift * 1.2):VectorToWorldSpace(direction) * 18
		end
		state.goal = nil
	else
		local tooFar = distance > (def.PreferredRangeMax or 85)
		local tooClose = distance < (def.PreferredRangeMin or 55)
		if state.goal == nil or now >= state.nextReposition or ((not canSee or tooFar or tooClose) and now >= state.nextReposition - 3) then
			state.goal = pickFiringSpot(z, kit, targetRoot, character)
			state.nextReposition = now + 5 + z.rng:NextNumber() * 3
		end
		goal = state.goal or targetRoot.Position
	end
	goal += kit.separation(z)
	local wantsToMove = CombatUtil.flatDistance(position, goal) > 2
	if wantsToMove then
		kit.moveTowards(z, goal, now)
	else
		z.humanoid:MoveTo(position)
		kit.faceTowards(z, targetRoot.Position)
	end
	kit.checkStuck(z, now, wantsToMove)
end

function ZombieArcherAI.release(z: any)
	targetOf[z] = nil
end

return ZombieArcherAI
