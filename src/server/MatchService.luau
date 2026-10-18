--!strict
-- The arena match state machine (one match per server) and every player's GameState.
--
--   Match:  idle (LOBBY) -> COUNTDOWN -> MATCH_ACTIVE <-> ROUND_COMPLETE -> VICTORY | MATCH_COMPLETE
--           -> CLEANUP -> idle            (published as "MatchState" on the arena folder)
--   Solo    : one fighter, rounds 1-2-4-8-16-32, then Round 7 (Otti), death ends the run.
--   Co-op   : 1-4 ready party members, scaled rounds, shared progression; the dead wait on the
--             tribune and return with 60 % health after a completed round; a full wipe ends it.
--             Round 7 is the Otti boss (OttiBossService); his defeat pays the boss reward once.
--   Team    : Red vs Blue via TeamBattleService; rewards 80 / 25 Aura.
-- Cleanup always removes zombies, Otti, projectiles, limbs, effects, shells and match attributes, returns
-- everybody to the lobby and frees the arena for the next match.
-- Also installs CombatRules (who may hit whom) and wires the lobby prompts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local GameModeDefinitions = require(ReplicatedStorage.Shared.GameModeDefinitions)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local Arena = require(script.Parent.Arena)
local AuraService = require(script.Parent.AuraService)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatRules = require(script.Parent.CombatRules)
local CombatUtil = require(script.Parent.CombatUtil)
local InventoryService = require(script.Parent.InventoryService)
local LobbyService = require(script.Parent.LobbyService)
local OttiBossConfig = require(ReplicatedStorage.Shared.OttiBossConfig)
local OttiBossService = require(script.Parent.OttiBossService)
local PartyService = require(script.Parent.PartyService)
local PlayerCombatService = require(script.Parent.PlayerCombatService)
local ProjectileService = require(script.Parent.ProjectileService)
local Remotes = require(script.Parent.Remotes)
local ShellService = require(script.Parent.ShellService)
local TeamBattleService = require(script.Parent.TeamBattleService)
local TrainingService = require(script.Parent.TrainingService)
local VictoryService = require(script.Parent.VictoryService)
local WaveService = require(script.Parent.WaveService)
local ZombieService = require(script.Parent.ZombieService)

type GameState = GameStates.GameState
type Location = GameStates.Location
type ModeId = GameModeDefinitions.ModeId

local PREFIX = "[OttiArena][Server]"
local PROMPT_COOLDOWN = 1.2

type Match = {
	id: number,
	mode: ModeId,
	participants: { Player },
	alive: { [Player]: boolean }, -- zombie modes: currently fighting (not waiting to revive)
	ended: boolean,
	bossRewarded: boolean, -- the Otti reward is paid at most once per match
}

local MatchService = {}

local lobby: LobbyService.LobbyLayout? = nil
local arenaFolder: Instance? = nil
local match: Match? = nil
local matchCounter = 0
local lastPromptUse: { [Player]: number } = {}

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
end

local function message(player: Player, text: string, ok: boolean)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, text, ok)
end

local function debounced(player: Player): boolean
	local now = os.clock()
	local last = lastPromptUse[player]
	if last and now - last < PROMPT_COOLDOWN then
		return true
	end
	lastPromptUse[player] = now
	return false
end

local function teleport(player: Player, cframe: CFrame)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(cframe)
	end
end

local function lobbyCFrame(): CFrame
	local layout = lobby :: LobbyService.LobbyLayout
	return layout.spawnCFrame + Vector3.new(math.random(-3, 3), 3.5, math.random(-3, 3))
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

local function updateGateSigns()
	local layout = lobby
	if not layout then
		return
	end
	local current = match
	local busy = current ~= nil
	layout.soloLabel.Text = if busy then "ARENA BUSY · watch from the TRIBUNES" else "ARENA READY"
	layout.soloLabel.TextColor3 = if busy then Color3.fromRGB(255, 130, 110) else Color3.fromRGB(140, 255, 140)
	local prompt = layout.soloGate:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = not busy -- the gate closes during an active match
	end
	if arenaFolder then
		arenaFolder:SetAttribute(Config.ArenaBusyAttribute, busy)
		arenaFolder:SetAttribute(Config.MatchModeAttribute, if current then current.mode else "")
	end
end

------------------------------------------------------------------------------------------
-- Cleanup
------------------------------------------------------------------------------------------

local function returnToLobby(player: Player)
	PlayerCombatService.resetCombatState(player)
	setState(player, GameStates.Lobby, "Lobby")
	local _, humanoid = CombatUtil.getLivingCharacter(player)
	if humanoid then
		teleport(player, lobbyCFrame())
	end
end

-- Ends the current match and resets everything. Safe to call more than once.
local function cleanupMatch(reason: string)
	local current = match
	if not current or current.ended then
		return
	end
	current.ended = true
	setMatchState(GameStates.Cleanup)
	print(PREFIX, ("Match %d (%s) cleanup: %s"):format(current.id, current.mode, reason))

	WaveService.abort()
	OttiBossService.stop()
	ZombieService.despawnAll()
	ProjectileService.clear()
	CombatEffects.clear()
	ShellService.setActiveCount(0)
	TeamBattleService.stop()

	for _, player in current.participants do
		if player.Parent then
			player:SetAttribute(Config.TeamAttribute, "")
			returnToLobby(player)
		end
	end
	match = nil
	if arenaFolder then
		arenaFolder:SetAttribute(Config.ResultAttribute, "")
	end
	publishPlayers()
	updateGateSigns()
	setMatchState(GameStates.Lobby)
	TeamBattleService.refreshLobby()
end

local function showResult(text: string)
	if arenaFolder then
		arenaFolder:SetAttribute(Config.ResultAttribute, text)
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
			cleanupMatch(if victory then "victory" else "defeat")
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
				teleport(player, Arena.getStartCFrame(index))
				humanoid.Health = math.floor(humanoid.MaxHealth * CombatConfig.CoopRespawnHealthFraction)
				setState(player, GameStates.RoundComplete, "Arena")
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
	publishPlayers()
	if #livingParticipants(current) == 0 then
		print(PREFIX, "All fighters defeated")
		endZombieMatch(current, false)
	elseif current.mode == "Coop" then
		message(player, "Defeated! You return after this round.", false)
	end
end

-- Otti defeated: boss reward exactly once, then the victory screen and the return to the lobby.
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

local function startZombieMatch(mode: ModeId, players: { Player }): boolean
	if match then
		for _, player in players do
			message(player, "The arena is busy. Watch from the TRIBUNES!", false)
		end
		return false
	end
	local valid = {}
	for _, player in players do
		local ok, reason = InventoryService.hasValidLoadout(player)
		local _, humanoid = CombatUtil.getLivingCharacter(player)
		if ok and humanoid and GameStates.isInLobby(getState(player)) then
			table.insert(valid, player)
		elseif not ok then
			message(player, reason, false)
		end
	end
	local definition = if mode == "Coop" then GameModeDefinitions.Coop else GameModeDefinitions.Solo
	if #valid < 1 or #valid > definition.MaxPlayers then
		return false
	end

	matchCounter += 1
	local current: Match = { id = matchCounter, mode = mode, participants = valid, alive = {}, ended = false, bossRewarded = false }
	match = current
	updateGateSigns()
	setMatchState(GameStates.Countdown)
	local shellCount = if mode == "Coop"
		then math.min(GameModeDefinitions.Coop.MaxShellCount, GameModeDefinitions.Coop.BaseShellCount + GameModeDefinitions.Coop.ShellsPerPlayer * #valid)
		else GameModeDefinitions.Solo.ShellCount
	ShellService.setActiveCount(shellCount)

	for index, player in valid do
		PartyService.remove(player)
		TeamBattleService.removeFromLobby(player)
		current.alive[player] = true
		AuraService.resetRunStats(player)
		PlayerCombatService.resetCombatState(player)
		PlayerCombatService.refreshEquipment(player) -- auto-equip the chosen weapon and shield
		setState(player, GameStates.Countdown, "Arena")
		teleport(player, Arena.getStartCFrame(index))
	end
	publishPlayers()
	print(PREFIX, ("Match %d: %s started with %d player(s), %d shells"):format(current.id, mode, #valid, shellCount))

	task.delay(0.5, function()
		if match ~= current or current.ended then
			return
		end
		for _, player in livingParticipants(current) do
			setState(player, GameStates.MatchActive)
		end
		setMatchState(GameStates.MatchActive)
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
			onRoundComplete = function()
				if match ~= current then
					return
				end
				setMatchState(GameStates.RoundComplete)
				for _, player in livingParticipants(current) do
					setState(player, GameStates.RoundComplete)
				end
				reviveWaitingPlayers(current)
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
				AuraService.awardZombieKill(zombie.definition.Coins, if killer and isParticipant(killer) then killer else nil, rewarded, assist)
			end,
		})
	end)
	return true
end

------------------------------------------------------------------------------------------
-- Team Battle
------------------------------------------------------------------------------------------

local function startTeamMatch(red: { Player }, blue: { Player }): boolean
	if match then
		return false
	end
	local all = {}
	for _, list in { red, blue } do
		for _, player in list do
			if player.Parent and CombatUtil.getLivingCharacter(player) then
				table.insert(all, player)
			end
		end
	end
	matchCounter += 1
	local current: Match = { id = matchCounter, mode = "TeamBattle", participants = all, alive = {}, ended = false, bossRewarded = false }
	match = current
	updateGateSigns()
	setMatchState(GameStates.MatchActive)
	ShellService.setActiveCount(if GameModeDefinitions.TeamBattle.ShellsEnabled then GameModeDefinitions.TeamBattle.ShellCount else 0)
	for _, list in { { team = "Red", players = red }, { team = "Blue", players = blue } } do
		for index, player in list.players do
			if table.find(all, player) then
				PartyService.remove(player)
				current.alive[player] = true
				AuraService.resetRunStats(player)
				PlayerCombatService.resetCombatState(player)
				PlayerCombatService.refreshEquipment(player)
				teleport(player, Arena.getTeamSpawnCFrame(list.team, index))
				PlayerCombatService.setSpawnProtection(player, CombatConfig.SpawnProtectionSeconds)
				setState(player, GameStates.MatchActive, "Arena")
			end
		end
	end
	TeamBattleService.beginMatch(red, blue)
	publishPlayers()
	print(PREFIX, ("Match %d: Team Battle %d v %d"):format(current.id, #red, #blue))
	return true
end

local function onTeamMatchFinished(winner: TeamBattleService.TeamName, reason: string)
	local current = match
	if not current or current.mode ~= "TeamBattle" or current.ended then
		return
	end
	local red, blue = TeamBattleService.getScore()
	showResult(("%s GLADIATORS WIN  %d - %d"):format(winner:upper(), red, blue))
	local winners, losers = {}, {}
	for _, player in TeamBattleService.getParticipants() do
		if player.Parent then
			if TeamBattleService.teamOf(player) == winner then
				table.insert(winners, player)
				setState(player, GameStates.Victory)
			else
				table.insert(losers, player)
				setState(player, GameStates.MatchComplete)
			end
		end
	end
	AuraService.awardMatchResult(winners, losers, GameModeDefinitions.TeamBattle.WinAura, GameModeDefinitions.TeamBattle.LoseAura)
	setMatchState(GameStates.Victory)
	if arenaFolder then
		VictoryService.play(arenaFolder)
	end
	print(PREFIX, ("Team Battle result: %s (%s)"):format(winner, reason))
	task.delay(GameModeDefinitions.TeamBattle.ResultSeconds, function()
		if match == current then
			cleanupMatch("team battle finished")
		end
	end)
end

------------------------------------------------------------------------------------------
-- Characters and players
------------------------------------------------------------------------------------------

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

local function onCharacterAdded(player: Player, character: Model)
	task.spawn(hookZombieModeDeath, player, character) -- every character, including revived ones
	local current = match
	if current and not current.ended and table.find(current.participants, player) then
		if current.mode == "TeamBattle" then
			if TeamBattleService.onCharacterAdded(player, character) then
				return
			end
		elseif current.mode == "Coop" and not current.alive[player] then
			-- Waits on the tribune until the current round is completed
			setState(player, GameStates.PlayerDefeated, "Tribune")
			task.spawn(function()
				character:WaitForChild("HumanoidRootPart", 5)
				task.wait(0.2)
				if match == current then
					teleport(player, Arena.getTribuneCFrame())
				end
			end)
			return
		end
	end
	setState(player, GameStates.Lobby, "Lobby")
end

local function onPlayerRemoving(player: Player)
	lastPromptUse[player] = nil
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
			cleanupMatch("all fighters left")
		end
	end
end

------------------------------------------------------------------------------------------
-- Lobby prompts
------------------------------------------------------------------------------------------

local function addPrompt(host: BasePart, actionText: string, objectText: string, holdDuration: number, onTriggered: (Player) -> ())
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = holdDuration
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.DPadUp
	prompt.Parent = host
	prompt.Triggered:Connect(function(player)
		if not debounced(player) then
			onTriggered(player)
		end
	end)
end

local function startSolo(player: Player)
	if not GameStates.isInLobby(getState(player)) then
		return
	end
	if PartyService.isMember(player) then
		PartyService.remove(player)
	end
	TeamBattleService.removeFromLobby(player)
	startZombieMatch("Solo", { player })
end

local function goToTribune(player: Player)
	if not GameStates.isInLobby(getState(player)) then
		return
	end
	PartyService.remove(player)
	TeamBattleService.removeFromLobby(player)
	PlayerCombatService.resetCombatState(player)
	setState(player, GameStates.Spectating, "Tribune")
	teleport(player, Arena.getTribuneCFrame())
end

local function leaveTribune(player: Player)
	local state = getState(player)
	if state == GameStates.Spectating then
		returnToLobby(player)
	elseif state == GameStates.PlayerDefeated and not isParticipant(player) then
		returnToLobby(player)
	end
end

------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------

function MatchService.isBusy(): boolean
	return match ~= nil
end

function MatchService.getLobbyCFrame(): CFrame
	return lobbyCFrame()
end

function MatchService.getState(player: Player): unknown
	return getState(player)
end

function MatchService.init(layout: LobbyService.LobbyLayout, folder: Instance)
	lobby = layout
	arenaFolder = folder
	Players.RespawnTime = GameModeDefinitions.TeamBattle.RespawnSeconds

	CombatRules.install({
		getContext = function(player: Player)
			local state = getState(player)
			local current = match
			if current and not current.ended and GameStates.isFighter(state) and table.find(current.participants, player) then
				if current.mode == "TeamBattle" then
					return "PvP"
				elseif current.alive[player] then
					return "Zombies"
				end
				return nil
			end
			if GameStates.isInLobby(state) then
				local _, _, root = CombatUtil.getLivingCharacter(player)
				if root and TrainingService.isInTrainingArea(root.Position) then
					return "Training"
				end
			end
			return nil
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

	PartyService.init(layout.folder, layout.coopJoin, layout.coopReady, layout.coopStart, layout.coopBoard, {
		onJoin = TeamBattleService.removeFromLobby,
		isArenaBusy = MatchService.isBusy,
		start = function(players)
			return startZombieMatch("Coop", players)
		end,
	})
	TeamBattleService.init(layout.folder, folder, {
		redPad = layout.redPad,
		bluePad = layout.bluePad,
		ready = layout.teamReady,
		leave = layout.teamLeave,
		balance = layout.teamBalance,
		redBoard = layout.redBoard,
		blueBoard = layout.blueBoard,
		status = layout.teamStatus,
	}, {
		onJoin = PartyService.remove,
		isArenaBusy = MatchService.isBusy,
		start = startTeamMatch,
		finished = onTeamMatchFinished,
	})

	addPrompt(layout.soloGate, "Start Solo Arena", "SOLO ARENA", 1, startSolo)
	addPrompt(layout.tribuneDoor, "Go to Tribunes", "TRIBUNES", 0.5, goToTribune)
	if Arena.Layout.ReturnDoor then
		addPrompt(Arena.Layout.ReturnDoor, "Return to Lobby", "RETURN TO LOBBY", 0.5, leaveTribune)
	end
	-- The spectator HUD's EXIT button does the same as the RETURN TO LOBBY door
	Remotes.CombatAction.OnServerEvent:Connect(function(player: Player, action: unknown)
		if action == "LeaveTribune" and not debounced(player) then
			leaveTribune(player)
		end
	end)

	local function setup(player: Player)
		setState(player, GameStates.Lobby, "Lobby")
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

	updateGateSigns()
	setMatchState(GameStates.Lobby)
	publishPlayers()
end

return MatchService
