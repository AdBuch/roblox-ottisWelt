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
	"DamageEffectsConfig", "AudioConfig", "ProjectileDefinitions", "OttiBossConfig", "OttiMoveDefinitions", "BossPhaseDefinitions", "ArmorDefinitions", "DamageConfig",
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
local CrowdReactionService = require(script.Parent.CrowdReactionService)
local DamageEffectsService = require(script.Parent.DamageEffectsService)
local EquipmentShopService = require(script.Parent.EquipmentShopService)
local InventoryService = require(script.Parent.InventoryService)
local LobbyService = require(script.Parent.LobbyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local MatchService = require(script.Parent.MatchService)
local OttiBossService = require(script.Parent.OttiBossService)
local PlayerCombatService = require(script.Parent.PlayerCombatService)
local ProjectileService = require(script.Parent.ProjectileService)
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
print(PREFIX, "Lobby ready: GLADIATOR ARMORY (weapons, shields, armor), SOLO / CO-OP / TEAM areas, ZOMBIE ARCHIVE, training, tribunes")

local _ = Remotes -- requiring the module validates/creates all remotes
print(PREFIX, "Combat remotes ready (CombatAction, ShieldBlock, CombatFeedback)")

-- Services
DamageEffectsService.init(arena)
CrowdReactionService.build(arena)
ShellService.init(arena, Arena.Layout.ShellPositions)
ZombieService.init(arena:WaitForChild(Config.ZombiesFolderName), {
	hitPlayer = PlayerCombatService.applyZombieHit,
	isBlockingToward = PlayerCombatService.isBlockingToward,
	isHeavyBlocking = PlayerCombatService.isHeavyBlocking,
	slowPlayer = PlayerCombatService.applySlow,
	gearValue = InventoryService.gearValue,
	fireArrow = function(arrow)
		-- Undead Sagittarius shot: server-simulated, blocked by walls/floor/gates, never hits spectators
		ProjectileService.fireEnemyArrow({
			origin = arrow.origin,
			direction = arrow.direction,
			speed = arrow.speed,
			range = arrow.range,
			isShooterAlive = arrow.isShooterAlive,
			onHitPlayer = function(player: Player)
				PlayerCombatService.applyEnemyArrowHit(player, arrow.origin, arrow.damage)
			end,
		})
	end,
})
PlayerDataService.init(PlayerCombatService.refreshEquipment) -- DataStore: Aura, gear, preferences
PlayerCombatService.init()
EquipmentShopService.build(lobby.folder, lobby.armory)
TrainingService.build(lobby.folder, lobby.trainingSlots, lobby.trainingCFrame, lobby.trainingSize)
ZombieDisplayService.build(lobby.folder, lobby.archiveSlots, lobby.archivePlaques)
WaveService.init(arena)
OttiBossService.init(arena, {
	hitPlayer = PlayerCombatService.applyBossHit,
	setControlLocked = PlayerCombatService.setControlLocked,
	grantImmunity = PlayerCombatService.grantImmunity,
	knockdown = PlayerCombatService.knockdown,
})
MatchService.init(lobby, arena)
ArenaSafetyService.init()

Players.PlayerAdded:Connect(setupLeaderstats)
for _, player in Players:GetPlayers() do
	setupLeaderstats(player)
end

print(PREFIX, "Ready: one arena match at a time (Solo, Co-op 1-4 with the Otti boss round, Team Battle up to 4v4)")
