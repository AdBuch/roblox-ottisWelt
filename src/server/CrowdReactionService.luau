--!strict
-- The Colosseum crowd: animal spectators in small groups across explicit tribune zones
-- (SpectatorPlacementService; density follows the match importance), plus reusable crowd reactions. The server publishes a mood and a pulse counter on the
-- arena folder; CrowdEffectsController (client) animates the spectators, shows short texts
-- ("WHAT A THROW!") and adjusts the arena light. Optional audio comes from AudioConfig: missing
-- IDs are fine (one concise warning in Studio, visual reactions still work).
--   Silent      quiet anticipation before the boss
--   Cheer       Otti enters, battle cries
--   Roar        louder: a successful throw (also a brief light boost)
--   Gasp        a heavy hit on a player (rate limited)
--   Celebrate   Otti defeated
-- Spectators are anchored decoration: non-colliding, never targets, never in the way.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AudioConfig = require(ReplicatedStorage.Shared.AudioConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local CrowdQualityConfig = require(ReplicatedStorage.Shared.CrowdQualityConfig)
local Arena = require(script.Parent.Arena)
local SpectatorPlacementService = require(script.Parent.SpectatorPlacementService)

export type Mood = "Idle" | "Silent" | "Cheer" | "Roar" | "Gasp" | "Celebrate"

local PREFIX = "[OttiArena][Server]"
local GASP_COOLDOWN = 3

local CrowdReactionService = {}

local arenaFolder: Instance? = nil
local pulse = 0
local lastGasp = 0
local warnedAudio = false
local baseLight = 0
local lightToken = 0

-- Importance follows the match: early rounds Low, then Normal, the final round / Otti / sudden
-- death / match point High (SpectatorPlacementService loads more groups).
local function updateImportance()
	local folder = arenaFolder
	if not folder then
		return
	end
	local round = tonumber(folder:GetAttribute(Config.RoundAttribute)) or 0
	local roundMax = tonumber(folder:GetAttribute(Config.RoundMaxAttribute)) or 7
	local boss = folder:GetAttribute(Config.BossActiveAttribute) == true
	local sudden = folder:GetAttribute(Config.SuddenDeathAttribute) == true
	local red = tonumber(folder:GetAttribute(Config.RedScoreAttribute)) or 0
	local blue = tonumber(folder:GetAttribute(Config.BlueScoreAttribute)) or 0
	local target = tonumber(folder:GetAttribute(Config.ScoreTargetAttribute)) or 0
	local matchPoint = target > 0 and (red >= target - 1 or blue >= target - 1)
	local level: CrowdQualityConfig.Importance = "Normal"
	if boss or sudden or matchPoint or (round > 0 and round >= roundMax - 1) then
		level = "High"
	elseif folder:GetAttribute(Config.MatchModeAttribute) ~= "TeamBattle" and round <= 2 then
		level = "Low"
	end
	SpectatorPlacementService.setImportance(level)
end

-- Builds the animal crowd in tribune zones (deterministic per server / match).
function CrowdReactionService.build(folder: Instance)
	arenaFolder = folder
	local seed = 7
	for i = 1, #game.JobId do
		seed = (seed * 31 + string.byte(game.JobId, i)) % 2147483647
	end
	SpectatorPlacementService.build(folder, seed)
	folder:SetAttribute(Config.CrowdMoodAttribute, "Idle")
	folder:SetAttribute(Config.CrowdPulseAttribute, 0)
	folder:SetAttribute(Config.ArenaLightAttribute, 0)
	for _, name in { Config.RoundAttribute, Config.BossActiveAttribute, Config.SuddenDeathAttribute, Config.RedScoreAttribute, Config.BlueScoreAttribute, Config.MatchModeAttribute } do
		folder:GetAttributeChangedSignal(name):Connect(updateImportance)
	end
	updateImportance()
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

-- A dramatic player move (Tier III special, Ultimate, parry counter): a cheer, but never more than
-- once per cooldown, so normal hits never make the crowd noisy.
local lastMajor = 0
function CrowdReactionService.majorMove(kind: string)
	local now = os.clock()
	local cooldown = if kind == "Ultimate" then CrowdQualityConfig.UltimateCooldown else CrowdQualityConfig.MajorMoveCooldown
	if now - lastMajor < cooldown then
		return
	end
	lastMajor = now
	if kind == "Ultimate" then
		lightPulse(math.min(1, baseLight + 0.5), 1)
	end
	CrowdReactionService.react("Cheer")
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
