--!strict
-- Safety net, checked twice per second (never every frame):
--   players in the arena (fighting, countdown, results) outside the floor -> arena start
--   spectators / waiting co-op players on the arena floor or lost         -> tribune walkway
--   anybody else (before admission, after the match) lost                  -> tribune walkway
--   eliminated players outside the closed waiting box                     -> waiting box
--   zombies or Otti outside the arena floor                               -> valid spot inside

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local Arena = require(script.Parent.Arena)
local PlayerMatchStateService = require(script.Parent.PlayerMatchStateService)

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
		local state = player:GetAttribute(GameStates.StateAttribute)
		if PlayerMatchStateService.getZone(player) == "ELIMINATED" then
			if not Arena.isInEliminationBox(position) then
				move(character, root, Arena.getEliminationCFrame(player.UserId), player.Name, "elimination box")
			end
			continue
		end
		local location = player:GetAttribute(GameStates.LocationAttribute)
		if location == "Arena" and (GameStates.isFighter(state) or state == GameStates.Countdown or state == GameStates.Victory or state == GameStates.MatchComplete) then
			if not Arena.isInside(position, 1) then
				move(character, root, Arena.getStartCFrame(), player.Name, "arena")
			end
		elseif location == "Tribune" then
			local onArenaFloor = Arena.isInside(position, -1) and position.Y < Arena.Layout.TribuneWalkwayY - 4
			if onArenaFloor or not Arena.isInTribune(position) then
				move(character, root, Arena.getTribuneCFrame(player.UserId), player.Name, "tribune")
			end
		else -- Arena place: everybody else belongs on the tribunes
			if not Arena.isInTribune(position) and not Arena.isInside(position, 1) then
				move(character, root, Arena.getTribuneCFrame(player.UserId), player.Name, "tribune")
			end
		end
	end
end

local function checkZombies()
	local enemies = CollectionService:GetTagged(CombatConfig.ZombieTag)
	for _, boss in CollectionService:GetTagged(Config.OttiTag) do
		table.insert(enemies, boss)
	end
	for _, model in enemies do
		if not model:IsA("Model") then
			continue
		end
		local root = model.PrimaryPart
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		-- Anchored roots are moved by script (Otti's entrance arc): never pull them back
		if root and humanoid and not root.Anchored and not Arena.isInside(root.Position, 1) then
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
