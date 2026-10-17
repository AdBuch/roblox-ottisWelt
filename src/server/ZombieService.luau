--!strict
-- Server-controlled Roman zombie: detects the nearest living player, chases with
-- PathfindingService, telegraphs and performs melee attacks, and respawns after defeat.
-- Every damage decision (range, line of sight, cooldown, block) is made here on the server.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Arena = require(script.Parent.Arena)
local CombatUtil = require(script.Parent.CombatUtil)
local Remotes = require(script.Parent.Remotes)
local ShieldService = require(script.Parent.ShieldService)
local ZombieModel = require(script.Parent.ZombieModel)

local PREFIX = "[OttiArena][Server]"
local WAYPOINT_REACHED = 2.5
local DIRECT_CHASE_DISTANCE = 14
local LEASH_MARGIN = 3

type Zombie = ZombieModel.ZombieRig & {
	alive: boolean,
	attacking: boolean,
	stunnedUntil: number,
	lastAttack: number,
	path: Path,
	waypoints: { PathWaypoint }?,
	waypointIndex: number,
	pathGoal: Vector3,
	lastPathTime: number,
	damagedBy: { [Player]: boolean },
	connections: { RBXScriptConnection },
	flashId: number,
}

local ZombieService = {}

local arenaFolder: Folder? = nil
local homeCFrame = CFrame.identity
local current: Zombie? = nil

local function setArenaAttributes(health: number, alive: boolean)
	if arenaFolder then
		arenaFolder:SetAttribute(CombatConfig.ZombieHealthAttribute, health)
		arenaFolder:SetAttribute(CombatConfig.ZombieMaxHealthAttribute, CombatConfig.ZombieMaxHealth)
		arenaFolder:SetAttribute(CombatConfig.ZombieAliveAttribute, alive)
	end
end

local function updateNameTag(z: Zombie)
	z.nameLabel.Text = ("Roman Zombie  %d / %d"):format(math.ceil(z.humanoid.Health), CombatConfig.ZombieMaxHealth)
end

local function setArmPose(z: Zombie, angleDegrees: number, seconds: number)
	local goal = { C0 = z.rightShoulderRest * CFrame.Angles(math.rad(angleDegrees), 0, 0) }
	TweenService:Create(z.rightShoulder, TweenInfo.new(seconds, Enum.EasingStyle.Quad), goal):Play()
end

local function flash(z: Zombie)
	z.flashId += 1
	local myId = z.flashId
	z.highlight.Enabled = true
	z.hitSparks.Enabled = true
	task.delay(0.12, function()
		if z.flashId == myId then
			z.highlight.Enabled = false
			z.hitSparks.Enabled = false
		end
	end)
end

local function faceTowards(z: Zombie, target: Vector3)
	local position = z.root.Position
	local flatTarget = Vector3.new(target.X, position.Y, target.Z)
	if (flatTarget - position).Magnitude > 0.1 then
		z.root.CFrame = CFrame.lookAt(position, flatTarget)
	end
end

local function findTarget(z: Zombie): (Player?, BasePart?)
	local bestPlayer, bestRoot, bestDistance = nil, nil, CombatConfig.ZombieDetectRadius
	for _, player in Players:GetPlayers() do
		local _, _, root = CombatUtil.getLivingCharacter(player)
		if root and Arena.isInside(root.Position) then
			local distance = (root.Position - z.root.Position).Magnitude
			if distance <= bestDistance then
				bestPlayer, bestRoot, bestDistance = player, root, distance
			end
		end
	end
	return bestPlayer, bestRoot
end

-- Keeps the zombie inside the arena even if physics pushes it somewhere odd.
local function keepInside(z: Zombie)
	if not Arena.isInside(z.root.Position, -LEASH_MARGIN) then
		z.root.AssemblyLinearVelocity = Vector3.zero
		z.model:PivotTo(homeCFrame)
		z.waypoints = nil
		print(PREFIX, "Zombie left the arena bounds and was returned to its spawn")
	end
end

local function pushBack(z: Zombie, fromPosition: Vector3)
	local away = CombatUtil.flat(z.root.Position - fromPosition)
	if away.Magnitude < 0.01 then
		away = -z.root.CFrame.LookVector
	end
	z.stunnedUntil = os.clock() + CombatConfig.ShieldStunSeconds
	z.humanoid:MoveTo(z.root.Position)
	z.root.AssemblyLinearVelocity = away.Unit * CombatConfig.ShieldPushBackSpeed + Vector3.new(0, 12, 0)
end

local function performAttack(z: Zombie, player: Player)
	z.attacking = true
	z.lastAttack = os.clock()

	-- Telegraph: raise the sword arm overhead
	setArmPose(z, 150, CombatConfig.ZombieWindUpSeconds * 0.85)
	task.wait(CombatConfig.ZombieWindUpSeconds)
	if not z.alive then
		return
	end
	setArmPose(z, 25, 0.1)

	-- Re-validate everything at the moment the blow lands
	local character, humanoid, targetRoot = CombatUtil.getLivingCharacter(player)
	if character and humanoid and targetRoot then
		local inReach = CombatUtil.flatDistance(z.root.Position, targetRoot.Position) <= CombatConfig.ZombieAttackReach
			and math.abs(z.root.Position.Y - targetRoot.Position.Y) <= 5
		local eye = z.root.Position + Vector3.new(0, 1.5, 0)
		if inReach and CombatUtil.hasLineOfSight(eye, targetRoot.Position, { z.model, character }) then
			local blocked = ShieldService.tryBlock(player, z.root.Position)
			local damage = CombatConfig.ZombieAttackDamage
			if blocked then
				damage = math.floor(damage * (1 - CombatConfig.ShieldDamageReduction) + 0.5)
				pushBack(z, targetRoot.Position)
			end
			humanoid:TakeDamage(damage)
			Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.PlayerHit, damage, blocked)
		end
	end

	task.wait(0.25)
	if z.alive then
		setArmPose(z, 0, 0.3)
	end
	z.attacking = false
end

local function followPath(z: Zombie, targetPosition: Vector3, now: number)
	local needsPath = z.waypoints == nil
		or now - z.lastPathTime >= CombatConfig.ZombiePathInterval
		or (targetPosition - z.pathGoal).Magnitude > 6
	if needsPath then
		z.lastPathTime = now
		local ok = pcall(function()
			z.path:ComputeAsync(z.root.Position, targetPosition)
		end)
		if not z.alive then
			return
		end
		if ok and z.path.Status == Enum.PathStatus.Success then
			z.waypoints = z.path:GetWaypoints()
			z.waypointIndex = 2
			z.pathGoal = targetPosition
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
	z.humanoid:MoveTo(targetPosition)
end

local function think(z: Zombie)
	keepInside(z)
	local now = os.clock()
	if z.attacking or now < z.stunnedUntil then
		return
	end

	local player, targetRoot = findTarget(z)
	if not player or not targetRoot then
		z.waypoints = nil
		if CombatUtil.flatDistance(z.root.Position, homeCFrame.Position) > 3 then
			z.humanoid:MoveTo(homeCFrame.Position)
		end
		return
	end

	local targetPosition = targetRoot.Position
	local distance = CombatUtil.flatDistance(z.root.Position, targetPosition)
	local eye = z.root.Position + Vector3.new(0, 1.5, 0)
	local character = player.Character :: Model
	local canSee = CombatUtil.hasLineOfSight(eye, targetPosition, { z.model, character })

	if distance <= CombatConfig.ZombieAttackRange and canSee then
		z.humanoid:MoveTo(z.root.Position)
		faceTowards(z, targetPosition)
		if now - z.lastAttack >= CombatConfig.ZombieAttackCooldown then
			task.spawn(performAttack, z, player)
		end
	elseif canSee and distance <= DIRECT_CHASE_DISTANCE then
		z.waypoints = nil
		z.humanoid:MoveTo(targetPosition)
	else
		followPath(z, targetPosition, now)
	end
end

local spawnZombie: () -> ()

local function onDied(z: Zombie)
	if not z.alive then
		return
	end
	z.alive = false
	for _, connection in z.connections do
		connection:Disconnect()
	end
	table.clear(z.connections)
	setArenaAttributes(0, false)

	for player in z.damagedBy do
		if player.Parent then
			player:SetAttribute(Config.ZombieDefeatedAttribute, true)
		end
	end
	table.clear(z.damagedBy)
	print(PREFIX, ("Roman Zombie defeated, respawning in %ds"):format(CombatConfig.ZombieRespawnSeconds))

	task.delay(1.5, function()
		z.model:Destroy()
	end)
	task.delay(CombatConfig.ZombieRespawnSeconds, spawnZombie)
end

spawnZombie = function()
	local folder = arenaFolder
	if not folder or not folder.Parent then
		warn(PREFIX, "Cannot spawn zombie: GeneratedArena is missing")
		return
	end

	local rig = ZombieModel.build()
	local z: Zombie = rig :: any
	z.alive = true
	z.attacking = false
	z.stunnedUntil = 0
	z.lastAttack = 0
	z.path = PathfindingService:CreatePath({
		AgentRadius = 2.5,
		AgentHeight = 7.5,
		AgentCanJump = false,
		AgentCanClimb = false,
	})
	z.waypoints = nil
	z.waypointIndex = 1
	z.pathGoal = Vector3.zero
	z.lastPathTime = 0
	z.damagedBy = {}
	z.connections = {}
	z.flashId = 0

	z.model:PivotTo(homeCFrame)
	z.model.Parent = folder
	z.root:SetNetworkOwner(nil) -- server simulates the zombie, clients can't move it

	table.insert(z.connections, z.humanoid.Died:Connect(function()
		onDied(z)
	end))
	table.insert(z.connections, z.humanoid.HealthChanged:Connect(function(health)
		setArenaAttributes(math.ceil(health), z.alive)
		updateNameTag(z)
	end))

	current = z
	updateNameTag(z)
	setArenaAttributes(CombatConfig.ZombieMaxHealth, true)
	print(PREFIX, ("Zombie spawned (%d HP)"):format(CombatConfig.ZombieMaxHealth))

	task.spawn(function()
		while z.alive do
			task.wait(CombatConfig.ZombieThinkInterval)
			if z.alive then
				think(z)
			end
		end
	end)
end

function ZombieService.init(folder: Folder, position: Vector3, facing: Vector3)
	arenaFolder = folder
	local rootPosition = position + Vector3.new(0, 3.4, 0)
	homeCFrame = CFrame.lookAt(rootPosition, Vector3.new(facing.X, rootPosition.Y, facing.Z))
	spawnZombie()
end

-- The zombie's model and root while it is alive, for server-side hit validation.
function ZombieService.getLiving(): (Model?, BasePart?)
	local z = current
	if z and z.alive then
		return z.model, z.root
	end
	return nil, nil
end

-- Applies validated damage from a player (callers must validate range/facing/LOS first).
function ZombieService.damage(attacker: Player, amount: number)
	local z = current
	if not z or not z.alive then
		return
	end
	z.damagedBy[attacker] = true
	flash(z)
	z.humanoid:TakeDamage(amount)
end

return ZombieService
