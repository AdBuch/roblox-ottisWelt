--!strict
-- TEAM BATTLE: Red Gladiators vs Blue Gladiators, 1v1 up to 4v4.
-- Lobby: stand on the RED or BLUE pad (prompt) to join, LEAVE TEAM, READY / UNREADY and
-- AUTO BALANCE posts. When each team has at least one ready player (and the arena is free) a
-- 15 s countdown starts; it cancels if that stops being true. Only ready players fight.
-- Match: no zombies, no friendly fire, respawn after 4 s at the team spawn with 2 s protection,
-- first to 20 eliminations wins; when 8 minutes run out the higher score wins, a tie goes to
-- sudden death (next valid elimination wins). Eliminations/assists/deaths are tracked on the
-- server from damage it applied itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local GameModeDefinitions = require(ReplicatedStorage.Shared.GameModeDefinitions)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local InventoryService = require(script.Parent.InventoryService)
local Remotes = require(script.Parent.Remotes)

export type TeamName = "Red" | "Blue"

export type Hooks = {
	onJoin: (player: Player) -> (), -- leave other lobby groups (party)
	isArenaBusy: () -> boolean,
	start: (red: { Player }, blue: { Player }) -> boolean,
	finished: (winner: TeamName, reason: string) -> (),
}

type Member = { player: Player, ready: boolean }

type Match = {
	teamOf: { [Player]: TeamName },
	score: { Red: number, Blue: number },
	timeLeft: number,
	suddenDeath: boolean,
	damageLog: { [Player]: { [Player]: number } }, -- victim -> attacker -> last hit time
	finished: boolean,
	token: number,
	matchId: number, -- MatchService match id (PlayerMatchStateService)
	active: boolean, -- false during the arena countdown
}

local PREFIX = "[OttiArena][Server]"
local MODE = GameModeDefinitions.TeamBattle
local TEAMS: { TeamName } = { "Red", "Blue" }

local TeamBattleService = {}

local lobbyTeams: { Red: { Member }, Blue: { Member } } = { Red = {}, Blue = {} }
local lobbyFolder: Instance? = nil
local arenaFolder: Instance? = nil
local boards: { Red: TextLabel?, Blue: TextLabel?, Status: TextLabel? } = { Red = nil, Blue = nil, Status = nil }
local hooks: Hooks? = nil
local countdownToken = 0
local countdownRunning = false
local match: Match? = nil
local matchCounter = 0

local function message(player: Player, text: string, ok: boolean)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, text, ok)
end

------------------------------------------------------------------------------------------
-- Lobby teams
------------------------------------------------------------------------------------------

local function findMember(player: Player): (TeamName?, number?)
	for _, team in TEAMS do
		for i, member in lobbyTeams[team] do
			if member.player == player then
				return (team :: any) :: TeamName, i
			end
		end
	end
	return nil, nil
end

local function readyCount(team: TeamName): number
	local count = 0
	for _, member in lobbyTeams[team] do
		if member.ready then
			count += 1
		end
	end
	return count
end

local updateCountdown: () -> ()

-- True while the player is still choosing a team in the lobby (never for match participants).
local function inLobbyFlow(player: Player): boolean
	local state = player:GetAttribute(GameStates.StateAttribute)
	return GameStates.isInLobby(state) or state == GameStates.Countdown
end

-- Takes the starting players out of the lobby lists WITHOUT touching their attributes: from this
-- moment the match owns their state. (Root cause of the old Team Battle bug: players were removed
-- one by one after the match had started, and every publish() reset the still-listed participants
-- to READY_CHECK / TEAM_SELECTION and cleared their team, so the arena safety net sent them back
-- to the lobby.)
local function detachForMatch(players: { Player })
	for _, player in players do
		local team, index = findMember(player)
		if team and index then
			table.remove(lobbyTeams[team], index)
		end
	end
end

local function publish()
	for _, team in TEAMS do
		local parts, lines = {}, {}
		for _, member in lobbyTeams[team] do
			table.insert(parts, ("%s|%s"):format(member.player.DisplayName, if member.ready then "ready" else ""))
			table.insert(lines, ("%s  %s"):format(member.player.DisplayName, if member.ready then "READY" else "…"))
			-- Only lobby players are touched here: match participants are never in these lists
			member.player:SetAttribute(Config.TeamAttribute, team)
			member.player:SetAttribute(Config.ReadyAttribute, member.ready)
			if not countdownRunning and inLobbyFlow(member.player) then
				member.player:SetAttribute(GameStates.StateAttribute, if member.ready then GameStates.ReadyCheck else GameStates.TeamSelection)
			end
		end
		if lobbyFolder then
			lobbyFolder:SetAttribute(if team == "Red" then Config.RedRosterAttribute else Config.BlueRosterAttribute, table.concat(parts, ";"))
		end
		local board = boards[team]
		if board then
			board.Text = if #lines > 0 then table.concat(lines, "\n") else "(empty)"
		end
	end
	updateCountdown()
end

local function clearLobbyPlayer(player: Player)
	if player.Parent then
		player:SetAttribute(Config.TeamAttribute, "")
		player:SetAttribute(Config.ReadyAttribute, false)
		local state = player:GetAttribute(GameStates.StateAttribute)
		if state == GameStates.TeamSelection or state == GameStates.ReadyCheck or state == GameStates.Countdown then
			player:SetAttribute(GameStates.StateAttribute, GameStates.Lobby)
		end
	end
end

function TeamBattleService.removeFromLobby(player: Player)
	local team, index = findMember(player)
	if team and index then
		table.remove(lobbyTeams[team], index)
		clearLobbyPlayer(player)
		publish()
	end
end

local function join(player: Player, team: TeamName)
	if not GameStates.isInLobby(player:GetAttribute(GameStates.StateAttribute)) and player:GetAttribute(GameStates.StateAttribute) ~= GameStates.Countdown then
		return
	end
	local current = findMember(player)
	if current == team then
		return
	end
	if #lobbyTeams[team] >= MODE.MaxPerTeam then
		message(player, team .. " team is full (4 players)", false)
		return
	end
	if current then
		TeamBattleService.removeFromLobby(player)
	end
	if hooks then
		hooks.onJoin(player)
	end
	table.insert(lobbyTeams[team], { player = player, ready = false })
	publish()
	message(player, ("You joined the %s Gladiators"):format(team), true)
end

local function toggleReady(player: Player)
	local team, index = findMember(player)
	if not team or not index then
		message(player, "Choose RED or BLUE first", false)
		return
	end
	local member = lobbyTeams[team][index]
	if not member.ready then
		local ok, reason = InventoryService.hasValidLoadout(player)
		if not ok then
			message(player, reason, false)
			return
		end
	end
	member.ready = not member.ready
	publish()
end

local function autoBalance(player: Player)
	local moved = 0
	while math.abs(#lobbyTeams.Red - #lobbyTeams.Blue) > 1 do
		local from: TeamName = if #lobbyTeams.Red > #lobbyTeams.Blue then "Red" else "Blue"
		local to: TeamName = if from == "Red" then "Blue" else "Red"
		local member = table.remove(lobbyTeams[from])
		if not member then
			break
		end
		member.ready = false
		table.insert(lobbyTeams[to], member)
		moved += 1
	end
	publish()
	message(player, if moved > 0 then ("Auto balance moved %d player(s)"):format(moved) else "Teams are already balanced", true)
end

updateCountdown = function()
	local currentHooks = hooks
	local canStart = currentHooks ~= nil and readyCount("Red") >= MODE.MinPerTeam and readyCount("Blue") >= MODE.MinPerTeam and not currentHooks.isArenaBusy()
	local status = boards.Status
	if not canStart then
		if countdownRunning then
			countdownRunning = false
			countdownToken += 1
			if lobbyFolder then
				lobbyFolder:SetAttribute(Config.TeamCountdownAttribute, 0)
			end
			for _, team in TEAMS do
				for _, member in lobbyTeams[team] do
					if inLobbyFlow(member.player) then
						member.player:SetAttribute(GameStates.StateAttribute, if member.ready then GameStates.ReadyCheck else GameStates.TeamSelection)
					end
				end
			end
		end
		if status then
			status.Text = if currentHooks and currentHooks.isArenaBusy() then "Arena busy" else "Need 1 ready player per team"
		end
		return
	end
	if countdownRunning then
		return
	end
	countdownRunning = true
	countdownToken += 1
	local myToken = countdownToken
	task.spawn(function()
		for remaining = MODE.StartCountdownSeconds, 1, -1 do
			if countdownToken ~= myToken then
				return
			end
			if lobbyFolder then
				lobbyFolder:SetAttribute(Config.TeamCountdownAttribute, remaining)
			end
			if status then
				status.Text = ("Starting in %d"):format(remaining)
			end
			for _, team in TEAMS do
				for _, member in lobbyTeams[team] do
					if inLobbyFlow(member.player) then
						member.player:SetAttribute(GameStates.StateAttribute, GameStates.Countdown)
					end
				end
			end
			task.wait(1)
		end
		if countdownToken ~= myToken then
			return
		end
		countdownRunning = false
		if lobbyFolder then
			lobbyFolder:SetAttribute(Config.TeamCountdownAttribute, 0)
		end
		local red, blue = {}, {}
		for _, member in lobbyTeams.Red do
			if member.ready and member.player.Parent then
				table.insert(red, member.player)
			end
		end
		for _, member in lobbyTeams.Blue do
			if member.ready and member.player.Parent then
				table.insert(blue, member.player)
			end
		end
		local startHooks = hooks
		if #red >= 1 and #blue >= 1 and startHooks then
			-- Detach first, atomically, then hand the players to the match
			local all = table.clone(red)
			table.move(blue, 1, #blue, #all + 1, all)
			detachForMatch(all)
			if not startHooks.start(red, blue) then
				-- The arena was taken meanwhile: put them back into their lobby teams
				for _, player in red do
					table.insert(lobbyTeams.Red, { player = player, ready = true })
				end
				for _, player in blue do
					table.insert(lobbyTeams.Blue, { player = player, ready = true })
				end
			end
		end
		publish()
	end)
end

------------------------------------------------------------------------------------------
-- Match runtime
------------------------------------------------------------------------------------------

local function publishMatch()
	local folder = arenaFolder
	local current = match
	if folder and current then
		folder:SetAttribute(Config.RedScoreAttribute, current.score.Red)
		folder:SetAttribute(Config.BlueScoreAttribute, current.score.Blue)
		folder:SetAttribute(Config.TimeLeftAttribute, current.timeLeft)
		folder:SetAttribute(Config.SuddenDeathAttribute, current.suddenDeath)
	end
end

local function participants(current: Match): { Player }
	local list = {}
	for player in current.teamOf do
		table.insert(list, player)
	end
	return list
end

local function broadcast(current: Match, text: string)
	for _, player in participants(current) do
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Elimination, text)
	end
end

local function finish(winner: TeamName, reason: string)
	local current = match
	if not current or current.finished then
		return -- exactly once
	end
	current.finished = true
	current.token += 1
	print(PREFIX, ("Team Battle finished: %s wins (%s) %d-%d"):format(winner, reason, current.score.Red, current.score.Blue))
	local currentHooks = hooks
	if currentHooks then
		task.spawn(currentHooks.finished, winner, reason)
	end
end

local function addStat(player: Player, attribute: string)
	player:SetAttribute(attribute, (tonumber(player:GetAttribute(attribute)) or 0) + 1)
end

local function onParticipantDied(victim: Player)
	local current = match
	if not current or current.finished or not current.teamOf[victim] then
		return
	end
	addStat(victim, Config.DeathsAttribute)
	victim:SetAttribute(GameStates.StateAttribute, GameStates.PlayerDefeated)
	local log: { [Player]: number } = current.damageLog[victim] or {}
	current.damageLog[victim] = nil
	local now = os.clock()
	local killer: Player? = nil
	local latest = -math.huge
	for attacker, time in log do
		if now - time <= MODE.AssistWindowSeconds and current.teamOf[attacker] and current.teamOf[attacker] ~= current.teamOf[victim] and time > latest then
			killer, latest = attacker, time
		end
	end
	if not killer then
		broadcast(current, ("%s was defeated"):format(victim.DisplayName))
		return
	end
	local team: TeamName = current.teamOf[killer]
	current.score[team] += 1
	addStat(killer, Config.EliminationsAttribute)
	for attacker, time in log do
		if attacker ~= killer and now - time <= MODE.AssistWindowSeconds and current.teamOf[attacker] == team then
			addStat(attacker, Config.AssistsAttribute)
		end
	end
	publishMatch()
	broadcast(current, ("%s eliminated %s"):format(killer.DisplayName, victim.DisplayName))
	if current.suddenDeath then
		finish(team, "sudden death")
	elseif current.score[team] >= MODE.ScoreToWin then
		finish(team, "score limit")
	end
end

-- Listens for this participant character's death (called for every (re)spawned character by
-- MatchSpawnService, which also places it at the team spawn).
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

-- True once the arena countdown is over for this match id.
function TeamBattleService.isActive(matchId: number): boolean
	local current = match
	return current ~= nil and current.matchId == matchId and current.active and not current.finished
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

function TeamBattleService.isEnemy(a: Player, b: Player): boolean
	local current = match
	if not current or current.finished then
		return false
	end
	local ta, tb = current.teamOf[a], current.teamOf[b]
	return ta ~= nil and tb ~= nil and ta ~= tb
end

-- Registers the teams for an already-teleported match (the arena countdown runs next).
function TeamBattleService.beginMatch(red: { Player }, blue: { Player }, matchId: number)
	matchCounter += 1
	local current: Match = {
		teamOf = {},
		score = { Red = 0, Blue = 0 },
		timeLeft = MODE.MatchSeconds,
		suddenDeath = false,
		damageLog = {},
		finished = false,
		token = matchCounter,
		matchId = matchId,
		active = false,
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
	end
	match = current
	for player in current.teamOf do
		if player.Character then
			task.spawn(TeamBattleService.hookCharacter, player, player.Character)
		end
	end
	publishMatch()
end

-- The arena countdown is over: the clock starts and combat counts.
function TeamBattleService.activate(matchId: number)
	local current = match
	if not current or current.matchId ~= matchId or current.active or current.finished then
		return
	end
	current.active = true
	local myToken = current.token
	task.spawn(function()
		while match == current and current.token == myToken and not current.finished do
			task.wait(1)
			if match ~= current or current.finished then
				return
			end
			if not current.suddenDeath then
				current.timeLeft = math.max(0, current.timeLeft - 1)
				if current.timeLeft == 0 then
					if current.score.Red ~= current.score.Blue then
						finish(if current.score.Red > current.score.Blue then "Red" else "Blue", "time")
					else
						current.suddenDeath = true
						broadcast(current, "SUDDEN DEATH: next elimination wins!")
					end
				end
				publishMatch()
			end
		end
	end)
end

-- A participant left the server during the match.
function TeamBattleService.removeParticipant(player: Player)
	local current = match
	if not current or not current.teamOf[player] then
		return
	end
	local team = current.teamOf[player]
	current.teamOf[player] = nil
	current.damageLog[player] = nil
	for _, log in current.damageLog do
		log[player] = nil -- no credit for hitting someone who disconnected
	end
	for _, other in current.teamOf do
		if other == team then
			return
		end
	end
	if not current.finished then
		finish(if team == "Red" then "Blue" else "Red", "opponents left")
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

-- Clears the match runtime (cleanup after the result screen).
function TeamBattleService.stop()
	local current = match
	if current then
		current.finished = true
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
	updateCountdown()
end

local function prompt(host: BasePart, action: string, objectText: string, callback: (Player) -> ())
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = objectText
	p.HoldDuration = 0.3
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.F
	p.GamepadKeyCode = Enum.KeyCode.DPadUp
	p.Parent = host
	local last: { [Player]: number } = {}
	p.Triggered:Connect(function(player)
		local now = os.clock()
		if last[player] and now - last[player] < 0.6 then
			return
		end
		last[player] = now
		callback(player)
	end)
end

export type LobbyParts = {
	redPad: BasePart,
	bluePad: BasePart,
	ready: BasePart,
	leave: BasePart,
	balance: BasePart,
	redBoard: TextLabel,
	blueBoard: TextLabel,
	status: TextLabel,
}

function TeamBattleService.init(lobby: Instance, arena: Instance, parts: LobbyParts, newHooks: Hooks)
	lobbyFolder = lobby
	arenaFolder = arena
	hooks = newHooks
	boards.Red, boards.Blue, boards.Status = parts.redBoard, parts.blueBoard, parts.status
	prompt(parts.redPad, "Join Red", "RED GLADIATORS", function(player)
		join(player, "Red")
	end)
	prompt(parts.bluePad, "Join Blue", "BLUE GLADIATORS", function(player)
		join(player, "Blue")
	end)
	prompt(parts.ready, "Ready / Unready", "TEAM BATTLE", toggleReady)
	prompt(parts.leave, "Leave Team", "TEAM BATTLE", function(player)
		TeamBattleService.removeFromLobby(player)
		message(player, "You left your team", true)
	end)
	prompt(parts.balance, "Auto Balance", "TEAM BATTLE", autoBalance)
	Players.PlayerRemoving:Connect(TeamBattleService.removeFromLobby)
	publish()
end

-- Re-evaluates the lobby countdown (e.g. when the arena becomes free again).
function TeamBattleService.refreshLobby()
	publish()
end

return TeamBattleService
