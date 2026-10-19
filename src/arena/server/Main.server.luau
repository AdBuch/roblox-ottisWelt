--!strict
-- COLOSSEUM ARENA place server entry. Every match runs on its own reserved server of this place:
-- complete Colosseum, tribunes, imperial box, zombie waves, Otti, Co-op, Team Battle submodes,
-- spectators, result sequence and the return to the Hub. Players are only ever admitted with a
-- valid one-time ticket (ArenaAdmissionService); progress loads from the same DataStore as the Hub.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PREFIX = "[OttiArena][Arena]"
print(PREFIX, "Arena server script started")

local shared = ReplicatedStorage:FindFirstChild("Shared")
local required = {
	"Config", "CombatConfig", "GameStates", "GameModeDefinitions", "WeaponDefinitions", "ShieldDefinitions", "ArmorDefinitions",
	"SpecialMoveDefinitions", "ZombieDefinitions", "ZombieAIProfiles", "RoundDefinitions",
	"DamageEffectsConfig", "AudioConfig", "ProjectileDefinitions", "OttiBossConfig", "OttiMoveDefinitions", "BossPhaseDefinitions",
	"ExperienceConfig", "EnvironmentConfig", "GameProtocol", "MatchDefinitions", "TeamModeDefinitions", "MatchTypes", "PlayerDataSchema",
}
for _, name in required do
	if not shared or not shared:FindFirstChild(name) then
		warn(PREFIX, ("ReplicatedStorage.Shared.%s is missing. Is Rojo connected with places/arena.project.json?"):format(name))
		return
	end
end

local Config = require(ReplicatedStorage.Shared.Config)
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local Server = script.Parent.Parent
local Arena = require(Server.Arena)
local ArenaSafetyService = require(Server.ArenaSafetyService)
local CrowdReactionService = require(Server.CrowdReactionService)
local DamageEffectsService = require(Server.DamageEffectsService)
local InventoryService = require(Server.InventoryService)
local OttiBossService = require(Server.OttiBossService)
local PlayerCombatService = require(Server.PlayerCombatService)
local PlayerDataService = require(Server.PlayerDataService)
local ProjectileService = require(Server.ProjectileService)
local Remotes = require(Server.Remotes)
local ShellService = require(Server.ShellService)
local TeamBattleService = require(Server.TeamBattleService)
local TeleportUtil = require(Server.TeleportUtil)
local WaveService = require(Server.WaveService)
local ZombieService = require(Server.ZombieService)
local ArenaMatchService = require(script.Parent.ArenaMatchService)
local ArenaReturnService = require(script.Parent.ArenaReturnService)
local ArenaSpectatorService = require(script.Parent.ArenaSpectatorService)
local EliminationService = require(script.Parent.EliminationService)
local FirstToKillsService = require(script.Parent.FirstToKillsService)
local TimeBattleService = require(script.Parent.TimeBattleService)

if EnvironmentConfig.role() ~= "Arena" then
	warn(PREFIX, "This place was not built as the Arena (PlaceRole). Build it from places/arena.project.json.")
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

-- World
local arena = Arena.build() -- also disables template SpawnLocations
print(PREFIX, ("Arena ready: Colosseum %dx%d studs, %d zombie gates, %d shell spots"):format(Arena.Layout.SemiAxisX * 2, Arena.Layout.SemiAxisZ * 2, #Arena.Layout.ZombieSpawns, #Arena.Layout.ShellPositions))
-- Everybody (re)spawns on the tribune; MatchSpawnService moves fighters to their zone
local spawn = Instance.new("SpawnLocation")
spawn.Name = "TribuneSpawn"
spawn.Anchored = true
spawn.Transparency = 1
spawn.CanCollide = false
spawn.Size = Vector3.new(6, 1, 6)
spawn.CFrame = Arena.getTribuneCFrame(0) - Vector3.new(0, 2.5, 0)
spawn.Neutral = true
spawn.Duration = 0
spawn.Parent = arena
local _ = Remotes

-- Services
TeleportUtil.init()
PlayerDataService.init(PlayerCombatService.refreshEquipment) -- same schema and store as the Hub
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
PlayerCombatService.init()
WaveService.init(arena)
OttiBossService.init(arena, {
	hitPlayer = PlayerCombatService.applyBossHit,
	setControlLocked = PlayerCombatService.setControlLocked,
	grantImmunity = PlayerCombatService.grantImmunity,
	knockdown = PlayerCombatService.knockdown,
})
TeamBattleService.setRules({
	TIME_BATTLE = TimeBattleService,
	FIRST_TO = FirstToKillsService,
	ELIMINATION = EliminationService,
})
ArenaSpectatorService.init()
ArenaReturnService.init()
ArenaMatchService.init(arena) -- MatchService, admission, heartbeat, return requests
ArenaSafetyService.init()

Players.PlayerAdded:Connect(setupLeaderstats)
for _, player in Players:GetPlayers() do
	setupLeaderstats(player)
end

print(PREFIX, "Ready:", EnvironmentConfig.describe(), if game.PrivateServerId ~= "" then "(reserved server)" else "")
