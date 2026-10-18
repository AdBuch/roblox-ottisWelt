--!strict
-- Client entry point: wires input, HUD, shop displays, the group panel and local feedback.
-- The client never decides damage, hits, combos, Aura, ownership, scores or victories.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PREFIX = "[OttiArena][Client]"
local WAIT_TIMEOUT = 10
local HIT_DISPLAY_SECONDS = 0.5
local ROUND_BANNER_SECONDS = 2
local TARGET_SEARCH_RADIUS = 30

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
local CombatHudController = load(script.Parent, "CombatHudController")
local InputController = load(script.Parent, "InputController")
local ShopController = load(script.Parent, "ShopController")
local PartyController = load(script.Parent, "PartyController")
local EffectsController = load(script.Parent, "EffectsController")
local ZombieAnimator = load(script.Parent, "ZombieAnimator")
if not (Config and CombatConfig and GameStates and GameModeDefinitions and WeaponDefinitions and ShieldDefinitions and SpecialMoveDefinitions
	and CombatHudController and InputController and ShopController and PartyController and EffectsController and ZombieAnimator) then
	return
end

local hud = CombatHudController.create(player:WaitForChild("PlayerGui"))

-- Local display state (driven by server feedback and replicated attributes)
local serverBlocking = false
local hitUntil = 0
local lastHitModel: Instance? = nil
local arena: Instance? = nil
local scheme = "Keyboard & Mouse"

local function gameState(): string
	return tostring(player:GetAttribute(GameStates.StateAttribute) or GameStates.Lobby)
end

local function location(): string
	return tostring(player:GetAttribute(GameStates.LocationAttribute) or "Lobby")
end

local function arenaAttr(name: string): any
	return if arena then arena:GetAttribute(name) else nil
end

local function modeName(id: any): string
	local def = GameModeDefinitions[id]
	return if type(def) == "table" and def.DisplayName then def.DisplayName else "ARENA"
end

local CONTROL_HINTS = {
	["Keyboard & Mouse"] = "LMB ATTACK · RMB BLOCK · Q / E SPECIALS · F INTERACT",
	["Gamepad"] = "R2 ATTACK · L2 BLOCK · X / Y SPECIALS · D-PAD UP INTERACT",
	["Touch"] = "ATTACK · hold BLOCK · SPECIAL cards · tap prompts",
}
local SPECIAL_KEYS = {
	["Keyboard & Mouse"] = { "Q", "E" },
	["Gamepad"] = { "X", "Y" },
	["Touch"] = { "TAP", "TAP" },
}

local function refreshSpecials()
	local weapon = WeaponDefinitions.ById[tostring(player:GetAttribute(Config.EquippedWeaponAttribute))] or WeaponDefinitions.ById[WeaponDefinitions.Starter]
	local keys = SPECIAL_KEYS[scheme] or SPECIAL_KEYS["Keyboard & Mouse"]
	local q = SpecialMoveDefinitions[weapon.Special1]
	local e = SpecialMoveDefinitions[weapon.Special2]
	hud.special1.setMove(keys[1], if q then q.Name else "-")
	hud.special2.setMove(keys[2], if e then e.Name else "-")
end

local STATE_COLORS = {
	READY = Color3.fromRGB(220, 220, 220),
	BLOCKING = Color3.fromRGB(120, 190, 255),
	HIT = Color3.fromRGB(255, 90, 80),
	["ROUND COMPLETE"] = Color3.fromRGB(110, 230, 120),
	VICTORY = Color3.fromRGB(255, 215, 90),
	DEFEATED = Color3.fromRGB(255, 70, 70),
	SPECTATING = Color3.fromRGB(200, 200, 255),
	LOBBY = Color3.fromRGB(220, 200, 160),
}

local function refreshState()
	local state = gameState()
	local now = os.clock()
	local shown = "READY"
	if state == GameStates.PlayerDefeated then
		shown = "DEFEATED"
	elseif state == GameStates.Victory then
		shown = "VICTORY"
	elseif state == GameStates.MatchComplete then
		shown = "MATCH COMPLETE"
	elseif state == GameStates.Spectating then
		shown = "SPECTATING"
	elseif state == GameStates.PartyForming then
		shown = "CO-OP PARTY"
	elseif state == GameStates.TeamSelection then
		shown = "TEAM SELECTION"
	elseif state == GameStates.ReadyCheck then
		shown = "READY CHECK"
	elseif state == GameStates.Countdown then
		shown = "COUNTDOWN"
	elseif GameStates.isInLobby(state) then
		shown = "LOBBY"
	elseif state == GameStates.RoundComplete then
		shown = "ROUND COMPLETE"
	elseif serverBlocking then
		shown = "BLOCKING"
	elseif now < hitUntil then
		shown = "HIT"
	end
	hud.setStatus(location(), shown, STATE_COLORS[shown] or Color3.new(1, 1, 1))
	hud.setBlocking(serverBlocking and (GameStates.isFighter(state) or GameStates.isInLobby(state)))
	hud.setSpecialsVisible(GameStates.isFighter(state) or GameStates.isInLobby(state) or state == GameStates.Countdown)
end

-- Header and banners from the player's state and the match attributes
local shownRound = 0
local bannerToken = 0

local function refreshMatch()
	local state = gameState()
	local mode: string = tostring(arenaAttr(Config.MatchModeAttribute) or "")
	local isTeamMode = mode == "TeamBattle"
	local hasMode = #mode > 0
	local isCoop = mode == "Coop"
	local round = tonumber(arenaAttr(Config.RoundAttribute)) or 0
	local roundMax = tonumber(arenaAttr(Config.RoundMaxAttribute)) or 6
	local alive = tonumber(arenaAttr(Config.ZombiesAliveAttribute)) or 0
	local total = tonumber(arenaAttr(Config.ZombiesTotalAttribute)) or 0
	local playersAlive = tonumber(arenaAttr(Config.PlayersAliveAttribute)) or 0
	local playersTotal = tonumber(arenaAttr(Config.PlayersTotalAttribute)) or 0
	local countdown = tonumber(arenaAttr(Config.CountdownAttribute)) or 0
	local phase = tostring(arenaAttr(Config.WavePhaseAttribute) or "Idle")
	local result = tostring(arenaAttr(Config.ResultAttribute) or "")
	local red = tonumber(arenaAttr(Config.RedScoreAttribute)) or 0
	local blue = tonumber(arenaAttr(Config.BlueScoreAttribute)) or 0
	local timeLeft = tonumber(arenaAttr(Config.TimeLeftAttribute)) or 0
	local suddenDeath = arenaAttr(Config.SuddenDeathAttribute) == true
	local inArena = location() == "Arena" or state == GameStates.PlayerDefeated and location() == "Tribune" and hasMode

	local teamHeader = ("RED %d — %d BLUE"):format(red, blue)
	local timeText = if suddenDeath then "SUDDEN DEATH" else ("TIME %02d:%02d"):format(timeLeft // 60, timeLeft % 60)
	local zombieHeader = ("%s · ROUND %d / %d"):format(modeName(mode), math.max(round, 1), roundMax)
	local zombieSub = ("ZOMBIES %d / %d · PLAYERS %d / %d"):format(alive, total, playersAlive, playersTotal)

	if inArena and isTeamMode then
		hud.setHeader(teamHeader, timeText)
	elseif inArena and hasMode then
		hud.setHeader(zombieHeader, zombieSub)
	elseif state == GameStates.Spectating then
		if isTeamMode then
			hud.setHeader("TRIBUNES · " .. teamHeader, timeText)
		elseif hasMode then
			hud.setHeader("TRIBUNES · " .. zombieHeader, zombieSub)
		else
			hud.setHeader("TRIBUNES", "No match right now · RETURN TO LOBBY at the east door")
		end
	else
		hud.setHeader("OTTI COLOSSEUM", if hasMode then ("%s in progress · watch from the TRIBUNES"):format(modeName(mode)) else "Choose equipment, then pick a mode")
	end

	local kills = tonumber(player:GetAttribute(Config.RunKillsAttribute)) or 0
	local earned = tonumber(player:GetAttribute(Config.RunAuraAttribute)) or 0
	if state == GameStates.Victory or state == GameStates.MatchComplete then
		local stats = if isTeamMode
			then ("Eliminations %d · Deaths %d · Assists %d · Aura earned %d"):format(
				tonumber(player:GetAttribute(Config.EliminationsAttribute)) or 0,
				tonumber(player:GetAttribute(Config.DeathsAttribute)) or 0,
				tonumber(player:GetAttribute(Config.AssistsAttribute)) or 0,
				earned
			)
			else ("Kills %d · Aura earned %d · returning to the lobby…"):format(kills, earned)
		hud.setBanner(if result ~= "" then result elseif state == GameStates.Victory then "VICTORY" else "MATCH COMPLETE", if state == GameStates.Victory then "GAME COMPLETE" else "Better luck next time", stats)
	elseif state == GameStates.PlayerDefeated then
		hud.setBanner("DEFEATED", if isCoop then "You return after this round" elseif isTeamMode then "Respawning…" else "You will respawn in the lobby", ("Kills %d · Aura earned %d · Aura and items are kept"):format(kills, earned))
	elseif inArena and hasMode and mode ~= "TeamBattle" then
		if phase == "Starting" then
			hud.setBanner("GET READY", if countdown > 0 then ("Round 1 in %d"):format(countdown) else nil, modeName(mode))
		elseif phase == "Intermission" then
			hud.setBanner("ROUND COMPLETE", ("Next round in %d"):format(countdown), nil)
		elseif phase == "Fighting" and round ~= shownRound then
			shownRound = round
			bannerToken += 1
			local myToken = bannerToken
			hud.setBanner(("ROUND %d"):format(round), ("%d zombie%s"):format(total, if total == 1 then "" else "s"), if round == roundMax then "FINAL ROUND" else nil)
			task.delay(ROUND_BANNER_SECONDS, function()
				if bannerToken == myToken then
					hud.setBanner(nil, nil, nil)
				end
			end)
		elseif phase ~= "Fighting" then
			hud.setBanner(nil, nil, nil)
		end
	elseif inArena and isTeamMode and suddenDeath then
		hud.setBanner(nil, "SUDDEN DEATH", "Next elimination wins")
	else
		shownRound = 0
		hud.setBanner(nil, nil, nil)
	end
	refreshState()
end

-- Remotes, input and feedback
local remotes = waitFor(ReplicatedStorage, Config.RemotesFolderName)
local combatAction = remotes and waitFor(remotes, Config.CombatActionRemoteName)
local shieldBlock = remotes and waitFor(remotes, Config.ShieldBlockRemoteName)
local feedback = remotes and waitFor(remotes, Config.CombatFeedbackRemoteName)

if combatAction and combatAction:IsA("RemoteEvent") and shieldBlock and shieldBlock:IsA("RemoteEvent") then
	InputController.init({
		remotes = { combatAction = combatAction, shieldBlock = shieldBlock },
		canAct = function()
			local state = gameState()
			return GameStates.isFighter(state) or GameStates.isInLobby(state) -- lobby: training dummies
		end,
		special1Button = hud.special1.button,
		special2Button = hud.special2.button,
		onSchemeChanged = function(newScheme: string)
			scheme = newScheme
			hud.setControlsHint(("%s  [%s]"):format(CONTROL_HINTS[newScheme] or "", newScheme))
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
				hud.special1.startCooldown(tonumber(c) or 0)
			elseif a == "Special2" then
				hud.special2.startCooldown(tonumber(c) or 0)
			end
			if typeof(d) == "string" then
				hud.combo(d)
			end
		elseif kind == F.Hit then
			if typeof(a) == "Instance" then
				lastHitModel = a
				EffectsController.damageNumber(a, tonumber(b) or 0, c == true)
			end
		elseif kind == F.Block then
			serverBlocking = a == true
		elseif kind == F.Parry then
			hud.popup("PARRY!", Color3.fromRGB(200, 230, 255))
		elseif kind == F.PlayerHit then
			hitUntil = os.clock() + HIT_DISPLAY_SECONDS
			hud.flashHit(b == true)
			if b == true then
				hud.popup(("BLOCKED · -%d"):format(tonumber(a) or 0), Color3.fromRGB(150, 200, 255))
			end
		elseif kind == F.Heal then
			hud.popup(("+%d HEALTH"):format(math.round(tonumber(a) or 0)), Color3.fromRGB(120, 255, 120))
		elseif kind == F.Aura then
			hud.popup(("+%d AURA%s"):format(tonumber(a) or 0, if b == "assist" then " (ASSIST)" else ""), Color3.fromRGB(255, 210, 80))
		elseif kind == F.Shop then
			hud.toast(tostring(a), b == true)
		elseif kind == F.Slowed then
			hud.popup("NETTED · SLOWED", Color3.fromRGB(200, 200, 230))
		elseif kind == F.Dash then
			if typeof(a) == "Vector3" then
				EffectsController.dash(a, tonumber(b) or 0)
			end
		elseif kind == F.Knockback then
			if typeof(a) == "Vector3" then
				EffectsController.knockback(a)
			end
		elseif kind == F.Elimination then
			hud.feed(tostring(a))
		end
		refreshState()
	end)
else
	warn(PREFIX, "CombatFeedback RemoteEvent not found; HUD feedback is disabled")
end

-- Health (no regeneration: it only changes through damage, shells, revives or respawning)
local function watchCharacter(character: Model)
	serverBlocking = false
	local humanoid = character:WaitForChild("Humanoid", WAIT_TIMEOUT)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local function update()
		hud.setHealth(humanoid.Health, humanoid.MaxHealth)
	end
	humanoid.HealthChanged:Connect(update)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)
	update()
	refreshState()
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	task.spawn(watchCharacter, player.Character)
end

-- Aura and loadout
local function refreshInventory()
	hud.setAura(tonumber(player:GetAttribute(Config.AuraAttribute)) or 0)
	local weapon = WeaponDefinitions.ById[tostring(player:GetAttribute(Config.EquippedWeaponAttribute))]
	local shield = ShieldDefinitions.ById[tostring(player:GetAttribute(Config.EquippedShieldAttribute))]
	local shieldText = if weapon and weapon.TwoHanded then "— (two-handed: parry)" elseif shield then shield.DisplayName else "–"
	hud.setLoadout(if weapon then weapon.DisplayName else "–", shieldText)
	refreshSpecials()
end
for _, attribute in { Config.AuraAttribute, Config.EquippedWeaponAttribute, Config.EquippedShieldAttribute } do
	player:GetAttributeChangedSignal(attribute):Connect(refreshInventory)
end
refreshInventory()

for _, attribute in { GameStates.StateAttribute, GameStates.LocationAttribute, Config.RunKillsAttribute, Config.RunAuraAttribute, Config.EliminationsAttribute } do
	player:GetAttributeChangedSignal(attribute):Connect(refreshMatch)
end

ShopController.start({
	tag = Config.ShopItemTag,
	aura = Config.AuraAttribute,
	equippedWeapon = Config.EquippedWeaponAttribute,
	equippedShield = Config.EquippedShieldAttribute,
	ownedWeapons = Config.OwnedWeaponsAttribute,
	ownedShields = Config.OwnedShieldsAttribute,
})

-- Arena and lobby attributes
task.spawn(function()
	arena = waitFor(Workspace, Config.ArenaFolderName)
	local lobby = waitFor(Workspace, Config.LobbyFolderName)
	if not arena then
		return
	end
	for _, name in {
		Config.MatchModeAttribute, Config.MatchStateAttribute, Config.RoundAttribute, Config.RoundMaxAttribute,
		Config.ZombiesAliveAttribute, Config.ZombiesTotalAttribute, Config.PlayersAliveAttribute, Config.PlayersTotalAttribute,
		Config.CountdownAttribute, Config.WavePhaseAttribute, Config.ArenaBusyAttribute, Config.ResultAttribute,
		Config.RedScoreAttribute, Config.BlueScoreAttribute, Config.TimeLeftAttribute, Config.SuddenDeathAttribute,
	} do
		arena:GetAttributeChangedSignal(name):Connect(refreshMatch)
	end
	refreshMatch()
	if lobby then
		PartyController.start(hud.gui, {
			lobbyFolder = lobby,
			arenaFolder = arena,
			coopRoster = Config.CoopRosterAttribute,
			redRoster = Config.RedRosterAttribute,
			blueRoster = Config.BlueRosterAttribute,
			teamCountdown = Config.TeamCountdownAttribute,
			inParty = Config.InPartyAttribute,
			team = Config.TeamAttribute,
			eliminations = Config.EliminationsAttribute,
			deaths = Config.DeathsAttribute,
			assists = Config.AssistsAttribute,
			matchMode = Config.MatchModeAttribute,
		})
	end
end)
refreshMatch()

-- Target bar: what you hit last (zombie, dummy, opponent), otherwise the nearest zombie
local function isValidTarget(model: Instance?): boolean
	if model == nil or model.Parent == nil then
		return false
	end
	return CollectionService:HasTag(model, CombatConfig.ZombieTag) or CollectionService:HasTag(model, Config.TrainingDummyTag)
		or Players:GetPlayerFromCharacter(model) ~= nil
end

-- Zombies and dummies carry Health/MaxHealth attributes; opponents are read from their Humanoid
local function targetInfo(model: Instance): (string, number, number)
	local opponent = Players:GetPlayerFromCharacter(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if opponent and humanoid then
		return opponent.DisplayName, humanoid.Health, humanoid.MaxHealth
	end
	return tostring(model:GetAttribute("ZombieType") or model.Name), tonumber(model:GetAttribute("Health")) or 0, tonumber(model:GetAttribute("MaxHealth")) or 1
end

local function findTarget(): Instance?
	if isValidTarget(lastHitModel) then
		return lastHitModel
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not GameStates.isFighter(gameState()) then
		return nil
	end
	local best, bestDistance = nil, TARGET_SEARCH_RADIUS
	for _, model in CollectionService:GetTagged(CombatConfig.ZombieTag) do
		local zombieRoot = model:FindFirstChild("HumanoidRootPart")
		if zombieRoot and zombieRoot:IsA("BasePart") then
			local distance = (zombieRoot.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best
end

-- Timed states and the target bar refresh 10x per second (no per-frame work)
task.spawn(function()
	while true do
		task.wait(0.1)
		local target = findTarget()
		if target then
			hud.setTarget(targetInfo(target))
		else
			hud.setTarget(nil, 0, 1)
		end
		refreshState()
	end
end)

ZombieAnimator.start(CombatConfig.ZombieTag)

print(PREFIX, "Ready: HUD, LMB/RMB/Q/E (gamepad + touch), shop displays, group panel")
