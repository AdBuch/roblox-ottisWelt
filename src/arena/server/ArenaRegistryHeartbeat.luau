--!strict
-- Publishes this Arena's PUBLIC registry record (MatchRegistryService) every HeartbeatSeconds
-- and right after important changes (throttled): mode, status, round, Otti phase, score, time,
-- alive counts, fighter and spectator counts, joinability and the public participant ids. The
-- spectator slot record (SpectatorSlotService) is refreshed in the same beat. Failures are
-- logged and ignored: a registry outage never affects the running match. When the match is
-- over, complete() removes the record at once (non-joinable immediately) and closes the slots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local GameProtocol = require(ReplicatedStorage.Shared.GameProtocol)
local MatchDefinitions = require(ReplicatedStorage.Shared.MatchDefinitions)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local Server = script.Parent.Parent
local MatchRecordService = require(Server.MatchRecordService)
local MatchRegistryService = require(Server.MatchRegistryService)
local MatchService = require(Server.MatchService)
local SpectatorSlotService = require(Server.SpectatorSlotService)
local ArenaSpectatorService = require(script.Parent.ArenaSpectatorService)

local THROTTLE = 3

local ArenaRegistryHeartbeat = {}

local arenaFolder: Instance? = nil
local matchRecord: MatchTypes.MatchRecord? = nil
local status: MatchTypes.MatchStatus = "STARTING"
local startedAt = os.time()
local lastBeat = 0
local queued = false
local completed = false

local function attr(name: string, default: number): number
	local folder = arenaFolder
	return if folder then tonumber(folder:GetAttribute(name)) or default else default
end

local function build(current: MatchTypes.MatchRecord): MatchTypes.RegistryRecord
	local definition = MatchDefinitions.get(current.mode)
	local folder = arenaFolder
	local isTeam = definition ~= nil and definition.Kind == "Team"
	local bossActive = folder ~= nil and folder:GetAttribute(Config.BossActiveAttribute) == true
	local spectators = ArenaSpectatorService.count()
	local maxSpectators = if definition then definition.MaxSpectators else ExperienceConfig.Capacity.MaxSpectators
	local ids, parties = {}, {}
	for _, fighter in current.fighters do
		table.insert(ids, fighter.userId)
		if fighter.partyId ~= "" and not table.find(parties, fighter.partyId) then
			table.insert(parties, fighter.partyId)
		end
	end
	return {
		matchId = current.matchId,
		mode = current.mode,
		subMode = if isTeam then current.mode else nil,
		status = status,
		protocol = GameProtocol.Version,
		policy = current.policy,
		round = attr(Config.RoundAttribute, 0),
		maxRounds = attr(Config.RoundMaxAttribute, 7),
		phase = "",
		bossPhase = if bossActive then attr(Config.BossPhaseAttribute, 1) else 0,
		redScore = attr(Config.RedScoreAttribute, 0),
		blueScore = attr(Config.BlueScoreAttribute, 0),
		target = attr(Config.ScoreTargetAttribute, 0),
		timeLeft = if isTeam then attr(Config.TimeLeftAttribute, -1) else -1,
		redAlive = attr(Config.RedAliveAttribute, 0),
		blueAlive = attr(Config.BlueAliveAttribute, 0),
		suddenDeath = folder ~= nil and folder:GetAttribute(Config.SuddenDeathAttribute) == true,
		fighterCount = #MatchService.fighters(),
		maxFighters = if definition then definition.MaxFighters else ExperienceConfig.Capacity.MaxFighters,
		spectatorCount = spectators,
		maxSpectators = maxSpectators,
		joinableAsSpectator = not completed and not MatchService.isFinished() and spectators < maxSpectators,
		startedAt = startedAt,
		heartbeatAt = os.time(),
		publicParticipantIds = ids,
		partyIds = parties,
	}
end

local function beat()
	local current = matchRecord
	if not current or completed then
		return
	end
	lastBeat = os.clock()
	local record = build(current)
	pcall(MatchRegistryService.publish, record)
	pcall(SpectatorSlotService.heartbeat, current.matchId, record.joinableAsSpectator, record.spectatorCount, record.maxSpectators)
	if arenaFolder then
		arenaFolder:SetAttribute(Config.SpectatorCountAttribute, record.spectatorCount)
	end
end

-- Publish soon (throttled): round, boss phase or score changed.
function ArenaRegistryHeartbeat.poke()
	if queued or completed then
		return
	end
	queued = true
	task.delay(math.max(0, THROTTLE - (os.clock() - lastBeat)), function()
		queued = false
		beat()
	end)
end

function ArenaRegistryHeartbeat.setStatus(newStatus: MatchTypes.MatchStatus)
	status = newStatus
	if newStatus == "ACTIVE" then
		startedAt = os.time()
	end
	ArenaRegistryHeartbeat.poke()
end

-- The match is over: not joinable any more, gone from every list right away.
function ArenaRegistryHeartbeat.complete()
	if completed then
		return
	end
	completed = true
	local current = matchRecord
	if current then
		pcall(MatchRegistryService.remove, current.matchId)
		pcall(SpectatorSlotService.close, current.matchId)
		task.delay(30, function()
			pcall(MatchRecordService.remove, current.matchId) -- after late arrivals were turned away
		end)
	end
end

-- Mock mode only: a new local match on the same server.
function ArenaRegistryHeartbeat.reset(newRecord: MatchTypes.MatchRecord)
	matchRecord = newRecord
	completed = false
	status = "STARTING"
	ArenaRegistryHeartbeat.poke()
end

function ArenaRegistryHeartbeat.start(folder: Instance, current: MatchTypes.MatchRecord)
	arenaFolder = folder
	if matchRecord then
		matchRecord = current
		return
	end
	matchRecord = current
	folder:SetAttribute(Config.ArenaMatchIdAttribute, current.matchId)
	task.spawn(function()
		while true do
			beat()
			task.wait(ExperienceConfig.Registry.HeartbeatSeconds)
		end
	end)
end

return ArenaRegistryHeartbeat
