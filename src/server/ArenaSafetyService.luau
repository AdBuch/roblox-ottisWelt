--!strict
-- Safety net, checked twice per second (never every frame):
--   fighters outside the arena floor      -> back to the arena start
--   spectators on the arena floor/lost    -> back to the tribune walkway
--   lobby players who fell out of the hall -> back to the lobby spawn
--   zombies outside the arena floor       -> back to a valid spot inside the arena

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local Arena = require(script.Parent.Arena)
local GameStateService = require(script.Parent.GameStateService)
local LobbyService = require(script.Parent.LobbyService)

local PREFIX = "[OttiArena][Server]"
local CHECK_INTERVAL = 0.5

local ArenaSafetyService = {}

local function move(character: Model, root: BasePart, cframe: CFrame, playerName: string, where: string)
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(cframe)
	print(PREFIX, playerName, "was out of bounds and was returned to the", where)
end

local function checkPlayers()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not root or not root:IsA("BasePart") then
			continue
		end
		local position = root.Position
		local state = GameStateService.getState(player)
		if GameStates.isFighter(state) or state == GameStates.EnteringArena or state == GameStates.Victory then
			if not Arena.isInside(position, 1) then
				move(character, root, Arena.getStartCFrame(), player.Name, "arena")
			end
		elseif state == GameStates.Spectating then
			local onArenaFloor = Arena.isInside(position, -1) and position.Y < Arena.Layout.TribuneWalkwayY - 4
			if onArenaFloor or not Arena.isInTribune(position) then
				move(character, root, Arena.getTribuneCFrame(), player.Name, "tribune")
			end
		elseif state == GameStates.Lobby or state == GameStates.EquipmentSelection then
			if not LobbyService.isInside(position) then
				move(character, root, GameStateService.getLobbyCFrame(), player.Name, "lobby")
			end
		end
	end
end

local function checkZombies()
	for _, model in CollectionService:GetTagged(CombatConfig.ZombieTag) do
		if not model:IsA("Model") then
			continue
		end
		local root = model.PrimaryPart
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if root and humanoid and not Arena.isInside(root.Position, 1) then
			local height = humanoid.HipHeight + root.Size.Y / 2
			root.AssemblyLinearVelocity = Vector3.zero
			model:PivotTo(CFrame.new(Arena.getSafePoint(root.Position) + Vector3.new(0, height, 0)))
			warn(PREFIX, model.Name, "left the arena bounds and was moved back inside")
		end
	end
end

function ArenaSafetyService.init()
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			checkPlayers()
			checkZombies()
		end
	end)
end

return ArenaSafetyService
