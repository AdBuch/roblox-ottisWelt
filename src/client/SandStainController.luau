--!strict
-- Stylized sand stains of zombie hits (client only, purely visual).
--   * a flat, non-colliding disc on the sand where a zombie hit lands close to the floor
--   * nearby stains merge (grow and darken) instead of piling up
--   * capped by quality (BloodConfig.Quality): the oldest stain is recycled when the cap is reached
--   * pooled: finished stains go back to a free list, nothing is created per hit
--   * the arena's StainEpoch bumps at every match start: older stains fade out and are recycled, so
--     nothing carries over between matches; stains also fade after the quality's lifetime
-- Never blocks movement, never queried by gameplay, cast no shadows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BloodConfig = require(Shared:WaitForChild("BloodConfig"))
local Config = require(Shared:WaitForChild("Config"))

export type SandStains = {
	stain: (position: Vector3, faint: boolean) -> (),
	setEpoch: (epoch: number) -> (),
	setQuality: (quality: string) -> (),
}

type Stain = { part: BasePart, epoch: number, x: number, z: number, radius: number, born: number, darkness: number }

local SandStainController = {}

local FLOOR_RAY_DEPTH = 8
local CHECK_INTERVAL = 2

function SandStainController.start(): SandStains
	local folder = Instance.new("Folder")
	folder.Name = "SandStains"
	folder.Parent = Workspace

	local active: { Stain } = {}
	local free: { BasePart } = {}
	local epoch = 0
	local quality = "High" :: any

	local function maxStains(): number
		return BloodConfig.Quality[quality :: any].MaxStains
	end

	local function newPart(): BasePart
		local part = table.remove(free) :: BasePart?
		if part then
			part.Transparency = 1
			return part
		end
		local created = Instance.new("Part")
		created.Shape = Enum.PartType.Cylinder
		created.Anchored = true
		created.CanCollide = false
		created.CanQuery = false
		created.CanTouch = false
		created.CastShadow = false
		created.Material = Enum.Material.Sand
		created.Color = BloodConfig.StainColor
		created.Transparency = 1
		created.Parent = folder
		return created
	end

	local function recycle(stain: Stain)
		local tween = TweenService:Create(stain.part, TweenInfo.new(0.6), { Transparency = 1 })
		tween:Play()
		local part = stain.part
		tween.Completed:Connect(function()
			table.insert(free, part)
		end)
	end

	local function removeAt(index: number)
		local stain = table.remove(active, index)
		if stain then
			recycle(stain)
		end
	end

	local function place(stain: Stain, radius: number, darkness: number)
		stain.radius = radius
		stain.darkness = darkness
		stain.part.Size = Vector3.new(0.05, radius * 2, radius * 2)
		stain.part.Transparency = 1 - darkness
	end

	local api = {} :: SandStains
	function api.stain(position: Vector3, faint: boolean)
		if not BloodConfig.EnableSandStains then
			return
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore: { Instance } = { folder }
		local effects = Workspace:FindFirstChild("LocalHitEffects")
		if effects then
			table.insert(ignore, effects)
		end
		local zombies = Workspace:FindFirstChild(Config.ZombiesFolderName)
		if zombies then
			table.insert(ignore, zombies)
		end
		params.FilterDescendantsInstances = ignore
		local hit = Workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -(FLOOR_RAY_DEPTH + 1), 0), params)
		if not hit or hit.Normal.Y < 0.7 or (hit.Position - position).Magnitude > BloodConfig.FloorMaxDistance then
			return
		end
		local floor = hit.Position
		local darkness = if faint then 0.3 else 0.6
		local radius = if faint then 0.9 else 1.3

		-- Merge into a nearby stain: it grows and darkens instead of piling up
		for _, stain in active do
			local dx, dz = floor.X - stain.x, floor.Z - stain.z
			if math.sqrt(dx * dx + dz * dz) < BloodConfig.StainMergeRadius then
				local grown = math.min(BloodConfig.MaxStainRadius, stain.radius + 0.25)
				place(stain, grown, math.min(BloodConfig.StainMaxDarkness, stain.darkness + 0.15))
				return
			end
		end

		if #active >= maxStains() then
			removeAt(1) -- the oldest one is recycled
		end
		local part = newPart()
		part.CFrame = CFrame.new(floor + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		local stain: Stain = { part = part, epoch = epoch, x = floor.X, z = floor.Z, radius = radius, born = os.clock(), darkness = darkness }
		place(stain, radius, darkness)
		table.insert(active, stain)
	end

	function api.setEpoch(newEpoch: number)
		if newEpoch == epoch then
			return
		end
		epoch = newEpoch
		-- Older matches: fade out and recycle everything from earlier epochs
		for index = #active, 1, -1 do
			if active[index].epoch ~= epoch then
				removeAt(index)
			end
		end
	end

	function api.setQuality(newQuality: string)
		if BloodConfig.Quality[newQuality :: any] then
			quality = newQuality
		end
	end

	-- Lifetime: stains fade after the quality's FadeSeconds
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			local lifetime = BloodConfig.Quality[quality :: any].FadeSeconds
			local now = os.clock()
			for index = #active, 1, -1 do
				if now - active[index].born > lifetime then
					removeAt(index)
				end
			end
		end
	end)

	return api
end

return SandStainController
