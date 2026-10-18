--!strict
-- Six-round zombie runs for Solo and Co-op. Round sizes come from RoundDefinitions (Co-op
-- scales with the number of participating players). At most `maxActive` zombies are alive at
-- once; the rest spawn as others die. The next round starts only after every zombie of the
-- current round is dead; after round 6 the victory callback fires exactly once.
-- A run token guards against stale callbacks (aborted runs) and duplicate round starts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RoundDefinitions = require(ReplicatedStorage.Shared.RoundDefinitions)
local Arena = require(script.Parent.Arena)
local ZombieService = require(script.Parent.ZombieService)

export type WavePhase = "Idle" | "Starting" | "Fighting" | "Intermission" | "Victory"

export type RunOptions = {
	mode: string,
	maxActive: number,
	getPlayerCount: () -> number,
	onRoundStarted: (round: number) -> (),
	onRoundComplete: (round: number) -> (),
	onVictory: () -> (),
	onZombieDied: (zombie: ZombieService.Zombie, killer: Player?, damagers: { Player }) -> (),
}

local PREFIX = "[OttiArena][Server]"

local WaveService = {}

local arenaFolder: Instance? = nil
local rng = Random.new()

local phase: WavePhase = "Idle"
local round = 0
local aliveCount = 0
local spawnedCount = 0
local totalThisRound = 0
local countdown = 0
local token = 0
local options: RunOptions? = nil

local function publish()
	local folder = arenaFolder
	if not folder then
		return
	end
	folder:SetAttribute(Config.WavePhaseAttribute, phase)
	folder:SetAttribute(Config.RoundAttribute, round)
	folder:SetAttribute(Config.RoundMaxAttribute, RoundDefinitions.TotalRounds)
	folder:SetAttribute(Config.ZombiesAliveAttribute, aliveCount)
	folder:SetAttribute(Config.ZombiesTotalAttribute, totalThisRound)
	folder:SetAttribute(Config.CountdownAttribute, countdown)
end

local startRound: (number) -> ()

local function countdownTo(nextRound: number, seconds: number, myToken: number)
	for remaining = seconds, 1, -1 do
		if token ~= myToken then
			return
		end
		countdown = remaining
		publish()
		task.wait(1)
	end
	if token ~= myToken then
		return
	end
	countdown = 0
	startRound(nextRound)
end

local function checkRoundComplete(myToken: number)
	if myToken ~= token or phase ~= "Fighting" or spawnedCount < totalThisRound or aliveCount > 0 then
		return
	end
	local run = options
	if round >= RoundDefinitions.TotalRounds then
		phase = "Victory" -- set before any yield: the victory can only fire once per run
		publish()
		print(PREFIX, "All rounds complete: COLOSSEUM CONQUERED")
		if run then
			task.spawn(run.onVictory)
		end
		return
	end
	phase = "Intermission"
	print(PREFIX, ("Round %d complete, next round in %ds"):format(round, RoundDefinitions.IntermissionSeconds))
	publish()
	if run then
		task.spawn(run.onRoundComplete, round)
	end
	task.spawn(countdownTo, round + 1, RoundDefinitions.IntermissionSeconds, myToken)
end

local function pickSpawn(index: number): CFrame
	local spawns = Arena.Layout.ZombieSpawns
	local gate = spawns[(index - 1) % #spawns + 1]
	local layer = math.floor((index - 1) / #spawns)
	local depth = layer % 5 * 3.5
	local lateral = ((layer % 2) * 2 - 1) * rng:NextNumber(1, 3.5)
	return gate * CFrame.new(lateral, 0, -depth)
end

startRound = function(newRound: number)
	local run = options
	if not run then
		return
	end
	token += 1
	local myToken = token
	round = newRound
	phase = "Fighting"
	totalThisRound = RoundDefinitions.zombieCount(run.mode, newRound, run.getPlayerCount())
	aliveCount = 0
	spawnedCount = 0
	publish()
	print(PREFIX, ("Round %d/%d started: %d zombie(s)"):format(newRound, RoundDefinitions.TotalRounds, totalThisRound))
	task.spawn(run.onRoundStarted, newRound)

	local gateOffset = rng:NextInteger(0, #Arena.Layout.ZombieSpawns - 1)
	for i = 1, totalThisRound do
		-- Respect the simultaneous cap: wait until someone dies
		while aliveCount >= run.maxActive and token == myToken do
			task.wait(0.25)
		end
		if token ~= myToken then
			return
		end
		local definition = RoundDefinitions.pickVariant(newRound, rng)
		local zombie = ZombieService.spawn(definition, pickSpawn(i + gateOffset), function(z, killer, damagers)
			if myToken ~= token then
				return -- belonged to an aborted run
			end
			run.onZombieDied(z, killer, damagers)
			aliveCount = math.max(0, aliveCount - 1)
			publish()
			checkRoundComplete(myToken)
		end)
		spawnedCount += 1
		if zombie then
			aliveCount += 1
			publish()
		end
		task.wait(RoundDefinitions.SpawnInterval)
	end
	if token ~= myToken then
		return
	end
	checkRoundComplete(myToken)
end

function WaveService.init(folder: Instance)
	arenaFolder = folder
	publish()
end

-- Starts a new run at Round 1 after a short GET READY countdown.
function WaveService.startRun(newOptions: RunOptions)
	ZombieService.despawnAll()
	token += 1
	options = newOptions
	round = 0
	aliveCount = 0
	spawnedCount = 0
	totalThisRound = 0
	phase = "Starting"
	publish()
	task.spawn(countdownTo, 1, RoundDefinitions.FirstRoundDelay, token)
end

-- Ends the run immediately and removes every zombie.
function WaveService.abort()
	token += 1
	options = nil
	ZombieService.despawnAll()
	phase = "Idle"
	round = 0
	aliveCount = 0
	spawnedCount = 0
	totalThisRound = 0
	countdown = 0
	publish()
end

function WaveService.getPhase(): WavePhase
	return phase
end

return WaveService
