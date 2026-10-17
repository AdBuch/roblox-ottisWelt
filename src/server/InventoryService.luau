--!strict
-- Server-owned inventory per player: coins, owned weapons/shields, equipped weapon/shield.
-- Profiles are kept in memory for this server session, keyed by UserId, so they survive
-- death, returning to the lobby and even rejoining the same server.
-- DataStore later: replace newProfile() with a load and call serialize() on save; nothing
-- else needs to change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ShieldDefinitions = require(ReplicatedStorage.Shared.ShieldDefinitions)
local WeaponDefinitions = require(ReplicatedStorage.Shared.WeaponDefinitions)

type WeaponDefinition = WeaponDefinitions.WeaponDefinition
type ShieldDefinition = ShieldDefinitions.ShieldDefinition

export type ItemKind = "Weapon" | "Shield"

export type Profile = {
	coins: number,
	ownedWeapons: { [string]: boolean },
	ownedShields: { [string]: boolean },
	equippedWeapon: string,
	equippedShield: string,
}

local InventoryService = {}

local profiles: { [number]: Profile } = {}

local function newProfile(): Profile
	return {
		coins = 0,
		ownedWeapons = { [WeaponDefinitions.Starter] = true },
		ownedShields = { [ShieldDefinitions.Starter] = true },
		equippedWeapon = WeaponDefinitions.Starter,
		equippedShield = ShieldDefinitions.Starter,
	}
end

local function getProfile(player: Player): Profile
	local profile = profiles[player.UserId]
	if not profile then
		profile = newProfile()
		profiles[player.UserId] = profile
	end
	return profile
end

local function joinOwned(owned: { [string]: boolean }): string
	local ids = {}
	for id, isOwned in owned do
		if isOwned then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

-- Mirrors the profile to player attributes for the HUD and shop displays (display only).
function InventoryService.publish(player: Player)
	local profile = getProfile(player)
	player:SetAttribute(Config.CoinsAttribute, profile.coins)
	player:SetAttribute(Config.EquippedWeaponAttribute, profile.equippedWeapon)
	player:SetAttribute(Config.EquippedShieldAttribute, profile.equippedShield)
	player:SetAttribute(Config.OwnedWeaponsAttribute, joinOwned(profile.ownedWeapons))
	player:SetAttribute(Config.OwnedShieldsAttribute, joinOwned(profile.ownedShields))
end

function InventoryService.getCoins(player: Player): number
	return getProfile(player).coins
end

function InventoryService.addCoins(player: Player, amount: number)
	if amount <= 0 or amount ~= amount then
		return
	end
	local profile = getProfile(player)
	profile.coins += math.floor(amount)
	InventoryService.publish(player)
end

local function lookup(kind: ItemKind, id: string): (string?, number)
	if kind == "Weapon" then
		local def = WeaponDefinitions.ById[id]
		if def then
			return def.DisplayName, def.Price
		end
	elseif kind == "Shield" then
		local def = ShieldDefinitions.ById[id]
		if def then
			return def.DisplayName, def.Price
		end
	end
	return nil, 0
end

function InventoryService.owns(player: Player, kind: ItemKind, id: string): boolean
	local profile = getProfile(player)
	local owned = if kind == "Weapon" then profile.ownedWeapons else profile.ownedShields
	return owned[id] == true
end

-- Buys an item. Never allows duplicates or a negative balance. Returns (success, message).
function InventoryService.purchase(player: Player, kind: ItemKind, id: string): (boolean, string)
	local name, price = lookup(kind, id)
	if not name then
		return false, "Unknown item"
	end
	if InventoryService.owns(player, kind, id) then
		return false, name .. " is already owned"
	end
	local profile = getProfile(player)
	if profile.coins < price then
		return false, ("Not enough coins for %s (%d needed)"):format(name, price)
	end
	profile.coins -= price
	local owned = if kind == "Weapon" then profile.ownedWeapons else profile.ownedShields
	owned[id] = true
	InventoryService.publish(player)
	return true, ("Bought %s for %d coins"):format(name, price)
end

-- Equips an owned item (exactly one weapon and one shield at a time). Returns (success, message).
function InventoryService.equip(player: Player, kind: ItemKind, id: string): (boolean, string)
	local name = lookup(kind, id)
	if not name then
		return false, "Unknown item"
	end
	if not InventoryService.owns(player, kind, id) then
		return false, name .. " is not owned yet"
	end
	local profile = getProfile(player)
	if kind == "Weapon" then
		profile.equippedWeapon = id
	else
		profile.equippedShield = id
	end
	InventoryService.publish(player)
	return true, name .. " equipped"
end

function InventoryService.getEquippedWeapon(player: Player): WeaponDefinition
	local profile = getProfile(player)
	local def = WeaponDefinitions.ById[profile.equippedWeapon]
	if def and profile.ownedWeapons[def.Id] then
		return def
	end
	return WeaponDefinitions.ById[WeaponDefinitions.Starter]
end

function InventoryService.getEquippedShield(player: Player): ShieldDefinition
	local profile = getProfile(player)
	local def = ShieldDefinitions.ById[profile.equippedShield]
	if def and profile.ownedShields[def.Id] then
		return def
	end
	return ShieldDefinitions.ById[ShieldDefinitions.Starter]
end

-- Exactly one owned weapon and at most one owned shield must be equipped to enter the arena.
function InventoryService.hasValidLoadout(player: Player): (boolean, string)
	local profile = getProfile(player)
	if not WeaponDefinitions.ById[profile.equippedWeapon] or not profile.ownedWeapons[profile.equippedWeapon] then
		return false, "Equip a weapon first"
	end
	if not ShieldDefinitions.ById[profile.equippedShield] or not profile.ownedShields[profile.equippedShield] then
		return false, "Equip a shield first"
	end
	return true, "OK"
end

-- Plain table for a future DataStore save.
function InventoryService.serialize(player: Player): { [string]: any }
	local profile = getProfile(player)
	return {
		coins = profile.coins,
		ownedWeapons = joinOwned(profile.ownedWeapons),
		ownedShields = joinOwned(profile.ownedShields),
		equippedWeapon = profile.equippedWeapon,
		equippedShield = profile.equippedShield,
	}
end

return InventoryService
