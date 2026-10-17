--!strict
-- Server-authoritative game state machine (per player, published as the "GameState" and
-- "Location" attributes) and the single active run.
--
--   LOBBY ──(ENTER ARENA prompt)──> ENTERING_ARENA ──> ROUND_ACTIVE <──> ROUND_COMPLETE
--     │                                                   │  dies              │ round 6 cleared
--     │                                                   v                    v
--     │                                            PLAYER_DEFEATED          VICTORY
--     │                                                   │ respawn            │ ~12 s
--     │<──────────────────────────────────────────────────┴────────────────────┘
--     └──(TRIBUNE door)──> SPECTATING ──(RETURN TO LOBBY door)──> LOBBY
--
-- This prototype supports ONE active fighter per server. While a run is active the arena
-- gate is closed; other players can watch from the tribune. Fighter-specific data lives in
-- `run`, so multiple runs could be added later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local RoundDefinitions = require(ReplicatedStorage.Shared.RoundDefinitions)
local Arena = require(script.Parent.Arena)
local CoinService = require(script.Parent.CoinService)
local CombatUtil = require(script.Parent.CombatUtil)
local InventoryService = require(script.Parent.InventoryService)
local LobbyService = require(script.Parent.LobbyService)
local PlayerCombatService = require(script.Parent.PlayerCombatService)
local Remotes = require(script.Parent.Remotes)
local VictoryService = require(script.Parent.VictoryService)
local WaveService = require(script.Parent.WaveService)

type GameState = GameStates.GameState
type Location = GameStates.Location

local PREFIX = "[OttiArena][Server]"
local PROMPT_COOLDOWN = 1.5

type Run = {
	fighter: Player,
	id: number,
	victory: boolean,
}

local GameStateService = {}

local lobby: LobbyService.LobbyLayout? = nil
local arenaFolder: Instance? = nil
local run: Run? = nil
local runCounter = 0
local transitioning = false
local lastPromptUse: { [Player]: number } = {}

local function setState(player: Player, state: GameState, location: Location?)
	player:SetAttribute(GameStates.StateAttribute, state)
	if location then
		player:SetAttribute(GameStates.LocationAttribute, location)
	end
end

local function getState(player: Player): unknown
	return player:GetAttribute(GameStates.StateAttribute)
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

local function setArenaBusy(busy: boolean, fighterName: string?)
	local folder = arenaFolder
	if folder then
		folder:SetAttribute(Config.ArenaBusyAttribute, busy)
		folder:SetAttribute(Config.FighterNameAttribute, fighterName or "")
	end
	local layout = lobby
	if layout then
		local prompt = layout.arenaGate:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = not busy -- the gate is closed during an active fight
		end
		layout.arenaGateLabel.Text = if busy then "ARENA BUSY" else "ENTER ARENA"
		layout.arenaGateLabel.TextColor3 = if busy then Color3.fromRGB(255, 120, 100) else Color3.fromRGB(240, 196, 80)
	end
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
	return layout.spawnCFrame + Vector3.new(0, 3.5, 0)
end

-- Ends the active run (if any) and cleans up every zombie. Safe to call more than once.
local function endRun(reason: string)
	local current = run
	if not current then
		return
	end
	run = nil
	WaveService.abort()
	PlayerCombatService.resetCombatState(current.fighter)
	setArenaBusy(false)
	print(PREFIX, ("Run %d ended: %s"):format(current.id, reason))
end

local function returnToLobby(player: Player)
	PlayerCombatService.resetCombatState(player)
	setState(player, GameStates.Lobby, "Lobby")
	teleport(player, lobbyCFrame())
end

local function onVictory(current: Run)
	if run ~= current or current.victory then
		return -- exactly once per run
	end
	current.victory = true
	local fighter = current.fighter
	setState(fighter, GameStates.Victory, "Arena")
	if arenaFolder then
		VictoryService.play(arenaFolder)
	end
	print(PREFIX, ("%s conquered the Colosseum: %d kills, %d coins this run"):format(
		fighter.Name,
		tonumber(fighter:GetAttribute(Config.RunKillsAttribute)) or 0,
		tonumber(fighter:GetAttribute(Config.RunCoinsAttribute)) or 0
	))
	task.delay(RoundDefinitions.VictoryReturnSeconds, function()
		if run ~= current then
			return
		end
		endRun("victory")
		if fighter.Parent then
			returnToLobby(fighter)
		end
	end)
end

local function enterArena(player: Player)
	if debounced(player) or transitioning then
		return
	end
	local state = getState(player)
	if not GameStates.canChangeEquipment(state) then
		return -- only from the lobby
	end
	if run then
		message(player, "The arena is busy. Watch from the TRIBUNE!", false)
		return
	end
	local _, humanoid = CombatUtil.getLivingCharacter(player)
	if not humanoid then
		return
	end
	local ok, reason = InventoryService.hasValidLoadout(player)
	if not ok then
		message(player, reason, false)
		return
	end

	transitioning = true
	runCounter += 1
	local current: Run = { fighter = player, id = runCounter, victory = false }
	run = current
	setArenaBusy(true, player.Name)
	setState(player, GameStates.EnteringArena, "Arena")
	CoinService.resetRunStats(player)
	PlayerCombatService.resetCombatState(player)
	PlayerCombatService.refreshEquipment(player) -- auto-equip the chosen weapon and shield
	teleport(player, Arena.getStartCFrame())
	print(PREFIX, ("Run %d: %s entered the arena"):format(current.id, player.Name))
	task.wait(0.5)
	transitioning = false
	if run ~= current then
		return
	end
	setState(player, GameStates.RoundActive, "Arena")

	WaveService.startRun({
		onRoundStarted = function()
			if run == current then
				setState(player, GameStates.RoundActive)
			end
		end,
		onRoundComplete = function()
			if run == current then
				setState(player, GameStates.RoundComplete)
			end
		end,
		onVictory = function()
			onVictory(current)
		end,
	})
end

local function goToTribune(player: Player)
	if debounced(player) then
		return
	end
	if not GameStates.canChangeEquipment(getState(player)) then
		return
	end
	PlayerCombatService.resetCombatState(player)
	setState(player, GameStates.Spectating, "Tribune")
	teleport(player, Arena.getTribuneCFrame())
end

local function leaveTribune(player: Player)
	if debounced(player) then
		return
	end
	if getState(player) ~= GameStates.Spectating then
		return
	end
	returnToLobby(player)
end

local function onCharacterAdded(player: Player, character: Model)
	local current = run
	if current and current.fighter == player then
		endRun("fighter respawned") -- safety: a respawn always ends the fighter's run
	end
	-- Every (re)spawn starts in the lobby
	setState(player, GameStates.Lobby, "Lobby")

	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			local active = run
			if active and active.fighter == player and not active.victory then
				setState(player, GameStates.PlayerDefeated)
				endRun("fighter defeated")
			elseif getState(player) ~= GameStates.Victory then
				setState(player, GameStates.PlayerDefeated)
			end
		end)
	end
end

local function addPrompt(host: BasePart, actionText: string, objectText: string, holdDuration: number, onTriggered: (Player) -> ())
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = holdDuration
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = host
	prompt.Triggered:Connect(onTriggered)
end

-- The players zombies may target: only the active fighter while a round is running.
function GameStateService.getFighters(): { Player }
	local current = run
	if current and current.fighter.Parent and GameStates.isFighter(getState(current.fighter)) then
		return { current.fighter }
	end
	return {}
end

function GameStateService.getState(player: Player): unknown
	return getState(player)
end

function GameStateService.getLobbyCFrame(): CFrame
	return lobbyCFrame()
end

function GameStateService.init(layout: LobbyService.LobbyLayout, folder: Instance)
	lobby = layout
	arenaFolder = folder
	setArenaBusy(false)

	addPrompt(layout.arenaGate, "Enter Arena", "ENTER ARENA", 1, enterArena)
	addPrompt(layout.tribuneDoor, "Go to Tribune", "TRIBUNE", 0.5, goToTribune)
	if Arena.Layout.ReturnDoor then
		addPrompt(Arena.Layout.ReturnDoor, "Return to Lobby", "RETURN TO LOBBY", 0.5, leaveTribune)
	end

	local function setup(player: Player)
		setState(player, GameStates.Lobby, "Lobby")
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
	Players.PlayerRemoving:Connect(function(player)
		lastPromptUse[player] = nil
		local current = run
		if current and current.fighter == player then
			endRun("fighter left")
		end
	end)
end

return GameStateService
