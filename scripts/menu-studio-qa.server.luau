--!strict
-- MENU QA (Studio only, never in normal builds; scripts/build-menu-qa.ps1): gives the test player
-- real owned gear and Aura through the normal InventoryService paths, and lets the client QA script
-- switch the player into a fight state to test the equipment lock.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local InventoryService = require(Server:WaitForChild("InventoryService")) :: any
local PlayerCombatService = require(Server:WaitForChild("PlayerCombatService")) :: any

local control = Instance.new("RemoteEvent")
control.Name = "MenuQAControl"
control.Parent = ReplicatedStorage

local function prepare(player: Player)
	repeat
		task.wait(0.25)
	until player:GetAttribute("DataStatus") ~= "Loading" or not player.Parent
	InventoryService.beginBattle(player, "Solo")
	InventoryService.addReward(player, 30000, 3000) -- level 41: every armory item unlocked
	for _, item in {
		{ "Weapon", "LegionSword" }, { "Weapon", "HunterBow" }, { "Weapon", "TwinDaggers" },
		{ "Shield", "LegionShield" }, { "Shield", "TowerShield" }, { "Armor", "MurmilloArmor" },
	} do
		local ok, message = InventoryService.purchase(player, item[1], item[2])
		print("[MenuQA] SERVER purchase", item[2], ok, message)
	end
	PlayerCombatService.refreshEquipment(player)
	player:SetAttribute("MenuQAReady", true)
	print("[MenuQA] SERVER test gear ready for", player.Name)
end

control.OnServerEvent:Connect(function(player: Player, action: unknown)
	if action == "Lock" then
		player:SetAttribute("GameState", "MATCH_ACTIVE")
		player:SetAttribute("Location", "Arena")
	elseif action == "Unlock" then
		player:SetAttribute("GameState", "LOBBY")
		player:SetAttribute("Location", "Lobby")
	end
	player:SetAttribute("MenuQAState", tostring(action))
end)

Players.PlayerAdded:Connect(function(player)
	task.spawn(prepare, player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(prepare, player)
end
