--!strict
-- Server-owned inventory per player: Aura (progress), Denarii (money), owned weapons/shields/armor,
-- the equipped item of each kind and a few player preferences. Profiles live in memory keyed by
-- UserId; PlayerDataService loads them from the DataStore on join (load) and saves serialize().
--   Aura     experience: earned by playing, never spent. It gives the GLADIATOR LEVEL
--            (GladiatorLevelDefinitions); an item is UNLOCKED at its LevelRequired.
--   Denarii  earned with every Aura reward and spent on unlocked items (their Price).
-- Buying needs the item unlocked AND enough Denarii; equipping needs it owned AND unlocked.
--
-- Used identically by the Hub and the Arena place (same schema, validation and migrations:
-- PlayerDataSchema). Migration: version 1 stored `coins` (moved into `auraPoints` once and
-- cleared); version 2 had no armor (Recruit Leather is granted); version 3 had no statistics
-- (all start at 0); version 4 spent Aura on gear: the old balance becomes the Denarii balance and
-- Aura becomes balance + what the owned gear cost back then, so nothing owned gets locked.
-- migrateProfile() is safe to call repeatedly and also removes unknown ids, so a saved profile can
-- never equip something that no longer exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmorDefinitions = require(ReplicatedStorage.Shared.ArmorDefinitions)
local Config = require(ReplicatedStorage.Shared.Config)
local CurrencyConfig = require(ReplicatedStorage.Shared.CurrencyConfig)
local GladiatorLevelDefinitions = require(ReplicatedStorage.Shared.GladiatorLevelDefinitions)
local PlayerDataSchema = require(ReplicatedStorage.Shared.PlayerDataSchema)
local ShieldDefinitions = require(ReplicatedStorage.Shared.ShieldDefinitions)
local WeaponDefinitions = require(ReplicatedStorage.Shared.WeaponDefinitions)

type WeaponDefinition = WeaponDefinitions.WeaponDefinition
type ShieldDefinition = ShieldDefinitions.ShieldDefinition
type ArmorDefinition = ArmorDefinitions.ArmorDefinition

export type ItemKind = "Weapon" | "Shield" | "Armor"

export type Profile = {
	version: number,
	auraPoints: number, -- progress (never spent)
	denarii: number, -- money
	coins: number?, -- legacy field (version 1); migrated into auraPoints
	ownedWeapons: { [string]: boolean },
	ownedShields: { [string]: boolean },
	ownedArmor: { [string]: boolean },
	equippedWeapon: string,
	equippedShield: string,
	equippedArmor: string,
	preferences: { [string]: string },
	stats: { [string]: number },
}

local PROFILE_VERSION = PlayerDataSchema.Version
local DENARII_VERSION = 5 -- first schema version with separate Denarii

-- Preferences a client may store (value must be one of the listed strings)
local PREFERENCES: { [string]: { string } } = PlayerDataSchema.Preferences :: any

local InventoryService = {}

local profiles: { [number]: Profile } = {}
local changedListeners: { (player: Player) -> () } = {}

local function newProfile(): Profile
	return {
		version = PROFILE_VERSION,
		auraPoints = 0,
		denarii = CurrencyConfig.StarterDenarii,
		coins = nil,
		ownedWeapons = { [WeaponDefinitions.Starter] = true },
		ownedShields = { [ShieldDefinitions.Starter] = true },
		ownedArmor = { [ArmorDefinitions.Starter] = true },
		equippedWeapon = WeaponDefinitions.Starter,
		equippedShield = ShieldDefinitions.Starter,
		equippedArmor = ArmorDefinitions.Starter,
		preferences = {},
		stats = {},
	}
end

local function cleanSet(value: unknown, known: { [string]: any }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	if typeof(value) == "string" then
		for id in value:gmatch("[^,]+") do
			if known[id] then
				set[id] = true
			end
		end
	elseif typeof(value) == "table" then
		for id, owned in value :: { [any]: any } do
			if typeof(id) == "string" and owned == true and known[id] then
				set[id] = true
			end
		end
	end
	return set
end

local function wholeNumber(value: unknown): number
	local n = tonumber(value) or 0
	return if n == n then math.max(0, math.floor(n)) else 0
end

-- The Aura spent on everything owned (old prices; used once when converting v4 profiles).
local function spentOn(profile: Profile): number
	local total = 0
	for id in profile.ownedWeapons do
		total += WeaponDefinitions.ById[id].Price
	end
	for id in profile.ownedShields do
		total += ShieldDefinitions.ById[id].Price
	end
	for id in profile.ownedArmor do
		total += ArmorDefinitions.ById[id].Price
	end
	return total
end

-- Brings any profile (new, legacy, or loaded from the DataStore) to the current version.
function InventoryService.migrateProfile(profile: Profile): Profile
	local savedVersion = tonumber(profile.version) or 0
	local legacy = profile.coins
	if legacy ~= nil then
		profile.auraPoints = (tonumber(profile.auraPoints) or 0) + math.max(0, math.floor(legacy))
		profile.coins = nil -- cleared in the same step: the value can't be counted twice
	end
	profile.auraPoints = wholeNumber(profile.auraPoints)
	profile.ownedWeapons = cleanSet(profile.ownedWeapons, WeaponDefinitions.ById)
	profile.ownedShields = cleanSet(profile.ownedShields, ShieldDefinitions.ById)
	profile.ownedArmor = cleanSet(profile.ownedArmor, ArmorDefinitions.ById)
	profile.ownedWeapons[WeaponDefinitions.Starter] = true
	profile.ownedShields[ShieldDefinitions.Starter] = true
	profile.ownedArmor[ArmorDefinitions.Starter] = true
	if savedVersion < DENARII_VERSION then
		-- v4 and older spent Aura on gear: the remaining balance keeps its buying power as Denarii,
		-- and Aura is restored by what the owned gear needs, so earlier unlocks stay unlocked.
		profile.denarii = profile.auraPoints
		profile.auraPoints += spentOn(profile)
	end
	profile.denarii = wholeNumber(profile.denarii)
	if typeof(profile.equippedWeapon) ~= "string" or not profile.ownedWeapons[profile.equippedWeapon] then
		profile.equippedWeapon = WeaponDefinitions.Starter
	end
	if typeof(profile.equippedShield) ~= "string" or not profile.ownedShields[profile.equippedShield] then
		profile.equippedShield = ShieldDefinitions.Starter
	end
	if typeof(profile.equippedArmor) ~= "string" or not profile.ownedArmor[profile.equippedArmor] then
		profile.equippedArmor = ArmorDefinitions.Starter
	end
	local preferences: { [string]: string } = {}
	if typeof(profile.preferences) == "table" then
		for key, value in profile.preferences :: { [any]: any } do
			local allowed = PREFERENCES[key]
			if allowed and table.find(allowed, value) then
				preferences[key] = value
			end
		end
	end
	profile.preferences = preferences
	local stats: { [string]: number } = {}
	local savedStats: any = profile.stats
	for _, key in PlayerDataSchema.Stats do
		local value = if typeof(savedStats) == "table" then tonumber(savedStats[key]) else nil
		stats[key] = if value and value == value then math.max(0, math.floor(value)) else 0
	end
	profile.stats = stats
	profile.version = math.max(PROFILE_VERSION, savedVersion)
	return profile
end

local function getProfile(player: Player): Profile
	local profile = profiles[player.UserId]
	if not profile then
		profile = newProfile()
		profiles[player.UserId] = profile
	elseif profile.version < PROFILE_VERSION or profile.coins ~= nil then
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

local function changed(player: Player)
	for _, callback in changedListeners do
		task.spawn(callback, player)
	end
end

-- Called after every change that should be saved (PlayerDataService marks the profile dirty).
function InventoryService.onChanged(callback: (player: Player) -> ())
	table.insert(changedListeners, callback)
end

-- Mirrors the profile to player attributes for the HUD and shop displays (display only).
function InventoryService.publish(player: Player)
	local profile = getProfile(player)
	player:SetAttribute(Config.AuraAttribute, profile.auraPoints)
	player:SetAttribute(Config.DenariiAttribute, profile.denarii)
	player:SetAttribute(Config.EquippedWeaponAttribute, profile.equippedWeapon)
	player:SetAttribute(Config.EquippedShieldAttribute, profile.equippedShield)
	player:SetAttribute(Config.EquippedArmorAttribute, profile.equippedArmor)
	player:SetAttribute(Config.OwnedWeaponsAttribute, joinOwned(profile.ownedWeapons))
	player:SetAttribute(Config.OwnedShieldsAttribute, joinOwned(profile.ownedShields))
	player:SetAttribute(Config.OwnedArmorAttribute, joinOwned(profile.ownedArmor))
	for key in PREFERENCES do
		player:SetAttribute(Config.PreferencePrefix .. key, profile.preferences[key] or "")
	end
end

-- Replaces the in-memory profile with a loaded one. Aura and Denarii earned before the load
-- finished (`earnedAura`, `earnedDenarii`) are kept on top, so nothing is lost while the
-- DataStore answers.
function InventoryService.load(player: Player, saved: { [string]: any }?, earnedAura: number, earnedDenarii: number)
	local profile: Profile = if saved then (table.clone(saved) :: any) else newProfile()
	InventoryService.migrateProfile(profile)
	profile.auraPoints += math.max(0, math.floor(earnedAura))
	profile.denarii += math.max(0, math.floor(earnedDenarii))
	profiles[player.UserId] = profile
	InventoryService.publish(player)
end

function InventoryService.forget(player: Player)
	profiles[player.UserId] = nil
end

function InventoryService.getAura(player: Player): number
	return getProfile(player).auraPoints
end

function InventoryService.getDenarii(player: Player): number
	return getProfile(player).denarii
end

-- Aura is progress: it only ever grows.
function InventoryService.addAura(player: Player, amount: number)
	if amount ~= amount or amount <= 0 then
		return
	end
	local profile = getProfile(player)
	profile.auraPoints += math.floor(amount)
	InventoryService.publish(player)
	changed(player)
end

function InventoryService.addDenarii(player: Player, amount: number)
	if amount ~= amount or amount <= 0 then
		return
	end
	local profile = getProfile(player)
	profile.denarii += math.floor(amount)
	InventoryService.publish(player)
	changed(player)
end

local function ownedSet(profile: Profile, kind: ItemKind): { [string]: boolean }
	return if kind == "Weapon" then profile.ownedWeapons elseif kind == "Shield" then profile.ownedShields else profile.ownedArmor
end

-- (display name, price in Denarii, gladiator level required) of an item, or nil.
local function lookup(kind: ItemKind, id: string): (string?, number, number)
	local def: { DisplayName: string, Price: number, LevelRequired: number }? = if kind == "Weapon"
		then WeaponDefinitions.ById[id] :: any
		elseif kind == "Shield" then ShieldDefinitions.ById[id] :: any
		elseif kind == "Armor" then ArmorDefinitions.ById[id] :: any
		else nil
	if def then
		return def.DisplayName, def.Price, def.LevelRequired
	end
	return nil, 0, 0
end

function InventoryService.isItem(kind: unknown, id: unknown): boolean
	if typeof(id) ~= "string" or (kind ~= "Weapon" and kind ~= "Shield" and kind ~= "Armor") then
		return false
	end
	return (lookup(kind :: ItemKind, id)) ~= nil
end

function InventoryService.owns(player: Player, kind: ItemKind, id: string): boolean
	return ownedSet(getProfile(player), kind)[id] == true
end

-- The player's gladiator level (derived from total Aura; never stored).
function InventoryService.getLevel(player: Player): number
	local current = GladiatorLevelDefinitions.levelFor(getProfile(player).auraPoints)
	return current.Level
end

-- A readable lock message, or nil when the player's level is high enough.
local function lockReason(profile: Profile, name: string, required: number): string?
	local current = GladiatorLevelDefinitions.levelFor(profile.auraPoints)
	if current.Level >= required then
		return nil
	end
	local needed = GladiatorLevelDefinitions.get(required)
	return ("LOCKED: %s needs level %d %s (you are level %d)"):format(name, required, if needed then needed.Title else "", current.Level)
end

-- High enough gladiator level to buy / use this item?
function InventoryService.isUnlocked(player: Player, kind: ItemKind, id: string): boolean
	local name, _, required = lookup(kind, id)
	return name ~= nil and lockReason(getProfile(player), name, required) == nil
end

function InventoryService.isEquipped(player: Player, kind: ItemKind, id: string): boolean
	local profile = getProfile(player)
	local equipped = if kind == "Weapon" then profile.equippedWeapon elseif kind == "Shield" then profile.equippedShield else profile.equippedArmor
	return equipped == id
end

-- Buys an unlocked item with Denarii. Never allows duplicates, a locked item or a negative balance.
-- Returns (success, message).
function InventoryService.purchase(player: Player, kind: ItemKind, id: string): (boolean, string)
	local name, price, required = lookup(kind, id)
	if not name then
		return false, "Unknown item"
	end
	if InventoryService.owns(player, kind, id) then
		return false, name .. " is already owned"
	end
	local profile = getProfile(player)
	local locked = lockReason(profile, name, required)
	if locked then
		return false, locked
	end
	if price < 0 or profile.denarii < price then
		return false, ("NOT ENOUGH DENARII for %s (%d needed)"):format(name, price)
	end
	profile.denarii -= price
	ownedSet(profile, kind)[id] = true
	InventoryService.publish(player)
	changed(player)
	return true, ("Bought %s for %d Denarii"):format(name, price)
end

-- Equips an owned, unlocked item (exactly one per kind). Returns (success, message).
function InventoryService.equip(player: Player, kind: ItemKind, id: string): (boolean, string)
	local name, _, required = lookup(kind, id)
	if not name then
		return false, "Unknown item"
	end
	if not InventoryService.owns(player, kind, id) then
		return false, name .. " is not owned yet"
	end
	local profile = getProfile(player)
	local locked = lockReason(profile, name, required)
	if locked then
		return false, locked
	end
	local message = name .. " equipped"
	if kind == "Weapon" then
		profile.equippedWeapon = id
		local weapon = WeaponDefinitions.ById[id]
		if weapon and weapon.TwoHanded then
			message ..= " (two-handed: shield unused, built-in parry)"
		end
	elseif kind == "Shield" then
		profile.equippedShield = id
		if InventoryService.getEquippedWeapon(player).TwoHanded then
			message ..= " (unused while twin daggers are equipped)"
		end
	else
		profile.equippedArmor = id
	end
	InventoryService.publish(player)
	changed(player)
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

-- The armor worn (always one: Recruit Leather is free and can't be lost).
function InventoryService.getEquippedArmor(player: Player): ArmorDefinition
	local profile = getProfile(player)
	local def = ArmorDefinitions.ById[profile.equippedArmor]
	if def and profile.ownedArmor[def.Id] then
		return def
	end
	return ArmorDefinitions.ById[ArmorDefinitions.Starter]
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
	return weapon.Price + (if shield then shield.Price else 0) + InventoryService.getEquippedArmor(player).Price
end

-- Stores a whitelisted preference. Returns true when it changed.
function InventoryService.setPreference(player: Player, key: unknown, value: unknown): boolean
	if typeof(key) ~= "string" or typeof(value) ~= "string" then
		return false
	end
	local allowed = PREFERENCES[key]
	if not allowed or not table.find(allowed, value) then
		return false
	end
	local profile = getProfile(player)
	if profile.preferences[key] == value then
		return false
	end
	profile.preferences[key] = value
	player:SetAttribute(Config.PreferencePrefix .. key, value)
	changed(player)
	return true
end

-- Increases a saved statistic (server decisions only, e.g. a validated kill or victory).
function InventoryService.addStat(player: Player, key: string, amount: number?)
	if not PlayerDataSchema.isStat(key) then
		return
	end
	local value = math.floor(amount or 1)
	if value <= 0 then
		return
	end
	local profile = getProfile(player)
	profile.stats[key] = (profile.stats[key] or 0) + value
	changed(player)
end

function InventoryService.getStat(player: Player, key: string): number
	return getProfile(player).stats[key] or 0
end

function InventoryService.getPreference(player: Player, key: string): string?
	return getProfile(player).preferences[key]
end

-- Plain table for the DataStore (only JSON-safe values).
function InventoryService.serialize(player: Player): { [string]: any }
	local profile = getProfile(player)
	return {
		version = PROFILE_VERSION,
		auraPoints = profile.auraPoints,
		denarii = profile.denarii,
		ownedWeapons = joinOwned(profile.ownedWeapons),
		ownedShields = joinOwned(profile.ownedShields),
		ownedArmor = joinOwned(profile.ownedArmor),
		equippedWeapon = profile.equippedWeapon,
		equippedShield = profile.equippedShield,
		equippedArmor = profile.equippedArmor,
		preferences = table.clone(profile.preferences),
		stats = table.clone(profile.stats),
	}
end

return InventoryService
