--!strict
-- TEAM BATTLE runtime in the Arena: Red vs Blue, 1v1 up to 4v4, no friendly fire, eliminations /
-- assists / deaths tracked from damage the server applied itself. The submode RULES are separate
-- modules (src/arena/server: TimeBattleService, FirstToKillsService, EliminationService) injected
-- with setRules(); this core owns teams, kill credit, alive state, publishing and the result.
-- Teams are formed by Hub matchmaking (never by clients); there is no lobby team selection here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local TeamModeDefinitions = require(ReplicatedStorage.Shared.TeamModeDefinitions)
local Arena = require(script.Parent.Arena)
local CombatUtil = require(script.Parent.CombatUtil)
local PlayerCombatService = require(script.Parent.PlayerCombatService)
local PlayerMatchStateService = require(script.Parent.PlayerMatchStateService)
local Remotes = require(script.Parent.Remotes)

export type TeamName = "Red" | "Blue"

export type Hooks = {
	finished: (winner: string, reason: string) -> (), -- "Red" | "Blue" | "Draw"
	statusChanged: () -> (),
}

-- What a submode's rules can see and do.
export type Context = {
	subMode: string,
	teamOf: { [Player]: TeamName },
	score: { Red: number, Blue: number },
	alive: { [Player]: boolean },
	timeLeft: number, -- -1 = no clock
	target: number,
	suddenDeath: boolean,
	round: number,
	teamSize: number,
	active: boolean,
	finished: boolean,
	token: number,
	-- actions
	finish: (winner: string, reason: string) -> (),
	broadcast: (text: string) -> (),
	publish: () -> (),
	setActive: (active: boolean) -> (),
	livingCount: (team: TeamName) -> number,
	respawnAll: () -> (), -- everyone back to their team spawn as a fighter
	stillCurrent: () -> boolean,
}

export type Rules = {
	respawns: boolean, -- false: a defeated player stays out until the next round
	setup: (ctx: Context) -> (),
	onActivated: ((ctx: Context) -> ())?,
	onSecond: (ctx: Context) -> (),
	onDeath: (ctx: Context, victim: Player, killerTeam: TeamName?) -> (),
}

type Match = Context & {
	matchId: number,
	damageLog: { [Player]: { [Player]: number } }, -- victim -> attacker -> last hit time
	rules: Rules,
}

local PREFIX = "[OttiArena][Server]"
local COMMON = TeamModeDefinitions.Common

local TeamBattleService = {}

local arenaFolder: Instance? = nil
local hooks: Hooks? = nil
local rulesById: { [string]: Rules } = {}
local match: Match? = nil
local tokenCounter = 0

local function participants(current: Match): { Player }
	local list = {}
	for player in current.teamOf do
		table.insert(list, player)
	end
	return list
end

local function addStat(player: Player, attribute: string)
	player:SetAttribute(attribute, (tonumber(player:GetAttribute(attribute)) or 0) + 1)
end

local function livingCount(current: Match, team: TeamName): number
	local count = 0
	for player, t in current.teamOf do
		if t == team and current.alive[player] ~= false and player.Parent then
			count += 1
		end
	end
	return count
end

local function publish(current: Match)
	local folder = arenaFolder
	if folder and match == current then
		folder:SetAttribute(Config.RedScoreAttribute, current.score.Red)
		folder:SetAttribute(Config.BlueScoreAttribute, current.score.Blue)
		folder:SetAttribute(Config.TimeLeftAttribute, math.max(0, current.timeLeft))
		folder:SetAttribute(Config.SuddenDeathAttribute, current.suddenDeath)
		folder:SetAttribute(Config.TeamSubModeAttribute, current.subMode)
		folder:SetAttribute(Config.ScoreTargetAttribute, current.target)
		folder:SetAttribute(Config.RedAliveAttribute, livingCount(current, "Red"))
		folder:SetAttribute(Config.BlueAliveAttribute, livingCount(current, "Blue"))
		folder:SetAttribute(Config.EliminationRoundAttribute, current.round)
	end
end

local function broadcast(current: Match, text: string)
	for _, player in participants(current) do
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Elimination, text)
	end
end

local function finish(current: Match, winner: string, reason: string)
	if current.finished or match ~= current then
		return -- exactly once
	end
	current.finished = true
	current.active = false
	current.token += 1
	print(PREFIX, ("Team Battle (%s) finished: %s (%s) %d-%d"):format(current.subMode, winner, reason, current.score.Red, current.score.Blue))
	local currentHooks = hooks
	if currentHooks then
		task.spawn(currentHooks.finished, winner, reason)
	end
end

local function zoneFor(team: TeamName): PlayerMatchStateService.SpawnZone
	return if team == "Red" then "RED_TEAM" else "BLUE_TEAM"
end

local function respawnAll(current: Match)
	for player, team in current.teamOf do
		if player.Parent then
			current.alive[player] = true
			current.damageLog[player] = nil
			PlayerMatchStateService.setZone(player, zoneFor(team :: TeamName))
			player:SetAttribute(Config.ArenaRoleAttribute, "FIGHTER")
			PlayerCombatService.resetCombatState(player)
			task.spawn(function()
				pcall(function()
					player:LoadCharacterAsync() -- MatchSpawnService places the new character at the team spawn
				end)
			end)
		end
	end
	publish(current)
end

local function onParticipantDied(victim: Player)
	local current = match
	if not current or current.finished or not current.teamOf[victim] then
		return
	end
	if current.alive[victim] == false then
		return -- already out this round
	end
	addStat(victim, Config.DeathsAttribute)
	victim:SetAttribute(GameStates.StateAttribute, GameStates.PlayerDefeated)
	local log: { [Player]: number } = current.damageLog[victim] or {}
	current.damageLog[victim] = nil
	local now = os.clock()
	local killer: Player? = nil
	local latest = -math.huge
	for attacker, time in log do
		if now - time <= COMMON.AssistWindowSeconds and current.teamOf[attacker] and current.teamOf[attacker] ~= current.teamOf[victim] and time > latest then
			killer, latest = attacker, time
		end
	end
	local killerTeam: TeamName? = nil
	if killer then
		killerTeam = current.teamOf[killer]
		addStat(killer, Config.EliminationsAttribute)
		for attacker, time in log do
			if attacker ~= killer and now - time <= COMMON.AssistWindowSeconds and current.teamOf[attacker] == killerTeam then
				addStat(attacker, Config.AssistsAttribute)
			end
		end
		broadcast(current, ("%s eliminated %s"):format(killer.DisplayName, victim.DisplayName))
	else
		broadcast(current, ("%s was defeated"):format(victim.DisplayName))
	end
	if not current.rules.respawns then
		-- Out for the rest of the round: respawn in the closed waiting box, follow teammates only
		current.alive[victim] = false
		PlayerMatchStateService.setZone(victim, "ELIMINATED")
		victim:SetAttribute(Config.ArenaRoleAttribute, "ELIMINATED_SPECTATOR")
	end
	current.rules.onDeath(current, victim, killerTeam)
	publish(current)
	local currentHooks = hooks
	if currentHooks then
		task.spawn(currentHooks.statusChanged)
	end
end

------------------------------------------------------------------------------------------
-- API used by MatchService / MatchSpawnService / CombatRules
------------------------------------------------------------------------------------------

function TeamBattleService.setRules(rules: { [string]: Rules })
	rulesById = rules
end

-- Listens for this participant character's death (called for every (re)spawned character).
function TeamBattleService.hookCharacter(player: Player, character: Model)
	local current = match
	if not current or current.finished or not current.teamOf[player] then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			if match == current then
				onParticipantDied(player)
			end
		end)
	end
end

-- True once the arena countdown (or the round countdown) is over for this match id.
function TeamBattleService.isActive(matchId: number): boolean
	local current = match
	return current ~= nil and current.matchId == matchId and current.active and not current.finished
end

function TeamBattleService.isAlive(player: Player): boolean
	local current = match
	return current ~= nil and current.teamOf[player] ~= nil and current.alive[player] ~= false
end

function TeamBattleService.livingParticipants(): { Player }
	local current = match
	local list = {}
	if current then
		for player in current.teamOf do
			if player.Parent and current.alive[player] ~= false and CombatUtil.getLivingCharacter(player) then
				table.insert(list, player)
			end
		end
	end
	return list
end

function TeamBattleService.recordDamage(victim: Player, attacker: Player?, _amount: number)
	local current = match
	if not current or not attacker or not current.teamOf[victim] then
		return
	end
	local log = current.damageLog[victim]
	if not log then
		log = {}
		current.damageLog[victim] = log
	end
	log[attacker] = os.clock()
end

function TeamBattleService.teamOf(player: Player): TeamName?
	local current = match
	return if current then current.teamOf[player] else nil
end

-- No friendly fire; only living fighters of opposite teams while the match is active.
function TeamBattleService.isEnemy(a: Player, b: Player): boolean
	local current = match
	if not current or current.finished or not current.active then
		return false
	end
	local ta, tb = current.teamOf[a], current.teamOf[b]
	return ta ~= nil and tb ~= nil and ta ~= tb and current.alive[a] ~= false and current.alive[b] ~= false
end

-- Registers the teams (the arena countdown runs next; activate() starts the rules' clock).
function TeamBattleService.beginMatch(red: { Player }, blue: { Player }, matchId: number, subMode: string)
	local rules = rulesById[subMode] or rulesById.TIME_BATTLE
	assert(rules, "TeamBattleService: no rules installed")
	tokenCounter += 1
	local current: Match
	current = {
		subMode = if rulesById[subMode] then subMode else "TIME_BATTLE",
		teamOf = {},
		score = { Red = 0, Blue = 0 },
		alive = {},
		timeLeft = -1,
		target = 0,
		suddenDeath = false,
		round = 0,
		teamSize = math.max(#red, #blue),
		active = false,
		finished = false,
		token = tokenCounter,
		matchId = matchId,
		damageLog = {},
		rules = rules,
		finish = function(winner: string, reason: string)
			finish(current, winner, reason)
		end,
		broadcast = function(text: string)
			broadcast(current, text)
		end,
		publish = function()
			publish(current)
			local currentHooks = hooks
			if currentHooks then
				task.spawn(currentHooks.statusChanged)
			end
		end,
		setActive = function(active: boolean)
			current.active = active and not current.finished
			Arena.setSpawnBarriers(not active)
			local folder = arenaFolder
			for player in current.teamOf do
				if player.Parent and current.alive[player] ~= false and CombatUtil.getLivingCharacter(player) then
					player:SetAttribute(GameStates.StateAttribute, if current.active then GameStates.MatchActive else GameStates.Countdown)
				end
			end
			if folder then
				folder:SetAttribute(Config.MatchStateAttribute, if current.active then GameStates.MatchActive else GameStates.RoundComplete)
			end
		end,
		livingCount = function(team: TeamName): number
			return livingCount(current, team)
		end,
		respawnAll = function()
			respawnAll(current)
		end,
		stillCurrent = function(): boolean
			return match == current and not current.finished
		end,
	}
	for _, player in red do
		current.teamOf[player] = "Red"
	end
	for _, player in blue do
		current.teamOf[player] = "Blue"
	end
	for player, team in current.teamOf do
		player:SetAttribute(Config.TeamAttribute, team)
		player:SetAttribute(Config.EliminationsAttribute, 0)
		player:SetAttribute(Config.DeathsAttribute, 0)
		player:SetAttribute(Config.AssistsAttribute, 0)
		current.alive[player] = true
	end
	match = current
	rules.setup(current)
	for player in current.teamOf do
		if player.Character then
			task.spawn(TeamBattleService.hookCharacter, player, player.Character)
		end
	end
	publish(current)
end

-- The arena countdown is over: the rules' clock starts and combat counts.
function TeamBattleService.activate(matchId: number)
	local current = match
	if not current or current.matchId ~= matchId or current.active or current.finished then
		return
	end
	current.active = true
	local onActivated = current.rules.onActivated
	if onActivated then
		onActivated(current)
	end
	local myToken = current.token
	task.spawn(function()
		while match == current and current.token == myToken and not current.finished do
			task.wait(1)
			if match ~= current or current.finished then
				return
			end
			current.rules.onSecond(current)
			publish(current)
		end
	end)
	publish(current)
end

-- A participant left the server during the match: the other team wins if one side is empty.
function TeamBattleService.removeParticipant(player: Player)
	local current = match
	if not current or not current.teamOf[player] then
		return
	end
	local team = current.teamOf[player]
	current.teamOf[player] = nil
	current.alive[player] = nil
	current.damageLog[player] = nil
	for _, log in current.damageLog do
		log[player] = nil -- no credit for hitting someone who disconnected
	end
	publish(current)
	for _, other in current.teamOf do
		if other == team then
			current.rules.onDeath(current, player, nil) -- e.g. Elimination: the round may end now
			return
		end
	end
	if not current.finished then
		finish(current, if team == "Red" then "Blue" else "Red", "opponents left")
	end
end

function TeamBattleService.getParticipants(): { Player }
	local current = match
	return if current then participants(current) else {}
end

function TeamBattleService.getScore(): (number, number)
	local current = match
	if current then
		return current.score.Red, current.score.Blue
	end
	return 0, 0
end

function TeamBattleService.getContext(): Context?
	return match
end

-- Clears the match runtime (cleanup after the result screen).
function TeamBattleService.stop()
	local current = match
	if current then
		current.finished = true
		current.active = false
		current.token += 1
		for player in current.teamOf do
			if player.Parent then
				player:SetAttribute(Config.TeamAttribute, "")
			end
		end
	end
	match = nil
	local folder = arenaFolder
	if folder then
		folder:SetAttribute(Config.RedScoreAttribute, 0)
		folder:SetAttribute(Config.BlueScoreAttribute, 0)
		folder:SetAttribute(Config.TimeLeftAttribute, 0)
		folder:SetAttribute(Config.SuddenDeathAttribute, false)
	end
end

function TeamBattleService.init(arena: Instance, newHooks: Hooks)
	arenaFolder = arena
	hooks = newHooks
end

return TeamBattleService
