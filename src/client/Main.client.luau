--!strict
-- Client entry point: wires input, HUD, shop displays and local feedback together.
-- The client never decides damage, targets, health, coins, cooldowns, ownership or block state.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local PREFIX = "[OttiArena][Client]"
local WAIT_TIMEOUT = 10
local ATTACK_DISPLAY_SECONDS = 0.4
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

local function waitForModule(parent: Instance?, name: string): ModuleScript?
	local child = parent and waitFor(parent, name)
	if child and child:IsA("ModuleScript") then
		return child
	end
	return nil
end

local shared = waitFor(ReplicatedStorage, "Shared")
local modules = {
	Config = waitForModule(shared, "Config"),
	CombatConfig = waitForModule(shared, "CombatConfig"),
	GameStates = waitForModule(shared, "GameStates"),
	WeaponDefinitions = waitForModule(shared, "WeaponDefinitions"),
	ShieldDefinitions = waitForModule(shared, "ShieldDefinitions"),
	HudController = waitForModule(script.Parent, "HudController"),
	InputController = waitForModule(script.Parent, "InputController"),
	ShopController = waitForModule(script.Parent, "ShopController"),
	EffectsController = waitForModule(script.Parent, "EffectsController"),
	ZombieAnimator = waitForModule(script.Parent, "ZombieAnimator"),
}
-- (missing modules are nil and therefore absent from the table, so check by name)
for _, name in { "Config", "CombatConfig", "GameStates", "WeaponDefinitions", "ShieldDefinitions", "HudController", "InputController", "ShopController", "EffectsController", "ZombieAnimator" } do
	if not (modules :: any)[name] then
		warn(PREFIX, ("Cannot start without module %s. Is Rojo synced?"):format(name))
		return
	end
end

local Config = require(modules.Config :: ModuleScript) :: any
local CombatConfig = require(modules.CombatConfig :: ModuleScript) :: any
local GameStates = require(modules.GameStates :: ModuleScript) :: any
local WeaponDefinitions = require(modules.WeaponDefinitions :: ModuleScript) :: any
local ShieldDefinitions = require(modules.ShieldDefinitions :: ModuleScript) :: any
local HudController = require(modules.HudController :: ModuleScript) :: any
local InputController = require(modules.InputController :: ModuleScript) :: any
local ShopController = require(modules.ShopController :: ModuleScript) :: any
local EffectsController = require(modules.EffectsController :: ModuleScript) :: any
local ZombieAnimator = require(modules.ZombieAnimator :: ModuleScript) :: any

local hud = HudController.create(player:WaitForChild("PlayerGui"))
local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local CONTROLS = if touchOnly then "ATTACK button · hold BLOCK" else "LMB ATTACK · RMB BLOCK"

-- Local display state (driven by server feedback and replicated attributes)
local serverBlocking = false
local attackingUntil = 0
local hitUntil = 0
local lastHitModel: Instance? = nil
local arena: Instance? = nil

local function gameState(): string
	return tostring(player:GetAttribute(GameStates.StateAttribute) or GameStates.Lobby)
end

local function location(): string
	return tostring(player:GetAttribute(GameStates.LocationAttribute) or "Lobby")
end

local function arenaAttr(name: string): any
	return if arena then arena:GetAttribute(name) else nil
end

local STATE_COLORS = {
	READY = Color3.fromRGB(220, 220, 220),
	ATTACKING = Color3.fromRGB(255, 205, 70),
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
	elseif state == GameStates.Spectating then
		shown = "SPECTATING"
	elseif state == GameStates.Lobby or state == GameStates.EquipmentSelection then
		shown = "LOBBY"
	elseif state == GameStates.RoundComplete then
		shown = "ROUND COMPLETE"
	elseif serverBlocking then
		shown = "BLOCKING"
	elseif now < hitUntil then
		shown = "HIT"
	elseif now < attackingUntil then
		shown = "ATTACKING"
	end
	hud.setStatus(location(), shown, STATE_COLORS[shown] or Color3.new(1, 1, 1))
	hud.setBlocking(serverBlocking and GameStates.isFighter(state))
	hud.setControlsHint(if GameStates.isFighter(state) then CONTROLS else CONTROLS .. "  (arena only)")
end

-- Header + banners from the player's state and the run attributes
local shownRound = 0
local bannerToken = 0

local function refreshWave()
	local state = gameState()
	local round = tonumber(arenaAttr(Config.RoundAttribute)) or 0
	local roundMax = tonumber(arenaAttr(Config.RoundMaxAttribute)) or 6
	local alive = tonumber(arenaAttr(Config.ZombiesAliveAttribute)) or 0
	local total = tonumber(arenaAttr(Config.ZombiesTotalAttribute)) or 0
	local countdown = tonumber(arenaAttr(Config.CountdownAttribute)) or 0
	local phase = tostring(arenaAttr(Config.WavePhaseAttribute) or "Idle")
	local busy = arenaAttr(Config.ArenaBusyAttribute) == true
	local fighterName = tostring(arenaAttr(Config.FighterNameAttribute) or "")

	if state == GameStates.Lobby or state == GameStates.EquipmentSelection then
		hud.setHeader("OTTI COLOSSEUM", if busy then ("Arena busy: %s is fighting · watch from the TRIBUNE"):format(fighterName) else "Choose equipment, then enter the arena")
	elseif state == GameStates.Spectating then
		hud.setHeader("TRIBUNE", if busy and round > 0 then ("%s · ROUND %d / %d · ZOMBIES %d / %d"):format(fighterName, round, roundMax, alive, total) else "Watching the arena")
	elseif round > 0 then
		hud.setHeader(("ROUND %d / %d"):format(round, roundMax), ("ZOMBIES %d / %d"):format(alive, total))
	else
		hud.setHeader("GET READY", "Round 1 is about to start")
	end

	if state == GameStates.Victory then
		hud.setBanner("COLOSSEUM CONQUERED", "GAME COMPLETE", ("Kills %d · Coins earned %d · returning to the lobby…"):format(
			tonumber(player:GetAttribute(Config.RunKillsAttribute)) or 0,
			tonumber(player:GetAttribute(Config.RunCoinsAttribute)) or 0
		))
	elseif state == GameStates.PlayerDefeated then
		hud.setBanner("DEFEATED", "You will respawn in the lobby", ("Kills %d · Coins earned %d · your coins and items are kept"):format(
			tonumber(player:GetAttribute(Config.RunKillsAttribute)) or 0,
			tonumber(player:GetAttribute(Config.RunCoinsAttribute)) or 0
		))
	elseif GameStates.isFighter(state) or state == GameStates.EnteringArena then
		if phase == "Starting" then
			hud.setBanner("GET READY", if countdown > 0 then ("Round 1 in %d"):format(countdown) else nil, nil)
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
		elseif phase == "Fighting" then
			-- keep the current ROUND banner until it times out
		else
			hud.setBanner(nil, nil, nil)
		end
	else
		shownRound = 0
		hud.setBanner(nil, nil, nil)
	end
	refreshState()
end

-- Remotes + input
local remotes = waitFor(ReplicatedStorage, Config.RemotesFolderName)
local weaponAttack = remotes and waitFor(remotes, Config.WeaponAttackRemoteName)
local shieldBlock = remotes and waitFor(remotes, Config.ShieldBlockRemoteName)
local feedback = remotes and waitFor(remotes, Config.CombatFeedbackRemoteName)

if weaponAttack and weaponAttack:IsA("RemoteEvent") and shieldBlock and shieldBlock:IsA("RemoteEvent") then
	InputController.init({ weaponAttack = weaponAttack, shieldBlock = shieldBlock }, function()
		return GameStates.isFighter(gameState())
	end)
else
	warn(PREFIX, "WeaponAttack/ShieldBlock RemoteEvents not found; combat input is disabled")
end

if feedback and feedback:IsA("RemoteEvent") then
	feedback.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any)
		if kind == CombatConfig.Feedback.Swing then
			attackingUntil = os.clock() + ATTACK_DISPLAY_SECONDS
		elseif kind == CombatConfig.Feedback.Hit then
			if typeof(a) == "Instance" then
				lastHitModel = a
				EffectsController.damageNumber(a, tonumber(b) or 0, c == true)
			end
		elseif kind == CombatConfig.Feedback.Block then
			serverBlocking = a == true
		elseif kind == CombatConfig.Feedback.PlayerHit then
			hitUntil = os.clock() + HIT_DISPLAY_SECONDS
			hud.flashHit(b == true)
			if b == true then
				hud.popup(("BLOCKED · -%d"):format(tonumber(a) or 0), Color3.fromRGB(150, 200, 255))
			end
		elseif kind == CombatConfig.Feedback.Heal then
			hud.popup(("+%d HEALTH"):format(math.round(tonumber(a) or 0)), Color3.fromRGB(120, 255, 120))
		elseif kind == CombatConfig.Feedback.Coins then
			hud.popup(("+%d COINS"):format(tonumber(a) or 0), Color3.fromRGB(255, 210, 80))
		elseif kind == CombatConfig.Feedback.Shop then
			hud.toast(tostring(a), b == true)
		elseif kind == CombatConfig.Feedback.Slowed then
			hud.popup("NETTED · SLOWED", Color3.fromRGB(200, 200, 230))
		end
		refreshState()
	end)
else
	warn(PREFIX, "CombatFeedback RemoteEvent not found; HUD feedback is disabled")
end

-- Player health (no regeneration: it only changes through damage, shells or respawning)
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

-- Coins and loadout
local function refreshInventory()
	hud.setCoins(tonumber(player:GetAttribute(Config.CoinsAttribute)) or 0)
	local weapon = WeaponDefinitions.ById[tostring(player:GetAttribute(Config.EquippedWeaponAttribute))]
	local shield = ShieldDefinitions.ById[tostring(player:GetAttribute(Config.EquippedShieldAttribute))]
	hud.setLoadout(if weapon then weapon.DisplayName else "–", if shield then shield.DisplayName else "–")
end
for _, attribute in { Config.CoinsAttribute, Config.EquippedWeaponAttribute, Config.EquippedShieldAttribute } do
	player:GetAttributeChangedSignal(attribute):Connect(refreshInventory)
end
refreshInventory()

for _, attribute in { GameStates.StateAttribute, GameStates.LocationAttribute, Config.RunKillsAttribute, Config.RunCoinsAttribute } do
	player:GetAttributeChangedSignal(attribute):Connect(refreshWave)
end

ShopController.start({
	tag = Config.ShopItemTag,
	coins = Config.CoinsAttribute,
	equippedWeapon = Config.EquippedWeaponAttribute,
	equippedShield = Config.EquippedShieldAttribute,
	ownedWeapons = Config.OwnedWeaponsAttribute,
	ownedShields = Config.OwnedShieldsAttribute,
})

-- Run attributes on the arena folder
task.spawn(function()
	arena = waitFor(Workspace, Config.ArenaFolderName)
	if not arena then
		return
	end
	for _, name in { Config.RoundAttribute, Config.RoundMaxAttribute, Config.ZombiesAliveAttribute, Config.ZombiesTotalAttribute, Config.CountdownAttribute, Config.WavePhaseAttribute, Config.ArenaBusyAttribute, Config.FighterNameAttribute } do
		arena:GetAttributeChangedSignal(name):Connect(refreshWave)
	end
	refreshWave()
end)
refreshWave()

-- Target bar: the zombie hit last, otherwise the nearest one
local function isLivingZombie(model: Instance?): boolean
	return model ~= nil and model.Parent ~= nil and CollectionService:HasTag(model, CombatConfig.ZombieTag)
end

local function findTarget(): Instance?
	if isLivingZombie(lastHitModel) then
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
			hud.setTarget(tostring(target:GetAttribute("ZombieType") or target.Name), tonumber(target:GetAttribute("Health")) or 0, tonumber(target:GetAttribute("MaxHealth")) or 1)
		else
			hud.setTarget(nil, 0, 1)
		end
		refreshState()
	end
end)

ZombieAnimator.start(CombatConfig.ZombieTag)

print(PREFIX, "Ready: HUD, LMB attack / RMB block, shop displays")
