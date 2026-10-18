--!strict
-- Server-simulated projectiles. Arrows fly in straight lines, raycasting every step: solid
-- geometry (walls, barrier, gates, floor) stops them, valid targets are hit, allies, spectators
-- and lobby players are ignored. Nothing here trusts client positions except the validated aim
-- direction.
--   Player arrows : up to `pierce` targets; onHit gets the travelled distance (damage falloff) and
--                   may return false to stop the arrow (walls, shields, players and Otti always do)
--   Enemy arrows  : Undead Sagittarius shots; only hit living arena fighters (never lobby players
--                   or spectators); no damage if the shooter died meanwhile
-- At most ProjectileDefinitions.ArrowPoolLimit arrows exist; the oldest is removed first.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ProjectileDefinitions = require(ReplicatedStorage.Shared.ProjectileDefinitions)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatRules = require(script.Parent.CombatRules)
local CombatTargets = require(script.Parent.CombatTargets)
local EquipmentModels = require(script.Parent.EquipmentModels)

type Target = CombatTargets.Target
type CombatContext = CombatRules.CombatContext

local ProjectileService = {}

type Flight = { finish: () -> (), started: number }

local folder: Instance? = nil
local active: { [Flight]: Instance } = {}
local activeCount = 0

local function getFolder(): Instance
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = Config.ProjectilesFolderName
	created.Parent = Workspace
	folder = created
	return created
end

-- Keeps the number of arrows bounded (no hundreds of arrow parts in the arena).
local function makeRoom()
	while activeCount >= ProjectileDefinitions.ArrowPoolLimit do
		local oldest: Flight? = nil
		for flight in active do
			if not oldest or flight.started < oldest.started then
				oldest = flight
			end
		end
		if not oldest then
			return
		end
		oldest.finish()
	end
end

type Step = (position: Vector3, step: number, traveled: number) -> boolean -- false = stop

-- Moves an arrow model along `direction`, calling `onStep` for every physics step.
local function fly(arrow: Model, shaft: BasePart, origin: Vector3, direction: Vector3, speed: number, range: number, onStep: Step)
	makeRoom()
	local flight: Flight
	local connection: RBXScriptConnection
	local finished = false
	local position = origin
	local traveled = 0
	flight = {
		started = os.clock(),
		finish = function()
			if finished then
				return
			end
			finished = true
			connection:Disconnect()
			if active[flight] then
				active[flight] = nil
				activeCount -= 1
			end
			task.delay(0.15, function()
				arrow:Destroy()
			end)
		end,
	}
	connection = RunService.Heartbeat:Connect(function(dt: number)
		local step = math.min(speed * dt, range - traveled)
		if step <= 0 then
			flight.finish()
			return
		end
		if not onStep(position, step, traveled) then
			flight.finish()
			return
		end
		position += direction * step
		traveled += step
		shaft.CFrame = CFrame.lookAt(position, position + direction)
	end)
	active[flight] = arrow
	activeCount += 1
	task.delay(range / speed + 0.5, flight.finish) -- lifetime safeguard
	return function(at: Vector3)
		shaft.CFrame = CFrame.lookAt(at, at + direction)
	end
end

export type ArrowOptions = {
	attacker: Player,
	context: CombatContext,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	range: number,
	pierce: number,
	-- Return false to stop the arrow at this target (e.g. it was blocked or isn't a zombie)
	onHit: (target: Target, position: Vector3, distance: number) -> boolean?,
}

function ProjectileService.fireArrow(options: ArrowOptions)
	local arrow, shaft = EquipmentModels.buildArrow()
	local direction = options.direction.Unit
	shaft.CFrame = CFrame.lookAt(options.origin, options.origin + direction)
	arrow.Parent = getFolder()

	-- Ignore the attacker, allies and anyone who isn't a valid target for this attacker
	local ignore: { Instance } = { arrow, CombatEffects.container() }
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if character and not (options.context == "PvP" and CombatRules.isEnemy(options.attacker, other)) then
			table.insert(ignore, character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local remainingHits = math.max(1, options.pierce)
	local placeAt: (Vector3) -> ()
	placeAt = fly(arrow, shaft, options.origin, direction, options.speed, options.range, function(position: Vector3, step: number, traveled: number): boolean
		local result = Workspace:Raycast(position, direction * step, params)
		while result do
			local target = CombatTargets.resolve(options.attacker, options.context, result.Instance)
			if not target then
				-- solid geometry (or a non-target): the arrow stops here
				placeAt(result.Position)
				return false
			end
			local distance = traveled + (result.Position - position).Magnitude
			local keepGoing = options.onHit(target, result.Position, distance)
			remainingHits -= 1
			if keepGoing == false or remainingHits <= 0 then
				placeAt(result.Position)
				return false
			end
			-- Piercing: ignore this target from now on and keep flying
			table.insert(ignore, target.model)
			params.FilterDescendantsInstances = ignore
			local remaining = (position + direction * step) - result.Position
			result = Workspace:Raycast(result.Position, remaining, params)
		end
		return true
	end)
end

export type EnemyArrowOptions = {
	origin: Vector3,
	direction: Vector3,
	speed: number,
	range: number,
	isShooterAlive: () -> boolean,
	onHitPlayer: (player: Player, position: Vector3) -> (),
}

-- An enemy (archer) arrow: stopped by walls, gates, floor, barrier; hits only living arena fighters.
function ProjectileService.fireEnemyArrow(options: EnemyArrowOptions)
	local arrow, shaft = EquipmentModels.buildArrow()
	for _, part in arrow:GetDescendants() do
		if part:IsA("Trail") then
			part.Color = ColorSequence.new(Color3.fromRGB(255, 120, 60)) -- enemy arrows: orange trail
			part.Lifetime = 0.35
		end
	end
	local direction = options.direction.Unit
	shaft.CFrame = CFrame.lookAt(options.origin, options.origin + direction)
	arrow.Parent = getFolder()

	local ignore: { Instance } = { arrow, CombatEffects.container() }
	local arena = Workspace:FindFirstChild(Config.ArenaFolderName)
	local zombies = arena and arena:FindFirstChild(Config.ZombiesFolderName)
	if zombies then
		table.insert(ignore, zombies) -- allies don't block their own arrows
	end
	for _, boss in CollectionService:GetTagged(Config.OttiTag) do
		table.insert(ignore, boss)
	end
	for _, other in Players:GetPlayers() do
		if other.Character and not CombatRules.canZombiesTarget(other) then
			table.insert(ignore, other.Character) -- lobby players, spectators, defeated players
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local placeAt: (Vector3) -> ()
	placeAt = fly(arrow, shaft, options.origin, direction, options.speed, options.range, function(position: Vector3, step: number): boolean
		local result = Workspace:Raycast(position, direction * step, params)
		if not result then
			return true
		end
		placeAt(result.Position)
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		local victim = model and Players:GetPlayerFromCharacter(model)
		if victim and options.isShooterAlive() and CombatRules.canZombiesTarget(victim) then
			options.onHitPlayer(victim, result.Position)
		end
		return false
	end)
end

-- Removes every projectile in flight (match cleanup).
function ProjectileService.clear()
	local flights = {}
	for flight in active do
		table.insert(flights, flight)
	end
	for _, flight in flights do
		flight.finish()
	end
	table.clear(active)
	activeCount = 0
	if folder then
		folder:ClearAllChildren()
	end
end

return ProjectileService
