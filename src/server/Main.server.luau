--!strict
-- Server entry point: checks required instances, builds the arena and wires up gameplay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PREFIX = "[OttiArena][Server]"
print(PREFIX, "Server script started")

local shared = ReplicatedStorage:FindFirstChild("Shared")
if not shared or not shared:FindFirstChild("Config") or not shared:FindFirstChild("CombatConfig") then
	warn(PREFIX, "ReplicatedStorage.Shared (Config, CombatConfig) is missing. Is Rojo connected and mapping src/shared?")
	return
end

local Config = require(ReplicatedStorage.Shared.Config)
local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Arena = require(script.Parent.Arena)
local ArenaSafetyService = require(script.Parent.ArenaSafetyService)
local Remotes = require(script.Parent.Remotes)
local Shells = require(script.Parent.Shells)
local ShieldService = require(script.Parent.ShieldService)
local SwordService = require(script.Parent.SwordService)
local ZombieService = require(script.Parent.ZombieService)

local BACKPACK_TIMEOUT = 5

local function grantEquipment(player: Player)
	local backpack = player:WaitForChild("Backpack", BACKPACK_TIMEOUT)
	if not backpack then
		warn(PREFIX, "No Backpack for", player.Name, "- equipment not granted")
		return
	end
	SwordService.give(backpack)
	ShieldService.give(player, backpack)
	print(PREFIX, ("Equipment granted to %s: %s, %s"):format(player.Name, CombatConfig.SwordToolName, CombatConfig.ShieldToolName))
end

local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		grantEquipment(player)
	end)
	if player.Character then
		task.spawn(grantEquipment, player)
	end

	if player:FindFirstChild("leaderstats") then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local shells = Instance.new("IntValue")
	shells.Name = "Shells"
	shells.Parent = leaderstats
	leaderstats.Parent = player

	player:GetAttributeChangedSignal(Config.ZombieDefeatedAttribute):Connect(function()
		if player:GetAttribute(Config.ZombieDefeatedAttribute) == true then
			print(PREFIX, player.Name, "completed the combat check (zombie defeated)")
		end
	end)
end

local arena = Arena.build()
print(PREFIX, "Arena ready (walls", Arena.Layout.WallHeight, "studs high, gate closed)")
ArenaSafetyService.init()
Shells.init(arena, Arena.Layout.ShellPositions)

ShieldService.init()
SwordService.init()
local _ = Remotes -- resolving the module validates/creates all remotes
print(PREFIX, "Combat remotes ready (SwordAttack, ShieldBlock, CombatFeedback)")

ZombieService.init(arena, Arena.Layout.ZombiePosition, Arena.Layout.SpawnPosition)

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(setupPlayer, player)
end

print(PREFIX, "Ready")
