--!strict
-- Shared zombie AI for 1-4 arena players. Every zombie has its own state, loop and connections
-- (all cleaned up on death); living zombies carry CombatConfig.ZombieTag.
-- Behaviour differences come from ZombieAIProfiles (one implementation, five personalities):
--
--   target   scored per living arena player: threat, proximity, low health, movement, gear,
--            exposure, minus crowding (players already chased by many zombies), plus a small
--            bonus for the current target; re-evaluated every ZombieRetargetInterval
--   crowd    melee slots per player (ZombieCrowdService), max 4 attackers per player
--   attack   from a slot, in range, with line of sight; telegraphed; re-validated on impact
--   profile  guard (Legion/Champion), circling + retreat (Velite), roar + block-break (Brute),
--            ranged net first + keep distance (Retiarius), shield bash + exposed after a miss
--            (Champion)
--   move     direct MoveTo with line of sight, otherwise budgeted pathfinding; separation
--            steering; stuck detection
--   damage   condition states (ZombieDamageStateService) change looks and behaviour at 65 % / 30 %;
--            strong hits may remove limbs or armor (ZombieDismembermentService): no weapon arm ->
--            weak unarmed bites, no shield arm -> no blocking, lost leg -> slow crawl, lost armor
--            -> takes a little more damage
--   archer   the Undead Sagittarius uses its own ranged AI (ZombieArcherAI) on the same helpers

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local DamageEffectsConfig = require(ReplicatedStorage.Shared.DamageEffectsConfig)
local ZombieAIProfiles = require(ReplicatedStorage.Shared.ZombieAIProfiles)
local ZombieDefinitions = require(ReplicatedStorage.Shared.ZombieDefinitions)
local Arena = require(script.Parent.Arena)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatRules = require(script.Parent.CombatRules)
local CombatUtil = require(script.Parent.CombatUtil)
local DamageEffectsService = require(script.Parent.DamageEffectsService)
local ZombieArcherAI = require(script.Parent.ZombieArcherAI)
local ZombieCrowdService = require(script.Parent.ZombieCrowdService)
local ZombieDamageStateService = require(script.Parent.ZombieDamageStateService)
local ZombieDismembermentService = require(script.Parent.ZombieDismembermentService)
local ZombieFactory = require(script.Parent.ZombieFactory)
local ZombieThreatService = require(script.Parent.ZombieThreatService)

type ZombieDefinition = ZombieDefinitions.ZombieDefinition
type ZombieAIProfile = ZombieAIProfiles.ZombieAIProfile
type ConditionMods = ZombieAIProfiles.ConditionMods

export type Zombie = {
	definition: ZombieDefinition,
	profile: ZombieAIProfile,
	rig: ZombieFactory.ZombieRig,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	rng: Random,
	alive: boolean,
	busy: boolean,
	stunnedUntil: number,
	slowUntil: number,
	lastAttack: number,
	attackDelayUntil: number,
	retreatUntil: number,
	target: Player?,
	nextRetarget: number,
	drift: number,
	nextDriftChange: number,
	path: Path,
	waypoints: { PathWaypoint }?,
	waypointIndex: number,
	pathGoal: Vector3,
	lastPathTime: number,
	lastSamplePosition: Vector3,
	lastSampleTime: number,
	stuckCount: number,
	unstickUntil: number,
	unstickGoal: Vector3,
	netReadyAt: number,
	guarding: boolean,
	guardUntil: number,
	guardReadyAt: number,
	lastAttacker: Player?,
	damagers: { [Player]: boolean },
	connections: { RBXScriptConnection },
	onDied: ((Zombie, Player?, { Player }) -> ())?,
	flashToken: number,
	condition: ZombieDamageStateService.Condition,
	mods: ConditionMods,
	limbs: ZombieDismembermentService.LimbState,
	unarmed: boolean, -- weapon arm lost: weak bites/kicks
	canBlock: boolean, -- shield arm lost: no guard, no bash, no net
	crawling: boolean, -- leg lost: slow, shorter reach
	burstUntil: number,
	restUntil: number,
	archer: any, -- ZombieArcherAI state (Undead Sagittarius only)
}

export type DamageExtra = {
	weaponId: string?,
	isSpecial: boolean?,
	spin: boolean?,
	hitPosition: Vector3?,
}

export type EnemyArrow = {
	origin: Vector3,
	direction: Vector3,
	speed: number,
	range: number,
	damage: number,
	isShooterAlive: () -> boolean,
}

export type Handlers = {
	hitPlayer: (player: Player, attackerPosition: Vector3, damage: number, blockPierce: number, knockback: number) -> (boolean, boolean, number),
	isBlockingToward: (player: Player, position: Vector3) -> boolean,
	isHeavyBlocking: (player: Player) -> boolean,
	slowPlayer: (player: Player, factor: number, seconds: number) -> (),
	gearValue: (player: Player) -> number,
	fireArrow: (arrow: EnemyArrow) -> (),
}

local PREFIX = "[OttiArena][Server]"
local WAYPOINT_REACHED = 2.5
local STUCK_SAMPLE_SECONDS = 1.2

local ZombieService = {}

local zombiesFolder: Instance? = nil
local handlers: Handlers? = nil
local registry: { [Model]: Zombie } = {}
local pathTokens = CombatConfig.PathRequestsPerSecond
local pathTokenTime = os.clock()

local function getHandlers(): Handlers
	return handlers :: Handlers
end

local function takePathToken(): boolean
	local now = os.clock()
	pathTokens = math.min(CombatConfig.PathRequestsPerSecond, pathTokens + (now - pathTokenTime) * CombatConfig.PathRequestsPerSecond)
	pathTokenTime = now
	if pathTokens >= 1 then
		pathTokens -= 1
		return true
	end
	return false
end

local function setPose(motor: Motor6D, rest: CFrame, angleDegrees: number, seconds: number)
	TweenService:Create(motor, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { C0 = rest * CFrame.Angles(math.rad(angleDegrees), 0, 0) }):Play()
end

local function updateHealth(z: Zombie, health: number)
	z.model:SetAttribute("Health", math.max(0, math.ceil(health)))
	if not z.alive or health <= 0 then
		return
	end
	-- Condition states only get worse (no healing for zombies)
	local condition: ZombieDamageStateService.Condition = ZombieDamageStateService.conditionFor(health / z.definition.Health)
	local rank = function(c: string): number
		return if c == "Critical" then 2 elseif c == "Wounded" then 1 else 0
	end
	if rank(condition) > rank(z.condition) then
		z.condition = condition
		z.mods = ZombieDamageStateService.modsFor(z.profile, condition)
		ZombieDamageStateService.apply(z.model, condition, if z.crawling then nil else z.rig.rootJoint, z.rig.rootJointRest)
	end
end

-- Effective combat values after condition modifiers and lost limbs.
local function attackRange(z: Zombie): number
	local range = z.definition.AttackRange
	if z.unarmed then
		range = math.min(range, 4.5)
	end
	return if z.crawling then math.max(3.5, range - 1.5) else range
end

local function attackReach(z: Zombie): number
	local reach = z.definition.AttackReach
	if z.unarmed then
		reach = math.min(reach, 5.5)
	end
	return if z.crawling then math.max(4.5, reach - 1.5) else reach
end

local function walkSpeed(z: Zombie, now: number): number
	local speed = z.definition.WalkSpeed * z.mods.SpeedMultiplier
	if z.crawling then
		speed *= 0.45
	end
	if z.mods.BurstSeconds > 0 then
		-- Short bursts followed by longer rests (critical skirmishers)
		if now >= z.restUntil and now >= z.burstUntil then
			z.burstUntil = now + z.mods.BurstSeconds
			z.restUntil = z.burstUntil + z.mods.RestSeconds
		end
		if now >= z.burstUntil then
			speed *= 0.35
		end
	end
	if now < z.slowUntil then
		speed *= 0.6
	end
	return speed
end

local function flash(z: Zombie, color: Color3)
	z.flashToken += 1
	local token = z.flashToken
	local highlight = Instance.new("Highlight") -- on demand: Roblox renders only ~31 at a time
	highlight.FillColor = color
	highlight.FillTransparency = 0.2
	highlight.OutlineColor = Color3.fromRGB(255, 200, 80)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = z.model
	z.rig.hitSparks.Enabled = true
	task.delay(0.12, function()
		highlight:Destroy()
		if z.flashToken == token then
			z.rig.hitSparks.Enabled = false
		end
	end)
end

local function ignoreList(character: Model?): { Instance }
	local list: { Instance } = { zombiesFolder :: Instance }
	if character then
		table.insert(list, character)
	end
	return list
end

local function faceTowards(z: Zombie, target: Vector3)
	local position = z.root.Position
	local flatTarget = Vector3.new(target.X, position.Y, target.Z)
	if (flatTarget - position).Magnitude > 0.1 then
		z.root.CFrame = CFrame.lookAt(position, flatTarget)
	end
end

local function isValidTarget(player: Player): (BasePart?)
	if not CombatRules.canZombiesTarget(player) then
		return nil
	end
	local _, _, root = CombatUtil.getLivingCharacter(player)
	if root and Arena.isInside(root.Position) then
		return root
	end
	return nil
end

------------------------------------------------------------------------------------------
-- Targeting
------------------------------------------------------------------------------------------

local function scoreTarget(z: Zombie, player: Player, root: BasePart, fairShare: number): number
	local weights = z.profile.TargetWeights
	local distance = (root.Position - z.root.Position).Magnitude
	if distance > (z.definition.DetectRange or z.profile.MaxChaseDistance) then
		return -math.huge
	end
	local _, humanoid = CombatUtil.getLivingCharacter(player)
	local healthMissing = if humanoid then 1 - humanoid.Health / math.max(1, humanoid.MaxHealth) else 0
	local velocity = root.AssemblyLinearVelocity
	local moving = math.clamp(Vector3.new(velocity.X, 0, velocity.Z).Magnitude / 16, 0, 1)
	local exposed = if getHandlers().isBlockingToward(player, z.root.Position) then 0 else 1
	local score = weights.Threat * math.min(ZombieThreatService.get(z, player) / 60, 1.5)
		+ weights.Proximity * (1 - math.clamp(distance / 60, 0, 1))
		+ weights.LowHealth * healthMissing
		+ weights.Moving * moving
		+ weights.Equipment * math.clamp(getHandlers().gearValue(player) / 500, 0, 1)
		+ weights.Exposed * exposed
	-- Spread out: players already chased by more than their share score lower
	local chasing = ZombieThreatService.targetCount(player) - (if z.target == player then 1 else 0)
	if chasing > fairShare then
		score -= 0.5 * (chasing - fairShare) / math.max(1, fairShare)
	end
	if z.target == player then
		score += 0.25 -- persistence: don't flip-flop
	end
	return score
end

local function pickTarget(z: Zombie, now: number): (Player?, BasePart?)
	local current = z.target
	if current and now < z.nextRetarget then
		local root = isValidTarget(current)
		if root then
			return current, root
		end
	end
	z.nextRetarget = now + CombatConfig.ZombieRetargetInterval * (0.8 + z.rng:NextNumber() * 0.4)

	local candidates = CombatRules.zombieTargets()
	local living = 0
	for _, player in candidates do
		if isValidTarget(player) then
			living += 1
		end
	end
	local alive = 0
	for _ in registry do
		alive += 1
	end
	local fairShare = math.ceil(alive / math.max(1, living))

	local bestPlayer: Player?, bestRoot: BasePart?, bestScore = nil, nil, -math.huge
	for _, player in candidates do
		local root = isValidTarget(player)
		if root then
			local score = scoreTarget(z, player, root, fairShare)
			if score > bestScore then
				bestPlayer, bestRoot, bestScore = player, root, score
			end
		end
	end
	if bestScore == -math.huge then
		bestPlayer, bestRoot = nil, nil
	end
	if bestPlayer ~= z.target then
		ZombieCrowdService.release(z)
	end
	z.target = bestPlayer
	ZombieThreatService.setTarget(z, bestPlayer)
	return bestPlayer, bestRoot
end

------------------------------------------------------------------------------------------
-- Movement helpers
------------------------------------------------------------------------------------------

local function separation(z: Zombie): Vector3
	local push = Vector3.zero
	local myPosition = z.root.Position
	for _, other in registry do
		if other ~= z and other.alive then
			local offset = CombatUtil.flat(myPosition - other.root.Position)
			local distance = offset.Magnitude
			if distance < CombatConfig.SeparationRadius then
				local direction = if distance > 0.05 then offset.Unit else Vector3.new(z.rng:NextNumber(-1, 1), 0, z.rng:NextNumber(-1, 1)).Unit
				push += direction * (CombatConfig.SeparationRadius - distance)
			end
		end
	end
	return push * 1.5
end

-- Retiarius yields to brutes/champions occupying the same space.
local function heavyNearby(z: Zombie): Vector3?
	for _, other in registry do
		if other ~= z and other.alive and (other.profile.Id == "Tank" or other.profile.Id == "Elite") then
			local offset = CombatUtil.flat(z.root.Position - other.root.Position)
			if offset.Magnitude < 5 then
				return if offset.Magnitude > 0.05 then offset.Unit else Vector3.xAxis
			end
		end
	end
	return nil
end

local function followPath(z: Zombie, goal: Vector3, now: number)
	local needsPath = z.waypoints == nil or now - z.lastPathTime >= CombatConfig.ZombiePathInterval or (goal - z.pathGoal).Magnitude > 8
	if needsPath and takePathToken() then
		z.lastPathTime = now
		local ok = pcall(function()
			z.path:ComputeAsync(z.root.Position, goal)
		end)
		if not z.alive then
			return
		end
		if ok and z.path.Status == Enum.PathStatus.Success then
			z.waypoints = z.path:GetWaypoints()
			z.waypointIndex = 2
			z.pathGoal = goal
		else
			z.waypoints = nil
		end
	end
	local waypoints = z.waypoints
	if waypoints then
		local waypoint = waypoints[z.waypointIndex]
		while waypoint and CombatUtil.flatDistance(z.root.Position, waypoint.Position) < WAYPOINT_REACHED do
			z.waypointIndex += 1
			waypoint = waypoints[z.waypointIndex]
		end
		if waypoint then
			z.humanoid:MoveTo(waypoint.Position)
			return
		end
	end
	z.humanoid:MoveTo(goal) -- budget exhausted or no path: direct fallback
end

local function moveTowards(z: Zombie, goal: Vector3, now: number)
	local position = z.root.Position
	local flatGoal = Vector3.new(goal.X, position.Y, goal.Z)
	if not Arena.isInside(flatGoal, -3) then
		flatGoal = Vector3.new(0, position.Y, 0):Lerp(flatGoal, 0.85)
	end
	local distance = (flatGoal - position).Magnitude
	if distance < 0.8 then
		z.humanoid:MoveTo(position)
		return
	end
	if distance <= CombatConfig.ZombieDirectMoveDistance and CombatUtil.hasLineOfSight(position, flatGoal, ignoreList(nil)) then
		z.waypoints = nil
		z.humanoid:MoveTo(flatGoal)
	else
		followPath(z, flatGoal, now)
	end
end

local function checkStuck(z: Zombie, now: number, wantsToMove: boolean)
	if now - z.lastSampleTime < STUCK_SAMPLE_SECONDS then
		return
	end
	local moved = CombatUtil.flatDistance(z.root.Position, z.lastSamplePosition)
	z.lastSamplePosition = z.root.Position
	z.lastSampleTime = now
	if not wantsToMove or moved > 0.8 then
		z.stuckCount = 0
		return
	end
	z.stuckCount += 1
	z.waypoints = nil
	if z.stuckCount >= 5 then
		z.stuckCount = 0
		z.root.AssemblyLinearVelocity = Vector3.zero
		local height = z.humanoid.HipHeight + z.root.Size.Y / 2
		z.model:PivotTo(CFrame.new(Arena.getSafePoint(z.root.Position) + Vector3.new(0, height, 0)))
	elseif z.stuckCount >= 2 then
		z.unstickGoal = z.root.Position + z.root.CFrame.RightVector * (if z.rng:NextNumber() < 0.5 then -5 else 5)
		z.unstickUntil = now + 0.7
	end
end

------------------------------------------------------------------------------------------
-- Guard, attacks and abilities
------------------------------------------------------------------------------------------

local function endGuard(z: Zombie)
	if not z.guarding then
		return
	end
	z.guarding = false
	if z.rig.guardGlow then
		z.rig.guardGlow.Enabled = false
	end
	if z.alive then
		setPose(z.rig.leftShoulder, z.rig.leftShoulderRest, 0, 0.25)
	end
end

local function startGuard(z: Zombie, now: number, seconds: number, cooldown: number)
	z.guarding = true
	z.guardUntil = now + seconds
	z.guardReadyAt = z.guardUntil + cooldown
	setPose(z.rig.leftShoulder, z.rig.leftShoulderRest, 75, 0.2) -- telegraph: shield raised
	if z.rig.guardGlow then
		z.rig.guardGlow.Enabled = true
	end
	CombatEffects.glow(z.model, Color3.fromRGB(255, 220, 120), math.min(seconds, 0.4))
end

-- RootJoint rest pose for the zombie's current condition (crawl pose after losing a leg).
local function restPose(z: Zombie): CFrame
	if z.crawling then
		return z.rig.rootJointRest * CFrame.new(0, -0.7, 0) * CFrame.Angles(math.rad(-38), 0, math.rad(6))
	end
	return z.rig.rootJointRest * ZombieDamageStateService.postureOffset(z.condition)
end

local function pushBack(z: Zombie, fromPosition: Vector3, speed: number, stagger: number)
	local away = CombatUtil.flat(z.root.Position - fromPosition)
	if away.Magnitude < 0.01 then
		away = -z.root.CFrame.LookVector
	end
	z.stunnedUntil = math.max(z.stunnedUntil, os.clock() + stagger)
	z.humanoid:MoveTo(z.root.Position)
	z.root.AssemblyLinearVelocity = away.Unit * speed * z.definition.KnockbackMultiplier + Vector3.new(0, 6, 0)
end

type AttackStyle = "Normal" | "Bash"

local function performAttack(z: Zombie, player: Player, style: AttackStyle)
	local def = z.definition
	local profile = z.profile
	local mods = z.mods
	z.busy = true
	z.lastAttack = os.clock()
	endGuard(z)

	local finish = function()
		z.busy = false
		ZombieCrowdService.endAttack(z)
	end

	-- Optional roar (Brute) or a critical brute's last heavy swing: extra, very visible telegraphs
	local heavy = style == "Normal" and not z.unarmed and mods.HeavySwingChance > 0 and z.rng:NextNumber() < mods.HeavySwingChance
	if style == "Normal" and not z.unarmed and (heavy or (profile.RoarChance > 0 and z.rng:NextNumber() < profile.RoarChance)) then
		setPose(z.rig.rightShoulder, z.rig.rightShoulderRest, 120, 0.2)
		if z.canBlock then
			setPose(z.rig.leftShoulder, z.rig.leftShoulderRest, 120, 0.2)
		end
		CombatEffects.ring(z.root.Position - Vector3.new(0, z.humanoid.HipHeight, 0), if heavy then 8 else 6, Color3.fromRGB(255, 120, 80))
		if heavy then
			CombatEffects.glow(z.model, Color3.fromRGB(255, 120, 80), 0.9)
		end
		task.wait(if heavy then 0.8 else 0.5)
		setPose(z.rig.leftShoulder, z.rig.leftShoulderRest, 0, 0.2)
		if not z.alive then
			finish()
			return
		end
	end

	-- Telegraph: weapon raised, shield pulled back for a bash, or head drawn back for a bite
	local windUp = def.WindUpSeconds * (if z.unarmed then 1.2 else 1)
	if z.unarmed then
		TweenService:Create(z.rig.rootJoint, TweenInfo.new(windUp * 0.8, Enum.EasingStyle.Quad), { C0 = z.rig.rootJointRest * CFrame.Angles(math.rad(15), 0, 0) }):Play()
	elseif style == "Bash" then
		setPose(z.rig.leftShoulder, z.rig.leftShoulderRest, 40, windUp * 0.8)
	else
		setPose(z.rig.rightShoulder, z.rig.rightShoulderRest, 150, windUp * 0.85)
	end
	task.wait(windUp)
	if not z.alive then
		finish()
		return
	end
	if z.unarmed then
		TweenService:Create(z.rig.rootJoint, TweenInfo.new(0.1, Enum.EasingStyle.Quad), { C0 = z.rig.rootJointRest * CFrame.Angles(math.rad(-35), 0, 0) }):Play()
	elseif style == "Bash" then
		setPose(z.rig.leftShoulder, z.rig.leftShoulderRest, 95, 0.1)
	else
		setPose(z.rig.rightShoulder, z.rig.rightShoulderRest, 25, 0.1)
	end

	-- Re-validate everything at the moment the blow lands (a dead zombie never deals damage)
	local landed = false
	local character, _, targetRoot = CombatUtil.getLivingCharacter(player)
	if z.alive and character and targetRoot and isValidTarget(player) then
		local inReach = CombatUtil.flatDistance(z.root.Position, targetRoot.Position) <= attackReach(z)
			and math.abs(z.root.Position.Y - targetRoot.Position.Y) <= 6
		local eye = z.root.Position + Vector3.new(0, 1.5, 0)
		if inReach and CombatUtil.hasLineOfSight(eye, targetRoot.Position, ignoreList(character)) then
			local multiplier = if style == "Bash" then 0.6 elseif z.unarmed then 0.55 elseif heavy then 1.4 else 1
			local damage = math.max(1, math.floor(def.Damage * multiplier * CombatConfig.ZombieDamageMultiplier + 0.5))
			local pierce = if style == "Bash" then 0.8 elseif heavy then math.max(profile.BlockPierce, 0.6) else profile.BlockPierce
			local knockback = if style == "Bash" then 25 elseif heavy then 20 else 0
			local hit, blocked, staggerMultiplier = getHandlers().hitPlayer(player, z.root.Position, damage, pierce, knockback)
			landed = hit
			if hit and blocked then
				ZombieThreatService.add(z, player, 5) -- blocking draws a little attention
				if style ~= "Bash" then
					pushBack(z, targetRoot.Position, CombatConfig.ShieldPushBackSpeed * staggerMultiplier, def.StaggerSeconds * staggerMultiplier)
				end
			end
		end
	end

	task.wait(0.25)
	if z.alive then
		setPose(z.rig.rightShoulder, z.rig.rightShoulderRest, 0, 0.3)
		setPose(z.rig.leftShoulder, z.rig.leftShoulderRest, 0, 0.3)
		if z.unarmed then
			TweenService:Create(z.rig.rootJoint, TweenInfo.new(0.3), { C0 = restPose(z) }):Play()
		end
		local now = os.clock()
		if not landed and profile.ExposedAfterMiss > 0 then
			-- Champion: a failed heavy attack leaves it open
			z.stunnedUntil = math.max(z.stunnedUntil, now + profile.ExposedAfterMiss)
			z.guardReadyAt = math.max(z.guardReadyAt, now + profile.ExposedAfterMiss + 1)
		end
		if heavy then
			z.stunnedUntil = math.max(z.stunnedUntil, now + 0.8) -- a big swing leaves it slow to recover
		end
		if def.Special == "Guard" then
			z.guardReadyAt = math.max(z.guardReadyAt, now + 2)
		end
		local retreat = profile.RetreatAfterAttack + mods.RetreatAdd
		if retreat > 0 then
			z.retreatUntil = now + retreat
			ZombieCrowdService.releaseSlot(z)
		elseif mods.ComboChance > 0 and z.rng:NextNumber() < mods.ComboChance then
			-- Desperate short combination: the next strike may follow almost immediately
			z.lastAttack = now - def.AttackCooldown * mods.CooldownMultiplier + 0.3
		end
	end
	finish()
end

local function throwNet(z: Zombie, player: Player)
	local def = z.definition
	z.busy = true
	z.netReadyAt = os.clock() + (def.NetCooldown or 7) * z.mods.NetCooldownMultiplier
	setPose(z.rig.leftShoulder, z.rig.leftShoulderRest, 160, (def.NetWindUp or 0.7) * 0.8)
	task.wait(def.NetWindUp or 0.7)
	if not z.alive then
		ZombieCrowdService.endAttack(z)
		return
	end
	setPose(z.rig.leftShoulder, z.rig.leftShoulderRest, 40, 0.12)
	local character, _, targetRoot = CombatUtil.getLivingCharacter(player)
	if character and targetRoot and isValidTarget(player) then
		local from = z.root.Position + Vector3.new(0, 1.5, 0)
		local inRange = (targetRoot.Position - z.root.Position).Magnitude <= (def.NetRange or 13) + 1
		if inRange and CombatUtil.hasLineOfSight(from, targetRoot.Position, ignoreList(character)) then
			CombatEffects.netThrow(from, targetRoot.Position + Vector3.new(0, 1.5, 0))
			getHandlers().slowPlayer(player, def.NetSlowFactor or 0.75, def.NetSlowSeconds or 2)
		end
	end
	task.wait(0.3)
	if z.alive then
		setPose(z.rig.leftShoulder, z.rig.leftShoulderRest, 0, 0.3)
	end
	z.busy = false
	ZombieCrowdService.endAttack(z)
end

------------------------------------------------------------------------------------------
-- Think
------------------------------------------------------------------------------------------

-- Long weapons stand farther out on the crowd ring, so the stopping distance matches the reach.
local function slotRadius(z: Zombie): number
	return math.clamp(attackRange(z) - 2.5, CombatConfig.CrowdSlotRadius, CombatConfig.CrowdSlotMaxRadius)
end

-- Shared helpers for ZombieArcherAI (passed in, so the archer module never requires this one).
local toolkit = {
	moveTowards = moveTowards,
	faceTowards = faceTowards,
	checkStuck = checkStuck,
	isValidTarget = isValidTarget,
	ignoreList = ignoreList,
	separation = separation,
	setPose = setPose,
	handlers = function(): Handlers
		return getHandlers()
	end,
	zombiesNear = function(position: Vector3, radius: number, except: any): number
		local count = 0
		for _, other in registry do
			if other ~= except and other.alive and CombatUtil.flatDistance(other.root.Position, position) <= radius then
				count += 1
			end
		end
		return count
	end,
	-- Weak close-range strike (cornered archer); false if the attack token isn't available
	melee = function(z: Zombie, player: Player): boolean
		if ZombieCrowdService.tryStartAttack(z, player) then
			z.humanoid:MoveTo(z.root.Position)
			task.spawn(function()
				performAttack(z, player, "Normal")
			end)
			return true
		end
		return false
	end,
}

local function think(z: Zombie)
	local now = os.clock()
	local def = z.definition
	local profile = z.profile
	if z.guarding and now >= z.guardUntil then
		endGuard(z)
	end
	local mods = z.mods
	z.humanoid.WalkSpeed = walkSpeed(z, now)
	if z.busy or now < z.stunnedUntil then
		return
	end
	if now < z.unstickUntil then
		z.humanoid:MoveTo(z.unstickGoal)
		return
	end
	if now >= z.nextDriftChange then
		z.nextDriftChange = now + profile.DriftChangeInterval * (0.7 + z.rng:NextNumber() * 0.6)
		if z.rng:NextNumber() < profile.CircleTendency then
			z.drift = -z.drift
		end
	end
	if def.Special == "Archer" and not z.unarmed then
		ZombieArcherAI.think(z, toolkit, now) -- ranged AI on the shared movement helpers
		return
	end

	local player, targetRoot = pickTarget(z, now)
	if not player or not targetRoot then
		ZombieCrowdService.release(z)
		z.waypoints = nil
		-- Nothing to chase (e.g. a brute with no one nearby): drift slowly toward the center
		if CombatUtil.flatDistance(z.root.Position, Arena.Layout.Center) > 20 then
			moveTowards(z, Arena.Layout.Center, now)
		else
			z.humanoid:MoveTo(z.root.Position)
		end
		checkStuck(z, now, false)
		return
	end

	local character = player.Character
	local position = z.root.Position
	local targetPosition = targetRoot.Position
	local distance = CombatUtil.flatDistance(position, targetPosition)
	local eye = position + Vector3.new(0, 1.5, 0)
	local canSee = CombatUtil.hasLineOfSight(eye, targetPosition, ignoreList(character))
	local netReady = def.Special == "Net" and z.canBlock and now >= z.netReadyAt

	-- Abilities
	if netReady and distance >= 5 and distance <= (def.NetRange or 13) and canSee and ZombieCrowdService.tryStartAttack(z, player) then
		faceTowards(z, targetPosition)
		z.humanoid:MoveTo(position)
		task.spawn(throwNet, z, player)
		return
	end
	if z.canBlock and mods.BlockMultiplier > 0 and not z.guarding and now >= z.guardReadyAt and distance <= 14 then
		if def.Special == "Guard" then
			startGuard(z, now, def.GuardSeconds or profile.GuardSeconds, (def.GuardCooldown or 4) / mods.BlockMultiplier)
		elseif profile.BlockChance > 0 then
			z.guardReadyAt = now + 3 -- roll again in a few seconds
			if z.rng:NextNumber() < profile.BlockChance * mods.BlockMultiplier then
				startGuard(z, now, profile.GuardSeconds, 2)
			end
		end
	end

	-- Crowd slot (some personalities stay out of melee for a while)
	local retreating = now < z.retreatUntil
	local cornered = distance <= 4.5
	local keepDistance = (profile.AvoidSlotsUntilAbilityUsed and netReady) or (mods.AvoidMelee and not cornered)
	local avoidShield = profile.AvoidHeavyShields and getHandlers().isHeavyBlocking(player) and getHandlers().isBlockingToward(player, position)
	local slot: number? = nil
	if distance <= CombatConfig.CrowdApproachRadius and not retreating and not keepDistance then
		slot = ZombieCrowdService.claimSlot(z, player, targetRoot, position)
	else
		ZombieCrowdService.releaseSlot(z)
	end

	-- Attack from a slot
	if slot and distance <= attackRange(z) and canSee and not avoidShield then
		faceTowards(z, targetPosition)
		if not z.guarding and now - z.lastAttack >= def.AttackCooldown * mods.CooldownMultiplier and now >= z.attackDelayUntil then
			if z.rng:NextNumber() > profile.Aggression + mods.AggressionAdd then
				z.attackDelayUntil = now + 0.4 -- hesitates
			elseif getHandlers().isBlockingToward(player, position) then
				local bashChance = if z.canBlock and not z.unarmed then profile.ShieldBashChance + mods.BashChanceAdd else 0
				if bashChance > 0 and z.rng:NextNumber() < bashChance then
					if ZombieCrowdService.tryStartAttack(z, player) then
						z.humanoid:MoveTo(position)
						task.spawn(function()
							performAttack(z, player, "Bash")
						end)
						return
					end
				elseif profile.BlockPierce <= 0 and z.rng:NextNumber() < 0.5 then
					-- Most zombies hesitate against a raised shield and try a neighbouring slot
					z.attackDelayUntil = now + 0.6
					ZombieCrowdService.shiftSlot(z, if z.drift > 0 then 1 else -1)
				elseif ZombieCrowdService.tryStartAttack(z, player) then
					z.humanoid:MoveTo(position)
					task.spawn(function()
					performAttack(z, player, "Normal")
				end)
					return
				end
			elseif ZombieCrowdService.tryStartAttack(z, player) then
				z.humanoid:MoveTo(position)
				task.spawn(function()
					performAttack(z, player, "Normal")
				end)
				return
			end
		end
	end

	-- Movement goal
	local goal: Vector3
	if avoidShield then
		-- Skirmisher: get around a big raised shield instead of attacking into it
		local behind = -CombatUtil.flat(targetRoot.CFrame.LookVector)
		local side = CombatUtil.flat(targetRoot.CFrame.RightVector) * (if z.drift > 0 then 1 else -1)
		goal = targetPosition + (behind + side).Unit * CombatConfig.CrowdSlotRadius
	elseif keepDistance and profile.PreferredDistance > 0 then
		local away = CombatUtil.flat(position - targetPosition)
		local direction = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
		goal = targetPosition + CFrame.fromAxisAngle(Vector3.yAxis, z.drift * 0.6):VectorToWorldSpace(direction) * (profile.PreferredDistance + mods.PreferredDistanceAdd)
	elseif slot then
		goal = ZombieCrowdService.slotPosition(targetRoot, slot, slotRadius(z))
	elseif retreating or distance <= CombatConfig.CrowdApproachRadius + 2 then
		local drift = z.drift * (0.15 + 0.5 * profile.CircleTendency)
		goal = ZombieCrowdService.waitPosition(targetRoot, position, drift)
	else
		goal = targetPosition
	end
	if profile.YieldToHeavies then
		local away = heavyNearby(z)
		if away then
			goal += away * 4
		end
	end
	goal += separation(z)

	local wantsToMove = CombatUtil.flatDistance(position, goal) > 1.5
	if wantsToMove then
		moveTowards(z, goal, now)
	else
		z.humanoid:MoveTo(position)
		faceTowards(z, targetPosition)
	end
	checkStuck(z, now, wantsToMove)
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------

local function cleanup(z: Zombie)
	z.alive = false
	CollectionService:RemoveTag(z.model, CombatConfig.ZombieTag)
	for _, connection in z.connections do
		connection:Disconnect()
	end
	table.clear(z.connections)
	ZombieCrowdService.release(z)
	ZombieThreatService.release(z)
	ZombieArcherAI.release(z)
	registry[z.model] = nil
end

local function onDied(z: Zombie)
	if not z.alive then
		return
	end
	local damagers = {}
	for player in z.damagers do
		table.insert(damagers, player)
	end
	cleanup(z)
	updateHealth(z, 0)
	endGuard(z)
	z.rig.hitSparks.Enabled = false
	z.rig.deathPuff.Enabled = true
	z.root.Anchored = true -- the corpse no longer blocks anything
	z.root.CanCollide = false
	z.root.CanQuery = false
	task.spawn(function()
		local steps = 5
		for step = 1, steps do
			task.wait(CombatConfig.ZombieDespawnSeconds / steps)
			for _, part in z.rig.visibleParts do
				part.Transparency = math.max(part.Transparency, step / steps)
			end
			if step == 2 then
				z.rig.deathPuff.Enabled = false
			end
		end
		z.model:Destroy()
	end)
	local callback = z.onDied
	z.onDied = nil
	if callback then
		callback(z, z.lastAttacker, damagers)
	end
end

local function setupCollisionGroup()
	local group = CombatConfig.ZombieCollisionGroup
	if not PhysicsService:IsCollisionGroupRegistered(group) then
		PhysicsService:RegisterCollisionGroup(group)
	end
	-- Solid bodies: zombies collide with the world, players and each other
	PhysicsService:CollisionGroupSetCollidable(group, "Default", true)
	PhysicsService:CollisionGroupSetCollidable(group, group, true)
end

function ZombieService.init(folder: Instance, newHandlers: Handlers)
	zombiesFolder = folder
	handlers = newHandlers
	local ok: boolean, err: any = (pcall :: any)(setupCollisionGroup)
	if not ok then
		warn(PREFIX, "Could not set up the zombie collision group:", err)
	end
end

-- Spawns one arena zombie. onDied(zombie, killer, damagers) fires exactly once on death
-- (never when removed by despawnAll).
function ZombieService.spawn(def: ZombieDefinition, cframe: CFrame, onDiedCallback: ((Zombie, Player?, { Player }) -> ())?): Zombie?
	local folder = zombiesFolder
	if not folder or not folder.Parent or not handlers then
		warn(PREFIX, "Cannot spawn zombie: ZombieService is not initialised")
		return nil
	end
	local profile = ZombieAIProfiles[def.AIProfile] or ZombieAIProfiles.Disciplined
	local rig = ZombieFactory.build(def)
	local scale = def.Body.Scale
	local now = os.clock()
	local rng = Random.new()
	local z: Zombie = {
		definition = def,
		profile = profile,
		rig = rig,
		model = rig.model,
		humanoid = rig.humanoid,
		root = rig.root,
		rng = rng,
		alive = true,
		busy = false,
		stunnedUntil = 0,
		slowUntil = 0,
		lastAttack = now - def.AttackCooldown * 0.5,
		attackDelayUntil = 0,
		retreatUntil = 0,
		target = nil,
		nextRetarget = 0,
		drift = if rng:NextNumber() < 0.5 then -1 else 1,
		nextDriftChange = now + profile.DriftChangeInterval,
		path = PathfindingService:CreatePath({ AgentRadius = 2 * scale, AgentHeight = 7 * scale, AgentCanJump = false, AgentCanClimb = false }),
		waypoints = nil,
		waypointIndex = 1,
		pathGoal = Vector3.zero,
		lastPathTime = 0,
		lastSamplePosition = cframe.Position,
		lastSampleTime = now,
		stuckCount = 0,
		unstickUntil = 0,
		unstickGoal = Vector3.zero,
		netReadyAt = now + 3,
		guarding = false,
		guardUntil = 0,
		guardReadyAt = now + 2,
		lastAttacker = nil,
		damagers = {},
		connections = {},
		onDied = onDiedCallback,
		flashToken = 0,
		condition = "Healthy",
		mods = ZombieDamageStateService.NeutralMods,
		limbs = { lost = {}, limbCount = 0, armorLost = 0 },
		unarmed = false,
		canBlock = true,
		crawling = false,
		burstUntil = 0,
		restUntil = 0,
		archer = nil,
	}
	rig.root.CollisionGroup = CombatConfig.ZombieCollisionGroup
	local height = rig.humanoid.HipHeight + rig.root.Size.Y / 2
	z.model:PivotTo(cframe + Vector3.new(0, height, 0))
	z.model.Parent = folder
	z.root:SetNetworkOwner(nil) -- the server simulates zombies; clients can't move them

	table.insert(z.connections, z.humanoid.Died:Connect(function()
		onDied(z)
	end))
	table.insert(z.connections, z.humanoid.HealthChanged:Connect(function(health)
		updateHealth(z, health)
	end))
	registry[z.model] = z
	CollectionService:AddTag(z.model, CombatConfig.ZombieTag)

	task.spawn(function()
		task.wait(rng:NextNumber() * CombatConfig.ZombieThinkInterval) -- staggered AI updates
		while z.alive do
			think(z)
			task.wait(CombatConfig.ZombieThinkInterval)
		end
	end)
	return z
end

function ZombieService.getByModel(model: Instance): Zombie?
	local z = registry[model :: any]
	if z and z.alive and z.humanoid.Health > 0 then
		return z
	end
	return nil
end

function ZombieService.healthFraction(z: Zombie): number
	return z.humanoid.Health / math.max(1, z.humanoid.MaxHealth)
end

-- Guard (Legion occasionally, Champion regularly): blocks hits from the front.
function ZombieService.tryGuardBlock(z: Zombie, attackerPosition: Vector3): boolean
	if not z.alive or not z.canBlock or not z.guarding or os.clock() >= z.guardUntil then
		return false
	end
	if not CombatUtil.isFacing(z.root.CFrame, attackerPosition, 0.35) then
		return false -- side and rear attacks bypass the shield
	end
	flash(z, Color3.fromRGB(255, 220, 120))
	return true
end

-- Applies server-validated damage plus a short stagger and controlled knockback.
-- GUARD BREAK combos: a raised guard is broken (true) and the zombie can't guard for a while.
function ZombieService.breakGuard(z: Zombie): boolean
	if not z.alive or not z.guarding then
		return false
	end
	endGuard(z)
	z.guardReadyAt = math.max(z.guardReadyAt, os.clock() + 4)
	z.stunnedUntil = math.max(z.stunnedUntil, os.clock() + 1)
	CombatEffects.burst(z.root.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 150, 80), 1)
	return true
end

-- Lost armor makes a zombie a little easier to hurt.
function ZombieService.damageMultiplier(z: Zombie): number
	return 1 + math.min(DamageEffectsConfig.MaxArmorDamageBonus, z.limbs.armorLost * DamageEffectsConfig.ArmorLostDamageBonus)
end

-- Gameplay consequences of a lost limb (ZombieDismembermentService handles the visuals).
local function onLimbLost(z: Zombie, key: string)
	local weaponArm = if z.definition.Special == "Archer" then (key == "LeftArm" or key == "RightArm") else key == "RightArm"
	if weaponArm then
		z.unarmed = true -- weak bites and kicks from now on
	end
	if key == "LeftArm" and z.definition.Special ~= "Archer" then
		z.canBlock = false -- no guard, no shield bash, no net
		endGuard(z)
	end
	if key == "RightLeg" or key == "LeftLeg" then
		z.crawling = true
		z.model:SetAttribute("Crawl", true) -- the client animator drags the remaining leg
		TweenService:Create(z.rig.rootJoint, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { C0 = restPose(z) }):Play()
		z.waypoints = nil
	end
	z.stunnedUntil = math.max(z.stunnedUntil, os.clock() + 0.5)
end

function ZombieService.applyDamage(z: Zombie, attacker: Player, amount: number, fromPosition: Vector3, stagger: number, knockback: number, extra: DamageExtra?): boolean
	if not z.alive or z.humanoid.Health <= 0 then
		return false
	end
	z.lastAttacker = attacker
	z.damagers[attacker] = true
	ZombieThreatService.add(z, attacker, amount)
	flash(z, Color3.new(1, 1, 1))
	local hitPosition = if extra and extra.hitPosition then extra.hitPosition else z.root.Position + Vector3.new(0, 1, 0)
	DamageEffectsService.hit("Zombie", hitPosition, math.clamp(amount / 30, 0.4, 1.5), CombatUtil.flat(z.root.Position - fromPosition))
	z.humanoid:TakeDamage(amount)
	if z.alive and z.humanoid.Health > 0 then
		local lost = ZombieDismembermentService.tryDismember(z.rig, z.limbs, {
			damage = amount,
			fractionAfter = z.humanoid.Health / math.max(1, z.humanoid.MaxHealth),
			weaponId = extra and extra.weaponId,
			isSpecial = extra ~= nil and extra.isSpecial == true,
			spin = extra ~= nil and extra.spin == true,
			hitPosition = extra and extra.hitPosition,
			fromPosition = fromPosition,
			rng = z.rng,
		})
		if lost then
			onLimbLost(z, lost)
		end
	end
	if z.alive and z.humanoid.Health > 0 and (stagger > 0 or knockback > 0) then
		local away = CombatUtil.flat(z.root.Position - fromPosition)
		if away.Magnitude > 0.01 then
			z.root.AssemblyLinearVelocity = away.Unit * knockback * z.definition.KnockbackMultiplier
		end
		if not z.busy then
			z.stunnedUntil = math.max(z.stunnedUntil, os.clock() + stagger * z.definition.KnockbackMultiplier)
		end
	end
	return true
end

function ZombieService.applySlow(z: Zombie, _factor: number, seconds: number)
	if z.alive then
		z.slowUntil = math.max(z.slowUntil, os.clock() + seconds)
		z.stunnedUntil = math.max(z.stunnedUntil, os.clock() + math.min(0.5, seconds))
	end
end

-- Healing near zombies draws a little attention.
function ZombieService.onPlayerHealed(player: Player, amount: number)
	local _, _, root = CombatUtil.getLivingCharacter(player)
	if not root then
		return
	end
	for _, z in registry do
		if (z.root.Position - root.Position).Magnitude < 25 then
			ZombieThreatService.add(z, player, amount * 2)
		end
	end
end

-- Removes every zombie immediately without death callbacks (aborted match / cleanup).
function ZombieService.despawnAll()
	local all = {}
	for _, z in registry do
		table.insert(all, z)
	end
	for _, z in all do
		z.onDied = nil
		cleanup(z)
		z.model:Destroy()
	end
	ZombieCrowdService.reset()
	ZombieThreatService.reset()
end

function ZombieService.countAliveOf(definitionId: string): number
	local count = 0
	for _, z in registry do
		if z.alive and z.definition.Id == definitionId then
			count += 1
		end
	end
	return count
end

function ZombieService.countAlive(): number
	local count = 0
	for _ in registry do
		count += 1
	end
	return count
end

return ZombieService
