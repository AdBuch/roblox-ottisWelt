--!strict
-- OTTI HUB (start place) server entry. Builds the three hero lobbies INTO the Colosseum's ground
-- hall (Otti's lobby with the zombie archive and the solo start in his gate, Schili's and
-- Krokero's lobbies whose gates lead down to the co-op and team cellars) and Rome around it
-- (Rome/RomeWorld: shops, smithy, the two training yards). Starts the Hub
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
local LobbyService = require(Server.LobbyService)
local LoadoutRequestService = require(Server.LoadoutRequestService)
local PlayerCombatService = require(Server.PlayerCombatService)
local PlayerDataService = require(Server.PlayerDataService)
local PurchaseService = require(Server.PurchaseService)
local TownServices = require(script.Parent.Rome.TownServices)
local Remotes = require(Server.Remotes)
local TeleportUtil = require(Server.TeleportUtil)
local TrainingService = require(Server.TrainingService)
local ZombieDisplayService = require(Server.ZombieDisplayService)
local HubMatchService = require(script.Parent.HubMatchService)
local HubTeleportService = require(script.Parent.HubTeleportService)
local CellarService = require(script.Parent.CellarService)
local RomeLayout = require(script.Parent.Rome.RomeLayout)
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
print(PREFIX, ("Lobby ready: %d pads, three hero halls, two cellars, %d gateways, tribunes"):format(#lobby.pads, #lobby.portals))
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
PurchaseService.init(function(player, product)
	if product.helmet then
		PlayerCombatService.refreshEquipment(player)
	end
	TownServices.purchaseGranted(player, product)
end)
PlayerCombatService.init()
LoadoutRequestService.init() -- equip OWNED gear from the lobby menu (server-validated)
-- Training: the straw dummies stand in the two yards behind the smithy and the helm shop in Rome
local trainingSlots, trainingAreas = RomeLayout.training()
TrainingService.build(lobby.folder, trainingSlots, trainingAreas)
-- The gates down to the cellars and back; nobody stays on the closed arena's sand
CellarService.start(lobby.portals, LobbyService.isOnSand, lobby.spawnCFrame, function(player: Player, text: string)
	HubTeleportService.message(player, text, true)
end)
ZombieDisplayService.build(lobby.folder, lobby.archiveSlots, lobby.archivePlaques, lobby.archiveIds)
HubMatchService.init(lobby)

-- Rome around the Colosseum (island, town, smithy, temple, harbour) and its two counters. The
-- lobbies are ready first; the town follows in the background, players can already play.
local Rome = script.Parent.Rome
local RomeWorld = require(Rome.RomeWorld)
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
-- Safety: a fall over the world's rim -> once to the forum fountain (the cellars lie above the deep-fall line)
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
