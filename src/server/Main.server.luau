--!strict
-- Server entry point: checks required instances, builds the world and starts the services.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PREFIX = "[OttiArena][Server]"
print(PREFIX, "Server script started")

local shared = ReplicatedStorage:FindFirstChild("Shared")
local required = {
	"Config", "CombatConfig", "GameStates", "GameModeDefinitions", "WeaponDefinitions", "ShieldDefinitions",
	"SpecialMoveDefinitions", "ComboDefinitions", "ZombieDefinitions", "ZombieAIProfiles", "RoundDefinitions",
}
for _, name in required do
	if not shared or not shared:FindFirstChild(name) then
		warn(PREFIX, ("ReplicatedStorage.Shared.%s is missing. Is Rojo connected and mapping src/shared?"):format(name))
		return
	end
end

local Config = require(ReplicatedStorage.Shared.Config)
local Arena = require(script.Parent.Arena)
local ArenaSafetyService = require(script.Parent.ArenaSafetyService)
local EquipmentShopService = require(script.Parent.EquipmentShopService)
local InventoryService = require(script.Parent.InventoryService)
local LobbyService = require(script.Parent.LobbyService)
local MatchService = require(script.Parent.MatchService)
local PlayerCombatService = require(script.Parent.PlayerCombatService)
local PlayerTagService = require(script.Parent.PlayerTagService)
local Remotes = require(script.Parent.Remotes)
local ShellService = require(script.Parent.ShellService)
local TrainingService = require(script.Parent.TrainingService)
local WaveService = require(script.Parent.WaveService)
local ZombieDisplayService = require(script.Parent.ZombieDisplayService)
local ZombieService = require(script.Parent.ZombieService)

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

-- World
local arena = Arena.build() -- also disables template SpawnLocations
local lobby = LobbyService.build() -- the only enabled SpawnLocation: everyone (re)spawns here
print(PREFIX, ("Arena ready: Colosseum %dx%d studs, %d zombie gates, %d shell spots"):format(Arena.Layout.SemiAxisX * 2, Arena.Layout.SemiAxisZ * 2, #Arena.Layout.ZombieSpawns, #Arena.Layout.ShellPositions))
print(PREFIX, "Lobby ready: weapons, shields, SOLO / CO-OP / TEAM areas, ZOMBIE ARCHIVE, training, tribunes")

local _ = Remotes -- requiring the module validates/creates all remotes
print(PREFIX, "Combat remotes ready (CombatAction, ShieldBlock, CombatFeedback)")

-- Services
ShellService.init(arena, Arena.Layout.ShellPositions)
ZombieService.init(arena:WaitForChild(Config.ZombiesFolderName), {
	hitPlayer = PlayerCombatService.applyZombieHit,
	isBlockingToward = PlayerCombatService.isBlockingToward,
	isHeavyBlocking = PlayerCombatService.isHeavyBlocking,
	slowPlayer = PlayerCombatService.applySlow,
	gearValue = InventoryService.gearValue,
})
PlayerCombatService.init()
PlayerTagService.init()
EquipmentShopService.build(lobby.folder, lobby.weaponSlots, lobby.shieldSlots)
TrainingService.build(lobby.folder, lobby.trainingSlots, lobby.trainingCFrame, lobby.trainingSize)
ZombieDisplayService.build(lobby.folder, lobby.archiveSlots, lobby.archivePlaques)
WaveService.init(arena)
MatchService.init(lobby, arena)
ArenaSafetyService.init()

Players.PlayerAdded:Connect(setupLeaderstats)
for _, player in Players:GetPlayers() do
	setupLeaderstats(player)
end

print(PREFIX, "Ready: one arena match at a time (Solo, Co-op 1-4, Team Battle up to 4v4)")
