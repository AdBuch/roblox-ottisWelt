--!strict
-- Server entry point: checks required instances, builds the arena and wires up gameplay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PREFIX = "[OttiArena][Server]"
print(PREFIX, "Server script started")

local shared = ReplicatedStorage:FindFirstChild("Shared")
if not shared or not shared:FindFirstChild("Config") then
	warn(PREFIX, "ReplicatedStorage.Shared.Config is missing. Is Rojo connected and default.project.json mapping src/shared?")
	return
end

local Config = require(ReplicatedStorage.Shared.Config)
local Arena = require(script.Parent.Arena)
local Shells = require(script.Parent.Shells)
local Dummy = require(script.Parent.Dummy)
local Combat = require(script.Parent.Combat)

-- Remotes are created by Rojo (default.project.json). Fall back to creating them so the test still runs.
local function getAttackRemote(): RemoteEvent
	local remotes = ReplicatedStorage:FindFirstChild(Config.RemotesFolderName)
	if not remotes then
		warn(PREFIX, "ReplicatedStorage.Remotes is missing (should come from Rojo); creating it at runtime")
		local folder = Instance.new("Folder")
		folder.Name = Config.RemotesFolderName
		folder.Parent = ReplicatedStorage
		remotes = folder
	end
	assert(remotes, "Remotes folder")

	local remote = remotes:FindFirstChild(Config.AttackRemoteName)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	warn(PREFIX, "Remotes.Attack RemoteEvent is missing (should come from Rojo); creating it at runtime")
	local created = Instance.new("RemoteEvent")
	created.Name = Config.AttackRemoteName
	created.Parent = remotes
	return created
end

local function setupPlayer(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local shells = Instance.new("IntValue")
	shells.Name = "Shells"
	shells.Parent = leaderstats
	leaderstats.Parent = player

	local completed = false
	local function checkComplete()
		if completed then
			return
		end
		if shells.Value >= Config.ShellCount and player:GetAttribute(Config.ZombieDefeatedAttribute) == true then
			completed = true
			print(PREFIX, player.Name, "completed the setup check (3 shells + zombie defeated)")
		end
	end
	shells.Changed:Connect(checkComplete)
	player:GetAttributeChangedSignal(Config.ZombieDefeatedAttribute):Connect(checkComplete)
end

local arena = Arena.build()
Shells.init(arena, Arena.Layout.ShellPositions)
Dummy.init(arena, Arena.Layout.DummyPosition, Arena.Layout.SpawnPosition)
Combat.init(getAttackRemote())

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(setupPlayer, player)
end

print(PREFIX, ("Ready: arena built with %d shells and a %d HP training zombie"):format(Config.ShellCount, Config.DummyMaxHealth))
