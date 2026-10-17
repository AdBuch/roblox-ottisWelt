--!strict
-- Server entry point: checks required instances, builds the world and starts the services.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PREFIX = "[OttiArena][Server]"
print(PREFIX, "Server script started")

local shared = ReplicatedStorage:FindFirstChild("Shared")
local required = { "Config", "CombatConfig", "GameStates", "WeaponDefinitions", "ShieldDefinitions", "ZombieDefinitions", "RoundDefinitions" }
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
local GameStateService = require(script.Parent.GameStateService)
local LobbyService = require(script.Parent.LobbyService)
local PlayerCombatService = require(script.Parent.PlayerCombatService)
local Remotes = require(script.Parent.Remotes)
local ShellService = require(script.Parent.ShellService)
local WaveService = require(script.Parent.WaveService)
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
print(PREFIX, ("Arena ready: Colosseum %dx%d studs, %d zombie gates, tribune walkways"):format(Arena.Layout.SemiAxisX * 2, Arena.Layout.SemiAxisZ * 2, #Arena.Layout.ZombieSpawns))
print(PREFIX, "Lobby ready: underground hall, equipment wall, ENTER ARENA gate, TRIBUNE door")

local _ = Remotes -- requiring the module validates/creates all remotes
print(PREFIX, "Combat remotes ready (WeaponAttack, ShieldBlock, CombatFeedback)")

-- Services
ShellService.init(arena, Arena.Layout.ShellPositions)
ZombieService.init(arena:WaitForChild(Config.ZombiesFolderName), {
	getTargets = GameStateService.getFighters,
	hitPlayer = PlayerCombatService.applyZombieHit,
	isBlockingToward = PlayerCombatService.isBlockingToward,
	slowPlayer = PlayerCombatService.applySlow,
})
PlayerCombatService.init()
EquipmentShopService.build(lobby.folder, lobby.weaponSlots, lobby.shieldSlots)
WaveService.init(arena)
GameStateService.init(lobby, arena)
ArenaSafetyService.init()

Players.PlayerAdded:Connect(setupLeaderstats)
for _, player in Players:GetPlayers() do
	setupLeaderstats(player)
end

print(PREFIX, "Ready: one fighter at a time, 6 rounds (1, 2, 4, 8, 16, 32 zombies)")
