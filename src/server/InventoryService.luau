--!strict
-- Server-owned inventory per player: Aura Points, owned weapons/shields, equipped items.
-- Profiles are kept in memory for this server session, keyed by UserId, so they survive death,
-- matches and even rejoining the same server.
--
-- Migration: older profiles stored `coins`. migrateProfile() moves that value into
-- `auraPoints` exactly once and clears `coins`, so nothing is duplicated or lost.
-- DataStore later: load a saved table into migrateProfile() and save serialize().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ShieldDefinitions = require(ReplicatedStorage.Shared.ShieldDefinitions)
local WeaponDefinitions = require(ReplicatedStorage.Shared.WeaponDefinitions)

type WeaponDefinition = WeaponDefinitions.WeaponDefinition
type ShieldDefinition = ShieldDefinitions.ShieldDefinition

export type ItemKind = "Weapon" | "Shield"

export type Profile = {
	version: number,
	auraPoints: number,
	coins: number?, -- legacy field (version 1); migrated into auraPoints
	ownedWeapons: { [string]: boolean },
	ownedShields: { [string]: boolean },
	equippedWeapon: string,
	equippedShield: string,
}

local PROFILE_VERSION = 2

local InventoryService = {}

local profiles: { [number]: Profile } = {}

local function newProfile(): Profile
	return {
		version = PROFILE_VERSION,
		auraPoints = 0,
		coins = nil,
		ownedWeapons = { [WeaponDefinitions.Starter] = true },
		ownedShields = { [ShieldDefinitions.Starter] = true },
		equippedWeapon = WeaponDefinitions.Starter,
		equippedShield = ShieldDefinitions.Starter,
	}
end

-- Moves a legacy coin balance into Aura Points once. Safe to call repeatedly.
function InventoryService.migrateProfile(profile: Profile): Profile
	local legacy = profile.coins
	if legacy ~= nil then
		profile.auraPoints = (profile.auraPoints or 0) + math.max(0, math.floor(legacy))
		profile.coins = nil -- cleared in the same step: the value can't be counted twice
	end
	profile.auraPoints = math.max(0, math.floor(profile.auraPoints or 0))
	profile.ownedWeapons[WeaponDefinitions.Starter] = true
	profile.ownedShields[ShieldDefinitions.Starter] = true
	profile.version = PROFILE_VERSION
	return profile
end

local function getProfile(player: Player): Profile
	local profile = profiles[player.UserId]
	if not profile then
		profile = newProfile()
		profiles[player.UserId] = profile
	elseif profile.version ~= PROFILE_VERSION or profile.coins ~= nil then
		InventoryService.migrateProfile(profile)
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
	player:SetAttribute(Config.AuraAttribute, profile.auraPoints)
	player:SetAttribute(Config.EquippedWeaponAttribute, profile.equippedWeapon)
	player:SetAttribute(Config.EquippedShieldAttribute, profile.equippedShield)
	player:SetAttribute(Config.OwnedWeaponsAttribute, joinOwned(profile.ownedWeapons))
	player:SetAttribute(Config.OwnedShieldsAttribute, joinOwned(profile.ownedShields))
end

function InventoryService.getAura(player: Player): number
	return getProfile(player).auraPoints
end

function InventoryService.addAura(player: Player, amount: number)
	if amount ~= amount or amount <= 0 then
		return
	end
	local profile = getProfile(player)
	profile.auraPoints += math.floor(amount)
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
	if profile.auraPoints < price then
		return false, ("NOT ENOUGH AURA for %s (%d needed)"):format(name, price)
	end
	profile.auraPoints -= price
	local owned = if kind == "Weapon" then profile.ownedWeapons else profile.ownedShields
	owned[id] = true
	InventoryService.publish(player)
	return true, ("Bought %s for %d Aura"):format(name, price)
end

-- Equips an owned item (exactly one weapon and one shield). Returns (success, message).
function InventoryService.equip(player: Player, kind: ItemKind, id: string): (boolean, string)
	local name = lookup(kind, id)
	if not name then
		return false, "Unknown item"
	end
	if not InventoryService.owns(player, kind, id) then
		return false, name .. " is not owned yet"
	end
	local profile = getProfile(player)
	local message = name .. " equipped"
	if kind == "Weapon" then
		profile.equippedWeapon = id
		local weapon = WeaponDefinitions.ById[id]
		if weapon and weapon.TwoHanded then
			message ..= " (two-handed: shield unused, built-in parry)"
		end
	else
		profile.equippedShield = id
		if InventoryService.getEquippedWeapon(player).TwoHanded then
			message ..= " (unused while twin daggers are equipped)"
		end
	end
	InventoryService.publish(player)
	return true, message
end

function InventoryService.getEquippedWeapon(player: Player): WeaponDefinition
	local profile = getProfile(player)
	local def = WeaponDefinitions.ById[profile.equippedWeapon]
	if def and profile.ownedWeapons[def.Id] then
		return def
	end
	return WeaponDefinitions.ById[WeaponDefinitions.Starter]
end

-- The shield actually in use, or nil when a two-handed weapon is equipped.
function InventoryService.getActiveShield(player: Player): ShieldDefinition?
	if InventoryService.getEquippedWeapon(player).TwoHanded then
		return nil
	end
	local profile = getProfile(player)
	local def = ShieldDefinitions.ById[profile.equippedShield]
	if def and profile.ownedShields[def.Id] then
		return def
	end
	return ShieldDefinitions.ById[ShieldDefinitions.Starter]
end

-- Exactly one owned weapon (+ an owned shield unless the weapon is two-handed).
function InventoryService.hasValidLoadout(player: Player): (boolean, string)
	local profile = getProfile(player)
	local weapon = WeaponDefinitions.ById[profile.equippedWeapon]
	if not weapon or not profile.ownedWeapons[weapon.Id] then
		return false, "Equip a weapon first"
	end
	if not weapon.TwoHanded and (not ShieldDefinitions.ById[profile.equippedShield] or not profile.ownedShields[profile.equippedShield]) then
		return false, "Equip a shield first"
	end
	return true, "OK"
end

-- A rough gear value (sum of prices) used by elite zombies to pick well-equipped targets.
function InventoryService.gearValue(player: Player): number
	local weapon = InventoryService.getEquippedWeapon(player)
	local shield = InventoryService.getActiveShield(player)
	return weapon.Price + (if shield then shield.Price else 0)
end

-- Plain table for a future DataStore save.
function InventoryService.serialize(player: Player): { [string]: any }
	local profile = getProfile(player)
	return {
		version = PROFILE_VERSION,
		auraPoints = profile.auraPoints,
		ownedWeapons = joinOwned(profile.ownedWeapons),
		ownedShields = joinOwned(profile.ownedShields),
		equippedWeapon = profile.equippedWeapon,
		equippedShield = profile.equippedShield,
	}
end

return InventoryService
