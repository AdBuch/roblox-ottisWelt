--!strict
-- Client entry point: builds the responsive HUD and wires server feedback, attributes and input
-- to it. The client never decides damage, hits, Momentum, blocks, parries, slides or victories.
--   ResponsiveHudController   layout, scale, compact health, round line, hints, hit flash
--   HudVisibilityController   UI state x Full / Minimal / Hidden (eye button, H key)
--   HudStateController        Lobby / Solo / Coop / TeamBattle / Boss / Spectator / Results
--   NotificationController    the one notification queue + short banners
--   ContextHealthController   world-space health bars (zombies, opponents, teammates)
--   TeamStatusController      team score + time, co-op teammate strip, lobby rosters
--   BossHudController         slim Otti bar + short warnings
--   AuraDisplayController     lobby Aura counter, "+n" rewards in combat
--   MobileControlsController  touch buttons (ATTACK, SPECIAL, BLOCK around Roblox's jump button)
--   SpecialChargeHudController the three-phase special charge bar (and the touch button fill)
--   CombatSettingsController  CAMERA pill (saved preference); Classic is the only control mode
--   InputController           Classic input -> CombatAction / ShieldBlock intents (block toggle, special hold)
--   SlideController           plays an approved slide on the own character
--   MomentumHudController     the ARENA MOMENTUM bar
--   CombatEffectsController   hit presentation by category (sparks, dust, CombatCamera; no blood)
--   InfoPanelController       optional "i" panel; SpectatorController for the tribunes

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PREFIX = "[OttiArena][Client]"
local WAIT_TIMEOUT = 10

local player = Players.LocalPlayer
print(PREFIX, "Client script started for", player.Name)

local function waitFor(parent: Instance, name: string): Instance?
	local child = parent:WaitForChild(name, WAIT_TIMEOUT)
	if not child then
		warn(PREFIX, ("Missing %s.%s after %ds"):format(parent:GetFullName(), name, WAIT_TIMEOUT))
	end
	return child
end

local function load(parent: Instance?, name: string): any
	local module = parent and waitFor(parent, name)
	if module and module:IsA("ModuleScript") then
		return require(module) :: any
	end
	warn(PREFIX, ("Cannot load module %s. Is Rojo synced?"):format(name))
	return nil
end

local shared = waitFor(ReplicatedStorage, "Shared")
local Config = load(shared, "Config")
local CombatConfig = load(shared, "CombatConfig")
local GameStates = load(shared, "GameStates")
local GameModeDefinitions = load(shared, "GameModeDefinitions")
local WeaponDefinitions = load(shared, "WeaponDefinitions")
local WeaponAttackDefinitions = load(shared, "WeaponAttackDefinitions")
local WeaponSpecialDefinitions = load(shared, "WeaponSpecialDefinitions")
local ShieldDefinitions = load(shared, "ShieldDefinitions")
local SpecialMoveDefinitions = load(shared, "SpecialMoveDefinitions")
local ResponsiveHudController = load(script.Parent, "ResponsiveHudController")
local HudVisibilityController = load(script.Parent, "HudVisibilityController")
local HudStateController = load(script.Parent, "HudStateController")
local NotificationController = load(script.Parent, "NotificationController")
local ContextHealthController = load(script.Parent, "ContextHealthController")
local TeamStatusController = load(script.Parent, "TeamStatusController")
local BossHudController = load(script.Parent, "BossHudController")
local AuraDisplayController = load(script.Parent, "AuraDisplayController")
local MobileControlsController = load(script.Parent, "MobileControlsController")
local InfoPanelController = load(script.Parent, "InfoPanelController")
local SpectatorController = load(script.Parent, "SpectatorController")
local InputController = load(script.Parent, "InputController")
local SpecialChargeHudController = load(script.Parent, "SpecialChargeHudController")
local CombatSettingsController = load(script.Parent, "CombatSettingsController")
local SlideController = load(script.Parent, "SlideController")
local MomentumHudController = load(script.Parent, "MomentumHudController")
local CombatEffectsController = load(script.Parent, "CombatEffectsController")
local CombatCameraController = load(script.Parent, "CombatCameraController")
local ShopController = load(script.Parent, "ShopController")
local EffectsController = load(script.Parent, "EffectsController")
local ZombieAnimator = load(script.Parent, "ZombieAnimator")
local OttiAnimator = load(script.Parent, "OttiAnimator")
local DamageEffectsController = load(script.Parent, "DamageEffectsController")
local CrowdEffectsController = load(script.Parent, "CrowdEffectsController")
local BowController = load(script.Parent, "BowController")
local ComboFeedbackController = load(script.Parent, "ComboFeedbackController")
local PlayerAnimator = load(script.Parent, "PlayerAnimator")
local OttiEntranceController = load(script.Parent, "OttiEntranceController")
local TeleportStatusController = load(script.Parent, "TeleportStatusController")
-- Build-time place role (Rojo project): the Hub shows the menus, the Arena the spectator tools
local placeRoleModule = shared and shared:FindFirstChild("PlaceRole")
local placeRole: string = if placeRoleModule and placeRoleModule:IsA("ModuleScript") then tostring(require(placeRoleModule) :: any) else "Hub"
local isArena = placeRole == "Arena"
local placeFolder = script.Parent:FindFirstChild("Place")
local GameModeMenuController = if not isArena then load(placeFolder, "GameModeMenuController") else nil
local ActiveBattlesController = if not isArena then load(placeFolder, "ActiveBattlesController") else nil
for _, module in {
	Config, CombatConfig, GameStates, GameModeDefinitions, WeaponDefinitions, WeaponAttackDefinitions, WeaponSpecialDefinitions,
	ShieldDefinitions, SpecialMoveDefinitions,
	ResponsiveHudController, HudVisibilityController, HudStateController, NotificationController, ContextHealthController,
	TeamStatusController, BossHudController, AuraDisplayController, MobileControlsController, InfoPanelController,
	SpectatorController, InputController, SpecialChargeHudController, CombatSettingsController, SlideController, MomentumHudController,
	CombatEffectsController, CombatCameraController,
	ShopController, EffectsController, ZombieAnimator, OttiAnimator, DamageEffectsController, CrowdEffectsController,
	BowController, ComboFeedbackController, PlayerAnimator, OttiEntranceController, TeleportStatusController,
} do
	if not module then
		return
	end
end

local playerGui = player:WaitForChild("PlayerGui")
local hud = ResponsiveHudController.create(playerGui)

-- Small edge buttons (eye = HUD mode, i = info) and the combat settings pills on the right edge
local edge = hud.group("EdgeButtons", Vector2.new(1, 0), UDim2.new(1, -8, 0, 40), UDim2.fromOffset(44, if isArena then 198 else 250))
local edgeList = Instance.new("UIListLayout")
edgeList.Padding = UDim.new(0, 8)
edgeList.SortOrder = Enum.SortOrder.LayoutOrder
edgeList.Parent = edge

local notifier: any = nil
local visibility = HudVisibilityController.create(edge, function(text: string)
	if notifier then
		notifier.push("Info", text)
	end
end)
notifier = NotificationController.create(hud.group, function()
	return visibility.allowed("Notifications")
end)
local function notify(kind: string, text: string, amount: number?)
	notifier.push(kind, text, amount)
end

local arena: Instance? = nil
local scheme = "Keyboard & Mouse"

local function gameState(): string
	return tostring(player:GetAttribute(GameStates.StateAttribute) or GameStates.Lobby)
end

local function arenaAttr(name: string): any
	return if arena then arena:GetAttribute(name) else nil
end

------------------------------------------------------------------ remotes and saved preferences
local remotes = waitFor(ReplicatedStorage, Config.RemotesFolderName)
local combatActionInstance = remotes and waitFor(remotes, Config.CombatActionRemoteName)
local shieldBlock = remotes and waitFor(remotes, Config.ShieldBlockRemoteName)
local feedback = remotes and waitFor(remotes, Config.CombatFeedbackRemoteName)
local combatAction: RemoteEvent? = if combatActionInstance and combatActionInstance:IsA("RemoteEvent") then combatActionInstance else nil
local matchRequestInstance = remotes and remotes:WaitForChild(Config.MatchRequestRemoteName, WAIT_TIMEOUT)
local matchEventInstance = remotes and remotes:WaitForChild(Config.MatchEventRemoteName, WAIT_TIMEOUT)
local matchRequest: RemoteFunction? = if matchRequestInstance and matchRequestInstance:IsA("RemoteFunction") then matchRequestInstance else nil
local matchEvent: RemoteEvent? = if matchEventInstance and matchEventInstance:IsA("RemoteEvent") then matchEventInstance else nil
local preferenceRemote = remotes and remotes:FindFirstChild(Config.PreferenceRemoteName)
local preferenceEvent: RemoteEvent? = if preferenceRemote and preferenceRemote:IsA("RemoteEvent") then preferenceRemote else nil

-- Match menus (Hub) / travel status (both): their own ScreenGui above the HUD
local menuGui = Instance.new("ScreenGui")
menuGui.Name = "MatchMenus"
menuGui.ResetOnSpawn = false
menuGui.DisplayOrder = 20
menuGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
menuGui.Parent = playerGui
TeleportStatusController.start(menuGui, matchRequest, matchEvent, isArena)
if not isArena and GameModeMenuController and ActiveBattlesController then
	local modeMenu: any = nil
	local live = ActiveBattlesController.start(menuGui, matchRequest, matchEvent, function()
		if modeMenu then
			modeMenu.open(nil)
		end
	end)
	modeMenu = GameModeMenuController.start(menuGui, edge, matchRequest, matchEvent, function()
		live.open()
	end, function(text: string)
		notify("Info", text)
	end)
	-- the overlay's MODE SELECTION button closes it and opens the menu
	local openMenu = modeMenu.open
	modeMenu.open = function(tab: string?)
		live.close()
		openMenu(tab)
	end
end

-- CAMERA setting (saved)
local settings = CombatSettingsController.start(edge, preferenceEvent, notify)

local aura = AuraDisplayController.start(hud.group, visibility, notify)
local controls = MobileControlsController.start(hud.group, visibility, hud.onLayout, function()
	return hud.layout.touch
end)
MomentumHudController.start(hud.group, visibility, hud.onLayout, player)

local function controlHint(): string
	if scheme == "Gamepad" then
		return "R2 Attack   L2 Block on/off   hold X Special   A Jump"
	elseif scheme == "Touch" then
		return ""
	end
	return "LMB Attack   RMB Block on/off   hold Q Special   Space Jump   F Interact"
end

local function equippedWeapon(): any
	return WeaponDefinitions.ById[tostring(player:GetAttribute(Config.EquippedWeaponAttribute))] or WeaponDefinitions.ById[WeaponDefinitions.Starter]
end

-- The TRAINING board (lobby training yard) shows the controls, the special tiers and Momentum
local lobbyFolder = if isArena then nil else Workspace:WaitForChild(Config.LobbyFolderName, WAIT_TIMEOUT)
local comboFeedback = ComboFeedbackController.start(hud.group, visibility, hud.onLayout, lobbyFolder)
local function refreshSpecials()
	comboFeedback.showBoard(equippedWeapon())
end

------------------------------------------------------------------ effects (shared by every fight)
local cameraFx = CombatCameraController.start()
cameraFx.setShake(settings.getCameraShake())
settings.onChanged(function()
	cameraFx.setShake(settings.getCameraShake())
end)
local combatEffects = CombatEffectsController.start({
	gui = hud.gui,
	camera = cameraFx,
	userId = function()
		return player.UserId
	end,
})

------------------------------------------------------------------ input: Classic controls + charge display
local chargeHud = SpecialChargeHudController.start(hud.group, visibility, controls.setCharge)
local input: any = nil
if combatAction and shieldBlock and shieldBlock:IsA("RemoteEvent") then
	input = InputController.init({
		remotes = { combatAction = combatAction, shieldBlock = shieldBlock },
		canAct = function()
			local state = gameState()
			return GameStates.isFighter(state) or GameStates.isInLobby(state) -- lobby: training dummies
		end,
		attackButton = controls.attackButton,
		blockButton = controls.blockButton,
		specialButton = controls.specialButton,
		onChargeStart = chargeHud.start,
		onChargeEnd = chargeHud.stop,
		onInput = comboFeedback.input,
		onSchemeChanged = function(newScheme: string)
			scheme = newScheme
			hud.setHint(controlHint())
			refreshSpecials()
		end,
	})
else
	warn(PREFIX, "CombatAction/ShieldBlock RemoteEvents not found; combat input is disabled")
end

------------------------------------------------------------------ HUD and match feedback
local context: any = nil -- ContextHealthController, started once the arena exists

if feedback and feedback:IsA("RemoteEvent") then
	local F = CombatConfig.Feedback
	feedback.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any, e: any)
		if kind == F.Action then
			if a == "Special" and typeof(b) == "string" then
				notify("Info", (if typeof(d) == "string" and d ~= "" then d else b) .. "!") -- the special with its tier
			end
			hud.fadeHint() -- the control hint fades once you start fighting
		elseif kind == F.Hit then
			if typeof(a) == "Instance" then
				EffectsController.damageNumber(a, tonumber(b) or 0, c == true)
				if context then
					context.markInteraction(a)
				end
			end
		elseif kind == F.Block then
			controls.setBlocking(a == true)
			if input then
				input.syncBlock(a == true) -- the toggle follows the server's real block state
			end
		elseif kind == F.SpecialCharge then
			if a == "cancel" then
				if input then
					input.chargeEnded()
				end
				chargeHud.stop()
				if typeof(b) == "string" then
					notify("Info", b) -- NOT READY / INTERRUPTED
				end
			elseif a == "fire" then
				chargeHud.stop()
			end
		elseif kind == F.Parry then
			notify("Info", "PARRY!")
		elseif kind == F.Dodge then
			notify("Info", "DODGE!")
		elseif kind == F.PerfectBlock then
			combatEffects.perfectBlock()
			notify("Info", "PERFECT BLOCK · COUNTER")
		elseif kind == F.Slide then
			if typeof(a) == "Vector3" then
				SlideController.play(player, a, tonumber(b) or 12, tonumber(c) or 0.55)
			end
		elseif kind == F.PlayerHit then
			hud.flashHit(b == true)
			local from = if typeof(c) == "Vector3" then c else nil
			DamageEffectsController.hitIndicator(hud.gui, from, b == true)
			if b == true then
				notify("Info", "BLOCKED")
			end
			if from and context then
				context.markAttackerNear(from)
			end
		elseif kind == F.Heal then
			local amount = math.round(tonumber(a) or 0)
			notify("Heal", ("+%d HEALTH"):format(amount), amount)
		elseif kind == F.Aura then
			aura.reward(tonumber(a) or 0, tonumber(c)) -- (aura, reason, denarii)
		elseif kind == F.Shop then
			notify("Info", tostring(a))
		elseif kind == F.Slowed then
			notify("Info", "SLOWED")
		elseif kind == F.Dash then
			if typeof(a) == "Vector3" then
				EffectsController.dash(a, tonumber(b) or 0)
			end
		elseif kind == F.Knockback then
			if typeof(a) == "Vector3" then
				EffectsController.knockback(a)
			end
		elseif kind == F.Elimination then
			notify("Info", tostring(a))
		elseif kind == F.DamageFx then
			-- (position, kind, scale, direction, extra): routed by CombatEffectsController
			if typeof(a) == "Vector3" then
				combatEffects.damageFx(a, tostring(b), tonumber(c) or 1, if typeof(d) == "Vector3" then d else nil, e)
			end
		elseif kind == F.Knockdown then
			EffectsController.knockdown(tonumber(a) or 1)
		elseif kind == F.Leap then
			if typeof(b) == "Vector3" then
				EffectsController.leap(tonumber(a) or 30, b, tonumber(c) or 0)
			end
		elseif kind == F.Dive then
			if typeof(a) == "Vector3" then
				EffectsController.dive(a, tonumber(b) or 0, tonumber(c) or 50)
			end
		elseif kind == F.ComboFail then
			comboFeedback.clear()
			notify("Info", tostring(a)) -- tiny NO COMBO / NOT READY / TOO SLOW
		end
	end)
else
	warn(PREFIX, "CombatFeedback RemoteEvent not found; HUD feedback is disabled")
end

------------------------------------------------------------------ health, Aura, loadout
local characterAlive = false
visibility.register("Health", hud.healthFrame, function()
	return characterAlive
end, function()
	return characterAlive and hud.isLowHealth() and visibility.getState() ~= "Lobby" -- critical warning: never hidden
end)
visibility.register("Round", hud.roundFrame, hud.roundVisible)
visibility.register("Hints", hud.hintFrame, function()
	return not hud.layout.touch
end)

local function watchCharacter(character: Model)
	controls.setBlocking(false)
	local humanoid = character:WaitForChild("Humanoid", WAIT_TIMEOUT)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	characterAlive = true
	local function update()
		hud.setHealth(humanoid.Health, humanoid.MaxHealth)
		characterAlive = humanoid.Health > 0
	end
	humanoid.HealthChanged:Connect(update)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)
	update()
	visibility.refresh()
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	task.spawn(watchCharacter, player.Character)
end

local function refreshInventory()
	aura.set(tonumber(player:GetAttribute(Config.AuraAttribute)) or 0, tonumber(player:GetAttribute(Config.DenariiAttribute)) or 0)
	refreshSpecials()
end
for _, attribute in { Config.AuraAttribute, Config.DenariiAttribute, Config.EquippedWeaponAttribute, Config.EquippedShieldAttribute } do
	player:GetAttributeChangedSignal(attribute):Connect(refreshInventory)
end
refreshInventory()
hud.setHint(controlHint())

ShopController.start({
	tag = Config.ShopItemTag,
	aura = Config.AuraAttribute,
	denarii = Config.DenariiAttribute,
	equippedWeapon = Config.EquippedWeaponAttribute,
	equippedShield = Config.EquippedShieldAttribute,
	equippedArmor = Config.EquippedArmorAttribute,
	ownedWeapons = Config.OwnedWeaponsAttribute,
	ownedShields = Config.OwnedShieldsAttribute,
	ownedArmor = Config.OwnedArmorAttribute,
	dataStatus = Config.DataStatusAttribute,
}, hud.group)

-- Saved preferences: the HUD mode follows the server-stored value and is sent back on change
local hudPreference = Config.PreferencePrefix .. "HudMode"
local function applyHudPreference()
	local saved = player:GetAttribute(hudPreference)
	if typeof(saved) == "string" and saved ~= "" then
		visibility.setMode(saved)
	end
end
player:GetAttributeChangedSignal(hudPreference):Connect(applyHudPreference)
applyHudPreference()
visibility.onModeChanged(function(mode: string)
	if preferenceEvent and player:GetAttribute(hudPreference) ~= mode then
		preferenceEvent:FireServer("HudMode", mode)
	end
end)

------------------------------------------------------------------ round line and banners
local shownRound = 0
local lastPhase = ""
local lastIntro = ""
local resultShown = false
local defeatShown = false
local teamCountdownShown = false

local function refreshMatch()
	local uiState = visibility.getState()
	local state = gameState()
	local mode = tostring(arenaAttr(Config.MatchModeAttribute) or "")
	local round = tonumber(arenaAttr(Config.RoundAttribute)) or 0
	local roundMax = tonumber(arenaAttr(Config.RoundMaxAttribute)) or 7
	local alive = tonumber(arenaAttr(Config.ZombiesAliveAttribute)) or 0
	local countdown = tonumber(arenaAttr(Config.CountdownAttribute)) or 0
	local phase = tostring(arenaAttr(Config.WavePhaseAttribute) or "Idle")
	local result = tostring(arenaAttr(Config.ResultAttribute) or "")
	local intro = tostring(arenaAttr(Config.BossIntroAttribute) or "")
	local zombieMode = mode == "Solo" or mode == "Coop"

	-- Compact round line: one slim line, shown briefly on every change
	if zombieMode and phase == "Fighting" then
		hud.setRoundLine(("ROUND %d / %d   •   %d LEFT"):format(round, roundMax, alive))
	elseif zombieMode and phase == "Intermission" then
		hud.setRoundLine(("NEXT ROUND   %d"):format(countdown), true)
	elseif zombieMode and phase == "Starting" then
		hud.setRoundLine(("GET READY   %d"):format(countdown), true)
	elseif uiState == "Spectator" and phase == "Boss" then
		hud.setRoundLine("ROUND 7 — OTTI", true)
	else
		hud.setRoundLine(nil)
	end

	-- Results, defeat and respawn information (never hidden)
	if uiState == "Results" then
		if not resultShown then
			resultShown = true
			local earned = tonumber(player:GetAttribute(Config.RunAuraAttribute)) or 0
			local coins = tonumber(player:GetAttribute(Config.RunDenariiAttribute)) or 0
			local kills = tonumber(player:GetAttribute(Config.RunKillsAttribute)) or 0
			local title = if result ~= "" then result elseif state == GameStates.Victory then "VICTORY" else "MATCH COMPLETE"
			local subtitle = if result == "OTTI DEFEATED" then "CHAMPION OF THE COLOSSEUM" elseif state == GameStates.Victory then "GAME COMPLETE" else nil
			local stats = if mode == "TeamBattle"
				then ("Elims %d · Deaths %d · +%d Aura · +%d Denarii"):format(tonumber(player:GetAttribute(Config.EliminationsAttribute)) or 0, tonumber(player:GetAttribute(Config.DeathsAttribute)) or 0, earned, coins)
				else ("Kills %d · +%d Aura · +%d Denarii"):format(kills, earned, coins)
			notifier.banner(title, subtitle, stats)
		end
		return
	end
	resultShown = false
	if state == GameStates.PlayerDefeated then
		defeatShown = true
		local eliminated = arenaAttr(Config.TeamSubModeAttribute) == "ELIMINATION"
		notifier.banner("DEFEATED", if mode == "Coop" then "Back after this round" elseif mode == "TeamBattle" and eliminated then "Out this round · follow your team" elseif mode == "TeamBattle" then "Respawning…" else "Watching from the tribune", nil)
		return
	elseif defeatShown then
		defeatShown = false
		notifier.banner(nil, nil, nil) -- back in the fight
	end

	-- Boss intro texts (the long title only appears here)
	if intro ~= lastIntro then
		lastIntro = intro
		if intro == "Silence" then
			notifier.banner("THE CROWD FALLS SILENT...", nil, nil)
		elseif intro == "Reveal" then
			notifier.banner("OTTI", "CHAMPION OF THE COLOSSEUM", nil)
		elseif uiState == "Boss" then
			notifier.banner("ROUND 7", "OTTI", nil, 2)
		end
	end
	if phase ~= lastPhase then
		local previous = lastPhase
		lastPhase = phase
		if zombieMode and phase == "Intermission" and previous == "Fighting" then
			notifier.banner("ROUND COMPLETE", nil, nil, 1.6)
		elseif phase == "Idle" and intro == "" then
			notifier.banner(nil, nil, nil)
		end
	end
	if mode == "TeamBattle" and uiState == "TeamBattle" then
		-- Arena countdown at the protected team spawns, then FIGHT!
		if countdown > 0 then
			teamCountdownShown = true
			notifier.banner(tostring(countdown), "GET READY", nil, 1.1)
		elseif teamCountdownShown then
			teamCountdownShown = false
			notifier.banner("FIGHT!", nil, nil, 1)
		end
	end
	if zombieMode and phase == "Starting" and countdown > 0 then
		notifier.banner(tostring(countdown), "GET READY", nil, 1.1) -- countdown: only the number and a short label
	elseif zombieMode and phase == "Fighting" and round ~= shownRound then
		shownRound = round
		notifier.banner(("ROUND %d"):format(round), if round == roundMax - 1 then "FINAL WAVE" else nil, nil, 1.5)
	elseif uiState == "Lobby" then
		shownRound = 0
		if intro == "" then
			notifier.banner(nil, nil, nil)
		end
	end
end

for _, attribute in { GameStates.StateAttribute, GameStates.LocationAttribute, Config.RunKillsAttribute, Config.RunAuraAttribute, Config.EliminationsAttribute } do
	player:GetAttributeChangedSignal(attribute):Connect(refreshMatch)
end

------------------------------------------------------------------ arena-dependent controllers
task.spawn(function()
	-- Arena place: the generated Colosseum. Hub: no arena exists, a local empty stand-in keeps the
	-- arena-driven HUD parts idle (no match attributes ever appear on it).
	if isArena then
		arena = waitFor(Workspace, Config.ArenaFolderName)
	else
		local standIn = Instance.new("Folder")
		standIn.Name = "NoArenaInHub"
		arena = standIn
	end
	local lobby = if isArena then nil else lobbyFolder
	local arenaFolder = arena
	if not arenaFolder then
		return
	end
	for _, name in {
		Config.MatchModeAttribute, Config.RoundAttribute, Config.RoundMaxAttribute, Config.ZombiesAliveAttribute,
		Config.CountdownAttribute, Config.WavePhaseAttribute, Config.ResultAttribute, Config.BossIntroAttribute,
		Config.BossActiveAttribute,
	} do
		arenaFolder:GetAttributeChangedSignal(name):Connect(refreshMatch)
	end

	local teamStatus = TeamStatusController.start(hud.group, visibility, arenaFolder, lobby, function()
		return hud.layout.device == "Phone"
	end, notify)
	local entrance = OttiEntranceController.start(arenaFolder)
	BossHudController.start(hud.group, visibility, hud.onLayout, arenaFolder, entrance)
	CrowdEffectsController.start(arenaFolder, notify, function()
		return hud.layout.device
	end)
	local spectator = SpectatorController.start(hud.group, visibility, combatAction, matchRequest)
	context = ContextHealthController.start(playerGui, {
		zombieTag = CombatConfig.ZombieTag,
		dummyTag = Config.TrainingDummyTag,
		teamAttribute = Config.TeamAttribute,
		isPhone = function()
			return hud.layout.device == "Phone"
		end,
		allowed = function()
			return visibility.allowed("Context")
		end,
		uiState = visibility.getState,
	})

	-- The optional info panel: everything that used to crowd the screen
	local function infoText(): string
		local weapon = equippedWeapon()
		local shield = ShieldDefinitions.ById[tostring(player:GetAttribute(Config.EquippedShieldAttribute))]
		local lines = {}
		local mode = tostring(arenaFolder:GetAttribute(Config.MatchModeAttribute) or "")
		local modeDef = GameModeDefinitions[mode]
		local subMode = tostring(arenaFolder:GetAttribute(Config.TeamSubModeAttribute) or "")
		local modeName = if mode == "TeamBattle" and subMode ~= "" then subMode:gsub("_", " ") elseif type(modeDef) == "table" and modeDef.DisplayName then modeDef.DisplayName elseif isArena then "WAITING" else "HUB"
		table.insert(lines, ("<b>MODE</b>  %s"):format(modeName))
		local round = tonumber(arenaFolder:GetAttribute(Config.RoundAttribute)) or 0
		if mode == "Solo" or mode == "Coop" then
			table.insert(lines, ("Round %d / %d · %d zombies left · players %d / %d"):format(round, tonumber(arenaFolder:GetAttribute(Config.RoundMaxAttribute)) or 7, tonumber(arenaFolder:GetAttribute(Config.ZombiesAliveAttribute)) or 0, tonumber(arenaFolder:GetAttribute(Config.PlayersAliveAttribute)) or 0, tonumber(arenaFolder:GetAttribute(Config.PlayersTotalAttribute)) or 0))
		end
		table.insert(lines, "")
		table.insert(lines, "<b>CONTROLS</b>")
		table.insert(lines, "Keyboard: WASD move · LMB attack (tap again = combo) · RMB block on / off · hold Q special, release to fire · Space jump")
		table.insert(lines, "Gamepad: left stick · R2 attack · L2 block on / off · hold X special · A jump")
		table.insert(lines, "Touch: thumbstick left · ATTACK · SPECIAL (hold) · BLOCK (on / off) · JUMP right · drag free screen space = camera")
		table.insert(lines, "Special tiers: I (tap) · II (hold 0.5 s) · III (hold 1.5 s, full at 2.5 s) · full Momentum + III = ULTIMATE")
		table.insert(lines, "F interact · H HUD mode")
		table.insert(lines, "")
		table.insert(lines, ("<b>WEAPON</b>  %s"):format(weapon.DisplayName))
		for _, moveId in { weapon.Basic, weapon.Aerial } do
			local move = SpecialMoveDefinitions[moveId]
			if move then
				table.insert(lines, ("  %s · %d dmg · range %d · %.1f s cooldown"):format(move.Name, move.Damage, move.Range, move.Cooldown))
			end
		end
		local shieldText = if weapon.TwoHanded then "none (two-handed: parry with block)" elseif shield then shield.DisplayName else "–"
		table.insert(lines, ("<b>SHIELD</b>  %s"):format(shieldText))
		local families = WeaponSpecialDefinitions.forPrefix(WeaponAttackDefinitions.prefixOf(weapon.Basic))
		if families then
			table.insert(lines, "")
			table.insert(lines, "<b>SPECIALS</b>  Momentum 0-100: vary attacks, slide-dodge, perfect-block to build it")
			for _, family in { "Left", "Right", "Up", "Down", "Circle", "Ultimate" } do
				local moveId = (families :: any)[family]
				local move = moveId and (SpecialMoveDefinitions :: any)[moveId]
				if move then
					table.insert(lines, ("  %s  %s"):format(family:upper(), move.Name))
				end
			end
		end
		table.insert(lines, "")
		table.insert(lines, teamStatus.rosterText())
		table.insert(lines, "")
		table.insert(lines, "<b>AURA</b>  progress, never spent: it unlocks weapons, shields and armor. Zombie kills pay their Aura (co-op assists 30 %). Otti: 500 solo, 400 per surviving co-op player, 250 for defeated helpers. Team Battle: 80 win / 25 loss.")
		table.insert(lines, "<b>DENARII</b>  money: every Aura reward also pays Denarii. Buy unlocked gear in the Gladiator Armory.")
		return table.concat(lines, "\n")
	end
	local info = InfoPanelController.start(hud.gui, edge, infoText)

	HudStateController.watch(arenaFolder, function(state: string)
		visibility.setState(state)
		info.onStateChanged(state, hud.layout)
		spectator.onStateChanged(state)
		if state == "Lobby" then
			hud.setHint(controlHint())
		elseif state ~= "Results" and state ~= "Spectator" then
			hud.setHint(controlHint())
			hud.fadeHint()
		end
		refreshMatch()
	end)
	refreshMatch()
end)

ZombieAnimator.start(CombatConfig.ZombieTag)
OttiAnimator.start(Config.OttiTag)
OttiAnimator.start(Config.OttiSpectatorTag)
PlayerAnimator.start()
BowController.start(hud.gui, Config.EquippedWeaponAttribute, function()
	local state = gameState()
	return GameStates.isFighter(state) or GameStates.isInLobby(state)
end)

print(PREFIX, "Ready: responsive HUD (Full / Minimal / Hidden), Classic controls, touch + gamepad + keyboard")
