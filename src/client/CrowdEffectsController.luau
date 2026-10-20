--!strict
-- Visual crowd and arena light, driven by server attributes (CrowdReactionService):
--   * animal spectators bounce, clap, lean in or recoil depending on the crowd mood; only complete
--     models near the camera are animated (CrowdQualityConfig), always from their server seat
--     (BaseCFrame attribute) - never from a pivot read before the model replicated
--   * "WHAT A THROW!" after a successful Otti throw (through the HUD notification queue)
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
local CrowdQualityConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CrowdQualityConfig"))
local Workspace = game:GetService("Workspace")

local CrowdEffectsController = {}

local MOOD_SECONDS: { [string]: number } = { Cheer = 3, Roar = 3.5, Gasp = 1.2, Celebrate = 10, Silent = 12 }

function CrowdEffectsController.start(arena: Instance, notify: (kind: string, text: string) -> (), getDevice: () -> string)
	local player = Players.LocalPlayer
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "OttiArenaLight"
	correction.Parent = Lighting

	local mood = "Idle"
	local moodStart = 0
	local parts: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any

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
			notify("Round", "WHAT A THROW!")
		end
	end
	arena:GetAttributeChangedSignal(Config.CrowdPulseAttribute):Connect(onPulse)
	arena:GetAttributeChangedSignal(Config.CrowdMoodAttribute):Connect(onPulse)
	arena:GetAttributeChangedSignal(Config.ArenaLightAttribute):Connect(applyLight)
	player:GetAttributeChangedSignal("Location"):Connect(applyLight)
	applyLight()

	-- Quality tier (phones animate fewer animals, everything far away stays still)
	local quality = CrowdQualityConfig.Quality[CrowdQualityConfig.qualityFor(getDevice())]
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < 1 / quality.UpdateHz then
			return
		end
		accumulator = 0
		if not inArena() then
			return
		end
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		local now = os.clock()
		local elapsed = now - moodStart
		local active = mood
		if MOOD_SECONDS[mood] and elapsed > MOOD_SECONDS[mood] then
			active = "Idle"
		end
		local intensity = math.clamp(tonumber(arena:GetAttribute("BattleIntensity")) or 0, 0, 1)
		local animated = 0
		for _, model in CollectionService:GetTagged(Config.CrowdSpectatorTag) do
			if not model:IsA("Model") or animated >= quality.MaxAnimated then
				continue
			end
			-- The authoritative seat comes from the server (attribute, replicated with the model).
			-- Never animate a model whose parts haven't all arrived yet: its pivot would be the
			-- world origin (= arena centre) - the old bug.
			local base = model:GetAttribute("BaseCFrame")
			local expected = tonumber(model:GetAttribute("PartCount")) or 0
			if typeof(base) ~= "CFrame" or not model.PrimaryPart then
				continue
			end
			local entry = parts[model]
			if not entry then
				local list = {}
				for _, child in model:GetChildren() do
					if child:IsA("BasePart") then
						table.insert(list, { part = child, rest = base:ToObjectSpace(child.CFrame), arm = child.Name == "Arm", side = tonumber(child:GetAttribute("Side")) or 0 })
					end
				end
				if #list < expected then
					continue -- still replicating
				end
				entry = list
				parts[model] = list
			end
			if (base.Position - eye).Magnitude > quality.AnimateDistance then
				continue -- far away: stays exactly on its seat
			end
			animated += 1
			local seed = tonumber(model:GetAttribute("Seed")) or 0
			local offset = CFrame.identity
			local armLift = 0
			if active == "Cheer" or active == "Roar" or active == "Celebrate" then
				local height = if active == "Cheer" then 0.6 elseif active == "Roar" then 1.0 else 1.2
				local hop = math.abs(math.sin(now * (8 + seed * 4) + seed * 10)) * height
				offset = CFrame.new(0, hop, 0) * CFrame.Angles(0, 0, math.sin(now * 6 + seed * 7) * 0.12)
				armLift = if active == "Celebrate" then math.abs(math.sin(now * 10 + seed * 3)) * 2.4 else 2.2 -- clapping / paws up
			elseif active == "Silent" then
				offset = CFrame.Angles(math.rad(-8 - intensity * 4), 0, 0) -- leaning in, holding its breath
			elseif active == "Gasp" then
				offset = CFrame.new(0, 0, 0.3) * CFrame.Angles(math.rad(10) * math.max(0, 1 - elapsed), 0, 0)
			else
				-- Idle: look left / right, lean in a little more the harder the battle gets
				local look = math.sin(now * 0.4 + seed * 31) * math.rad(14)
				offset = CFrame.new(0, math.max(0, math.sin(now * 1.5 + seed * 20)) * 0.08, 0) * CFrame.Angles(math.rad(-intensity * 6), look, 0)
			end
			local pivot = base * offset
			for _, item in entry :: { any } do
				local rest: CFrame = item.rest
				if item.arm and armLift > 0 then
					rest = rest * CFrame.new(0, armLift * 0.25, 0) * CFrame.Angles(0, 0, item.side * -armLift * 0.6)
				end
				item.part.CFrame = pivot * rest
			end
		end
	end)
end

return CrowdEffectsController
