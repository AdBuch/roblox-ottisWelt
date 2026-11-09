--!strict
-- OTTI HUB (start place) server entry. Builds the three hero lobbies INTO the Colosseum's ground
-- hall (Otti's lobby with the zombie archive, the shop street, the training yard, Schili's and
-- Krokero's lobbies with their groups) and Rome around it (Rome/RomeWorld). Starts the Hub
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
local Config = require(ReplicatedStorage.Shared.Config)
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local Server = script.Parent.Parent
local CombatRules = require(Server.CombatRules)
local CombatUtil = require(Server.CombatUtil)
local EquipmentShopService = require(Server.EquipmentShopService)
local LobbyService = require(Server.LobbyService)
local LoadoutRequestService = require(Server.LoadoutRequestService)
local PlayerCombatService = require(Server.PlayerCombatService)
local PlayerDataService = require(Server.PlayerDataService)
local Remotes = require(Server.Remotes)
local TeleportUtil = require(Server.TeleportUtil)
local TrainingService = require(Server.TrainingService)
local ZombieDisplayService = require(Server.ZombieDisplayService)
local HubMatchService = require(script.Parent.HubMatchService)
local LobbyIntroService = require(script.Parent.LobbyIntroService)

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

-- World: the three hero lobbies, plus the shared playable Colosseum architecture.
local lobby = LobbyService.build()
print(PREFIX, ("Lobby ready: %d pads, three hero halls, shop street, training yard, tribunes"):format(#lobby.pads))
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
LobbyIntroService.init(lobby)
PlayerDataService.init(function(player: Player) -- same schema and store as the Arena
	PlayerCombatService.refreshEquipment(player)
	LobbyIntroService.onLoaded(player)
end)
PlayerCombatService.init()
EquipmentShopService.build(lobby.folder, lobby.armory)
LoadoutRequestService.init() -- equip OWNED gear from the lobby menu (server-validated)
TrainingService.build(lobby.folder, lobby.trainingSlots, lobby.trainingCFrame, lobby.trainingSize)
ZombieDisplayService.build(lobby.folder, lobby.archiveSlots, lobby.archivePlaques)
HubMatchService.init(lobby)

-- Rome around the Colosseum (island, town, smithy, temple, harbour) and its two counters. The
-- lobbies are ready first; the town follows in the background, players can already play.
local Rome = script.Parent.Rome
local RomeWorld = require(Rome.RomeWorld)
local TownServices = require(Rome.TownServices)
local WorldEdgeService = require(Rome.WorldEdgeService)
local function remote(name: string, class: string): Instance
	local folder = ReplicatedStorage:WaitForChild(Config.RemotesFolderName)
	local existing = folder:FindFirstChild(name)
	if existing and existing.ClassName == class then
		return existing
	end
	local created = Instance.new(class)
	created.Name = name
	created.Parent = folder
	return created
end
local romeRequest = remote("RomeRequest", "RemoteFunction") :: RemoteFunction
local romeEvent = remote("RomeEvent", "RemoteEvent") :: RemoteEvent
local forumRespawn: CFrame? = nil
-- Safety: a fall over the world's rim -> once to the forum fountain; the sand -> lobby respawn
WorldEdgeService.start(function()
	return forumRespawn
end, lobby.spawnCFrame, function(player: Player, kind: string)
	romeEvent:FireClient(player, "Respawned", { kind = kind })
end)
task.spawn(function()
	local world = RomeWorld.build(TownServices.openForge, TownServices.openOracle)
	forumRespawn = world.forumRespawn
	TownServices.start(romeRequest, romeEvent, world.smith.root, world.oracle.root)
end)

Players.PlayerAdded:Connect(setupLeaderstats)
for _, player in Players:GetPlayers() do
	setupLeaderstats(player)
end

print(PREFIX, "Ready:", EnvironmentConfig.describe())
