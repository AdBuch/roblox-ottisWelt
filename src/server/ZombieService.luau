--!strict
-- Runs every zombie independently: each one has its own AI loop, health, target, path,
-- cooldowns and event connections, all cleaned up when it dies. Living zombies carry the
-- CollectionService tag CombatConfig.ZombieTag; dead ones lose it immediately, so combat
-- code never sees a dead zombie as a valid target.
--
-- AI per tick (CombatConfig.ZombieThinkInterval):
--   target   nearest fighter inside the arena (re-evaluated every ZombieRetargetInterval)
--   crowd    claim a melee slot when close (ZombieCrowdService), otherwise circle further out
--   attack   only from a slot, in range, with line of sight and an attack token (max 4 at once);
--            every attack has a visible wind-up and is re-validated when it lands
--   move     direct MoveTo when the goal is visible and near, PathfindingService otherwise;
--            separation steering keeps bodies apart; stuck detection sidesteps or relocates
--   special  Net Fighter: telegraphed net throw (slow). Champion: telegraphed shield guard.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local ZombieDefinitions = require(ReplicatedStorage.Shared.ZombieDefinitions)
local Arena = require(script.Parent.Arena)
local CombatUtil = require(script.Parent.CombatUtil)
local ZombieCrowdService = require(script.Parent.ZombieCrowdService)
local ZombieFactory = require(script.Parent.ZombieFactory)

type ZombieDefinition = ZombieDefinitions.ZombieDefinition

export type Zombie = {
	definition: ZombieDefinition,
	rig: ZombieFactory.ZombieRig,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	rng: Random,
	alive: boolean,
	busy: boolean, -- attacking or throwing a net
	stunnedUntil: number,
	lastAttack: number,
	attackDelayUntil: number,
	target: Player?,
	nextRetarget: number,
	drift: number,
	-- pathing
	path: Path,
	waypoints: { PathWaypoint }?,
	waypointIndex: number,
	pathGoal: Vector3,
	lastPathTime: number,
	-- stuck detection
	lastSamplePosition: Vector3,
	lastSampleTime: number,
	stuckCount: number,
	unstickUntil: number,
	unstickGoal: Vector3,
	-- specials
	netReadyAt: number,
	guarding: boolean,
	guardUntil: number,
	guardReadyAt: number,
	-- bookkeeping
	lastAttacker: Player?,
	connections: { RBXScriptConnection },
	onDied: ((Zombie, Player?) -> ())?,
	flashToken: number,
}

export type Handlers = {
	getTargets: () -> { Player }, -- players zombies may attack (the active fighter)
	hitPlayer: (player: Player, attackerPosition: Vector3, damage: number) -> (boolean, boolean, number), -- landed, blocked, staggerMultiplier
	isBlockingToward: (player: Player, position: Vector3) -> boolean,
	slowPlayer: (player: Player, factor: number, seconds: number) -> (),
}

local PREFIX = "[OttiArena][Server]"
local WAYPOINT_REACHED = 2.5
local STUCK_SAMPLE_SECONDS = 1.2

local ZombieService = {}

local zombiesFolder: Instance? = nil
local handlers: Handlers? = nil
local registry: { [Model]: Zombie } = {}

local function setPose(motor: Motor6D, rest: CFrame, angleDegrees: number, seconds: number)
	local goal = { C0 = rest * CFrame.Angles(math.rad(angleDegrees), 0, 0) }
	TweenService:Create(motor, TweenInfo.new(seconds, Enum.EasingStyle.Quad), goal):Play()
end

local function updateHealth(z: Zombie, health: number)
	z.model:SetAttribute("Health", math.max(0, math.ceil(health)))
	z.rig.healthFill.Size = UDim2.fromScale(math.clamp(health / z.definition.Health, 0, 1), 1)
end

local function flash(z: Zombie, color: Color3)
	z.flashToken += 1
	local token = z.flashToken
	-- Highlights are created on demand: Roblox renders only ~31 at a time
	local highlight = Instance.new("Highlight")
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
	-- Zombies never block each other's line of sight; only walls and solid geometry do
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

local function getHandlers(): Handlers
	return handlers :: Handlers
end

-- Nearest valid fighter inside the arena; keeps the current target between re-evaluations.
local function pickTarget(z: Zombie, now: number): (Player?, BasePart?)
	local current = z.target
	if current and now < z.nextRetarget then
		local _, _, root = CombatUtil.getLivingCharacter(current)
		if root and Arena.isInside(root.Position) and table.find(getHandlers().getTargets(), current) then
			return current, root
		end
	end
	z.nextRetarget = now + CombatConfig.ZombieRetargetInterval

	local bestPlayer, bestRoot, bestDistance = nil, nil, CombatConfig.ZombieDetectRadius
	for _, player in getHandlers().getTargets() do
		local _, _, root = CombatUtil.getLivingCharacter(player)
		if root and Arena.isInside(root.Position) then
			local distance = (root.Position - z.root.Position).Magnitude
			if distance <= bestDistance then
				bestPlayer, bestRoot, bestDistance = player, root, distance
			end
		end
	end
	if bestPlayer ~= z.target then
		ZombieCrowdService.release(z)
	end
	z.target = bestPlayer
	return bestPlayer, bestRoot
end

-- Push away from nearby zombies so bodies never stack on one point.
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

local function pushBack(z: Zombie, fromPosition: Vector3, speed: number, stagger: number)
	local away = CombatUtil.flat(z.root.Position - fromPosition)
	if away.Magnitude < 0.01 then
		away = -z.root.CFrame.LookVector
	end
	z.stunnedUntil = math.max(z.stunnedUntil, os.clock() + stagger)
	z.humanoid:MoveTo(z.root.Position)
	z.root.AssemblyLinearVelocity = away.Unit * speed * z.definition.KnockbackMultiplier + Vector3.new(0, 6, 0)
end

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

local function startGuard(z: Zombie, now: number)
	local def = z.definition
	z.guarding = true
	z.guardUntil = now + (def.GuardSeconds or 1.5)
	z.guardReadyAt = z.guardUntil + (def.GuardCooldown or 4)
	-- Telegraph: shield raised in front + golden glow
	setPose(z.rig.leftShoulder, z.rig.leftShoulderRest, 75, 0.2)
	if z.rig.guardGlow then
		z.rig.guardGlow.Enabled = true
	end
end

local function performAttack(z: Zombie, player: Player)
	local def = z.definition
	z.busy = true
	z.lastAttack = os.clock()
	endGuard(z)

	-- Telegraph: raise the weapon arm overhead
	setPose(z.rig.rightShoulder, z.rig.rightShoulderRest, 150, def.WindUpSeconds * 0.85)
	task.wait(def.WindUpSeconds)
	if not z.alive then
		ZombieCrowdService.endAttack(z)
		return
	end
	setPose(z.rig.rightShoulder, z.rig.rightShoulderRest, 25, 0.1)

	-- Re-validate everything at the moment the blow lands
	local character, _, targetRoot = CombatUtil.getLivingCharacter(player)
	if character and targetRoot and table.find(getHandlers().getTargets(), player) then
		local inReach = CombatUtil.flatDistance(z.root.Position, targetRoot.Position) <= def.AttackReach
			and math.abs(z.root.Position.Y - targetRoot.Position.Y) <= 6
		local eye = z.root.Position + Vector3.new(0, 1.5, 0)
		if inReach and CombatUtil.hasLineOfSight(eye, targetRoot.Position, ignoreList(character)) then
			local damage = math.max(1, math.floor(def.Damage * CombatConfig.ZombieDamageMultiplier + 0.5))
			local landed, blocked, staggerMultiplier = getHandlers().hitPlayer(player, z.root.Position, damage)
			if landed and blocked then
				pushBack(z, targetRoot.Position, CombatConfig.ShieldPushBackSpeed * staggerMultiplier, def.StaggerSeconds * staggerMultiplier)
			end
		end
	end

	task.wait(0.25)
	if z.alive then
		setPose(z.rig.rightShoulder, z.rig.rightShoulderRest, 0, 0.3)
		if def.Special == "Guard" then
			-- Exposed right after attacking
			z.guardReadyAt = math.max(z.guardReadyAt, os.clock() + 2)
		end
	end
	z.busy = false
	ZombieCrowdService.endAttack(z)
end

local function throwNet(z: Zombie, player: Player)
	local def = z.definition
	z.busy = true
	z.netReadyAt = os.clock() + (def.NetCooldown or 7)

	-- Telegraph: raise the net arm and swirl it
	setPose(z.rig.leftShoulder, z.rig.leftShoulderRest, 160, (def.NetWindUp or 0.7) * 0.8)
	task.wait(def.NetWindUp or 0.7)
	if not z.alive then
		ZombieCrowdService.endAttack(z)
		return
	end
	setPose(z.rig.leftShoulder, z.rig.leftShoulderRest, 40, 0.12)

	local character, _, targetRoot = CombatUtil.getLivingCharacter(player)
	if character and targetRoot and table.find(getHandlers().getTargets(), player) then
		local from = z.root.Position + Vector3.new(0, 1.5, 0)
		local inRange = (targetRoot.Position - z.root.Position).Magnitude <= (def.NetRange or 13) + 1
		if inRange and CombatUtil.hasLineOfSight(from, targetRoot.Position, ignoreList(character)) then
			-- Visual: a net flies to the player (anchored, no physics)
			local net = Instance.new("Part")
			net.Name = "ThrownNet"
			net.Anchored = true
			net.CanCollide = false
			net.CanQuery = false
			net.CanTouch = false
			net.Size = Vector3.new(3, 0.2, 3)
			net.Color = Color3.fromRGB(196, 182, 150)
			net.Material = Enum.Material.Fabric
			net.Transparency = 0.25
			net.CFrame = CFrame.new(from)
			net.Parent = Workspace
			TweenService:Create(net, TweenInfo.new(0.25), { CFrame = CFrame.new(targetRoot.Position + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, math.rad(45), 0) }):Play()
			task.delay(0.6, function()
				net:Destroy()
			end)
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

local function followPath(z: Zombie, goal: Vector3, now: number)
	local needsPath = z.waypoints == nil
		or now - z.lastPathTime >= CombatConfig.ZombiePathInterval
		or (goal - z.pathGoal).Magnitude > 8
	if needsPath then
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
	z.humanoid:MoveTo(goal)
end

-- Moves toward a goal: direct when visible and near, pathfinding otherwise.
local function moveTowards(z: Zombie, goal: Vector3, now: number)
	local position = z.root.Position
	local flatGoal = Vector3.new(goal.X, position.Y, goal.Z)
	if not Arena.isInside(flatGoal, -3) then
		flatGoal = Vector3.new(0, position.Y, 0):Lerp(flatGoal, 0.85) -- keep goals on the arena floor
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

-- Detects zombies that want to move but don't: first sidestep, then relocate if it persists.
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
		local side = z.root.CFrame.RightVector * (if z.rng:NextNumber() < 0.5 then -5 else 5)
		z.unstickGoal = z.root.Position + side
		z.unstickUntil = now + 0.7
	end
end

local function think(z: Zombie)
	local now = os.clock()
	local def = z.definition
	if z.guarding and now >= z.guardUntil then
		endGuard(z)
	end
	if z.busy or now < z.stunnedUntil then
		return
	end
	if now < z.unstickUntil then
		z.humanoid:MoveTo(z.unstickGoal)
		return
	end

	local player, targetRoot = pickTarget(z, now)
	if not player or not targetRoot then
		ZombieCrowdService.release(z)
		z.waypoints = nil
		z.humanoid:MoveTo(z.root.Position)
		checkStuck(z, now, false)
		return
	end

	local character = player.Character
	local position = z.root.Position
	local targetPosition = targetRoot.Position
	local distance = CombatUtil.flatDistance(position, targetPosition)
	local eye = position + Vector3.new(0, 1.5, 0)
	local canSee = CombatUtil.hasLineOfSight(eye, targetPosition, ignoreList(character))

	-- Specials
	if def.Special == "Net" and now >= z.netReadyAt and distance >= 5 and distance <= (def.NetRange or 13) and canSee then
		if ZombieCrowdService.tryStartAttack(z, player) then
			faceTowards(z, targetPosition)
			z.humanoid:MoveTo(position)
			task.spawn(throwNet, z, player)
			return
		end
	end
	if def.Special == "Guard" and not z.guarding and now >= z.guardReadyAt and distance <= 14 then
		startGuard(z, now)
	end

	-- Crowd slot
	local slot: number? = nil
	if distance <= CombatConfig.CrowdApproachRadius then
		slot = ZombieCrowdService.claimSlot(z, player, targetRoot, position)
	else
		ZombieCrowdService.releaseSlot(z)
	end

	-- Attack from a slot
	if slot and distance <= def.AttackRange and canSee then
		faceTowards(z, targetPosition)
		if not z.guarding and now - z.lastAttack >= def.AttackCooldown and now >= z.attackDelayUntil then
			if getHandlers().isBlockingToward(player, position) and z.rng:NextNumber() < 0.5 then
				-- The player is blocking toward us: hesitate and try a neighbouring slot
				z.attackDelayUntil = now + 0.6
				ZombieCrowdService.shiftSlot(z, if z.rng:NextNumber() < 0.5 then -1 else 1)
			elseif ZombieCrowdService.tryStartAttack(z, player) then
				z.humanoid:MoveTo(position)
				task.spawn(performAttack, z, player)
				return
			end
		end
	end

	-- Movement goal: own slot, otherwise circle on the waiting ring, otherwise approach
	local goal: Vector3
	if slot then
		goal = ZombieCrowdService.slotPosition(targetRoot, slot)
	elseif distance <= CombatConfig.CrowdApproachRadius + 2 then
		goal = ZombieCrowdService.waitPosition(targetRoot, position, z.drift)
	else
		goal = targetPosition
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

-- Stops AI, disconnects events, releases crowd slots and removes the tag. Safe to call twice.
local function cleanup(z: Zombie)
	z.alive = false
	CollectionService:RemoveTag(z.model, CombatConfig.ZombieTag)
	for _, connection in z.connections do
		connection:Disconnect()
	end
	table.clear(z.connections)
	ZombieCrowdService.release(z)
	registry[z.model] = nil
end

local function onDied(z: Zombie)
	if not z.alive then
		return
	end
	cleanup(z)
	updateHealth(z, 0)
	endGuard(z)
	z.rig.nameTag.Enabled = false
	z.rig.hitSparks.Enabled = false
	z.rig.deathPuff.Enabled = true
	-- The corpse no longer blocks anything
	z.root.Anchored = true
	z.root.CanCollide = false
	z.root.CanQuery = false

	-- Short death effect: puff and fade out, then remove the model
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
		callback(z, z.lastAttacker)
	end
end

local function setupCollisionGroup()
	local group = CombatConfig.ZombieCollisionGroup
	if not PhysicsService:IsCollisionGroupRegistered(group) then
		PhysicsService:RegisterCollisionGroup(group)
	end
	-- Zombies collide with the world, players and each other (solid bodies, no merging)
	PhysicsService:CollisionGroupSetCollidable(group, "Default", true)
	PhysicsService:CollisionGroupSetCollidable(group, group, true)
end

function ZombieService.init(folder: Instance, newHandlers: Handlers)
	zombiesFolder = folder
	handlers = newHandlers
	local ok, err = (pcall :: any)(setupCollisionGroup)
	if not ok then
		warn(PREFIX, "Could not set up the zombie collision group:", err)
	end
end

-- Spawns one zombie. onDied(zombie, killer) fires exactly once when it dies
-- (never when it is removed by despawnAll).
function ZombieService.spawn(def: ZombieDefinition, cframe: CFrame, onDiedCallback: ((Zombie, Player?) -> ())?): Zombie?
	local folder = zombiesFolder
	if not folder or not folder.Parent or not handlers then
		warn(PREFIX, "Cannot spawn zombie: ZombieService is not initialised")
		return nil
	end

	local rig = ZombieFactory.build(def)
	local scale = def.Body.Scale
	local now = os.clock()
	local rng = Random.new()
	local z: Zombie = {
		definition = def,
		rig = rig,
		model = rig.model,
		humanoid = rig.humanoid,
		root = rig.root,
		rng = rng,
		alive = true,
		busy = false,
		stunnedUntil = 0,
		lastAttack = now - def.AttackCooldown * 0.5, -- short grace period after spawning
		attackDelayUntil = 0,
		target = nil,
		nextRetarget = 0,
		drift = if rng:NextNumber() < 0.5 then -0.35 else 0.35,
		path = PathfindingService:CreatePath({
			AgentRadius = 2 * scale,
			AgentHeight = 7 * scale,
			AgentCanJump = false,
			AgentCanClimb = false,
		}),
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
		connections = {},
		onDied = onDiedCallback,
		flashToken = 0,
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
		task.wait(rng:NextNumber() * CombatConfig.ZombieThinkInterval) -- spread AI ticks out
		while z.alive do
			think(z)
			task.wait(CombatConfig.ZombieThinkInterval)
		end
	end)

	return z
end

-- The living zombie for a tagged model, or nil (dead, despawned or not a zombie).
function ZombieService.getByModel(model: Instance): Zombie?
	local z = registry[model :: any]
	if z and z.alive and z.humanoid.Health > 0 then
		return z
	end
	return nil
end

-- Champion guard: true if this zombie blocks a hit coming from attackerPosition.
function ZombieService.tryGuardBlock(z: Zombie, attackerPosition: Vector3): boolean
	if not z.alive or not z.guarding or os.clock() >= z.guardUntil then
		return false
	end
	if not CombatUtil.isFacing(z.root.CFrame, attackerPosition, 0.35) then
		return false -- side and rear attacks bypass the shield
	end
	flash(z, Color3.fromRGB(255, 220, 120))
	return true
end

-- Applies server-validated damage plus a short stagger and controlled knockback.
-- Returns false if the zombie can't take damage (already dead).
function ZombieService.applyDamage(z: Zombie, attacker: Player, amount: number, fromPosition: Vector3, stagger: number, knockback: number): boolean
	if not z.alive or z.humanoid.Health <= 0 then
		return false
	end
	z.lastAttacker = attacker
	flash(z, Color3.new(1, 1, 1))
	z.humanoid:TakeDamage(amount)
	if z.alive and z.humanoid.Health > 0 and (stagger > 0 or knockback > 0) then
		local away = CombatUtil.flat(z.root.Position - fromPosition)
		if away.Magnitude > 0.01 then
			z.root.AssemblyLinearVelocity = away.Unit * knockback * z.definition.KnockbackMultiplier
		end
		if not z.busy then
			z.stunnedUntil = math.max(z.stunnedUntil, os.clock() + stagger)
		end
	end
	return true
end

-- Removes every zombie immediately without firing death callbacks (aborted run / reset).
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
end

function ZombieService.countAlive(): number
	local count = 0
	for _ in registry do
		count += 1
	end
	return count
end

return ZombieService
