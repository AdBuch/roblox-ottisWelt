--!strict
-- OTTI HUB (start place) server entry. Builds the gladiator dungeon under the Colosseum (central
-- hall with the Otti statue, arena corridor with the Zombie Archive, singleplayer and multiplayer
-- pads, Gladiator Armory, training yard, tribune stairs, Gate to Rome) and starts the Hub
-- services: persistent data, equipment, training combat, parties, matchmaking, live battles and
-- the teleports to reserved Arena servers. No arena match ever runs in the Hub.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PREFIX = "[OttiArena][Hub]"
print(PREFIX, "Hub server script started")

local shared = ReplicatedStorage:FindFirstChild("Shared")
for _, name in { "Config", "CombatConfig", "GameStates", "ExperienceConfig", "EnvironmentConfig", "GameProtocol", "MatchDefinitions", "PlayerDataSchema", "ArmorDefinitions", "WeaponDefinitions", "ShieldDefinitions" } do
	if not shared or not shared:FindFirstChild(name) then
		warn(PREFIX, ("ReplicatedStorage.Shared.%s is missing. Is Rojo connected with places/hub.project.json?"):format(name))
		return
	end
end

local GameStates = require(ReplicatedStorage.Shared.GameStates)
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local Server = script.Parent.Parent
local CombatRules = require(Server.CombatRules)
local CombatUtil = require(Server.CombatUtil)
local EquipmentShopService = require(Server.EquipmentShopService)
local LobbyService = require(Server.LobbyService)
local PlayerCombatService = require(Server.PlayerCombatService)
local PlayerDataService = require(Server.PlayerDataService)
local Remotes = require(Server.Remotes)
local TeleportUtil = require(Server.TeleportUtil)
local TrainingService = require(Server.TrainingService)
local ZombieDisplayService = require(Server.ZombieDisplayService)
local HubMatchService = require(script.Parent.HubMatchService)

if EnvironmentConfig.role() ~= "Hub" then
	warn(PREFIX, "This place was not built as the Hub (PlaceRole). Build it from places/hub.project.json.")
end

local function setupLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local shells = Instance.new("IntValue")
	shells.Name = "Shells"
	shells.Parent = leaderstats
	leaderstats.Parent = player
end

-- World: the basement only (the Colosseum itself lives in the Arena place)
local lobby = LobbyService.build()
print(PREFIX, ("Lobby ready: %d pads, GLADIATOR ARMORY, ZOMBIE ARCHIVE, training, tribunes"):format(#lobby.pads))
local _ = Remotes

-- Lobby combat rules: only the training dummies can be hit, nobody can be hurt
CombatRules.install({
	getContext = function(player: Player)
		if GameStates.isInLobby(player:GetAttribute(GameStates.StateAttribute)) then
			local _, _, root = CombatUtil.getLivingCharacter(player)
			if root and TrainingService.isInTrainingArea(root.Position) then
				return "Training"
			end
		end
		return nil
	end,
	isEnemy = function()
		return false
	end,
	canZombiesTarget = function()
		return false
	end,
	onPlayerDamaged = function() end,
	zombieTargets = function()
		return {}
	end,
})

TeleportUtil.init()
PlayerDataService.init(PlayerCombatService.refreshEquipment) -- same schema and store as the Arena
PlayerCombatService.init()
EquipmentShopService.build(lobby.folder, lobby.armory)
TrainingService.build(lobby.folder, lobby.trainingSlots, lobby.trainingCFrame, lobby.trainingSize)
ZombieDisplayService.build(lobby.folder, lobby.archiveSlots, lobby.archivePlaques)
HubMatchService.init(lobby)

-- Safety net: lobby players who fell out of the basement return to the spawn
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local character, _, root = CombatUtil.getLivingCharacter(player)
			if character and root and not LobbyService.isInside(root.Position) then
				root.AssemblyLinearVelocity = Vector3.zero
				character:PivotTo(lobby.spawnCFrame + Vector3.new(0, 3.5, 0))
			end
		end
	end
end)

Players.PlayerAdded:Connect(setupLeaderstats)
for _, player in Players:GetPlayers() do
	setupLeaderstats(player)
end

print(PREFIX, "Ready:", EnvironmentConfig.describe())
