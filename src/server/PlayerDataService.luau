--!strict
-- Persistent player data (DataStore), identical in the Hub and the Arena place: Aura, Denarii, owned
-- and equipped weapons / shields / armor, statistics and preferences (PlayerDataSchema). The store
-- name comes from the environment (ExperienceConfig: OttiPlayerData_DEV_v1 / _PROD_v1) and never
-- changes for normal updates; Studio uses mock data unless StudioMockData = false. The DataStore
-- only ever sees InventoryService.serialize(); loaded data always goes through migrateProfile.
--
-- WHAT COUNTS AS SAVED. A save is confirmed only when UpdateAsync returned OUR record (its
-- `saveId`): a call that failed, or whose write was refused, is never reported as saved. Every
-- change raises the session's change counter; the profile is "dirty" until a confirmed save
-- covered that counter, so a change made while a write is on its way is written by the next one.
--
-- ONE SERVER PER PROFILE (`lock` in the record: { server, at }).
--   * Load claims the lock with UpdateAsync. A profile held by another server is not read: the
--     load waits (the other server releases the lock with its last save, e.g. on a teleport) and
--     takes the lock over after LOCK_WAIT_SECONDS, or at once when the lock is older than
--     LOCK_STALE_SECONDS (a crashed server).
--   * Every save checks the lock inside UpdateAsync: a server that lost it writes NOTHING more
--     (it can't overwrite the newer server's data) and the player is sent out of that server.
--   * The last save of a session (leave, shutdown, the flush before a teleport) releases the lock.
--
-- ONE WRITE AT A TIME per profile: a save that starts while another runs waits for it, then
-- writes whatever is still unsaved. Nothing is dropped and no caller is told "saved" early.
--
--   * Cross-place teleports: beginTransfer() freezes the profile ("Transferring": no purchases),
--     flushes it and releases the lock; the destination loads it again from the DataStore (never
--     from TeleportData).
--   * Load on join (retries). Until it finishes the player is "Loading": the shops refuse
--     purchases, so nothing bought can be overwritten by the late load.
--   * If loading fails (or Studio has no API access) the player plays with a fresh in-memory
--     profile marked "Unsaved": it is NEVER written back, so real saved progress can't be wiped,
--     and flush() answers false for it (a Robux receipt is not confirmed on such a profile).
--   * Save: when something changed (debounced), every AutosaveSeconds, on leave and on server
--     shutdown. BindToClose starts the last save of every profile and waits until every running
--     write (its own, the leave saves of PlayerRemoving, autosaves) has answered.
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
local PlayerDataResetConfig = require(script.Parent.PlayerDataResetConfig)
local Remotes = require(script.Parent.Remotes)

local PREFIX = "[OttiArena][Server]"
-- Store name per environment (ExperienceConfig): stable across updates, DEV never touches PROD.
local LEGACY_STORE_NAME = "OttiColosseum_PlayerData_v1" -- pre-multi-place saves: imported once if present
local AUTOSAVE_SECONDS = 120
local SAVE_DEBOUNCE = 8 -- seconds after a change before it is written
local LOAD_ATTEMPTS = 3
local SAVE_ATTEMPTS = 3
local PREFERENCE_RATE = 1 -- seconds between preference messages per player
local LOCK_WAIT_SECONDS = 20 -- how long a load waits for another server to release the profile
local LOCK_RETRY_SECONDS = 4
local LOCK_STALE_SECONDS = 30 * 60 -- a lock this old belongs to a server that is gone
local SHUTDOWN_SECONDS = 25 -- BindToClose gives 30 s
local SHUTDOWN_SECONDS_STUDIO = 5

type Status = "Loading" | "Loaded" | "Unsaved" | "Mock" | "Transferring"

type Session = {
	status: Status,
	changeId: number, -- raised by every change of the profile
	savedId: number, -- the changeId a CONFIRMED save covered
	saving: boolean, -- a write is on its way
	lockHeld: boolean, -- the record carries this server's lock
	debounce: boolean, -- a "change" save is scheduled
	closing: boolean, -- the last save of this session has started
	lost: boolean, -- another server holds the profile: nothing is written any more
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
local activeWrites = 0 -- DataStore writes on their way (all profiles)
local closingSessions = 0 -- last saves on their way
local shuttingDown = false

local function key(player: Player): string
	return "player_" .. player.UserId
end

local function setStatus(player: Player, session: Session, status: Status)
	session.status = status
	player:SetAttribute(Config.DataStatusAttribute, status)
end

local function isDirty(session: Session): boolean
	return session.changeId ~= session.savedId
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

-- The record is held by ANOTHER server.
local function lockedByOther(record: any): boolean
	return typeof(record) == "table" and typeof(record.lock) == "table" and record.lock.server ~= serverId
end

-- Another server took the profile over: this server never writes it again.
local function loseProfile(player: Player, session: Session, reason: string)
	if session.lost then
		return
	end
	session.lost = true
	session.lockHeld = false
	warn(PREFIX, ("The profile of %s is held by another server (%s): this server stops saving it"):format(player.Name, reason))
	setStatus(player, session, "Unsaved")
	if player.Parent and not session.closing and not shuttingDown then
		player:Kick("Dein Profil wurde auf einem anderen Server geöffnet. Bitte tritt neu bei.")
	end
end

-- Writes the profile and answers true ONLY when the DataStore confirmed this very record.
--   release   the last save of this server for now: the lock is given back
--   transfer  called by beginTransfer (the profile is already frozen as "Transferring")
-- A save that finds another one running waits for it. If nothing changed since the last confirmed
-- save (and the lock is already as wanted) nothing is written and the answer is true.
local function save(player: Player, reason: string, release: boolean?, transfer: boolean?): boolean
	local session = sessions[player]
	local dataStore = store
	if not session or not dataStore then
		return false
	end
	local function writable(): boolean
		return sessions[player] == session and not session.lost and (session.status == "Loaded" or (transfer == true and session.status == "Transferring"))
	end
	while session.saving do
		task.wait(0.1) -- one write at a time per profile
	end
	if not writable() then
		return false
	end
	local wantLock = release ~= true
	if not isDirty(session) and session.lockHeld == wantLock then
		return true -- everything is confirmed already
	end
	session.saving = true
	activeWrites += 1
	local covered = session.changeId
	local saveId = HttpService:GenerateGUID(false)
	local data = InventoryService.serialize(player)
	data.session = serverId
	data.savedAt = os.time()
	data.saveId = saveId
	data.lock = if wantLock then { server = serverId, at = os.time() } else nil
	local outcome = "PENDING"
	local ok, result = retry(SAVE_ATTEMPTS, function()
		return dataStore:UpdateAsync(key(player), function(old: any)
			if lockedByOther(old) then
				outcome = "LOCKED" -- another server owns the profile now: keep its data
				return nil
			end
			outcome = "WRITE"
			return data
		end)
	end)
	local committed = ok and outcome == "WRITE" and typeof(result) == "table" and (result :: any).saveId == saveId
	session.saving = false
	activeWrites -= 1
	if committed then
		session.savedId = covered
		session.lockHeld = wantLock
	elseif ok and outcome == "LOCKED" then
		loseProfile(player, session, reason)
	else
		-- still dirty (savedId unchanged): the next autosave / flush / leave tries again
		warn(PREFIX, ("Saving data for %s failed (%s): %s"):format(player.Name, reason, if ok then "the write was not confirmed" else tostring(result)))
	end
	return committed
end

-- Claims the profile for this server and returns its record. Returns (ok, record or error).
local function claim(player: Player, session: Session, dataStore: DataStore): (boolean, any)
	local deadline = os.clock() + LOCK_WAIT_SECONDS
	local takeOver = false
	while true do
		local outcome = "PENDING"
		local ok, result = retry(LOAD_ATTEMPTS, function()
			return dataStore:UpdateAsync(key(player), function(old: any)
				if lockedByOther(old) and not takeOver and os.time() - (tonumber(old.lock.at) or 0) < LOCK_STALE_SECONDS then
					outcome = "LOCKED"
					return nil
				end
				outcome = "CLAIMED"
				local record: any = if typeof(old) == "table" then old else { empty = true } -- no profile yet: only the lock
				record.lock = { server = serverId, at = os.time() }
				return record
			end)
		end)
		if not ok then
			return false, result
		end
		if outcome == "CLAIMED" and typeof(result) == "table" then
			return true, result
		end
		if sessions[player] ~= session then
			return false, "left while loading"
		end
		if os.clock() >= deadline then
			takeOver = true
			warn(PREFIX, ("The profile of %s is still held by another server after %d s: taking it over"):format(player.Name, LOCK_WAIT_SECONDS))
		else
			task.wait(LOCK_RETRY_SECONDS)
		end
	end
end

-- Gives a claimed lock back without touching the data (the player left while loading).
local function releaseLock(userKey: string, dataStore: DataStore)
	activeWrites += 1
	retry(SAVE_ATTEMPTS, function()
		return dataStore:UpdateAsync(userKey, function(old: any)
			if typeof(old) ~= "table" or typeof(old.lock) ~= "table" or old.lock.server ~= serverId then
				return nil
			end
			old.lock = nil
			return old
		end)
	end)
	activeWrites -= 1
end

local function applyPreferences(player: Player)
	if InventoryService.getPreference(player, "BossIntro") == "Seen" then
		player:SetAttribute(Config.IntroSeenAttribute, true)
	end
end

local function onPlayerAdded(player: Player)
	local session: Session = {
		status = "Loading",
		changeId = 0,
		savedId = 0,
		saving = false,
		lockHeld = false,
		debounce = false,
		closing = false,
		lost = false,
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
		if EnvironmentConfig.useMockData() and ExperienceConfig.Studio.UnlockAllGear then
			InventoryService.unlockAll(player)
			print(PREFIX, "Studio test switch UnlockAllGear: every weapon, shield and armor, ELITE level for", player.Name)
		end
		local refresh = loadedCallback
		if refresh then
			refresh(player)
		end
		return
	end
	local ok, result = claim(player, session, dataStore)
	if sessions[player] ~= session then
		if ok then
			releaseLock(key(player), dataStore) -- left while loading: nobody holds the profile
		end
		return
	end
	if not ok then
		warn(PREFIX, ("Loading data for %s failed: %s - progress this session will NOT be saved"):format(player.Name, tostring(result)))
		setStatus(player, session, "Unsaved")
		return
	end
	session.lockHeld = true
	local saved: { [string]: any }? = if typeof(result) == "table" and result.empty ~= true then result else nil
	local legacy = legacyStore
	if saved == nil and legacy then
		-- No profile in the environment store yet: import a pre-multi-place save once (same schema
		-- family, migrated below); the next save writes it to the environment store.
		local legacyOk, legacyResult = retry(1, function()
			return legacy:GetAsync(key(player))
		end)
		if sessions[player] ~= session then
			releaseLock(key(player), dataStore)
			return
		end
		if legacyOk and typeof(legacyResult) == "table" then
			saved = legacyResult
			print(PREFIX, ("Imported the legacy save of %s"):format(player.Name))
		end
	end
	local isNew = saved == nil
	local earned = math.max(0, InventoryService.getAura(player) - session.auraAtJoin)
	local earnedDenarii = math.max(0, InventoryService.getDenarii(player) - session.denariiAtJoin)
	-- Controlled one-time test-data reset (PlayerDataResetConfig, OFF by default, DEV only)
	local resetToken = PlayerDataResetConfig.tokenFor(player.UserId, EnvironmentConfig.name(), if saved then saved.resetToken else nil)
	if resetToken and saved then
		warn(PREFIX, ("TEST DATA RESET for %s (%d) with token %q"):format(player.Name, player.UserId, resetToken))
		saved = nil
	end
	InventoryService.load(player, saved, earned, earnedDenarii, resetToken)
	session.savedId = session.changeId -- what was loaded is what is stored ...
	if saved == nil or isNew or earned > 0 or earnedDenarii > 0 then
		session.changeId += 1 -- ... except a new / reset / imported profile and rewards earned meanwhile
	end
	applyPreferences(player)
	setStatus(player, session, "Loaded")
	print(PREFIX, ("Data loaded for %s (%s, %d Aura, %d Denarii)"):format(player.Name, if saved then "saved profile" else "new profile", InventoryService.getAura(player), InventoryService.getDenarii(player)))
	-- Equipment in the hands / on the body follows the loaded loadout
	local refresh = loadedCallback
	if refresh then
		refresh(player)
	end
end

-- The last save of a session (leave or shutdown): writes what is unsaved and releases the lock.
-- Runs once per session; a second caller waits until it has answered.
local function closeSession(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	if session.closing then
		while session.closing and sessions[player] == session do
			task.wait(0.1)
		end
		return
	end
	session.closing = true
	closingSessions += 1
	if session.status == "Transferring" and isDirty(session) and not session.lost then
		session.status = "Loaded" -- something changed after the transfer flush: write it too (refused if the destination holds the profile already)
	end
	if session.status == "Loaded" then
		save(player, if shuttingDown then "shutdown" else "leave", true)
	end
	closingSessions -= 1
	session.closing = false
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	closeSession(player)
	if sessions[player] == session then
		sessions[player] = nil
		InventoryService.forget(player)
	end
end

-- Before a cross-place teleport: freeze the profile as "Transferring" (no purchases, no further
-- regular saves), write it and release the lock, so the destination loads exactly this state and
-- a late save from this server can never overwrite newer data written by the destination.
-- Returns false if the profile could not be flushed (the caller must not teleport).
function PlayerDataService.beginTransfer(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	if session.status == "Mock" or session.status == "Unsaved" then
		return true -- nothing persistent to protect
	end
	if session.status == "Transferring" then
		while session.saving do
			task.wait(0.1) -- the flush of an earlier call is still on its way
		end
		return sessions[player] == session and session.status == "Transferring"
	end
	if session.status ~= "Loaded" then
		return false
	end
	setStatus(player, session, "Transferring")
	local flushed = save(player, "transfer", true, true)
	if sessions[player] ~= session or session.lost then
		return false
	end
	if not flushed then
		if session.status == "Transferring" then
			setStatus(player, session, "Loaded")
		end
		return false
	end
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

-- The teleport failed: the profile is normal again; the next save takes the lock back.
function PlayerDataService.cancelTransfer(player: Player)
	local session = sessions[player]
	if session and session.status == "Transferring" and not session.lost then
		setStatus(player, session, "Loaded")
		task.spawn(save, player, "after transfer")
	end
end

-- Writes the profile now (e.g. match rewards before the return teleport, a Robux receipt). Yields.
-- True only when everything is confirmed in the DataStore (or the data is Studio mock data).
function PlayerDataService.flush(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	if session.status == "Mock" then
		return true
	end
	if session.status == "Transferring" then
		while session.saving do
			task.wait(0.1)
		end
		return sessions[player] == session and not session.lost and not isDirty(session)
	end
	if session.status ~= "Loaded" then
		return false -- "Loading" / "Unsaved": nothing of this session reaches the DataStore
	end
	return save(player, "flush")
end

-- True once purchases may be made (the saved profile is in memory, or saving is unavailable).
function PlayerDataService.isReady(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.status ~= "Loading" and session.status ~= "Transferring"
end

-- True when this session's progress can reach the DataStore (or is Studio mock data).
function PlayerDataService.canPersist(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and not session.lost and (session.status == "Loaded" or session.status == "Mock")
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
		if not session then
			return
		end
		session.changeId += 1 -- "Transferring": written on leave (closeSession)
		if session.status ~= "Loaded" or session.debounce then
			return
		end
		session.debounce = true
		task.delay(SAVE_DEBOUNCE, function()
			session.debounce = false
			if sessions[player] == session and isDirty(session) and not session.closing then
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
				if isDirty(session) and session.status == "Loaded" and not session.closing then
					task.spawn(save, player, "autosave")
				end
			end
		end
	end)

	-- Server shutdown: the last save of every profile starts now; then wait until EVERY write has
	-- answered (these, the leave saves PlayerRemoving started, a running autosave), or the time
	-- Roblox allows is nearly over.
	game:BindToClose(function()
		shuttingDown = true
		if not store then
			return
		end
		for player in sessions do
			task.spawn(closeSession, player)
		end
		local deadline = os.clock() + (if RunService:IsStudio() then SHUTDOWN_SECONDS_STUDIO else SHUTDOWN_SECONDS)
		while (closingSessions > 0 or activeWrites > 0) and os.clock() < deadline do
			task.wait(0.1)
		end
		if closingSessions > 0 or activeWrites > 0 then
			warn(PREFIX, ("Shutdown: %d profile save(s) did not answer in time"):format(math.max(closingSessions, activeWrites)))
		end
	end)
end

return PlayerDataService
