--!strict
-- The arena match runtime of ONE reserved Arena server (one match per server) and every player's
-- GameState in it. ArenaMatchService starts exactly one match after admission; the result
-- sequence ends with `hooks.ended`, which returns everyone to the Hub (ArenaReturnService).
--
--   Match:  COUNTDOWN -> MATCH_ACTIVE <-> ROUND_COMPLETE -> VICTORY | MATCH_COMPLETE -> CLEANUP
--           (published as "MatchState" on the arena folder)
--   Solo    : one fighter, rounds 1-2-4-8-16-32, then Round 7 (Otti), death ends the run.
--   Co-op   : 1-4 fighters, scaled rounds, shared progression; the dead wait on the tribune and
--             return with 60 % health after a completed round; a full wipe ends it.
--   Team    : Red vs Blue via TeamBattleService with a submode (Time / First to / Elimination).
-- Spectators (admitted by ticket) watch from the tribunes and never take part.
-- Rewards are paid exactly once per match (Aura + saved statistics), by the server only.
-- Also installs CombatRules (who may hit whom).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local GameModeDefinitions = require(ReplicatedStorage.Shared.GameModeDefinitions)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local OttiBossConfig = require(ReplicatedStorage.Shared.OttiBossConfig)
local TeamModeDefinitions = require(ReplicatedStorage.Shared.TeamModeDefinitions)
local Arena = require(script.Parent.Arena)
local AuraService = require(script.Parent.AuraService)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatRules = require(script.Parent.CombatRules)
local CombatUtil = require(script.Parent.CombatUtil)
local DamageEffectsService = require(script.Parent.DamageEffectsService)
local InventoryService = require(script.Parent.InventoryService)
local MatchSpawnService = require(script.Parent.MatchSpawnService)
local MomentumService = require(script.Parent.MomentumService)
local MomentumConfig = require(ReplicatedStorage.Shared.MomentumConfig)
local OttiBossService = require(script.Parent.OttiBossService)
local OttiSpectatorService = require(script.Parent.OttiSpectatorService)
local PlayerCombatService = require(script.Parent.PlayerCombatService)
local PlayerMatchStateService = require(script.Parent.PlayerMatchStateService)
local ProjectileService = require(script.Parent.ProjectileService)
local Remotes = require(script.Parent.Remotes)
local ShellService = require(script.Parent.ShellService)
local TeamBattleService = require(script.Parent.TeamBattleService)
local VictoryService = require(script.Parent.VictoryService)
local WaveService = require(script.Parent.WaveService)
local ZombieService = require(script.Parent.ZombieService)

type GameState = GameStates.GameState
type Location = GameStates.Location
type ModeId = GameModeDefinitions.ModeId

local PREFIX = "[OttiArena][Server]"

export type Result = { reason: string, victory: boolean, mode: ModeId }

export type Hooks = {
	ended: (result: Result) -> (), -- result sequence over: return everybody to the Hub
	statusChanged: () -> (), -- publish the registry record now (round / boss / score changes)
}

type Match = {
	id: number,
	mode: ModeId,
	participants: { Player },
	alive: { [Player]: boolean }, -- zombie modes: currently fighting (not waiting to revive)
	ended: boolean,
	rewarded: boolean, -- match rewards are paid at most once
	bossRewarded: boolean,
	boss: string?, -- BOSS_SOLO: the boss fought directly (Otti, Kroko or Schili); nil = zombie run
}

local MatchService = {}

local arenaFolder: Instance? = nil
local hooks: Hooks? = nil
local match: Match? = nil
local finished = false -- this server's one match is over (no second match on a reserved server)

------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------

local function setState(player: Player, state: GameState, location: Location?)
	if not player.Parent then
		return
	end
	player:SetAttribute(GameStates.StateAttribute, state)
	if location then
		player:SetAttribute(GameStates.LocationAttribute, location)
	end
end

local function getState(player: Player): unknown
	return player:GetAttribute(GameStates.StateAttribute)
end

local function setMatchState(state: GameState)
	if arenaFolder then
		arenaFolder:SetAttribute(Config.MatchStateAttribute, state)
	end
	local current = hooks
	if current then
		task.spawn(current.statusChanged)
	end
end

local function message(player: Player, text: string, ok: boolean)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, text, ok)
end

local function isParticipant(player: Player): boolean
	local current = match
	return current ~= nil and not current.ended and table.find(current.participants, player) ~= nil
end

local function publishPlayers()
	local current = match
	local folder = arenaFolder
	if not folder then
		return
	end
	local alive, total = 0, 0
	if current then
		for _, player in current.participants do
			if player.Parent then
				total += 1
				if current.mode == "TeamBattle" or current.alive[player] then
					alive += 1
				end
			end
		end
	end
	folder:SetAttribute(Config.PlayersAliveAttribute, alive)
	folder:SetAttribute(Config.PlayersTotalAttribute, total)
end

local function showResult(text: string)
	if arenaFolder then
		arenaFolder:SetAttribute(Config.ResultAttribute, text)
	end
end

------------------------------------------------------------------------------------------
-- End of the match
------------------------------------------------------------------------------------------

-- Stops everything; fighters wait on the tribune until the return teleport. Safe to call twice.
local function cleanupMatch(reason: string, victory: boolean)
	local current = match
	if not current or current.ended then
		return
	end
	current.ended = true
	finished = true
	setMatchState(GameStates.Cleanup)
	print(PREFIX, ("Match %d (%s) completed: %s"):format(current.id, current.mode, reason))

	WaveService.abort()
	OttiBossService.stop()
	OttiSpectatorService.stop()
	Arena.setSpawnBarriers(false)
	ZombieService.despawnAll()
	ProjectileService.clear()
	CombatEffects.clear()
	ShellService.setActiveCount(0)
	TeamBattleService.stop()

	for _, player in current.participants do
		if player.Parent then
			PlayerCombatService.resetCombatState(player)
			PlayerMatchStateService.setZone(player, "SPECTATOR")
			MomentumService.reset(player, 0)
			setState(player, GameStates.MatchComplete, "Tribune")
			if CombatUtil.getLivingCharacter(player) then
				MatchSpawnService.place(player)
			end
		end
	end
	publishPlayers()
	local currentHooks = hooks
	if currentHooks then
		task.spawn(currentHooks.ended, { reason = reason, victory = victory, mode = current.mode })
	end
end

------------------------------------------------------------------------------------------
-- Zombie modes (Solo / Co-op)
------------------------------------------------------------------------------------------

local function livingParticipants(current: Match): { Player }
	local list = {}
	for _, player in current.participants do
		if player.Parent and current.alive[player] then
			table.insert(list, player)
		end
	end
	return list
end

local function endZombieMatch(current: Match, victory: boolean, resultText: string?)
	if match ~= current or current.ended then
		return
	end
	setMatchState(if victory then GameStates.Victory else GameStates.MatchComplete)
	if not current.rewarded then
		current.rewarded = true
		for _, player in current.participants do
			if player.Parent then
				InventoryService.addStat(player, "zombieRuns", 1)
				if victory then
					InventoryService.addStat(player, if current.mode == "Solo" then "soloVictories" else "coopVictories", 1)
				end
			end
		end
	end
	for _, player in current.participants do
		if player.Parent then
			if victory then
				setState(player, GameStates.Victory)
			elseif current.alive[player] then
				setState(player, GameStates.MatchComplete)
			end
		end
	end
	if victory then
		showResult(resultText or "COLOSSEUM CONQUERED")
		if arenaFolder then
			VictoryService.play(arenaFolder)
		end
	else
		showResult("DEFEAT")
	end
	local delay = if victory then GameModeDefinitions.VictoryReturnSeconds else GameModeDefinitions.DefeatReturnSeconds
	task.delay(delay, function()
		if match == current then
			cleanupMatch(if victory then "victory" else "defeat", victory)
		end
	end)
end

local function reviveWaitingPlayers(current: Match)
	if current.mode ~= "Coop" then
		return
	end
	for index, player in current.participants do
		if player.Parent and not current.alive[player] then
			local _, humanoid = CombatUtil.getLivingCharacter(player)
			if humanoid then
				current.alive[player] = true
				PlayerCombatService.resetCombatState(player)
				PlayerMatchStateService.setZone(player, "ZOMBIE_ARENA")
				MatchSpawnService.place(player, index)
				humanoid.Health = math.floor(humanoid.MaxHealth * CombatConfig.CoopRespawnHealthFraction)
				setState(player, GameStates.RoundComplete, "Arena")
				player:SetAttribute(Config.ArenaRoleAttribute, "FIGHTER")
				message(player, "Back in the fight with 60% health!", true)
			end
		end
	end
	publishPlayers()
end

local function onZombieParticipantDied(current: Match, player: Player)
	if match ~= current or current.ended or not current.alive[player] then
		return
	end
	current.alive[player] = false
	setState(player, GameStates.PlayerDefeated)
	-- Co-op: respawn on the tribune and wait for the round; Solo: the run is over (tribune too)
	PlayerMatchStateService.setZone(player, "SPECTATOR")
	OttiSpectatorService.react("PlayerDefeated")
	publishPlayers()
	if #livingParticipants(current) == 0 then
		print(PREFIX, "All fighters defeated")
		endZombieMatch(current, false)
	elseif current.mode == "Coop" then
		message(player, "Defeated! You return after this round.", false)
	end
end

-- Otti defeated: boss reward exactly once, then the victory screen and the return to the Hub.
local function onBossDefeated(current: Match, damageBy: { [Player]: number })
	if match ~= current or current.ended or current.bossRewarded then
		return
	end
	current.bossRewarded = true
	local rewards: { { player: Player, amount: number } } = {}
	for _, player in current.participants do
		if player.Parent then
			if current.mode == "Solo" then
				table.insert(rewards, { player = player, amount = OttiBossConfig.SoloReward })
			elseif current.alive[player] then
				table.insert(rewards, { player = player, amount = OttiBossConfig.CoopSurvivorReward })
			elseif (damageBy[player] or 0) > 0 then
				table.insert(rewards, { player = player, amount = OttiBossConfig.CoopContributorReward })
			end
			if current.alive[player] or (damageBy[player] or 0) > 0 then
				InventoryService.addStat(player, "bossDefeats", 1)
			end
		end
	end
	AuraService.awardBossVictory(rewards)
	endZombieMatch(current, true, "OTTI DEFEATED")
end

-- Round 7: after the last Round 6 zombie, clean the arena and start the Otti encounter.
local function startBossRound(current: Match)
	if match ~= current or current.ended then
		return
	end
	WaveService.setBossPhase("BossIntro")
	ZombieService.despawnAll()
	local zombies = arenaFolder and arenaFolder:FindFirstChild(Config.ZombiesFolderName)
	if zombies then
		zombies:ClearAllChildren() -- remaining corpses
	end
	ProjectileService.clear()
	CombatEffects.clear() -- detached limbs, markers
	OttiBossService.startEncounter({
		companion = current.boss,
		playerCount = math.max(1, #livingParticipants(current)),
		participants = function()
			return current.participants
		end,
		fighters = function()
			if match ~= current or current.ended then
				return {}
			end
			local list = {}
			for _, player in livingParticipants(current) do
				if CombatRules.canZombiesTarget(player) then
					table.insert(list, player)
				end
			end
			return list
		end,
		onFightStarted = function()
			if match ~= current or current.ended then
				return
			end
			WaveService.setBossPhase("Boss")
			setMatchState(GameStates.MatchActive)
			for _, player in livingParticipants(current) do
				setState(player, GameStates.MatchActive)
			end
		end,
		onDefeated = function(damageBy)
			onBossDefeated(current, damageBy)
		end,
	})
end

local function newMatch(mode: ModeId, players: { Player }): Match
	return { id = 1, mode = mode, participants = players, alive = {}, ended = false, rewarded = false, bossRewarded = false }
end

-- Starts the zombie run for the admitted fighters ("Solo" or "Coop").
function MatchService.startZombies(mode: ModeId, players: { Player }, bossId: string?): boolean
	if match or finished then
		return false
	end
	local valid = {}
	for _, player in players do
		if player.Parent then
			table.insert(valid, player)
		end
	end
	local definition = if mode == "Coop" then GameModeDefinitions.Coop else GameModeDefinitions.Solo
	if #valid < 1 or #valid > definition.MaxPlayers then
		return false
	end

	local current = newMatch(mode, valid)
	current.boss = bossId
	match = current
	DamageEffectsService.newMatch() -- battle intensity resets
	if arenaFolder then
		arenaFolder:SetAttribute(Config.MatchModeAttribute, mode)
		arenaFolder:SetAttribute(Config.ArenaBusyAttribute, true)
	end
	setMatchState(GameStates.Countdown)
	local shellCount = if mode == "Coop"
		then math.min(GameModeDefinitions.Coop.MaxShellCount, GameModeDefinitions.Coop.BaseShellCount + GameModeDefinitions.Coop.ShellsPerPlayer * #valid)
		else GameModeDefinitions.Solo.ShellCount
	ShellService.setActiveCount(shellCount)

	for index, player in valid do
		current.alive[player] = true
		AuraService.resetRunStats(player)
		PlayerCombatService.resetCombatState(player)
		MomentumService.reset(player, if mode == "Coop" then MomentumConfig.Start.Coop else MomentumConfig.Start.Solo)
		PlayerCombatService.refreshEquipment(player) -- the saved weapon, shield and armor
		PlayerMatchStateService.assign(player, current.id, mode, "", "ZOMBIE_ARENA")
		player:SetAttribute(Config.ArenaRoleAttribute, "FIGHTER")
		setState(player, GameStates.Countdown, "Arena")
		MatchSpawnService.place(player, index)
	end
	OttiSpectatorService.begin() -- Otti watches from the imperial box
	publishPlayers()
	print(PREFIX, ("Match: %s started with %d player(s), %d shells"):format(mode, #valid, shellCount))

	task.delay(0.5, function()
		if match ~= current or current.ended then
			return
		end
		for _, player in livingParticipants(current) do
			setState(player, GameStates.MatchActive)
		end
		setMatchState(GameStates.MatchActive)
		if current.boss then
			startBossRound(current) -- a boss fight has no zombie rounds: straight to the boss
			return
		end
		WaveService.startRun({
			mode = mode,
			maxActive = if mode == "Coop" then GameModeDefinitions.Coop.MaxActiveZombies else GameModeDefinitions.Solo.MaxActiveZombies,
			getPlayerCount = function()
				local count = 0
				for _, player in current.participants do
					if player.Parent then
						count += 1
					end
				end
				return math.max(1, count)
			end,
			onRoundStarted = function()
				if match ~= current then
					return
				end
				setMatchState(GameStates.MatchActive)
				for _, player in livingParticipants(current) do
					setState(player, GameStates.MatchActive)
				end
			end,
			onRoundComplete = function(round: number)
				if match ~= current then
					return
				end
				setMatchState(GameStates.RoundComplete)
				for _, player in livingParticipants(current) do
					setState(player, GameStates.RoundComplete)
				end
				AuraService.awardRoundComplete(livingParticipants(current), current.id, round) -- once per round and player
				reviveWaitingPlayers(current)
				OttiSpectatorService.react("RoundComplete") -- applause from the imperial box
			end,
			onBossRound = function()
				startBossRound(current)
			end,
			onZombieDied = function(zombie, killer, damagers)
				local assist = if mode == "Coop" then GameModeDefinitions.Coop.AssistRewardFraction else 0
				local rewarded = {}
				for _, player in damagers do
					if isParticipant(player) then
						table.insert(rewarded, player)
					end
				end
				local validKiller = if killer and isParticipant(killer) then killer else nil
				if validKiller then
					InventoryService.addStat(validKiller, "zombieKills", 1)
				end
				AuraService.awardZombieKill(zombie.definition.Coins, validKiller, rewarded, assist)
			end,
		})
	end)
	return true
end

------------------------------------------------------------------------------------------
-- Team Battle
------------------------------------------------------------------------------------------

local function onTeamMatchFinished(winner: string, reason: string)
	local current = match
	if not current or current.mode ~= "TeamBattle" or current.ended then
		return
	end
	local red, blue = TeamBattleService.getScore()
	showResult(if winner == "Draw" then ("DRAW  %d - %d"):format(red, blue) else ("%s GLADIATORS WIN  %d - %d"):format(winner:upper(), red, blue))
	local winners, losers, draws = {}, {}, {}
	for _, player in TeamBattleService.getParticipants() do
		if player.Parent then
			if winner == "Draw" then
				table.insert(draws, player)
				setState(player, GameStates.MatchComplete)
			elseif TeamBattleService.teamOf(player) == winner then
				table.insert(winners, player)
				setState(player, GameStates.Victory)
			else
				table.insert(losers, player)
				setState(player, GameStates.MatchComplete)
			end
		end
	end
	if not current.rewarded then
		current.rewarded = true
		local common = TeamModeDefinitions.Common
		AuraService.awardMatchResult(winners, losers, common.WinAura, common.LoseAura)
		if #draws > 0 then
			AuraService.awardMatchResult(draws, {}, common.DrawAura, 0)
		end
		for _, player in TeamBattleService.getParticipants() do
			if player.Parent then
				InventoryService.addStat(player, "teamMatches", 1)
				InventoryService.addStat(player, "eliminations", tonumber(player:GetAttribute(Config.EliminationsAttribute)) or 0)
				InventoryService.addStat(player, "deaths", tonumber(player:GetAttribute(Config.DeathsAttribute)) or 0)
			end
		end
		for _, player in winners do
			InventoryService.addStat(player, "teamVictories", 1)
		end
	end
	setMatchState(GameStates.Victory)
	if arenaFolder then
		VictoryService.play(arenaFolder)
	end
	print(PREFIX, ("Team Battle result: %s (%s)"):format(winner, reason))
	task.delay(TeamModeDefinitions.Common.ResultSeconds, function()
		if match == current then
			cleanupMatch("team battle finished", winner ~= "Draw")
		end
	end)
end

-- Team Battle start (1v1 .. 4v4). Steps, all under one match:
--   teams assigned -> COUNTDOWN -> protected team spawns behind closed barriers -> arena
--   countdown -> MATCH_ACTIVE, barriers open. The submode rules live in TeamBattleService.
function MatchService.startTeams(red: { Player }, blue: { Player }, subMode: string): boolean
	if match or finished then
		return false
	end
	local teams: { { team: string, zone: PlayerMatchStateService.SpawnZone, players: { Player } } } = {
		{ team = "Red", zone = "RED_TEAM", players = {} },
		{ team = "Blue", zone = "BLUE_TEAM", players = {} },
	}
	local all = {}
	for i, list in { red, blue } do
		for _, player in list do
			if player.Parent then
				table.insert(all, player)
				table.insert(teams[i].players, player)
			end
		end
	end
	if #teams[1].players == 0 or #teams[2].players == 0 then
		return false
	end
	local current = newMatch("TeamBattle", all)
	match = current
	DamageEffectsService.newMatch()
	if arenaFolder then
		arenaFolder:SetAttribute(Config.MatchModeAttribute, "TeamBattle")
		arenaFolder:SetAttribute(Config.ArenaBusyAttribute, true)
	end
	print(PREFIX, ("Match: %s %d v %d"):format(subMode, #teams[1].players, #teams[2].players))
	setMatchState(GameStates.Countdown)
	local common = TeamModeDefinitions.Common
	ShellService.setActiveCount(if common.ShellsEnabled then common.ShellCount else 0)
	Arena.setSpawnBarriers(true)
	for _, entry in teams do
		for index, player in entry.players do
			current.alive[player] = true
			AuraService.resetRunStats(player)
			MomentumService.reset(player, if subMode == "ELIMINATION" then MomentumConfig.Start.EliminationRound else MomentumConfig.Start.TeamBattle)
			PlayerMatchStateService.assign(player, current.id, "TeamBattle", entry.team, entry.zone)
			player:SetAttribute(Config.ArenaRoleAttribute, "FIGHTER")
			PlayerCombatService.resetCombatState(player)
			PlayerCombatService.refreshEquipment(player)
			setState(player, GameStates.Countdown, "Arena")
			MatchSpawnService.place(player, index)
			PlayerCombatService.setSpawnProtection(player, common.ArenaCountdownSeconds + common.SpawnProtectionSeconds)
		end
	end
	TeamBattleService.beginMatch(teams[1].players, teams[2].players, current.id, subMode)
	publishPlayers()

	-- Arena countdown: barriers closed, no combat (COUNTDOWN is not a fighting state)
	task.spawn(function()
		for remaining = common.ArenaCountdownSeconds, 1, -1 do
			if match ~= current or current.ended then
				return
			end
			if arenaFolder then
				arenaFolder:SetAttribute(Config.CountdownAttribute, remaining)
			end
			task.wait(1)
		end
		if match ~= current or current.ended then
			return
		end
		if arenaFolder then
			arenaFolder:SetAttribute(Config.CountdownAttribute, 0)
		end
		Arena.setSpawnBarriers(false)
		setMatchState(GameStates.MatchActive)
		for _, player in current.participants do
			if player.Parent and PlayerMatchStateService.getMatchId(player) == current.id and CombatUtil.getLivingCharacter(player) then
				setState(player, GameStates.MatchActive, "Arena")
			end
		end
		TeamBattleService.activate(current.id)
		print(PREFIX, "Team match started: FIGHT")
	end)
	return true
end

------------------------------------------------------------------------------------------
-- Spectators and characters
------------------------------------------------------------------------------------------

-- An admitted spectator (or a fighter whose match ended / never started) on the tribunes.
function MatchService.addSpectator(player: Player)
	PlayerCombatService.resetCombatState(player)
	PlayerMatchStateService.setSpectator(player, true)
	PlayerMatchStateService.setZone(player, "SPECTATOR")
	player:SetAttribute(Config.ArenaRoleAttribute, "SPECTATOR")
	setState(player, GameStates.Spectating, "Tribune")
	MatchSpawnService.place(player)
end

local function hookZombieModeDeath(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			local active = match
			if active and not active.ended and active.mode ~= "TeamBattle" and table.find(active.participants, player) then
				onZombieParticipantDied(active, player)
			end
		end)
	end
end

-- Every (re)spawn is placed by the authoritative zone (ExpectedSpawnZone), never by guessing.
local function onCharacterAdded(player: Player, character: Model)
	task.spawn(hookZombieModeDeath, player, character)
	local zone = PlayerMatchStateService.getZone(player)
	if zone == "SPECTATOR" and isParticipant(player) and getState(player) == GameStates.PlayerDefeated then
		setState(player, GameStates.PlayerDefeated, "Tribune") -- co-op: waits for the round
	end
	if zone == "LOBBY" then
		-- No lobby in the Arena place: anybody without a zone waits on the tribune
		PlayerMatchStateService.setZone(player, "SPECTATOR")
	end
	MatchSpawnService.onCharacterAdded(player, character)
end

local function onPlayerRemoving(player: Player)
	local current = match
	if not current or current.ended or not table.find(current.participants, player) then
		return
	end
	if current.mode == "TeamBattle" then
		TeamBattleService.removeParticipant(player)
	else
		current.alive[player] = false
		local index = table.find(current.participants, player)
		if index then
			table.remove(current.participants, index)
		end
		publishPlayers()
		if #livingParticipants(current) == 0 then
			cleanupMatch("all fighters left", false)
		end
	end
end

------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------

function MatchService.isBusy(): boolean
	return match ~= nil
end

function MatchService.isFinished(): boolean
	return finished
end

function MatchService.getState(player: Player): unknown
	return getState(player)
end

function MatchService.isFighter(player: Player): boolean
	return isParticipant(player)
end

-- Fighters of the running match that are still connected.
function MatchService.fighters(): { Player }
	local current = match
	local list = {}
	if current then
		for _, player in current.participants do
			if player.Parent then
				table.insert(list, player)
			end
		end
	end
	return list
end

-- Living fighters (zombie modes: not waiting to revive; team modes: alive this round).
function MatchService.livingFighters(): { Player }
	local current = match
	if not current or current.ended then
		return {}
	end
	if current.mode == "TeamBattle" then
		return TeamBattleService.livingParticipants()
	end
	return livingParticipants(current)
end

function MatchService.getMode(): string
	local current = match
	return if current then current.mode else ""
end

-- Aborts a match that can't run (e.g. a team arrived incomplete): no rewards.
function MatchService.cancel(reason: string)
	if match then
		cleanupMatch(reason, false)
	else
		finished = true
		local currentHooks = hooks
		if currentHooks then
			task.spawn(currentHooks.ended, { reason = reason, victory = false, mode = "Solo" :: ModeId })
		end
	end
end

-- Mock mode only (Studio): allow a fresh match on the same server after the previous one.
function MatchService.resetForMock()
	match = nil
	finished = false
	if arenaFolder then
		arenaFolder:SetAttribute(Config.ResultAttribute, "")
		arenaFolder:SetAttribute(Config.MatchModeAttribute, "")
		arenaFolder:SetAttribute(Config.ArenaBusyAttribute, false)
	end
	publishPlayers()
end

function MatchService.init(folder: Instance, newHooks: Hooks)
	arenaFolder = folder
	hooks = newHooks
	Players.RespawnTime = TeamModeDefinitions.Common.RespawnSeconds

	CombatRules.install({
		getContext = function(player: Player)
			local state = getState(player)
			local current = match
			if current and not current.ended and GameStates.isFighter(state) and table.find(current.participants, player) then
				if current.mode == "TeamBattle" then
					return if TeamBattleService.isAlive(player) then "PvP" else nil
				elseif current.alive[player] then
					return "Zombies"
				end
			end
			return nil -- spectators, defeated players, the result sequence
		end,
		isEnemy = function(attacker: Player, victim: Player)
			return TeamBattleService.isEnemy(attacker, victim)
		end,
		canZombiesTarget = function(player: Player)
			local current = match
			return current ~= nil
				and not current.ended
				and current.mode ~= "TeamBattle"
				and current.alive[player] == true
				and GameStates.isFighter(getState(player))
		end,
		onPlayerDamaged = function(victim: Player, attacker: Player?, amount: number)
			TeamBattleService.recordDamage(victim, attacker, amount)
		end,
		zombieTargets = function()
			local current = match
			if not current or current.ended or current.mode == "TeamBattle" then
				return {}
			end
			return livingParticipants(current)
		end,
	})

	TeamBattleService.init(folder, {
		finished = onTeamMatchFinished,
		statusChanged = function()
			local currentHooks = hooks
			if currentHooks then
				task.spawn(currentHooks.statusChanged)
			end
		end,
	})

	MatchSpawnService.init({
		teamMatchActive = TeamBattleService.isActive,
		onTeamCharacter = TeamBattleService.hookCharacter,
	})

	local function setup(player: Player)
		PlayerMatchStateService.init(player)
		PlayerMatchStateService.setZone(player, "SPECTATOR")
		setState(player, GameStates.Spectating, "Tribune") -- until admission decides
		player:SetAttribute(Config.TeamAttribute, "")
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	setMatchState(GameStates.Lobby)
	publishPlayers()
end

-- BOSS FIGHT (solo): the chosen boss ("Otti" | "Kroko" | "Schili") straight away, no zombie rounds.
function MatchService.startBoss(players: { Player }, bossId: string): boolean
	return MatchService.startZombies("Solo", players, bossId)
end

return MatchService
