--!strict
-- The Colosseum crowd: friendly animal spectators (otters, mice, rabbits, squirrels) in the upper
-- stands, plus reusable crowd reactions. The server publishes a mood and a pulse counter on the
-- arena folder; CrowdEffectsController (client) animates the spectators, shows short texts
-- ("WHAT A THROW!") and adjusts the arena light. Optional audio comes from AudioConfig: missing
-- IDs are fine (one concise warning in Studio, visual reactions still work).
--   Silent      quiet anticipation before the boss
--   Cheer       Otti enters, battle cries
--   Roar        louder: a successful throw (also a brief light boost)
--   Gasp        a heavy hit on a player (rate limited)
--   Celebrate   Otti defeated
-- Spectators are anchored decoration: non-colliding, never targets, never in the way.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AudioConfig = require(ReplicatedStorage.Shared.AudioConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local Arena = require(script.Parent.Arena)

export type Mood = "Idle" | "Silent" | "Cheer" | "Roar" | "Gasp" | "Celebrate"

local PREFIX = "[OttiArena][Server]"
local GASP_COOLDOWN = 3

type Species = { body: Color3, belly: Color3, ears: string, tail: boolean }
local SPECIES: { Species } = {
	{ body = Color3.fromRGB(110, 72, 46), belly = Color3.fromRGB(230, 210, 175), ears = "Round", tail = false }, -- otter
	{ body = Color3.fromRGB(150, 150, 158), belly = Color3.fromRGB(225, 220, 220), ears = "Big", tail = false }, -- mouse
	{ body = Color3.fromRGB(236, 230, 218), belly = Color3.fromRGB(250, 246, 240), ears = "Long", tail = false }, -- rabbit
	{ body = Color3.fromRGB(196, 106, 50), belly = Color3.fromRGB(240, 210, 170), ears = "Tuft", tail = true }, -- squirrel
}

local CrowdReactionService = {}

local arenaFolder: Instance? = nil
local pulse = 0
local lastGasp = 0
local warnedAudio = false
local baseLight = 0
local lightToken = 0

local function part(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, ball: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	if ball then
		p.Shape = Enum.PartType.Ball
	end
	p.Parent = model
	return p
end

local function spectator(parent: Instance, base: CFrame, species: Species, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Spectator"
	local scale = rng:NextNumber(0.85, 1.15)
	local body = part(model, "Body", Vector3.new(1.6, 1.9, 1.3) * scale, base * CFrame.new(0, 0.95 * scale, 0), species.body)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	part(model, "Belly", Vector3.new(1.0, 1.2, 0.3) * scale, base * CFrame.new(0, 0.9 * scale, -0.55 * scale), species.belly, true)
	local headCF = base * CFrame.new(0, 2.15 * scale, -0.05)
	part(model, "Head", Vector3.one * 1.25 * scale, headCF, species.body, true)
	part(model, "Snout", Vector3.one * 0.55 * scale, headCF * CFrame.new(0, -0.15 * scale, -0.55 * scale), species.belly, true)
	part(model, "Nose", Vector3.one * 0.18 * scale, headCF * CFrame.new(0, -0.05 * scale, -0.82 * scale), Color3.fromRGB(40, 28, 24), true)
	for _, side in { -1, 1 } do
		part(model, "Eye", Vector3.one * 0.16 * scale, headCF * CFrame.new(side * 0.25 * scale, 0.15 * scale, -0.55 * scale), Color3.fromRGB(20, 16, 14), true)
		if species.ears == "Long" then
			part(model, "Ear", Vector3.new(0.25, 1.1, 0.15) * scale, headCF * CFrame.new(side * 0.3 * scale, 0.95 * scale, 0) * CFrame.Angles(0, 0, side * math.rad(-10)), species.body)
		elseif species.ears == "Big" then
			part(model, "Ear", Vector3.one * 0.6 * scale, headCF * CFrame.new(side * 0.55 * scale, 0.55 * scale, 0), species.body, true)
		elseif species.ears == "Tuft" then
			part(model, "Ear", Vector3.new(0.25, 0.5, 0.15) * scale, headCF * CFrame.new(side * 0.4 * scale, 0.65 * scale, 0), species.body)
		else
			part(model, "Ear", Vector3.one * 0.3 * scale, headCF * CFrame.new(side * 0.5 * scale, 0.45 * scale, 0), species.body, true)
		end
		part(model, "Arm", Vector3.new(0.35, 0.9, 0.35) * scale, base * CFrame.new(side * 0.85 * scale, 1.1 * scale, -0.2), species.body)
	end
	if species.tail then
		part(model, "Tail", Vector3.new(0.8, 1.8, 0.6) * scale, base * CFrame.new(0, 1.3 * scale, 0.8 * scale) * CFrame.Angles(math.rad(-20), 0, 0), species.body)
	end
	model.PrimaryPart = body
	model:SetAttribute("Seed", rng:NextNumber())
	model.Parent = parent
	CollectionService:AddTag(model, Config.CrowdSpectatorTag)
end

-- Fills the upper stands (tier 2 outside the staircases, and tier 4) with spectators.
function CrowdReactionService.build(folder: Instance)
	arenaFolder = folder
	local crowd = Instance.new("Folder")
	crowd.Name = "Crowd"
	local layout = Arena.Layout
	local rng = Random.new(7)
	local floor = layout.FloorTop
	for _, tier in { 2, 4 } do
		local offset = layout.PodiumThickness + (tier - 1) * layout.SeatDepth + layout.SeatDepth * 0.55
		local y = floor + layout.PodiumHeight + tier * layout.SeatRise
		local count = if tier == 4 then 44 else 30
		for i = 0, count - 1 do
			local degrees = (i + rng:NextNumber(0.1, 0.9)) / count * 360
			local nearStairs = tier == 2 and (math.abs(degrees - 30) < 12 or math.abs(degrees - 210) < 12)
			local nearReturnDoor = math.abs(((degrees + 180) % 360) - 180) < 10 -- east door
			if not nearStairs and not nearReturnDoor then
				spectator(crowd, Arena.frameAt(math.rad(degrees), offset, y), SPECIES[rng:NextInteger(1, #SPECIES)], rng)
			end
		end
	end
	crowd.Parent = folder
	folder:SetAttribute(Config.CrowdMoodAttribute, "Idle")
	folder:SetAttribute(Config.CrowdPulseAttribute, 0)
	folder:SetAttribute(Config.ArenaLightAttribute, 0)
end

local AUDIO: { [Mood]: string } = {
	Silent = AudioConfig.CrowdMurmur,
	Cheer = AudioConfig.CrowdCheer,
	Roar = AudioConfig.CrowdRoar,
	Gasp = AudioConfig.CrowdGasp,
	Celebrate = AudioConfig.CrowdCelebrate,
	Idle = "",
}

local function playAudio(mood: Mood)
	local id = AUDIO[mood]
	local folder = arenaFolder
	if not folder or mood == "Idle" then
		return
	end
	if id == nil or id == "" then
		if not warnedAudio and RunService:IsStudio() then
			warnedAudio = true
			warn(PREFIX, "Optional crowd audio is not configured (AudioConfig). Using visual crowd reactions instead.")
		end
		return
	end
	local host = Instance.new("Part")
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.Transparency = 1
	host.Size = Vector3.one
	host.CFrame = CFrame.new(Arena.Layout.Center + Vector3.new(0, 20, 0))
	host.Parent = folder
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = AudioConfig.Volume
	sound.RollOffMaxDistance = 1000
	sound.Parent = host
	sound:Play()
	Debris:AddItem(host, 8)
end

-- Base arena light (-1 dark .. 1 bright) used outside of short pulses.
function CrowdReactionService.setBaseLight(level: number)
	baseLight = level
	lightToken += 1
	if arenaFolder then
		arenaFolder:SetAttribute(Config.ArenaLightAttribute, level)
	end
end

local function lightPulse(level: number, seconds: number)
	lightToken += 1
	local token = lightToken
	if arenaFolder then
		arenaFolder:SetAttribute(Config.ArenaLightAttribute, level)
	end
	task.delay(seconds, function()
		if token == lightToken and arenaFolder then
			arenaFolder:SetAttribute(Config.ArenaLightAttribute, baseLight)
		end
	end)
end

-- Plays a crowd reaction. kind: Silent | Enter | Cheer | Throw | Gasp | Celebrate | Idle
function CrowdReactionService.react(kind: string)
	local folder = arenaFolder
	if not folder then
		return
	end
	local mood: Mood = "Idle"
	if kind == "Silent" then
		mood = "Silent"
	elseif kind == "Enter" or kind == "Cheer" then
		mood = "Cheer"
	elseif kind == "Throw" then
		mood = "Roar"
		lightPulse(math.min(1, baseLight + 0.7), 1.2)
	elseif kind == "Gasp" then
		local now = os.clock()
		if now - lastGasp < GASP_COOLDOWN then
			return
		end
		lastGasp = now
		mood = "Gasp"
	elseif kind == "Celebrate" then
		mood = "Celebrate"
		lightPulse(0.6, 6)
	end
	pulse += 1
	folder:SetAttribute(Config.CrowdMoodAttribute, mood)
	folder:SetAttribute(Config.CrowdPulseAttribute, pulse)
	playAudio(mood)
end

-- Back to normal (match cleanup).
function CrowdReactionService.reset()
	lastGasp = 0
	CrowdReactionService.setBaseLight(0)
	if arenaFolder then
		arenaFolder:SetAttribute(Config.CrowdMoodAttribute, "Idle")
	end
end

return CrowdReactionService
