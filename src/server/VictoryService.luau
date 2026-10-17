--!strict
-- Victory celebration: colorful fireworks over the arena and a short fanfare, built only from
-- anchored Parts, ParticleEmitters, lights and a built-in Studio sound. Everything it creates
-- is cleaned up afterwards.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Arena = require(script.Parent.Arena)

local COLORS = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(140, 255, 120),
	Color3.fromRGB(220, 120, 255),
	Color3.fromRGB(255, 150, 220),
}
local ROCKETS = 16
local ROCKET_INTERVAL = 0.5

local VictoryService = {}

local function anchoredPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Parent = parent
	return part
end

local function launchRocket(parent: Instance, rng: Random)
	local a, b = Arena.Layout.SemiAxisX * 0.6, Arena.Layout.SemiAxisZ * 0.6
	local angle = rng:NextNumber(0, 2 * math.pi)
	local radius = math.sqrt(rng:NextNumber())
	local start = Vector3.new(math.cos(angle) * a * radius, Arena.Layout.FloorTop + 1, math.sin(angle) * b * radius)
	local burstAt = start + Vector3.new(0, rng:NextNumber(38, 55), 0)
	local color = COLORS[rng:NextInteger(1, #COLORS)]

	local rocket = anchoredPart("Rocket", Vector3.new(0.5, 1.4, 0.5), CFrame.new(start), color, parent)
	local trail = Instance.new("ParticleEmitter")
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 230, 180))
	trail.LightEmission = 1
	trail.Size = NumberSequence.new(0.5, 0)
	trail.Lifetime = NumberRange.new(0.3, 0.5)
	trail.Speed = NumberRange.new(1, 3)
	trail.Rate = 60
	trail.Parent = rocket
	TweenService:Create(rocket, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(burstAt) }):Play()

	task.delay(0.9, function()
		rocket:Destroy()
		local burst = anchoredPart("Burst", Vector3.one * 0.2, CFrame.new(burstAt), color, parent)
		burst.Transparency = 1
		local sparks = Instance.new("ParticleEmitter")
		sparks.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
		sparks.Lifetime = NumberRange.new(1.0, 1.6)
		sparks.Speed = NumberRange.new(22, 30)
		sparks.Drag = 2
		sparks.Acceleration = Vector3.new(0, -8, 0)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Rate = 500
		sparks.Parent = burst
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 45
		light.Brightness = 5
		light.Parent = burst
		TweenService:Create(light, TweenInfo.new(1.2), { Brightness = 0 }):Play()
		task.delay(0.12, function()
			sparks.Enabled = false
		end)
		Debris:AddItem(burst, 2.5)
	end)
end

local function playFanfare(parent: Instance)
	-- Rising notes from one built-in sound (placeholder fanfare, no uploaded audio)
	local host = anchoredPart("FanfareHost", Vector3.one, CFrame.new(Arena.Layout.Center + Vector3.new(0, 10, 0)), Color3.new(1, 1, 1), parent)
	host.Transparency = 1
	for i, pitch in { 1, 1.26, 1.5, 2, 1.5, 2 } do
		task.delay((i - 1) * 0.18, function()
			local sound = Instance.new("Sound")
			sound.SoundId = CombatConfig.FanfareSoundId
			sound.Volume = 0.7
			sound.PlaybackSpeed = pitch
			sound.RollOffMaxDistance = 1000
			sound.Parent = host
			sound:Play()
			Debris:AddItem(sound, 2)
		end)
	end
	Debris:AddItem(host, 4)
end

-- Plays the celebration over roughly ROCKETS * ROCKET_INTERVAL seconds (non-blocking).
function VictoryService.play(arenaFolder: Instance)
	local effects = Instance.new("Folder")
	effects.Name = "VictoryEffects"
	effects.Parent = arenaFolder
	local rng = Random.new()
	playFanfare(effects)
	task.spawn(function()
		for _ = 1, ROCKETS do
			if not effects.Parent then
				return
			end
			launchRocket(effects, rng)
			task.wait(ROCKET_INTERVAL)
		end
	end)
	Debris:AddItem(effects, ROCKETS * ROCKET_INTERVAL + 4)
end

return VictoryService
