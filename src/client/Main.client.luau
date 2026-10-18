--!strict
-- Client entry point: builds the responsive HUD and wires server feedback, attributes and input
-- to it. The client never decides damage, hits, combos, Aura, ownership, scores or victories.
--   ResponsiveHudController   layout, scale, compact health, round line, hints, hit flash
--   HudVisibilityController   UI state x Full / Minimal / Hidden (eye button, H key)
--   HudStateController        Lobby / Solo / Coop / TeamBattle / Boss / Spectator / Results
--   NotificationController    the one notification queue + short banners
--   ContextHealthController   world-space health bars (zombies, opponents, teammates)
--   TeamStatusController      team score + time, co-op teammate strip, lobby rosters
--   BossHudController         slim Otti bar + short warnings
--   AuraDisplayController     lobby Aura counter, "+n" rewards in combat
--   MobileControlsController   touch buttons / desktop special cards
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
local ShieldDefinitions = load(shared, "ShieldDefinitions")
local SpecialMoveDefinitions = load(shared, "SpecialMoveDefinitions")
local ComboDefinitions = load(shared, "ComboDefinitions")
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
local ShopController = load(script.Parent, "ShopController")
local EffectsController = load(script.Parent, "EffectsController")
local ZombieAnimator = load(script.Parent, "ZombieAnimator")
local OttiAnimator = load(script.Parent, "OttiAnimator")
local DamageEffectsController = load(script.Parent, "DamageEffectsController")
local CrowdEffectsController = load(script.Parent, "CrowdEffectsController")
local BowController = load(script.Parent, "BowController")
for _, module in {
	Config, CombatConfig, GameStates, GameModeDefinitions, WeaponDefinitions, ShieldDefinitions, SpecialMoveDefinitions, ComboDefinitions,
	ResponsiveHudController, HudVisibilityController, HudStateController, NotificationController, ContextHealthController,
	TeamStatusController, BossHudController, AuraDisplayController, MobileControlsController, InfoPanelController,
	SpectatorController, InputController, ShopController, EffectsController, ZombieAnimator, OttiAnimator,
	DamageEffectsController, CrowdEffectsController, BowController,
} do
	if not module then
		return
	end
end

local playerGui = player:WaitForChild("PlayerGui")
local hud = ResponsiveHudController.create(playerGui)

-- Small edge buttons (eye = HUD mode, i = info) on the right edge, below the Aura counter
local edge = hud.group("EdgeButtons", Vector2.new(1, 0), UDim2.new(1, -8, 0, 40), UDim2.fromOffset(44, 96))
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

------------------------------------------------------------------ core HUD elements
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

local aura = AuraDisplayController.start(hud.group, visibility, notify)
local controls = MobileControlsController.start(hud.group, visibility, hud.onLayout, function()
	return hud.layout.touch
end)

local CONTROL_HINTS = {
	["Keyboard & Mouse"] = "LMB Attack   RMB Block   Q / E Specials   F Interact   H HUD",
	["Gamepad"] = "R2 Attack   L2 Block   X / Y Specials   D-pad up Interact",
	["Touch"] = "",
}
local SPECIAL_KEYS = {
	["Keyboard & Mouse"] = { "Q", "E" },
	["Gamepad"] = { "X", "Y" },
	["Touch"] = { "", "" },
}

local function equippedWeapon(): any
	return WeaponDefinitions.ById[tostring(player:GetAttribute(Config.EquippedWeaponAttribute))] or WeaponDefinitions.ById[WeaponDefinitions.Starter]
end

local function refreshSpecials()
	local weapon = equippedWeapon()
	local keys = SPECIAL_KEYS[scheme] or SPECIAL_KEYS["Keyboard & Mouse"]
	local q = SpecialMoveDefinitions[weapon.Special1]
	local e = SpecialMoveDefinitions[weapon.Special2]
	controls.special1.setMove(keys[1], if q then q.Name else "-")
	controls.special2.setMove(keys[2], if e then e.Name else "-")
end

------------------------------------------------------------------ remotes, input and feedback
local remotes = waitFor(ReplicatedStorage, Config.RemotesFolderName)
local combatActionInstance = remotes and waitFor(remotes, Config.CombatActionRemoteName)
local shieldBlock = remotes and waitFor(remotes, Config.ShieldBlockRemoteName)
local feedback = remotes and waitFor(remotes, Config.CombatFeedbackRemoteName)
local combatAction: RemoteEvent? = if combatActionInstance and combatActionInstance:IsA("RemoteEvent") then combatActionInstance else nil

local context: any = nil -- ContextHealthController, started once the arena exists

if combatAction and shieldBlock and shieldBlock:IsA("RemoteEvent") then
	InputController.init({
		remotes = { combatAction = combatAction, shieldBlock = shieldBlock },
		canAct = function()
			local state = gameState()
			return GameStates.isFighter(state) or GameStates.isInLobby(state) -- lobby: training dummies
		end,
		attackButton = controls.attackButton,
		blockButton = controls.blockButton,
		special1Button = controls.special1Button,
		special2Button = controls.special2Button,
		onSchemeChanged = function(newScheme: string)
			scheme = newScheme
			hud.setHint(CONTROL_HINTS[newScheme] or "")
			refreshSpecials()
		end,
	})
else
	warn(PREFIX, "CombatAction/ShieldBlock RemoteEvents not found; combat input is disabled")
end

if feedback and feedback:IsA("RemoteEvent") then
	local F = CombatConfig.Feedback
	feedback.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any)
		if kind == F.Action then
			if a == "Special1" then
				controls.special1.startCooldown(tonumber(c) or 0)
			elseif a == "Special2" then
				controls.special2.startCooldown(tonumber(c) or 0)
			end
			if typeof(d) == "string" then
				notify("Info", d .. "!") -- combo
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
		elseif kind == F.Parry then
			notify("Info", "PARRY!")
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
			aura.reward(tonumber(a) or 0)
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
			if typeof(a) == "Vector3" then
				DamageEffectsController.burst(a, tostring(b), tonumber(c) or 1, if typeof(d) == "Vector3" then d else nil)
			end
		elseif kind == F.Knockdown then
			EffectsController.knockdown(tonumber(a) or 1)
		end
	end)
else
	warn(PREFIX, "CombatFeedback RemoteEvent not found; HUD feedback is disabled")
end

------------------------------------------------------------------ health, Aura, loadout
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
	aura.set(tonumber(player:GetAttribute(Config.AuraAttribute)) or 0)
	refreshSpecials()
end
for _, attribute in { Config.AuraAttribute, Config.EquippedWeaponAttribute, Config.EquippedShieldAttribute } do
	player:GetAttributeChangedSignal(attribute):Connect(refreshInventory)
end
refreshInventory()

ShopController.start({
	tag = Config.ShopItemTag,
	aura = Config.AuraAttribute,
	equippedWeapon = Config.EquippedWeaponAttribute,
	equippedShield = Config.EquippedShieldAttribute,
	ownedWeapons = Config.OwnedWeaponsAttribute,
	ownedShields = Config.OwnedShieldsAttribute,
})

------------------------------------------------------------------ round line and banners
local shownRound = 0
local lastPhase = ""
local lastIntro = ""
local resultShown = false
local defeatShown = false

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
			local kills = tonumber(player:GetAttribute(Config.RunKillsAttribute)) or 0
			local title = if result ~= "" then result elseif state == GameStates.Victory then "VICTORY" else "MATCH COMPLETE"
			local subtitle = if result == "OTTI DEFEATED" then "CHAMPION OF THE COLOSSEUM" elseif state == GameStates.Victory then "GAME COMPLETE" else nil
			local stats = if mode == "TeamBattle"
				then ("Elims %d · Deaths %d · +%d Aura"):format(tonumber(player:GetAttribute(Config.EliminationsAttribute)) or 0, tonumber(player:GetAttribute(Config.DeathsAttribute)) or 0, earned)
				else ("Kills %d · +%d Aura"):format(kills, earned)
			notifier.banner(title, subtitle, stats)
		end
		return
	end
	resultShown = false
	if state == GameStates.PlayerDefeated then
		defeatShown = true
		notifier.banner("DEFEATED", if mode == "Coop" then "Back after this round" elseif mode == "TeamBattle" then "Respawning…" else nil, nil)
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
	arena = waitFor(Workspace, Config.ArenaFolderName)
	local lobby = waitFor(Workspace, Config.LobbyFolderName)
	local arenaFolder = arena
	if not arenaFolder or not lobby then
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
	BossHudController.start(hud.group, visibility, hud.onLayout, arenaFolder, combatAction)
	CrowdEffectsController.start(arenaFolder, notify)
	local spectator = SpectatorController.start(hud.group, visibility, combatAction)
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
		table.insert(lines, ("<b>MODE</b>  %s"):format(if type(modeDef) == "table" and modeDef.DisplayName then modeDef.DisplayName else "LOBBY"))
		local round = tonumber(arenaFolder:GetAttribute(Config.RoundAttribute)) or 0
		if mode == "Solo" or mode == "Coop" then
			table.insert(lines, ("Round %d / %d · %d zombies left · players %d / %d"):format(round, tonumber(arenaFolder:GetAttribute(Config.RoundMaxAttribute)) or 7, tonumber(arenaFolder:GetAttribute(Config.ZombiesAliveAttribute)) or 0, tonumber(arenaFolder:GetAttribute(Config.PlayersAliveAttribute)) or 0, tonumber(arenaFolder:GetAttribute(Config.PlayersTotalAttribute)) or 0))
		end
		table.insert(lines, "")
		table.insert(lines, "<b>CONTROLS</b>")
		table.insert(lines, "Keyboard: LMB attack · RMB hold to block · Q / E specials · F interact · H HUD mode")
		table.insert(lines, "Gamepad: R2 attack · L2 block · X / Y specials · D-pad up interact")
		table.insert(lines, "Touch: ATK · hold BLOCK · special buttons · tap prompts · 👁 HUD mode")
		table.insert(lines, "")
		table.insert(lines, ("<b>WEAPON</b>  %s"):format(weapon.DisplayName))
		for _, moveId in { weapon.Basic, weapon.Special1, weapon.Special2 } do
			local move = SpecialMoveDefinitions[moveId]
			if move then
				table.insert(lines, ("  %s · %d dmg · range %d · %.1f s cooldown"):format(move.Name, move.Damage, move.Range, move.Cooldown))
			end
		end
		local shieldText = if weapon.TwoHanded then "none (two-handed: parry with block)" elseif shield then shield.DisplayName else "–"
		table.insert(lines, ("<b>SHIELD</b>  %s"):format(shieldText))
		local combos = ComboDefinitions[weapon.Id]
		if combos then
			table.insert(lines, "")
			table.insert(lines, "<b>COMBOS</b>")
			for _, combo in combos do
				table.insert(lines, ("  %s: %s (×%.2g)"):format(combo.Name, table.concat(combo.Sequence, " → "), combo.DamageMultiplier))
			end
		end
		table.insert(lines, "")
		table.insert(lines, teamStatus.rosterText())
		table.insert(lines, "")
		table.insert(lines, "<b>AURA</b>  Zombie kills pay their Aura (co-op assists 30 %). Otti: 500 solo, 400 per surviving co-op player, 250 for defeated helpers. Team Battle: 80 win / 25 loss.")
		return table.concat(lines, "\n")
	end
	local info = InfoPanelController.start(hud.gui, edge, infoText)

	HudStateController.watch(arenaFolder, function(state: string)
		visibility.setState(state)
		info.onStateChanged(state, hud.layout)
		spectator.onStateChanged(state)
		if state == "Lobby" then
			hud.setHint(CONTROL_HINTS[scheme] or "")
		elseif state ~= "Results" and state ~= "Spectator" then
			hud.setHint(CONTROL_HINTS[scheme] or "")
			hud.fadeHint()
		end
		refreshMatch()
	end)
	refreshMatch()
end)

ZombieAnimator.start(CombatConfig.ZombieTag)
OttiAnimator.start(Config.OttiTag)
BowController.start(hud.gui, Config.EquippedWeaponAttribute, function()
	local state = gameState()
	return GameStates.isFighter(state) or GameStates.isInLobby(state)
end)

print(PREFIX, "Ready: responsive HUD (Full / Minimal / Hidden), touch + gamepad + keyboard")
