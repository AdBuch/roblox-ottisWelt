--!strict
-- Persistent player data (DataStore), identical in the Hub and the Arena place: Aura, Denarii, owned
-- and equipped weapons / shields / armor, statistics and preferences (PlayerDataSchema). The store
-- name comes from the environment (ExperienceConfig: OttiPlayerData_DEV_v1 / _PROD_v1) and never
-- changes for normal updates; Studio uses mock data unless StudioMockData = false. The DataStore
-- only ever sees InventoryService.serialize(); loaded data always goes through migrateProfile.
--   * Cross-place teleports: beginTransfer() flushes and freezes the profile; the destination
--     loads it again from the DataStore (never from TeleportData).
--   * Load on join (retries). Until it finishes the player is "Loading": the armory refuses
--     purchases, so nothing bought can be overwritten by the late load.
--   * If loading fails (or Studio has no API access) the player plays with a fresh in-memory
--     profile marked "Unsaved": it is NEVER written back, so real saved progress can't be wiped.
--   * Save: UpdateAsync when something changed (debounced), every AutosaveSeconds, on leave and
--     on server shutdown (BindToClose). A session tag in the record makes a newer server's save win.
--   * Preferences: the client may only send whitelisted key/value pairs (SavePreference remote,
--     rate limited); everything else is server-decided.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local InventoryService = require(script.Parent.InventoryService)
local Remotes = require(script.Parent.Remotes)

local PREFIX = "[OttiArena][Server]"
-- Store name per environment (ExperienceConfig): stable across updates, DEV never touches PROD.
local LEGACY_STORE_NAME = "OttiColosseum_PlayerData_v1" -- pre-multi-place saves: imported once if present
local AUTOSAVE_SECONDS = 120
local SAVE_DEBOUNCE = 8 -- seconds after a change before it is written
local LOAD_ATTEMPTS = 3
local SAVE_ATTEMPTS = 3
local PREFERENCE_RATE = 1 -- seconds between preference messages per player

type Status = "Loading" | "Loaded" | "Unsaved" | "Mock" | "Transferring"

type Session = {
	status: Status,
	dirty: boolean,
	saving: boolean,
	saveQueued: boolean,
	lastPreference: number,
	auraAtJoin: number,
	denariiAtJoin: number,
	transferToken: number,
}

local PlayerDataService = {}

local sessions: { [Player]: Session } = {}
local serverId = HttpService:GenerateGUID(false)
local store: DataStore? = nil
local legacyStore: DataStore? = nil
local loadedCallback: ((player: Player) -> ())? = nil

local function key(player: Player): string
	return "player_" .. player.UserId
end

local function setStatus(player: Player, session: Session, status: Status)
	session.status = status
	player:SetAttribute(Config.DataStatusAttribute, status)
end

local function retry<T>(attempts: number, call: () -> T): (boolean, T | string)
	local lastError = ""
	for attempt = 1, attempts do
		local ok, result = pcall(call)
		if ok then
			return true, result
		end
		lastError = tostring(result)
		if attempt < attempts then
			task.wait(attempt * 1.5)
		end
	end
	return false, lastError
end

local function save(player: Player, reason: string): boolean
	local session = sessions[player]
	local dataStore = store
	if not session or session.status ~= "Loaded" or not dataStore then
		return false
	end
	if session.saving then
		session.saveQueued = true
		return false
	end
	session.saving = true
	session.dirty = false
	local data = InventoryService.serialize(player)
	data.session = serverId
	data.savedAt = os.time()
	local ok, result = retry(SAVE_ATTEMPTS, function()
		return dataStore:UpdateAsync(key(player), function(old: any)
			if typeof(old) == "table" and old.session ~= serverId and typeof(old.savedAt) == "number" and old.savedAt > data.savedAt then
				return nil -- a newer save from another server: keep it
			end
			return data
		end)
	end)
	session.saving = false
	if not ok then
		session.dirty = true -- try again on the next autosave
		warn(PREFIX, ("Saving data for %s failed (%s): %s"):format(player.Name, reason, tostring(result)))
	end
	if session.saveQueued then
		session.saveQueued = false
		if player.Parent then
			task.spawn(save, player, "queued")
		end
	end
	return ok
end

local function applyPreferences(player: Player)
	if InventoryService.getPreference(player, "BossIntro") == "Seen" then
		player:SetAttribute(Config.IntroSeenAttribute, true)
	end
end

local function onPlayerAdded(player: Player)
	local session: Session = {
		status = "Loading",
		dirty = false,
		saving = false,
		saveQueued = false,
		lastPreference = 0,
		auraAtJoin = InventoryService.getAura(player),
		denariiAtJoin = InventoryService.getDenarii(player),
		transferToken = 0,
	}
	sessions[player] = session
	setStatus(player, session, "Loading")

	local dataStore = store
	if not dataStore then
		setStatus(player, session, if EnvironmentConfig.useMockData() then "Mock" else "Unsaved")
		local refresh = loadedCallback
		if refresh then
			refresh(player)
		end
		return
	end
	local ok, result = retry(LOAD_ATTEMPTS, function()
		return dataStore:GetAsync(key(player))
	end)
	local legacy = legacyStore
	if ok and result == nil and legacy then
		-- No profile in the environment store yet: import a pre-multi-place save once (same schema
		-- family, migrated below); the next save writes it to the environment store.
		local legacyOk, legacyResult = retry(1, function()
			return legacy:GetAsync(key(player))
		end)
		if legacyOk and typeof(legacyResult) == "table" then
			result = legacyResult
			print(PREFIX, ("Imported the legacy save of %s"):format(player.Name))
		end
	end
	if sessions[player] ~= session then
		return -- left while loading
	end
	if not ok then
		warn(PREFIX, ("Loading data for %s failed: %s - progress this session will NOT be saved"):format(player.Name, tostring(result)))
		setStatus(player, session, "Unsaved")
		return
	end
	local saved = if typeof(result) == "table" then result :: { [string]: any } else nil
	local earned = math.max(0, InventoryService.getAura(player) - session.auraAtJoin)
	local earnedDenarii = math.max(0, InventoryService.getDenarii(player) - session.denariiAtJoin)
	InventoryService.load(player, saved, earned, earnedDenarii)
	applyPreferences(player)
	setStatus(player, session, "Loaded")
	print(PREFIX, ("Data loaded for %s (%s, %d Aura, %d Denarii)"):format(player.Name, if saved then "saved profile" else "new profile", InventoryService.getAura(player), InventoryService.getDenarii(player)))
	-- Equipment in the hands / on the body follows the loaded loadout
	local refresh = loadedCallback
	if refresh then
		refresh(player)
	end
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if session and session.status == "Transferring" and session.dirty then
		session.status = "Loaded" -- something changed after the transfer flush: write it too
	end
	if session and session.status == "Loaded" then
		save(player, "leave")
	end
	sessions[player] = nil
	InventoryService.forget(player)
end

-- Before a cross-place teleport: write the profile now and freeze it as "Transferring" (no
-- purchases, no further regular saves), so the destination loads exactly this state and a late
-- save from this server can never overwrite newer data written by the destination.
-- Returns false if the profile could not be flushed (the caller should not teleport).
function PlayerDataService.beginTransfer(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	if session.status == "Mock" or session.status == "Unsaved" then
		return true -- nothing persistent to protect
	end
	if session.status == "Transferring" then
		return true
	end
	if session.status ~= "Loaded" then
		return false
	end
	if not save(player, "transfer") and session.dirty then
		return false
	end
	session.status = "Transferring"
	player:SetAttribute(Config.DataStatusAttribute, "Transferring")
	session.transferToken += 1
	local token = session.transferToken
	task.delay(ExperienceConfig.Teleport.TransitionHoldSeconds, function()
		-- Still here long after the teleport should have happened: back to normal
		if sessions[player] == session and session.status == "Transferring" and session.transferToken == token then
			PlayerDataService.cancelTransfer(player)
		end
	end)
	return true
end

-- The teleport failed: the profile is normal again (and saved if something changed meanwhile).
function PlayerDataService.cancelTransfer(player: Player)
	local session = sessions[player]
	if session and session.status == "Transferring" then
		setStatus(player, session, "Loaded")
		if session.dirty then
			task.spawn(save, player, "after transfer")
		end
	end
end

-- Writes the profile now (e.g. match rewards before the return teleport). Yields.
function PlayerDataService.flush(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	if session.status ~= "Loaded" then
		return session.status == "Mock" or session.status == "Unsaved"
	end
	return save(player, "flush")
end

-- True once purchases may be made (the saved profile is in memory, or saving is unavailable).
function PlayerDataService.isReady(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.status ~= "Loading" and session.status ~= "Transferring"
end

function PlayerDataService.getStatus(player: Player): string
	local session = sessions[player]
	return if session then session.status else "Loading"
end

function PlayerDataService.init(onLoaded: (player: Player) -> ())
	loadedCallback = onLoaded
	local storeName = EnvironmentConfig.get().DataStoreName
	if EnvironmentConfig.useMockData() then
		print(PREFIX, "Studio mock player data: nothing is read from or written to", storeName)
	else
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(storeName)
		end)
		if ok then
			store = result
			do -- read-only import source, never written
				local legacyOk, legacyResult = pcall(function()
					return DataStoreService:GetDataStore(LEGACY_STORE_NAME)
				end)
				legacyStore = if legacyOk then legacyResult else nil
			end
		else
			warn(PREFIX, "DataStore unavailable (enable Studio API access to test saving):", tostring(result))
		end
	end
	print(PREFIX, "Player data:", EnvironmentConfig.describe())

	InventoryService.onChanged(function(player: Player)
		local session = sessions[player]
		if session and session.status == "Transferring" then
			session.dirty = true -- written on leave (see onPlayerRemoving)
			return
		end
		if not session or session.status ~= "Loaded" or session.dirty then
			return
		end
		session.dirty = true
		task.delay(SAVE_DEBOUNCE, function()
			if sessions[player] == session and session.dirty then
				save(player, "change")
			end
		end)
	end)

	Remotes.SavePreference.OnServerEvent:Connect(function(player: Player, prefKey: unknown, value: unknown)
		local session = sessions[player]
		if not session then
			return
		end
		local now = os.clock()
		if now - session.lastPreference < PREFERENCE_RATE then
			return
		end
		session.lastPreference = now
		InventoryService.setPreference(player, prefKey, value) -- whitelist checked there
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
		player:GetAttributeChangedSignal(Config.IntroSeenAttribute):Connect(function()
			if player:GetAttribute(Config.IntroSeenAttribute) == true then
				InventoryService.setPreference(player, "BossIntro", "Seen")
			end
		end)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player, session in sessions do
				if session.dirty and session.status == "Loaded" then
					task.spawn(save, player, "autosave")
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, session in sessions do
			if session.status == "Loaded" then
				pending += 1
				task.spawn(function()
					save(player, "shutdown")
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + (if RunService:IsStudio() then 5 else 25)
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

return PlayerDataService
