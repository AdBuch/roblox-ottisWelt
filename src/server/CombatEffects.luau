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

-- The folder for temporary combat visuals (detached zombie parts, markers). Cleared on cleanup.
function CombatEffects.container(): Instance
	return getContainer()
end

-- A thin, fading aim line (archer draw telegraph): shows where the shot will fly.
function CombatEffects.aimLine(from: Vector3, to: Vector3, seconds: number, color: Color3?)
	local length = (to - from).Magnitude
	if length < 1 then
		return
	end
	local line = anchored(Vector3.new(0.12, 0.12, length), CFrame.lookAt((from + to) / 2, to), color or Color3.fromRGB(255, 150, 60))
	line.Transparency = 0.65
	TweenService:Create(line, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Transparency = 0.9 }):Play()
	Debris:AddItem(line, seconds)
end

-- A flat ground warning disc that fills up until impact (boss tail slam, etc.).
function CombatEffects.groundMarker(position: Vector3, radius: number, seconds: number, color: Color3): BasePart
	local disc = anchored(Vector3.new(0.15, radius * 2, radius * 2), CFrame.new(position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)), color)
	disc.Shape = Enum.PartType.Cylinder
	disc.Transparency = 0.75
	local core = anchored(Vector3.new(0.17, 0.4, 0.4), disc.CFrame, color)
	core.Shape = Enum.PartType.Cylinder
	core.Transparency = 0.35
	TweenService:Create(core, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = Vector3.new(0.17, radius * 2, radius * 2) }):Play()
	Debris:AddItem(disc, seconds + 0.1)
	Debris:AddItem(core, seconds + 0.1)
	return disc
end

-- Sand bursting outward from a point (impacts, phase changes, dashes).
function CombatEffects.sandBurst(position: Vector3, radius: number, amount: number?)
	local holder = anchored(Vector3.one * 0.2, CFrame.new(position), Color3.new(1, 1, 1))
	holder.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(226, 202, 145), Color3.fromRGB(190, 160, 110))
	emitter.Size = NumberSequence.new(0.8, 2.2)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(radius * 1.2, radius * 2)
	emitter.SpreadAngle = Vector2.new(80, 20)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -20, 0)
	emitter.Rate = (amount or 1) * 250
	emitter.Parent = holder
	task.delay(0.12, function()
		emitter.Enabled = false
	end)
	Debris:AddItem(holder, 1.2)
	CombatEffects.ring(position, radius, Color3.fromRGB(230, 210, 160))
end

-- ARROW RAIN visuals: a few arrows fall into the marked circle (damage is checked separately).
function CombatEffects.arrowRain(center: Vector3, radius: number, seconds: number)
	local rng = Random.new()
	for i = 1, 7 do
		task.delay(seconds * (0.35 + i * 0.08), function()
			local offset = Vector3.new(rng:NextNumber(-radius, radius), 0, rng:NextNumber(-radius, radius)) * 0.8
			local landing = center + offset
			local arrow, shaft = EquipmentModels.buildArrow()
			local from = landing + Vector3.new(0, 30, 0)
			shaft.CFrame = CFrame.lookAt(from, landing)
			arrow.Parent = getContainer()
			TweenService:Create(shaft, TweenInfo.new(0.25, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(landing + Vector3.new(0, 1, 0), landing - Vector3.new(0, 1, 0)) }):Play()
			Debris:AddItem(arrow, 1.2)
		end)
	end
end

-- Removes every leftover effect (match cleanup).
function CombatEffects.clear()
	if container then
		container:ClearAllChildren()
	end
end

return CombatEffects
