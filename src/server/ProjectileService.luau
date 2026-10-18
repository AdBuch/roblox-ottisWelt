--!strict
-- Server-simulated projectiles. Arrows fly in straight lines, raycasting every step: solid
-- geometry (walls, barrier, floor) stops them, valid targets are hit (up to `pierce` of them),
-- allies, spectators and lobby players are ignored. Nothing here trusts client positions
-- except the validated aim direction.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CombatRules = require(script.Parent.CombatRules)
local CombatTargets = require(script.Parent.CombatTargets)
local EquipmentModels = require(script.Parent.EquipmentModels)

type Target = CombatTargets.Target
type CombatContext = CombatRules.CombatContext

local ProjectileService = {}

local folder: Instance? = nil
local active: { [RBXScriptConnection]: Instance } = {}

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

export type ArrowOptions = {
	attacker: Player,
	context: CombatContext,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	range: number,
	pierce: number,
	onHit: (target: Target, position: Vector3) -> (),
}

function ProjectileService.fireArrow(options: ArrowOptions)
	local arrow, shaft = EquipmentModels.buildArrow()
	local direction = options.direction.Unit
	shaft.CFrame = CFrame.lookAt(options.origin, options.origin + direction)
	arrow.Parent = getFolder()

	-- Ignore the attacker, allies and anyone who isn't a valid target for this attacker
	local ignore: { Instance } = { arrow }
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if character and not (options.context == "PvP" and CombatRules.isEnemy(options.attacker, other)) then
			table.insert(ignore, character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local position = options.origin
	local traveled = 0
	local remainingHits = math.max(1, options.pierce)
	local finished = false
	local connection: RBXScriptConnection

	local function finish()
		if finished then
			return
		end
		finished = true
		connection:Disconnect()
		active[connection] = nil
		task.delay(0.15, function()
			arrow:Destroy()
		end)
	end

	connection = RunService.Heartbeat:Connect(function(dt: number)
		local step = math.min(options.speed * dt, options.range - traveled)
		if step <= 0 then
			finish()
			return
		end
		local result = Workspace:Raycast(position, direction * step, params)
		while result do
			local target = CombatTargets.resolve(options.attacker, options.context, result.Instance)
			if not target then
				-- solid geometry (or a non-target): the arrow stops here
				shaft.CFrame = CFrame.lookAt(result.Position, result.Position + direction)
				finish()
				return
			end
			options.onHit(target, result.Position)
			remainingHits -= 1
			if remainingHits <= 0 then
				shaft.CFrame = CFrame.lookAt(result.Position, result.Position + direction)
				finish()
				return
			end
			-- Piercing: ignore this target from now on and keep flying
			table.insert(ignore, target.model)
			params.FilterDescendantsInstances = ignore
			local remaining = (position + direction * step) - result.Position
			result = Workspace:Raycast(result.Position, remaining, params)
		end
		position += direction * step
		traveled += step
		shaft.CFrame = CFrame.lookAt(position, position + direction)
	end)
	active[connection] = arrow
	task.delay(options.range / options.speed + 0.5, finish) -- lifetime safeguard
end

-- Removes every projectile in flight (match cleanup).
function ProjectileService.clear()
	for connection, instance in active do
		connection:Disconnect()
		instance:Destroy()
	end
	table.clear(active)
	if folder then
		folder:ClearAllChildren()
	end
end

return ProjectileService
