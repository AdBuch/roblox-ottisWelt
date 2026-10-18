--!strict
-- Small, child-friendly server-side effects: impact sparkles, telegraph glows and rings.
-- Everything created here is temporary and removed automatically.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EquipmentModels = require(script.Parent.EquipmentModels)

local CombatEffects = {}

local container: Instance? = nil

local function getContainer(): Instance
	if container and container.Parent then
		return container
	end
	local folder = Instance.new("Folder")
	folder.Name = "CombatEffects"
	folder.Parent = Workspace
	container = folder
	return folder
end

local function anchored(size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Parent = getContainer()
	return part
end

-- A short burst of sparkles (hits, blocks, pickups).
function CombatEffects.burst(position: Vector3, color: Color3, amount: number?)
	local holder = anchored(Vector3.one * 0.2, CFrame.new(position), color)
	holder.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.45, 0)
	emitter.Lifetime = NumberRange.new(0.2, 0.4)
	emitter.Speed = NumberRange.new(8, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = (amount or 1) * 150
	emitter.Parent = holder
	task.delay(0.1, function()
		emitter.Enabled = false
	end)
	Debris:AddItem(holder, 0.8)
end

-- A glowing outline on a model for `seconds` (wind-up telegraphs, guards).
function CombatEffects.glow(model: Instance, color: Color3, seconds: number)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.FillTransparency = 0.55
	highlight.OutlineColor = color
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	Debris:AddItem(highlight, seconds)
end

-- An expanding ground ring (spin attacks, roars).
function CombatEffects.ring(position: Vector3, radius: number, color: Color3)
	local ring = anchored(Vector3.new(0.2, 1, 1), CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), color)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.3
	TweenService:Create(ring, TweenInfo.new(0.3), { Size = Vector3.new(0.2, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.4)
end

-- A net flying from one point to another (Retiarius and the trident's NET AND STRIKE).
function CombatEffects.netThrow(from: Vector3, to: Vector3)
	local net = EquipmentModels.buildNet()
	net.CFrame = CFrame.new(from)
	net.Parent = getContainer()
	TweenService:Create(net, TweenInfo.new(0.25), { CFrame = CFrame.new(to) * CFrame.Angles(0, math.rad(45), 0) }):Play()
	Debris:AddItem(net, 0.8)
end

-- Removes every leftover effect (match cleanup).
function CombatEffects.clear()
	if container then
		container:ClearAllChildren()
	end
end

return CombatEffects
