--!strict
-- Visual crowd and arena light, driven by server attributes (CrowdReactionService):
--   * animal spectators bounce, lean in or recoil depending on the crowd mood
--   * "WHAT A THROW!" after a successful Otti throw
--   * arena light: slightly darker before/during the boss, a brief boost after a throw, bright
--     celebration after Otti's defeat (local ColorCorrection, only while in the arena or tribunes)
-- Works without any crowd audio. Updates ~30x per second, only near the arena.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CrowdEffectsController = {}

local MOOD_SECONDS: { [string]: number } = { Cheer = 3, Roar = 3.5, Gasp = 1.2, Celebrate = 10, Silent = 12 }

function CrowdEffectsController.start(gui: ScreenGui, arena: Instance)
	local player = Players.LocalPlayer
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "OttiArenaLight"
	correction.Parent = Lighting

	local shout = Instance.new("TextLabel")
	shout.Name = "CrowdShout"
	shout.AnchorPoint = Vector2.new(0.5, 0.5)
	shout.Position = UDim2.fromScale(0.5, 0.3)
	shout.Size = UDim2.fromOffset(600, 60)
	shout.BackgroundTransparency = 1
	shout.Font = Enum.Font.GothamBlack
	shout.TextSize = 46
	shout.TextColor3 = Color3.fromRGB(255, 215, 90)
	shout.TextStrokeTransparency = 0.2
	shout.TextTransparency = 1
	shout.TextStrokeTransparency = 1
	shout.Parent = gui

	local mood = "Idle"
	local moodStart = 0
	local bases: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

	local function inArena(): boolean
		local location = player:GetAttribute("Location")
		return location == "Arena" or location == "Tribune"
	end

	local function applyLight()
		local level = if inArena() then tonumber(arena:GetAttribute(Config.ArenaLightAttribute)) or 0 else 0
		TweenService:Create(correction, TweenInfo.new(0.8), {
			Brightness = level * 0.12,
			Contrast = math.abs(level) * 0.12,
			Saturation = if level < 0 then level * 0.25 else level * 0.1,
			TintColor = if level < 0 then Color3.fromRGB(235, 225, 255) else Color3.fromRGB(255, 248, 235),
		}):Play()
	end

	local function onPulse()
		mood = tostring(arena:GetAttribute(Config.CrowdMoodAttribute) or "Idle")
		moodStart = os.clock()
		if mood == "Roar" and inArena() then
			shout.Text = "WHAT A THROW!"
			shout.TextTransparency = 0
			shout.TextStrokeTransparency = 0.2
			task.delay(1.4, function()
				TweenService:Create(shout, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end)
		end
	end
	arena:GetAttributeChangedSignal(Config.CrowdPulseAttribute):Connect(onPulse)
	arena:GetAttributeChangedSignal(Config.CrowdMoodAttribute):Connect(onPulse)
	arena:GetAttributeChangedSignal(Config.ArenaLightAttribute):Connect(applyLight)
	player:GetAttributeChangedSignal("Location"):Connect(applyLight)
	applyLight()

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < 1 / 30 then
			return
		end
		accumulator = 0
		if not inArena() then
			return
		end
		local now = os.clock()
		local elapsed = now - moodStart
		local active = mood
		if MOOD_SECONDS[mood] and elapsed > MOOD_SECONDS[mood] then
			active = "Idle"
		end
		for _, model in CollectionService:GetTagged(Config.CrowdSpectatorTag) do
			if model:IsA("Model") then
				local base = bases[model]
				if not base then
					base = model:GetPivot()
					bases[model] = base
				end
				local seed = tonumber(model:GetAttribute("Seed")) or 0
				local offset = CFrame.identity
				if active == "Cheer" or active == "Roar" or active == "Celebrate" then
					local height = if active == "Cheer" then 0.6 elseif active == "Roar" then 1.0 else 1.2
					local hop = math.abs(math.sin(now * (8 + seed * 4) + seed * 10)) * height
					offset = CFrame.new(0, hop, 0) * CFrame.Angles(0, 0, math.sin(now * 6 + seed * 7) * 0.12)
				elseif active == "Silent" then
					offset = CFrame.Angles(math.rad(-8), 0, 0) -- leaning in, holding its breath
				elseif active == "Gasp" then
					offset = CFrame.new(0, 0, 0.3) * CFrame.Angles(math.rad(10) * math.max(0, 1 - elapsed), 0, 0)
				else
					offset = CFrame.new(0, math.max(0, math.sin(now * 1.5 + seed * 20)) * 0.08, 0)
				end
				model:PivotTo(base * offset)
			end
		end
	end)
end

return CrowdEffectsController
