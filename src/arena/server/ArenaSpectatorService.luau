--!strict
-- Spectators inside a reserved Arena server (role SPECTATOR from an admission ticket, or a fighter
-- whose run is over). They:
--   * spawn on a lower / middle tribune spot (never the arena floor, never the imperial box)
--   * have no combat context: they can't deal or receive damage, collect shells or Aura, affect
--     objectives, trigger Otti or zombies (CombatRules / MatchService only know fighters)
--   * use their own PhysicsService collision group "Spectators": they walk through each other and
--     never collide with zombies or Otti; projectiles already ignore every non-target character
--   * stay out of the arena: the podium barrier and ArenaSafetyService keep them on the stands
-- Counts (connected spectators) feed the registry heartbeat and the spectator capacity.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local Server = script.Parent.Parent
local MatchService = require(Server.MatchService)

local PREFIX = "[OttiArena][Arena]"
local GROUP = Config.SpectatorCollisionGroup

local ArenaSpectatorService = {}

local spectators: { [Player]: boolean } = {}

local function registerGroups()
	if not PhysicsService:IsCollisionGroupRegistered(GROUP) then
		PhysicsService:RegisterCollisionGroup(GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	for _, other in { CombatConfig.ZombieCollisionGroup, "OttiBoss" } do
		if PhysicsService:IsCollisionGroupRegistered(other) then
			PhysicsService:CollisionGroupSetCollidable(GROUP, other, false)
		end
	end
end

local function applyGroup(character: Model, group: string)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

local function hook(player: Player, character: Model)
	local group = if spectators[player] then GROUP else "Default"
	applyGroup(character, group)
	character.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = if spectators[player] then GROUP else "Default"
		end
	end)
end

-- Makes the player a spectator (tribune spawn, no combat, own collision group).
function ArenaSpectatorService.add(player: Player)
	spectators[player] = true
	MatchService.addSpectator(player)
	if player.Character then
		applyGroup(player.Character, GROUP)
	end
	print(PREFIX, player.Name, "watches from the tribunes")
end

-- A fighter (back) in the fight: normal collisions.
function ArenaSpectatorService.remove(player: Player)
	spectators[player] = nil
	if player.Character then
		applyGroup(player.Character, "Default")
	end
end

function ArenaSpectatorService.isSpectator(player: Player): boolean
	return spectators[player] == true
end

function ArenaSpectatorService.count(): number
	local n = 0
	for player in spectators do
		if player.Parent then
			n += 1
		end
	end
	return n
end

function ArenaSpectatorService.init()
	local ok, err = pcall(function()
		registerGroups()
	end)
	if not ok then
		warn(PREFIX, "Spectator collision group:", err)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			hook(player, character)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		spectators[player] = nil
	end)
end

return ArenaSpectatorService
