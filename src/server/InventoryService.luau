--!strict
-- Server-owned inventory per player: Aura (progress), Denarii (money), owned weapons/shields/armor,
-- the equipped item of each kind and a few player preferences. Profiles live in memory keyed by
-- UserId; PlayerDataService loads them from the DataStore on join (load) and saves serialize().
--   Aura     experience: earned by playing, never spent. It gives the GLADIATOR LEVEL
--            (GladiatorLevelDefinitions); an item is UNLOCKED at its LevelRequired.
--   Denarii  earned with every Aura reward and spent on unlocked items (their Price).
-- Buying needs the item unlocked AND enough Denarii; equipping only needs it OWNED (gear that was
-- bought legitimately stays usable when level requirements are re-balanced).
--
-- Used identically by the Hub and the Arena place (same schema, validation and migrations:
-- PlayerDataSchema). Migration: version 1 stored `coins` (moved into `auraPoints` once and
-- cleared); version 2 had no armor (Recruit Leather is granted); version 3 had no statistics
-- (all start at 0); version 4 spent Aura on gear: the old balance becomes the Denarii balance and
-- Aura becomes balance + what the owned gear cost back then, so nothing owned gets locked.
-- Version 7 had no earnings history: v8 adds the persistent earnings counters (total Aura and
-- Denarii EARNED since tracking began, never derived from the balance), the play session, the last
-- battle and the active-play statistics for the time estimate. Old profiles start these counters at
-- 0 and are marked `complete = false` ("since tracking began"); nothing is invented.
-- migrateProfile() is safe to call repeatedly and also removes unknown ids, so a saved profile can
-- never equip something that no longer exists, and no value is ever granted twice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmorDefinitions = require(ReplicatedStorage.Shared.ArmorDefinitions)
local Config = require(ReplicatedStorage.Shared.Config)
local CurrencyConfig = require(ReplicatedStorage.Shared.CurrencyConfig)
local ForgeDefinitions = require(ReplicatedStorage.Shared.ForgeDefinitions)
local GladiatorLevelDefinitions = require(ReplicatedStorage.Shared.GladiatorLevelDefinitions)
local PlayerDataSchema = require(ReplicatedStorage.Shared.PlayerDataSchema)
local ShieldDefinitions = require(ReplicatedStorage.Shared.ShieldDefinitions)
local WeaponDefinitions = require(ReplicatedStorage.Shared.WeaponDefinitions)
local WeaponSpecialDefinitions = require(ReplicatedStorage.Shared.WeaponSpecialDefinitions)
local WeaponAttackDefinitions = require(ReplicatedStorage.Shared.WeaponAttackDefinitions)
local SpecialPracticeDefinitions = require(ReplicatedStorage.Shared.SpecialPracticeDefinitions)

type WeaponDefinition = WeaponDefinitions.WeaponDefinition
type ShieldDefinition = ShieldDefinitions.ShieldDefinition
type ArmorDefinition = ArmorDefinitions.ArmorDefinition

export type ItemKind = "Weapon" | "Shield" | "Armor"

-- Persistent earnings counters (only ever increased by server rewards; spending never touches them).
export type Earnings = {
	aura: number,
	denarii: number,
	since: number, -- os.time() when tracking began for this profile
	complete: boolean, -- true when tracking began with the profile itself (lifetime totals)
}

-- The current play session: survives Hub <-> Arena teleports, restarts after SessionGapSeconds away.
export type Session = { aura: number, denarii: number, startedAt: number, lastSeen: number }

-- Rewards of the last battle (started by beginBattle, filled by every reward of that battle).
export type LastBattle = { aura: number, denarii: number, mode: string, at: number }

-- Active fighting time and the Aura earned meanwhile: the basis of the optional play-time estimate.
export type Activity = { aura: number, seconds: number, rewards: number }

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
	specialAttempts: { [string]: number }, -- practice steps per weapon:move (SpecialPracticeDefinitions)
	specialDaily: { [string]: { day: number, Training: number, Arena: number } }, -- today's gained points
	resetToken: string?, -- the last controlled test-data reset applied (PlayerDataResetConfig)
	earnings: Earnings,
	session: Session,
	lastBattle: LastBattle?,
	activity: Activity,
	-- v10 (ForgeDefinitions): every owned weapon as copies with stage, wear, design and smith job
	weaponCopies: { [string]: { ForgeDefinitions.Copy } },
	activeCopy: { [string]: string }, -- weapon id -> uid of the copy in use
	nextCopy: number, -- uid counter
	shieldDesigns: { [string]: string }, -- shield id -> paint option
	forgeCredits: { [string]: number }, -- Robux-bought, not yet used: Skip, Design
	receipts: { string }, -- processed Robux purchase ids (newest last)
	forge: { [string]: number }?, -- v9 stages, folded into the copies on migration
}

local PROFILE_VERSION = PlayerDataSchema.Version
local DENARII_VERSION = 5 -- first schema version with separate Denarii
local SESSION_GAP = PlayerDataSchema.SessionGapSeconds
local ESTIMATE = PlayerDataSchema.Estimate

-- Preferences a client may store (value must be one of the listed strings)
local PREFERENCES: { [string]: { string } } = PlayerDataSchema.Preferences :: any

local InventoryService = {}

local profiles: { [number]: Profile } = {}
local changedListeners: { (player: Player) -> () } = {}
local practiceKeys: { [string]: boolean } = {}
for _, weapon in WeaponDefinitions.ById do
	local families = WeaponSpecialDefinitions.forPrefix(WeaponAttackDefinitions.prefixOf(weapon.Basic))
	if families then
		for _, moveId in families do
			practiceKeys[SpecialPracticeDefinitions.key(weapon.Id, moveId)] = true
		end
	end
end

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
		specialAttempts = {},
		specialDaily = {},
		earnings = { aura = 0, denarii = 0, since = os.time(), complete = true },
		session = { aura = 0, denarii = 0, startedAt = os.time(), lastSeen = os.time() },
		lastBattle = nil,
		activity = { aura = 0, seconds = 0, rewards = 0 },
		weaponCopies = { [WeaponDefinitions.Starter] = { { uid = WeaponDefinitions.Starter .. "-1", forge = 0, wear = 0, design = {} } } },
		activeCopy = { [WeaponDefinitions.Starter] = WeaponDefinitions.Starter .. "-1" },
		nextCopy = 2,
		shieldDesigns = {},
		forgeCredits = {},
		receipts = {},
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

-- WEAPON COPIES (ForgeDefinitions). A job ends by itself once its time is over: `settle` applies
-- the work when a copy is next looked at (so the result is the same in the Hub and the Arena).
local function newCopy(profile: Profile, weaponId: string, stage: number): ForgeDefinitions.Copy
	local copy: ForgeDefinitions.Copy = { uid = ("%s-%d"):format(weaponId, profile.nextCopy), forge = stage, wear = 0, design = {} }
	profile.nextCopy += 1
	local list = profile.weaponCopies[weaponId]
	if not list then
		list = {}
		profile.weaponCopies[weaponId] = list
		profile.activeCopy[weaponId] = copy.uid
	end
	table.insert(list, copy)
	return copy
end

local function finishJob(copy: ForgeDefinitions.Copy)
	local job = copy.job
	if not job then
		return
	end
	if job.kind == "Harden" then
		copy.forge = math.min(ForgeDefinitions.MaxLevel, copy.forge + 1)
	elseif job.kind == "Sharpen" then
		copy.wear = math.max(0, copy.wear - ForgeDefinitions.SharpenAmount)
	elseif job.kind == "Repair" then
		copy.wear = 0
	elseif job.kind == "Design" and job.slot and job.option then
		copy.design[job.slot] = job.option
	end -- "Copy": the new copy is simply ready
	copy.job = nil
end

-- Completes every job whose time is over. Returns true when something changed.
local function settle(profile: Profile, now: number): boolean
	local any = false
	for _, list in profile.weaponCopies do
		for _, copy in list do
			if copy.job and copy.job.untilTime <= now then
				finishJob(copy)
				any = true
			end
		end
	end
	return any
end

-- The copy of a weapon the player fights with: the chosen one if it is free, else any free one.
local function usableCopy(profile: Profile, weaponId: string): ForgeDefinitions.Copy?
	local list = profile.weaponCopies[weaponId]
	if not list then
		return nil
	end
	settle(profile, os.time())
	local chosen = profile.activeCopy[weaponId]
	local fallback: ForgeDefinitions.Copy? = nil
	for _, copy in list do
		if not copy.job then
			if copy.uid == chosen then
				return copy
			end
			fallback = fallback or copy
		end
	end
	return fallback
end

local function findCopy(profile: Profile, weaponId: string, uid: string): ForgeDefinitions.Copy?
	for _, copy in (profile.weaponCopies[weaponId] or {}) :: { ForgeDefinitions.Copy } do
		if copy.uid == uid then
			return copy
		end
	end
	return nil
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
	-- Stored steps are kept as they are (version 6 counted attempts; each attempt is one step)
	local attempts: { [string]: number } = {}
	local savedAttempts: any = profile.specialAttempts
	local daily: { [string]: { day: number, Training: number, Arena: number } } = {}
	local savedDaily: any = profile.specialDaily
	for key in practiceKeys do
		local value = if typeof(savedAttempts) == "table" then tonumber(savedAttempts[key]) else nil
		if value and value == value then
			attempts[key] = SpecialPracticeDefinitions.clampSteps(value)
		end
		local entry: any = if typeof(savedDaily) == "table" then savedDaily[key] else nil
		if typeof(entry) == "table" then
			local day, training, arena = tonumber(entry.day), tonumber(entry.Training), tonumber(entry.Arena)
			if day and training and arena then
				daily[key] = { day = math.floor(day), Training = math.max(0, training), Arena = math.max(0, arena) }
			end
		end
	end
	profile.specialAttempts = attempts
	profile.specialDaily = daily
	if typeof(profile.resetToken) ~= "string" then
		profile.resetToken = nil
	end
	-- v8: earnings history. Created ONCE with counters at 0 (never derived from the balance); an
	-- existing table is only sanitized, so repeating the migration never adds anything.
	local now = os.time()
	local earnings: any = profile.earnings
	if typeof(earnings) ~= "table" then
		earnings = { aura = 0, denarii = 0, since = now, complete = savedVersion == 0 and profile.auraPoints == 0 and profile.denarii == 0 }
	end
	profile.earnings = {
		aura = wholeNumber(earnings.aura),
		denarii = wholeNumber(earnings.denarii),
		since = if typeof(earnings.since) == "number" and earnings.since > 0 then math.floor(earnings.since) else now,
		complete = earnings.complete == true,
	}
	local session: any = profile.session
	local hasSession = typeof(session) == "table"
	profile.session = {
		aura = if hasSession then wholeNumber(session.aura) else 0,
		denarii = if hasSession then wholeNumber(session.denarii) else 0,
		startedAt = if hasSession and typeof(session.startedAt) == "number" then session.startedAt else now,
		lastSeen = if hasSession and typeof(session.lastSeen) == "number" then session.lastSeen else now,
	}
	local last: any = profile.lastBattle
	if typeof(last) == "table" and typeof(last.at) == "number" then
		profile.lastBattle = { aura = wholeNumber(last.aura), denarii = wholeNumber(last.denarii), mode = if typeof(last.mode) == "string" then last.mode else "", at = last.at }
	else
		profile.lastBattle = nil
	end
	local activity: any = profile.activity
	local hasActivity = typeof(activity) == "table"
	profile.activity = {
		aura = if hasActivity then wholeNumber(activity.aura) else 0,
		seconds = if hasActivity then wholeNumber(activity.seconds) else 0,
		rewards = if hasActivity then wholeNumber(activity.rewards) else 0,
	}
	-- v10: weapon copies. Saved copies are cleaned (unknown weapons dropped, stage and wear clamped,
	-- broken jobs removed, uids unique); every owned weapon gets at least one copy, and the v9 stage
	-- of a weapon (`forge`) goes onto its first copy, once (the v9 table is cleared in the same step).
	local savedForge: any = profile.forge
	local savedCopies: any = profile.weaponCopies
	local copies: { [string]: { ForgeDefinitions.Copy } } = {}
	local seen: { [string]: boolean } = {}
	local counter = math.max(1, wholeNumber(profile.nextCopy))
	local jobKinds = ForgeDefinitions.JobSeconds :: any
	if typeof(savedCopies) == "table" then
		for id, list in savedCopies do
			if ForgeDefinitions.isSupported(id) and typeof(list) == "table" then
				local clean: { ForgeDefinitions.Copy } = {}
				for _, c in list do
					if typeof(c) == "table" and typeof(c.uid) == "string" and not seen[c.uid] and #clean < ForgeDefinitions.MaxCopies then
						seen[c.uid] = true
						local design: { [string]: string } = {}
						if typeof(c.design) == "table" then
							for slotId, optionId in c.design do
								local slot = ForgeDefinitions.designSlot(slotId)
								if slot and ForgeDefinitions.designOption(slot, optionId) then
									design[slotId] = optionId
								end
							end
						end
						local job: ForgeDefinitions.Job? = nil
						local j = c.job
						if typeof(j) == "table" and typeof(j.kind) == "string" and jobKinds[j.kind] and typeof(j.untilTime) == "number" then
							job = { kind = j.kind :: any, untilTime = j.untilTime, slot = if typeof(j.slot) == "string" then j.slot else nil, option = if typeof(j.option) == "string" then j.option else nil }
						end
						table.insert(clean, { uid = c.uid, forge = ForgeDefinitions.clampLevel(c.forge), wear = ForgeDefinitions.clampWear(c.wear), design = design, job = job })
					end
				end
				if #clean > 0 then
					copies[id] = clean
				end
			end
		end
	end
	for id in profile.ownedWeapons do
		if not copies[id] then
			local uid = id .. "-" .. counter
			counter += 1
			local stage = if typeof(savedForge) == "table" then ForgeDefinitions.clampLevel(savedForge[id]) else 0
			copies[id] = { { uid = uid, forge = stage, wear = 0, design = {} } }
		end
	end
	for id in copies do
		profile.ownedWeapons[id] = true -- a copy is ownership
	end
	profile.weaponCopies = copies
	profile.nextCopy = counter
	profile.forge = nil
	local active: { [string]: string } = {}
	local savedActive: any = profile.activeCopy
	for id, list in copies do
		local chosen = if typeof(savedActive) == "table" then savedActive[id] else nil
		local valid = false
		for _, c in list do
			if c.uid == chosen then
				valid = true
			end
		end
		active[id] = if valid then chosen else list[1].uid
	end
	profile.activeCopy = active
	local shieldDesigns: { [string]: string } = {}
	if typeof(profile.shieldDesigns) == "table" then
		for id, option in profile.shieldDesigns :: any do
			if ShieldDefinitions.ById[id] and ForgeDefinitions.designOption(ForgeDefinitions.ShieldSlot, option) then
				shieldDesigns[id] = option
			end
		end
	end
	profile.shieldDesigns = shieldDesigns
	local credits: { [string]: number } = {}
	if typeof(profile.forgeCredits) == "table" then
		for _, key in { "Skip", "Design" } do
			credits[key] = wholeNumber((profile.forgeCredits :: any)[key])
		end
	end
	profile.forgeCredits = credits
	local receipts: { string } = {}
	if typeof(profile.receipts) == "table" then
		for _, r in profile.receipts :: any do
			if typeof(r) == "string" then
				table.insert(receipts, r)
			end
		end
	end
	while #receipts > ForgeDefinitions.MaxReceipts do
		table.remove(receipts, 1)
	end
	profile.receipts = receipts
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
	for key in practiceKeys do
		player:SetAttribute(SpecialPracticeDefinitions.attribute(key), profile.specialAttempts[key] or 0)
	end
	for key in PREFERENCES do
		player:SetAttribute(Config.PreferencePrefix .. key, profile.preferences[key] or "")
	end
	-- Earnings (display only): the profile's own counters, never the balance
	player:SetAttribute(Config.EarnedAuraAttribute, profile.earnings.aura)
	player:SetAttribute(Config.EarnedDenariiAttribute, profile.earnings.denarii)
	player:SetAttribute(Config.EarnedSinceAttribute, profile.earnings.since)
	player:SetAttribute(Config.EarnedCompleteAttribute, profile.earnings.complete)
	player:SetAttribute(Config.SessionAuraAttribute, profile.session.aura)
	player:SetAttribute(Config.SessionDenariiAttribute, profile.session.denarii)
	local last = profile.lastBattle
	player:SetAttribute(Config.LastBattleAuraAttribute, if last then last.aura else nil)
	player:SetAttribute(Config.LastBattleDenariiAttribute, if last then last.denarii else nil)
	player:SetAttribute(Config.LastBattleModeAttribute, if last then last.mode else nil)
	player:SetAttribute(Config.AuraPerHourAttribute, InventoryService.auraPerActiveHour(player))
	local levels: { [string]: number } = {}
	for id in profile.weaponCopies do
		local copy = usableCopy(profile, id)
		levels[id] = if copy then copy.forge else 0
	end
	player:SetAttribute(ForgeDefinitions.Attribute, ForgeDefinitions.encode(levels))
end

-- Replaces the in-memory profile with a loaded one. Aura and Denarii earned before the load
-- finished (`earnedAura`, `earnedDenarii`) are kept on top, so nothing is lost while the
-- DataStore answers.
function InventoryService.load(player: Player, saved: { [string]: any }?, earnedAura: number, earnedDenarii: number, resetToken: string?)
	local profile: Profile = if saved then (table.clone(saved) :: any) else newProfile()
	InventoryService.migrateProfile(profile)
	local now = os.time()
	if now - profile.session.lastSeen > SESSION_GAP then
		-- away for a while: a new play session (a Hub <-> Arena teleport takes seconds, not minutes)
		profile.session = { aura = 0, denarii = 0, startedAt = now, lastSeen = now }
	end
	profile.session.lastSeen = now
	local lateAura = math.max(0, math.floor(earnedAura))
	local lateDenarii = math.max(0, math.floor(earnedDenarii))
	profile.auraPoints += lateAura
	profile.denarii += lateDenarii
	-- rewards paid while the DataStore answered were never saved: they count as earnings once
	profile.earnings.aura += lateAura
	profile.earnings.denarii += lateDenarii
	profile.session.aura += lateAura
	profile.session.denarii += lateDenarii
	if resetToken then
		profile.resetToken = resetToken -- this profile is reset at most once per token
	end
	profiles[player.UserId] = profile
	InventoryService.publish(player)
end

-- Studio test switch (ExperienceConfig.Studio.UnlockAllGear): every item owned, top level.
-- Only called for mock player data, so it is never written to a DataStore.
function InventoryService.unlockAll(player: Player)
	local profile = getProfile(player)
	for id in WeaponDefinitions.ById do
		profile.ownedWeapons[id] = true
		if not profile.weaponCopies[id] then
			newCopy(profile, id, 0)
		end
	end
	for id in ShieldDefinitions.ById do
		profile.ownedShields[id] = true
	end
	for id in ArmorDefinitions.ById do
		profile.ownedArmor[id] = true
	end
	local levels = GladiatorLevelDefinitions.Levels
	profile.auraPoints = math.max(profile.auraPoints, levels[#levels].Aura)
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

-- One server-decided reward: Aura + Denarii, counted ONCE in the persistent earnings, the session,
-- the last battle (if one was started) and, unless `active` is false, the active-play statistics.
function InventoryService.addReward(player: Player, aura: number, denarii: number, active: boolean?)
	local a = if aura == aura then math.max(0, math.floor(aura)) else 0
	local d = if denarii == denarii then math.max(0, math.floor(denarii)) else 0
	if a <= 0 and d <= 0 then
		return
	end
	local profile = getProfile(player)
	profile.auraPoints += a
	profile.denarii += d
	profile.earnings.aura += a
	profile.earnings.denarii += d
	profile.session.aura += a
	profile.session.denarii += d
	local last = profile.lastBattle
	if last then
		last.aura += a
		last.denarii += d
	end
	if active ~= false then
		profile.activity.aura += a
		profile.activity.rewards += 1
	end
	InventoryService.publish(player)
	changed(player)
end

-- A battle starts: its rewards are collected as "last battle" from now on.
function InventoryService.beginBattle(player: Player, mode: string)
	local profile = getProfile(player)
	profile.lastBattle = { aura = 0, denarii = 0, mode = mode, at = os.time() }
	InventoryService.publish(player)
	changed(player)
end

-- Seconds of ACTIVE fighting (match states only; lobby waiting never counts).
function InventoryService.addActiveSeconds(player: Player, seconds: number)
	if seconds ~= seconds or seconds <= 0 then
		return
	end
	local profile = getProfile(player)
	profile.activity.seconds += math.floor(seconds + 0.5)
	player:SetAttribute(Config.AuraPerHourAttribute, InventoryService.auraPerActiveHour(player))
end

-- Aura per hour of active play, or 0 while there is too little real data for an honest estimate.
function InventoryService.auraPerActiveHour(player: Player): number
	local activity = getProfile(player).activity
	if activity.rewards < ESTIMATE.MinRewards or activity.seconds < ESTIMATE.MinActiveSeconds or activity.aura <= 0 then
		return 0
	end
	return math.floor(activity.aura / activity.seconds * 3600 + 0.5)
end

function InventoryService.getEarnings(player: Player): Earnings
	return table.clone(getProfile(player).earnings)
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
	if kind == "Weapon" and not profile.weaponCopies[id] then
		newCopy(profile, id, 0) -- the first copy of a bought weapon
	end
	InventoryService.publish(player)
	changed(player)
	return true, ("Bought %s for %d Denarii"):format(name, price)
end

-- Equips an OWNED item (exactly one per kind). The level only limits buying: gear that was bought
-- legitimately stays usable after a re-balance of LevelRequired. Never costs Denarii.
-- Returns (success, message).
function InventoryService.equip(player: Player, kind: ItemKind, id: string): (boolean, string)
	if not InventoryService.isItem(kind, id) then
		return false, "Unknown item"
	end
	local name = lookup(kind, id) :: string
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
	elseif kind == "Shield" then
		profile.equippedShield = id
		-- kept as the choice for one-handed weapons; a two-handed weapon ignores it
		if InventoryService.getEquippedWeapon(player).TwoHanded then
			message ..= " (unused while a two-handed weapon is equipped)"
		end
	else
		profile.equippedArmor = id
	end
	InventoryService.publish(player)
	changed(player)
	return true, message
end

-- The weapon in the hand: the equipped weapon while a copy of it is free (not at the smith),
-- otherwise the starter gladius (a plain loaner if every starter copy is at the smith, too).
function InventoryService.getEquippedWeapon(player: Player): WeaponDefinition
	local profile = getProfile(player)
	local def = WeaponDefinitions.ById[profile.equippedWeapon]
	if def and profile.ownedWeapons[def.Id] and usableCopy(profile, def.Id) then
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

-- Hardening stage of the copy the player fights with (0 = none or no free copy).
function InventoryService.forgeLevel(player: Player, weaponId: string): number
	local copy = usableCopy(getProfile(player), weaponId)
	return if copy then copy.forge else 0
end

-- The PvE factor of the copy in use (hardening x wear); 1 for a loaner or without a copy.
function InventoryService.copyFactor(player: Player, weaponId: string): number
	local copy = usableCopy(getProfile(player), weaponId)
	return if copy then ForgeDefinitions.copyFactor(copy.forge, copy.wear) else 1
end

-- The copy in use (read-only for callers: designs for the weapon model, values for dialogs).
function InventoryService.copyInUse(player: Player, weaponId: string): ForgeDefinitions.Copy?
	return usableCopy(getProfile(player), weaponId)
end

-- Every copy of a weapon (jobs settled), oldest first.
function InventoryService.copies(player: Player, weaponId: string): { ForgeDefinitions.Copy }
	local profile = getProfile(player)
	if settle(profile, os.time()) then
		InventoryService.publish(player)
		changed(player)
	end
	return profile.weaponCopies[weaponId] or {}
end

function InventoryService.activeCopyId(player: Player, weaponId: string): string?
	return getProfile(player).activeCopy[weaponId]
end

-- Completes due jobs. Returns true when a job ended (callers refresh the equipment).
function InventoryService.settleJobs(player: Player): boolean
	local profile = getProfile(player)
	if settle(profile, os.time()) then
		InventoryService.publish(player)
		changed(player)
		return true
	end
	return false
end

-- PvE wear on the copy in use (hits on zombies and bosses only; PlayerCombatService). Publishes
-- only when the copy passes into another wear step.
function InventoryService.addWear(player: Player, weaponId: string, amount: number)
	if amount ~= amount or amount <= 0 then
		return
	end
	local copy = usableCopy(getProfile(player), weaponId)
	if not copy then
		return
	end
	local before = ForgeDefinitions.wearStep(copy.wear)
	copy.wear = ForgeDefinitions.clampWear(copy.wear + amount)
	if ForgeDefinitions.wearStep(copy.wear) ~= before then
		InventoryService.publish(player)
	end
	changed(player)
end

-- Which copy to fight with (a free one of the player's own).
function InventoryService.setActiveCopy(player: Player, weaponId: string, uid: string): (boolean, string)
	local profile = getProfile(player)
	local copy = findCopy(profile, weaponId, uid)
	if not copy then
		return false, "Dieses Exemplar gehört dir nicht."
	end
	settle(profile, os.time())
	if copy.job then
		return false, "Dieses Exemplar ist noch beim Schmied."
	end
	profile.activeCopy[weaponId] = uid
	InventoryService.publish(player)
	changed(player)
	return true, "Exemplar gewählt."
end

-- A job at the smith as ONE operation: checks weapon, copy, ownership, that the copy is free,
-- the job's precondition and the server price, then takes the Denarii and starts the job together
-- (nothing yields in between, so nothing is charged twice or without the job). `Copy` makes a new
-- copy (uid ignored). `Design` is paid with a Robux credit (TownServices), so its price here is 0.
-- Returns (success, message, price, uid of the copy worked on).
function InventoryService.startJob(player: Player, weaponId: string, uid: string?, kind: ForgeDefinitions.JobKind, slot: string?, option: string?): (boolean, string, number, string?)
	if not ForgeDefinitions.isSupported(weaponId) then
		return false, "Diese Waffe kennt der Schmied nicht.", 0, nil
	end
	local profile = getProfile(player)
	local name = WeaponDefinitions.ById[weaponId].DisplayName
	if not profile.ownedWeapons[weaponId] then
		return false, name .. " gehört dir nicht.", 0, nil
	end
	local now = os.time()
	settle(profile, now)
	local seconds = (ForgeDefinitions.JobSeconds :: any)[kind]
	if not seconds then
		return false, "Diese Arbeit kennt der Schmied nicht.", 0, nil
	end
	local price = 0
	local copy: ForgeDefinitions.Copy? = nil
	if kind == "Copy" then
		local owned = #(profile.weaponCopies[weaponId] or {})
		if owned >= ForgeDefinitions.MaxCopies then
			return false, ("Mehr als %d Exemplare nimmt der Schmied nicht an."):format(ForgeDefinitions.MaxCopies), 0, nil
		end
		price = ForgeDefinitions.copyPrice(weaponId, owned)
	else
		copy = if uid then findCopy(profile, weaponId, uid) else nil
		if not copy then
			return false, "Dieses Exemplar gehört dir nicht.", 0, nil
		end
		local c = copy :: ForgeDefinitions.Copy
		if c.job then
			return false, "Dieses Exemplar ist schon beim Schmied.", 0, nil
		end
		if kind == "Harden" then
			if c.forge >= ForgeDefinitions.MaxLevel then
				return false, name .. " ist bereits gehärtet.", 0, nil
			end
			price = ForgeDefinitions.price(weaponId, c.forge)
		elseif kind == "Sharpen" or kind == "Repair" then
			if c.wear <= 0 then
				return false, name .. " ist in gutem Zustand.", 0, nil
			end
			price = if kind == "Sharpen" then ForgeDefinitions.sharpenPrice(weaponId) else ForgeDefinitions.repairPrice(weaponId, c.wear)
		elseif kind == "Design" then
			local designSlot = ForgeDefinitions.designSlot(slot)
			if not designSlot or not ForgeDefinitions.designOption(designSlot, option) then
				return false, "Dieses Design gibt es nicht.", 0, nil
			end
			if c.design[slot :: string] == option then
				return false, "Dieses Exemplar hat das Design schon.", 0, nil
			end
		end
	end
	if profile.denarii < price then
		return false, ("Zu wenig Denarii: %d nötig, du hast %d."):format(price, profile.denarii), price, nil
	end
	profile.denarii -= price
	if kind == "Copy" then
		copy = newCopy(profile, weaponId, 0)
	end
	local worked = copy :: ForgeDefinitions.Copy
	worked.job = { kind = kind, untilTime = now + seconds, slot = slot, option = option }
	InventoryService.publish(player)
	changed(player)
	local label = (ForgeDefinitions.JobLabels :: any)[kind]
	return true, ("%s: %s, fertig in %d Minuten%s."):format(name, label, math.ceil(seconds / 60), if price > 0 then (" (%d Denarii)"):format(price) else ""), price, worked.uid
end

-- Finishes a running job now (a ForgeSkip purchase). Returns (success, message).
function InventoryService.finishJobNow(player: Player, weaponId: string, uid: string): (boolean, string)
	local profile = getProfile(player)
	local copy = findCopy(profile, weaponId, uid)
	if not copy or not copy.job then
		return false, "Für dieses Exemplar läuft keine Arbeit."
	end
	finishJob(copy)
	InventoryService.publish(player)
	changed(player)
	return true, "Der Schmied ist fertig."
end

function InventoryService.shieldDesign(player: Player, shieldId: string): string?
	return getProfile(player).shieldDesigns[shieldId]
end

function InventoryService.setShieldDesign(player: Player, shieldId: string, option: string): (boolean, string)
	local profile = getProfile(player)
	if not profile.ownedShields[shieldId] then
		return false, "Dieser Schild gehört dir nicht."
	end
	if not ForgeDefinitions.designOption(ForgeDefinitions.ShieldSlot, option) then
		return false, "Diese Bemalung gibt es nicht."
	end
	profile.shieldDesigns[shieldId] = option
	InventoryService.publish(player)
	changed(player)
	return true, "Schild bemalt."
end

-- Robux credits (bought, not yet used): "Skip" finishes a job, "Design" pays a design.
function InventoryService.credits(player: Player, key: string): number
	return getProfile(player).forgeCredits[key] or 0
end

function InventoryService.addCredit(player: Player, key: string, count: number?)
	local profile = getProfile(player)
	profile.forgeCredits[key] = (profile.forgeCredits[key] or 0) + (count or 1)
	changed(player)
end

function InventoryService.useCredit(player: Player, key: string): boolean
	local profile = getProfile(player)
	if (profile.forgeCredits[key] or 0) < 1 then
		return false
	end
	profile.forgeCredits[key] -= 1
	changed(player)
	return true
end

-- Processed Robux purchases: a receipt is granted at most once per profile.
function InventoryService.hasReceipt(player: Player, purchaseId: string): boolean
	return table.find(getProfile(player).receipts, purchaseId) ~= nil
end

function InventoryService.recordReceipt(player: Player, purchaseId: string)
	local receipts = getProfile(player).receipts
	table.insert(receipts, purchaseId)
	while #receipts > ForgeDefinitions.MaxReceipts do
		table.remove(receipts, 1)
	end
	changed(player)
end

-- Pays a fixed service price (e.g. the oracle) exactly once. Never makes the balance negative.
function InventoryService.spendDenarii(player: Player, amount: number): boolean
	if amount ~= amount or amount <= 0 or amount % 1 ~= 0 then
		return false
	end
	local profile = getProfile(player)
	if profile.denarii < amount then
		return false
	end
	profile.denarii -= amount
	InventoryService.publish(player)
	changed(player)
	return true
end

-- Plain table for the DataStore (only JSON-safe values).
-- Day number in UTC; the daily allowance resets when it changes.
local function currentDay(): number
	return math.floor(os.time() / 86400)
end

-- One execution of a special move. Returns the odds BEFORE this execution (Fail chance, Perfect
-- chance; the caller rolls the outcome), then counts one step of progress while the place's
-- daily allowance (`source`: "Training" or "Arena") lasts.
function InventoryService.practiceSpecial(player: Player, weaponId: string, moveId: string, source: string): (number, number)
	local key = SpecialPracticeDefinitions.key(weaponId, moveId)
	assert(practiceKeys[key], "Unknown special practice key")
	local allowance = SpecialPracticeDefinitions.DailyAllowance[source]
	assert(allowance ~= nil, "Unknown practice source")
	local profile = getProfile(player)
	local steps = SpecialPracticeDefinitions.clampSteps(profile.specialAttempts[key] or 0)
	local failure = SpecialPracticeDefinitions.failure(steps)
	local perfect = SpecialPracticeDefinitions.perfect(steps)
	local today = currentDay()
	local stored = profile.specialDaily[key]
	local daily: { day: number, Training: number, Arena: number }
	if stored and stored.day == today then
		daily = stored
	else
		daily = { day = today, Training = 0, Arena = 0 }
		profile.specialDaily[key] = daily
	end
	local step = SpecialPracticeDefinitions.PerfectStep
	local used = if source == "Training" then daily.Training else daily.Arena
	if steps < SpecialPracticeDefinitions.MaxSteps and used + step <= allowance + 1e-9 then
		if source == "Training" then
			daily.Training += step
		else
			daily.Arena += step
		end
		steps += 1
		profile.specialAttempts[key] = steps
		player:SetAttribute(SpecialPracticeDefinitions.attribute(key), steps)
		changed(player)
	end
	return failure, perfect
end

-- Mastery stage of a weapon: the highest stage reached by any of its moves.
function InventoryService.weaponStage(player: Player, weaponId: string): number
	local profile = getProfile(player)
	local prefix = weaponId .. ":"
	local steps = {}
	for key, value in profile.specialAttempts do
		if key:sub(1, #prefix) == prefix then
			table.insert(steps, value)
		end
	end
	return SpecialPracticeDefinitions.weaponStage(steps)
end

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
		specialAttempts = table.clone(profile.specialAttempts),
		specialDaily = (function()
			local copy = {}
			for key, entry in profile.specialDaily do
				copy[key] = table.clone(entry)
			end
			return copy
		end)(),
		resetToken = profile.resetToken,
		earnings = table.clone(profile.earnings),
		session = { aura = profile.session.aura, denarii = profile.session.denarii, startedAt = profile.session.startedAt, lastSeen = os.time() },
		lastBattle = if profile.lastBattle then table.clone(profile.lastBattle) else nil,
		activity = table.clone(profile.activity),
		weaponCopies = (function()
			local copy = {}
			for id, list in profile.weaponCopies do
				local out = {}
				for _, c in list do
					table.insert(out, { uid = c.uid, forge = c.forge, wear = c.wear, design = table.clone(c.design), job = if c.job then table.clone(c.job) else nil })
				end
				copy[id] = out
			end
			return copy
		end)(),
		activeCopy = table.clone(profile.activeCopy),
		nextCopy = profile.nextCopy,
		shieldDesigns = table.clone(profile.shieldDesigns),
		forgeCredits = table.clone(profile.forgeCredits),
		receipts = table.clone(profile.receipts),
	}
end

return InventoryService
