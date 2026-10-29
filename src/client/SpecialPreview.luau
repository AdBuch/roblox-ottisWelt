--!strict
-- Display only. The server repeats selection, level and practice checks on release.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Levels = require(Shared.GladiatorLevelDefinitions)
local Charge = require(Shared.SpecialChargeDefinitions)
local Practice = require(Shared.SpecialPracticeDefinitions)
local Weapons = require(Shared.WeaponDefinitions)
local Moves = require(Shared.SpecialMoveDefinitions)
local Preview = {}

function Preview.text(player: Player, seconds: number, momentum: number): string
	local tier, ultimate = Charge.forRelease(seconds, momentum)
	if not tier then return "RECHARGING" end
	local weapon = Weapons.ById[tostring(player:GetAttribute(Config.EquippedWeaponAttribute))]
	if not weapon then return "" end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local air = humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air
	local block = character ~= nil and (character:GetAttribute("Blocking") == true or character:GetAttribute("SpecialBlockHeld") == true)
	local level = Levels.levelFor(tonumber(player:GetAttribute(Config.AuraAttribute)) or 0).Level
	local family = Practice.family(tier.Family, ultimate, air, block, level)
	local id = Charge.specialFor(nil, weapon.Basic, family)
	local move = id and (Moves :: any)[id]
	if not move or not id then return "" end
	return move.Name .. " · " .. Practice.label(player, weapon.Id, id)
end

return Preview
