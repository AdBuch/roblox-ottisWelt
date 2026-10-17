--!strict
-- Six fixed rounds for one run: 1, 2, 4, 8, 16 and 32 zombies (RoundDefinitions).
-- The next round starts only after every zombie of the current round is dead, followed by a
-- countdown. After round 6 the victory callback fires exactly once. A run token guards
-- against stale callbacks: deaths from an aborted run are ignored, and the phase changes
-- synchronously, so simultaneous deaths can't start a round (or the victory) twice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local RoundDefinitions = require(ReplicatedStorage.Shared.RoundDefinitions)
local Arena = require(script.Parent.Arena)
local CoinService = require(script.Parent.CoinService)
local ZombieService = require(script.Parent.ZombieService)

export type WavePhase = "Idle" | "Starting" | "Fighting" | "Intermission" | "Victory"

export type RunCallbacks = {
	onRoundStarted: (round: number) -> (),
	onRoundComplete: (round: number) -> (),
	onVictory: () -> (),
}

local PREFIX = "[OttiArena][Server]"

local WaveService = {}

local arenaFolder: Instance? = nil
local rng = Random.new()

local phase: WavePhase = "Idle"
local round = 0
local aliveCount = 0
local totalThisRound = 0
local countdown = 0
local spawning = false
local token = 0 -- changes whenever a run starts, a round starts or the run is aborted
local callbacks: RunCallbacks? = nil

local function publish()
	local folder = arenaFolder
	if not folder then
		return
	end
	folder:SetAttribute(Config.WavePhaseAttribute, phase)
	folder:SetAttribute(Config.RoundAttribute, round)
	folder:SetAttribute(Config.RoundMaxAttribute, RoundDefinitions.totalRounds())
	folder:SetAttribute(Config.ZombiesAliveAttribute, aliveCount)
	folder:SetAttribute(Config.ZombiesTotalAttribute, totalThisRound)
	folder:SetAttribute(Config.CountdownAttribute, countdown)
end

local startRound: (number) -> ()

-- Counts down, then starts the given round unless the run was aborted/advanced meanwhile.
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
	if myToken ~= token or phase ~= "Fighting" or spawning or aliveCount > 0 then
		return
	end
	local cb = callbacks
	if round >= RoundDefinitions.totalRounds() then
		phase = "Victory" -- set before any yield: the victory can only fire once per run
		publish()
		print(PREFIX, "All rounds complete: COLOSSEUM CONQUERED")
		if cb then
			task.spawn(cb.onVictory)
		end
		return
	end
	phase = "Intermission"
	print(PREFIX, ("Round %d complete, next round in %ds"):format(round, RoundDefinitions.IntermissionSeconds))
	publish()
	if cb then
		task.spawn(cb.onRoundComplete, round)
	end
	task.spawn(countdownTo, round + 1, RoundDefinitions.IntermissionSeconds, myToken)
end

local function onZombieDied(myToken: number, zombie: ZombieService.Zombie, killer: Player?)
	if myToken ~= token then
		return -- belonged to an aborted run
	end
	CoinService.awardKill(zombie.definition, killer)
	aliveCount = math.max(0, aliveCount - 1)
	publish()
	checkRoundComplete(myToken)
end

local function pickSpawn(index: number): CFrame
	local spawns = Arena.Layout.ZombieSpawns
	local gate = spawns[(index - 1) % #spawns + 1]
	-- Spread zombies sideways and deeper into the arena so they never spawn inside each other
	local depth = math.floor((index - 1) / #spawns) % 5 * 3.5
	local lateral = ((math.floor((index - 1) / #spawns) % 2) * 2 - 1) * rng:NextNumber(1, 3.5)
	return gate * CFrame.new(lateral, 0, -depth)
end

startRound = function(newRound: number)
	token += 1
	local myToken = token
	round = newRound
	phase = "Fighting"
	totalThisRound = RoundDefinitions.zombieCount(newRound, CombatConfig.MaxActiveZombies)
	aliveCount = 0
	spawning = true
	publish()
	print(PREFIX, ("Round %d/%d started: %d zombie(s)"):format(newRound, RoundDefinitions.totalRounds(), totalThisRound))
	local cb = callbacks
	if cb then
		task.spawn(cb.onRoundStarted, newRound)
	end

	local gateOffset = rng:NextInteger(0, #Arena.Layout.ZombieSpawns - 1)
	for i = 1, totalThisRound do
		if token ~= myToken then
			return
		end
		local definition = RoundDefinitions.pickVariant(newRound, rng)
		local zombie = ZombieService.spawn(definition, pickSpawn(i + gateOffset), function(z, killer)
			onZombieDied(myToken, z, killer)
		end)
		if zombie then
			aliveCount += 1
			publish()
		end
		task.wait(RoundDefinitions.SpawnInterval)
	end

	if token ~= myToken then
		return
	end
	spawning = false
	checkRoundComplete(myToken)
end

function WaveService.init(folder: Instance)
	arenaFolder = folder
	publish()
end

-- Starts a new run at Round 1 (after a short GET READY countdown).
function WaveService.startRun(newCallbacks: RunCallbacks)
	ZombieService.despawnAll()
	token += 1
	callbacks = newCallbacks
	round = 0
	aliveCount = 0
	totalThisRound = 0
	spawning = false
	phase = "Starting"
	publish()
	task.spawn(countdownTo, 1, RoundDefinitions.FirstRoundDelay, token)
end

-- Ends the current run immediately and removes every zombie (death, victory cleanup, leaving).
function WaveService.abort()
	token += 1
	callbacks = nil
	ZombieService.despawnAll()
	phase = "Idle"
	round = 0
	aliveCount = 0
	totalThisRound = 0
	countdown = 0
	spawning = false
	publish()
end

function WaveService.getPhase(): WavePhase
	return phase
end

return WaveService
