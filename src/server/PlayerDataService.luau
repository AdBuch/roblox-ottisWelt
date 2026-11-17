--!strict
-- Shared Hub/Arena persistence. See docs/PLAYER_DATA_API.md for the record and caller contracts.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local PlayerDataSchema = require(ReplicatedStorage.Shared.PlayerDataSchema)
local InventoryService = require(script.Parent.InventoryService)
local PlayerDataResetConfig = require(script.Parent.PlayerDataResetConfig)
local Remotes = require(script.Parent.Remotes)

local PREFIX = "[OttiArena][Server]"
local LEGACY_STORE_NAME = "OttiColosseum_PlayerData_v1"
local AUTOSAVE_SECONDS = 120
local SAVE_DEBOUNCE = 8
local RETRY_ATTEMPTS = 3
local PREFERENCE_RATE = 1
local CLAIM_WAIT_SECONDS = 20
local CLAIM_RETRY_SECONDS = 4
local LEASE_SECONDS = 5 * 60
local LEGACY_LEASE_SECONDS = 30 * 60
local CALL_WAIT_SECONDS = 15
local CLOSE_RETRY_SECONDS = 5
local SHUTDOWN_SECONDS = 25
local SHUTDOWN_SECONDS_STUDIO = 5

type Status = "Loading" | "Loaded" | "Unsaved" | "Mock" | "Transferring" | "Incompatible"

type Session = {
	status: Status,
	token: string,
	epoch: number?,
	expiresAt: number,
	revision: number,
	committedRevision: number,
	releaseId: string?,
	released: boolean,
	busy: boolean,
	loading: boolean,
	initialized: boolean,
	debounce: boolean,
	closing: boolean,
	closeRunning: boolean,
	lost: boolean,
	lastPreference: number,
	transferAttempt: number,
	recoveryAttempt: number?,
	resuming: boolean,
}

local PlayerDataService = {}
local sessions: { [Player]: Session } = {}
local store: DataStore? = nil
local legacyStore: DataStore? = nil
local loadedCallback: ((player: Player) -> ())? = nil
local shutdownDeadline: number? = nil

local function key(player: Player): string
	return "player_" .. player.UserId
end

local function setStatus(player: Player, session: Session, status: Status)
	session.status = status
	player:SetAttribute(Config.DataStatusAttribute, status)
end

local function incompatible(player: Player, session: Session)
	session.lost = true
	setStatus(player, session, "Incompatible")
	player:SetAttribute(Config.DataStatusMessageAttribute, "Deine gespeicherten Daten benötigen eine andere Spielversion. Bitte tritt einem aktuellen Server bei.")
end

local function retry<T>(call: () -> T): (boolean, T | string)
	local lastError = ""
	for attempt = 1, RETRY_ATTEMPTS do
		local ok, result = pcall(call)
		if ok then
			return true, result
		end
		lastError = tostring(result)
		if attempt < RETRY_ATTEMPTS then
			task.wait(attempt * 1.5)
		end
	end
	return false, lastError
end

local function owns(record: any, token: string, epoch: number?): boolean
	return typeof(record) == "table"
		and epoch ~= nil and record.leaseEpoch == epoch
		and typeof(record.lock) == "table" and record.lock.server == token
end

local function lockExpires(record: any): number
	local lock = if typeof(record) == "table" then record.lock else nil
	if typeof(lock) ~= "table" then
		return 0
	end
	return tonumber(lock.expiresAt) or ((tonumber(lock.at) or 0) + LEGACY_LEASE_SECONDS)
end

local function acquire(record: any, token: string): any
	local nextRecord = if typeof(record) == "table" then table.clone(record) else { empty = true }
	local now = os.time()
	nextRecord.leaseEpoch = (tonumber(nextRecord.leaseEpoch) or 0) + 1
	nextRecord.lock = { server = token, at = now, expiresAt = now + LEASE_SECONDS }
	return nextRecord
end

local function releasedBy(record: any, epoch: number?, saveId: string?): boolean
	return typeof(record) == "table" and epoch ~= nil and record.leaseEpoch == epoch
		and record.lock == nil and saveId ~= nil and record.saveId == saveId
end

local function loseProfile(player: Player, session: Session, reason: string)
	session.lost = true
	warn(PREFIX, ("Profile lease lost for %s (%s)"):format(player.Name, reason))
	setStatus(player, session, "Unsaved")
	if player.Parent and not session.closing and not shutdownDeadline then
		player:Kick("Dein Profil wurde auf einem anderen Server geöffnet. Bitte tritt neu bei.")
	end
end

-- The worker owns the write even if its caller stops waiting. No second UpdateAsync can run
-- for this session until the first has answered.
local function waitForCommit(work: (number) -> boolean): boolean
	local deadline = os.clock() + CALL_WAIT_SECONDS
	local result: boolean? = nil
	task.spawn(function()
		result = work(deadline) and os.clock() <= deadline
	end)
	while result == nil and os.clock() < deadline do
		task.wait(0.1)
	end
	return result == true
end

local function save(player: Player, session: Session, reason: string, release: boolean, deadline: number?): boolean
	while session.busy do
		if deadline and os.clock() >= deadline then
			return false
		end
		task.wait(0.1)
	end
	if (deadline and os.clock() >= deadline) or sessions[player] ~= session or session.lost then
		return false
	end
	local dataStore = store
	if not dataStore or not session.epoch then
		return false
	end
	if release then
		if session.released then
			return session.committedRevision == session.revision
		end
		if not session.closing and (session.status ~= "Transferring" or session.resuming) then
			return false
		end
	else
		if session.status ~= "Loaded" or session.closing or session.released then
			return false
		end
		if session.committedRevision == session.revision and reason ~= "autosave" and os.time() < session.expiresAt then
			return true
		end
	end

	session.busy = true
	local covered = session.revision
	local saveId = if release and session.releaseId then session.releaseId else HttpService:GenerateGUID(false)
	if release then
		session.releaseId = saveId -- reused after ambiguous outcomes, including a timed-out release
	end
	local snapshot: { [string]: any }? = nil
	if session.initialized then
		local serialized, data = pcall(InventoryService.serialize, player)
		if not serialized then
			session.busy = false
			warn(PREFIX, ("Profile snapshot failed for %s: %s"):format(player.Name, tostring(data)))
			return false
		end
		snapshot = data
		if not PlayerDataSchema.canWrite(snapshot.version) then
			session.busy = false
			incompatible(player, session)
			return false
		end
	end
	local epoch = session.epoch
	local denied = false
	local unsupported = false
	local function confirmed(record: any): boolean
		if release then
			return releasedBy(record, epoch, saveId)
		end
		return owns(record, session.token, epoch) and record.saveId == saveId
	end
	local ok, result = retry(function()
		return dataStore:UpdateAsync(key(player), function(old: any)
			denied = false
			unsupported = typeof(old) == "table" and (not PlayerDataSchema.canRead(old.version)
				or (snapshot ~= nil and not InventoryService.canWriteRecord(old)))
			if unsupported then return nil end
			if confirmed(old) then
				return old -- the prior attempt committed but its response was lost
			end
			if not owns(old, session.token, epoch) then
				denied = true
				return nil
			end
			-- When a player leaves during Load, release just the lease and preserve the old profile.
			local nextRecord = table.clone(old)
			if snapshot then
				for field, value in snapshot do nextRecord[field] = value end
				nextRecord.lastBattle = snapshot.lastBattle
				nextRecord.resetToken = snapshot.resetToken
				nextRecord.coins, nextRecord.forge, nextRecord.empty = nil, nil, nil
			end
			local now = os.time()
			nextRecord.leaseEpoch = epoch
			nextRecord.saveId = saveId
			nextRecord.savedAt = now
			nextRecord.lock = if release then nil else { server = session.token, at = now, expiresAt = now + LEASE_SECONDS }
			return nextRecord
		end)
	end)

	local committed = ok and confirmed(result)
	if committed then
		session.committedRevision = covered
		session.released = release
		session.expiresAt = lockExpires(result)
	elseif ok and unsupported then
		incompatible(player, session)
	elseif ok and denied then
		loseProfile(player, session, reason)
	else
		warn(PREFIX, ("Save unconfirmed for %s (%s): %s"):format(player.Name, reason, if ok then "unexpected UpdateAsync result" else tostring(result)))
	end
	session.busy = false
	return committed
end

local function claim(player: Player, session: Session, dataStore: DataStore): (boolean, any)
	local deadline = os.clock() + CLAIM_WAIT_SECONDS
	while not session.closing and os.clock() < deadline do
		local unsupported = false
		local ok, result = retry(function()
			return dataStore:UpdateAsync(key(player), function(old: any)
				if typeof(old) == "table" and not PlayerDataSchema.canRead(old.version) then
					unsupported = true
					return nil
				end
				if typeof(old) == "table" and owns(old, session.token, old.leaseEpoch) then
					return old -- retry of this same claim
				end
				if session.closing or os.clock() >= deadline or lockExpires(old) > os.time() then
					return nil
				end
				return acquire(old, session.token)
			end)
		end)
		if ok and typeof(result) == "table" and owns(result, session.token, result.leaseEpoch) then
			return true, result
		end
		if not ok or unsupported then
			return false, if unsupported then "unsupported profile schema" else result
		end
		task.wait(math.min(CLAIM_RETRY_SECONDS, math.max(0, deadline - os.clock())))
	end
	return false, "profile claim not confirmed before the wait expired"
end

-- Load before enabling persistent mutations. While it yields, only pre-load balance rewards
-- can be staged by InventoryService, for compatibility with Arena joins.
function PlayerDataService.load(player: Player)
	if sessions[player] or not player.Parent or shutdownDeadline then
		return
	end
	local session: Session = {
		status = "Loading",
		token = HttpService:GenerateGUID(false),
		epoch = nil,
		expiresAt = 0,
		revision = 0,
		committedRevision = 0,
		releaseId = nil,
		released = false,
		busy = false,
		loading = true,
		initialized = false,
		debounce = false,
		closing = false,
		closeRunning = false,
		lost = false,
		lastPreference = 0,
		transferAttempt = 0,
		resuming = false,
	}
	sessions[player] = session
	setStatus(player, session, "Loading")

	local dataStore = store
	if not dataStore then
		setStatus(player, session, if EnvironmentConfig.useMockData() then "Mock" else "Unsaved")
		session.loading = false
		if session.status == "Mock" and ExperienceConfig.Studio.UnlockAllGear then
			InventoryService.unlockAll(player)
		end
		if loadedCallback then
			loadedCallback(player)
		end
		return
	end

	local auraAtJoin = InventoryService.getAura(player)
	local denariiAtJoin = InventoryService.getDenarii(player)
	local ok, record = claim(player, session, dataStore)
	if not ok then
		session.loading = false
		if not session.closing then
			warn(PREFIX, ("Load unconfirmed for %s: %s"):format(player.Name, tostring(record)))
			if record == "unsupported profile schema" then incompatible(player, session)
			else setStatus(player, session, "Unsaved") end
		end
		return
	end

	session.epoch = record.leaseEpoch
	session.expiresAt = lockExpires(record)
	local saved = if record.empty == true then nil else record
	local legacy = legacyStore
	if saved == nil and legacy and not session.closing then
		local legacyOk, legacyRecord = retry(function()
			return legacy:GetAsync(key(player))
		end)
		if not legacyOk or (typeof(legacyRecord) == "table" and not PlayerDataSchema.canRead(legacyRecord.version)) then
			warn(PREFIX, ("Legacy profile could not be loaded for %s"):format(player.Name))
			session.loading = false
			if legacyOk then incompatible(player, session) else setStatus(player, session, "Unsaved") end
			return
		end
		if typeof(legacyRecord) == "table" then
			saved = legacyRecord
		end
	end
	if session.closing then
		session.loading = false
		return
	end

	local earnedAura = math.max(0, InventoryService.getAura(player) - auraAtJoin)
	local earnedDenarii = math.max(0, InventoryService.getDenarii(player) - denariiAtJoin)
	local resetToken = PlayerDataResetConfig.tokenFor(player.UserId, EnvironmentConfig.name(), if saved then saved.resetToken else nil)
	if resetToken and saved and ((typeof(saved.receipts) == "table" and next(saved.receipts) ~= nil)
		or (typeof(saved.rewardIds) == "table" and next(saved.rewardIds) ~= nil)) then
		warn(PREFIX, ("Skipped test reset for %s: the profile has durable grant history"):format(player.Name))
		resetToken = nil
	end
	if resetToken and saved then
		warn(PREFIX, ("TEST DATA RESET for %s (%d) with token %q"):format(player.Name, player.UserId, resetToken))
		saved = nil
	end
	local loaded, loadError = pcall(InventoryService.load, player, saved, earnedAura, earnedDenarii, resetToken)
	if not loaded then
		warn(PREFIX, ("Profile could not be loaded for %s: %s"):format(player.Name, tostring(loadError)))
		session.loading = false
		incompatible(player, session)
		return
	end
	session.initialized = true
	session.revision += 1 -- migration, legacy import, new profile and play-session timestamps
	session.loading = false
	setStatus(player, session, "Loaded")
	if InventoryService.getPreference(player, "BossIntro") == "Seen" then
		player:SetAttribute(Config.IntroSeenAttribute, true)
	end
	if loadedCallback then
		loadedCallback(player)
	end
end

-- Freeze a leaving profile, wait for Load and earlier writes, then commit and release it.
-- If the write is unconfirmed, keep the session registered for retry and for BindToClose.
function PlayerDataService.releaseSession(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	while session.closeRunning do
		task.wait(0.1)
	end
	if sessions[player] ~= session then
		return session.released
	end
	session.closing = true
	session.closeRunning = true
	while session.loading do
		task.wait(0.1)
	end
	local committed = save(player, session, "close", true)
	if committed or session.epoch == nil or session.lost then
		sessions[player] = nil
		InventoryService.forget(player)
	else
		local deadline = shutdownDeadline
		if not deadline or os.clock() + CLOSE_RETRY_SECONDS < deadline then
			task.delay(CLOSE_RETRY_SECONDS, function()
				if sessions[player] == session and not session.closeRunning then
					PlayerDataService.releaseSession(player)
				end
			end)
		end
	end
	session.closeRunning = false
	return committed
end

function PlayerDataService.isTransferPrepared(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and not shutdownDeadline and not session.closing and not session.resuming
		and session.status == "Transferring" and session.released and session.committedRevision == session.revision
end

function PlayerDataService.beginTransfer(player: Player): boolean
	local session = sessions[player]
	if not session or shutdownDeadline or session.closing or session.resuming
		or (session.status ~= "Loaded" and session.status ~= "Transferring") then
		return false
	end
	if session.status == "Loaded" then
		session.transferAttempt += 1
		local attempt = session.transferAttempt
		setStatus(player, session, "Transferring")
		task.delay(ExperienceConfig.Teleport.TransitionHoldSeconds, function()
			if sessions[player] == session and session.transferAttempt == attempt then
				PlayerDataService.cancelTransfer(player)
			end
		end)
	end
	local attempt = session.transferAttempt
	return waitForCommit(function(deadline)
		local committed = save(player, session, "transfer", true, deadline)
		return committed and sessions[player] == session and session.transferAttempt == attempt
			and PlayerDataService.isTransferPrepared(player)
	end)
end

-- Resume only the still-owned lease or exactly this transfer's release. Even a destination that
-- has already finished and released its own lease makes this CAS fail.
function PlayerDataService.cancelTransfer(player: Player)
	local session = sessions[player]
	local dataStore = store
	if not session or not dataStore or session.status ~= "Transferring" or session.closing or session.resuming then
		return
	end
	session.resuming = true
	local attempt = session.transferAttempt
	if session.recoveryAttempt ~= attempt then
		session.recoveryAttempt = attempt
		task.delay(ExperienceConfig.Teleport.RecoveryTimeoutSeconds, function()
			if sessions[player] == session and not session.closing and session.transferAttempt == attempt
				and session.status == "Transferring" then
				-- Ownership could not be confirmed. Keep this profile playable in memory;
				-- any unacknowledged lease expires and a rejoin performs a fresh load.
				session.epoch = nil
				setStatus(player, session, "Unsaved")
				warn(PREFIX, ("Transfer recovery timed out for %s; progress is session-only"):format(player.Name))
			end
		end)
	end
	task.spawn(function()
		while session.busy do
			task.wait(0.1)
		end
		if session.closing or session.lost or session.status ~= "Transferring" then
			session.resuming = false
			return
		end
		session.busy = true
		local epoch = session.epoch
		local resumedEpoch = (epoch or 0) + 1
		local denied = false
		local unsupported = false
		local ok, result = retry(function()
			return dataStore:UpdateAsync(key(player), function(old: any)
				denied = false
				unsupported = typeof(old) == "table" and not PlayerDataSchema.canRead(old.version)
				if unsupported then return nil end
				if session.status ~= "Transferring" then
					return nil
				end
				if owns(old, session.token, resumedEpoch) then
					return old -- reacquire committed before an earlier response was lost
				end
				if owns(old, session.token, epoch) then
					local renewed = table.clone(old)
					local now = os.time()
					renewed.lock = { server = session.token, at = now, expiresAt = now + LEASE_SECONDS }
					return renewed
				end
				if releasedBy(old, epoch, session.releaseId) then
					return acquire(old, session.token)
				end
				denied = true
				return nil
			end)
		end)
		if session.status ~= "Transferring" then
			-- The watchdog already entered session-only mode. Ignore the late result.
		elseif ok and (owns(result, session.token, epoch) or owns(result, session.token, resumedEpoch)) then
			session.epoch = (result :: any).leaseEpoch
			session.expiresAt = lockExpires(result)
			session.releaseId = nil
			session.released = false
			setStatus(player, session, "Loaded")
		elseif ok and unsupported then
			incompatible(player, session)
		elseif ok and denied then
			loseProfile(player, session, "cancel transfer")
		else
			warn(PREFIX, ("Transfer recovery unconfirmed for %s"):format(player.Name))
			task.delay(CLOSE_RETRY_SECONDS, function()
				if sessions[player] == session and session.transferAttempt == attempt then
					PlayerDataService.cancelTransfer(player)
				end
			end)
		end
		session.busy = false
		session.resuming = false
	end)
end

-- true confirms at least all mutations made before this call. Mock and Unsaved always return false.
function PlayerDataService.flush(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	return waitForCommit(function(deadline)
		return save(player, session, "flush", false, deadline)
	end)
end

function PlayerDataService.isReady(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and not shutdownDeadline and not session.closing and not session.lost
		and (session.status == "Mock" or session.status == "Unsaved"
			or (session.status == "Loaded" and os.time() < session.expiresAt))
end

function PlayerDataService.canPersist(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.status == "Loaded" and not session.lost
		and not shutdownDeadline and not session.closing and os.time() < session.expiresAt
end

function PlayerDataService.getStatus(player: Player): string
	local session = sessions[player]
	return if session then session.status else "Loading"
end

function PlayerDataService.init(onLoaded: (player: Player) -> ())
	loadedCallback = onLoaded
	if not EnvironmentConfig.useMockData() then
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(EnvironmentConfig.get().DataStoreName)
		end)
		if ok then
			store = result
			local legacyOk, legacyResult = pcall(function()
				return DataStoreService:GetDataStore(LEGACY_STORE_NAME)
			end)
			legacyStore = if legacyOk then legacyResult else nil
		else
			warn(PREFIX, "DataStore unavailable:", tostring(result))
		end
	end
	print(PREFIX, "Player data:", EnvironmentConfig.describe())

	InventoryService.setMutationGuard(function(player: Player, preloadReward: boolean?)
		local session = sessions[player]
		return PlayerDataService.isReady(player)
			or (preloadReward == true and not shutdownDeadline and session ~= nil and session.loading and not session.closing)
	end)

	InventoryService.onChanged(function(player: Player, deferSave: boolean?)
		local session = sessions[player]
		if not session then
			return
		end
		session.revision += 1
		if deferSave or session.status ~= "Loaded" or session.debounce then
			return
		end
		session.debounce = true
		task.delay(SAVE_DEBOUNCE, function()
			session.debounce = false
			save(player, session, "change", false)
		end)
	end)

	Remotes.SavePreference.OnServerEvent:Connect(function(player: Player, prefKey: unknown, value: unknown)
		local session = sessions[player]
		if not session or os.clock() - session.lastPreference < PREFERENCE_RATE then
			return
		end
		session.lastPreference = os.clock()
		InventoryService.setPreference(player, prefKey, value)
	end)

	local function setup(player: Player)
		player:GetAttributeChangedSignal(Config.IntroSeenAttribute):Connect(function()
			if player:GetAttribute(Config.IntroSeenAttribute) == true then
				InventoryService.setPreference(player, "BossIntro", "Seen")
			end
		end)
		task.spawn(PlayerDataService.load, player)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		PlayerDataService.releaseSession(player)
	end)

	task.spawn(function()
		while not shutdownDeadline do
			task.wait(AUTOSAVE_SECONDS)
			for player, session in sessions do
				if session.status == "Loaded" and not session.closing then
					task.spawn(save, player, session, "autosave", false) -- renew clean leases too
				end
			end
		end
	end)

	game:BindToClose(function()
		local deadline = os.clock() + (if RunService:IsStudio() then SHUTDOWN_SECONDS_STUDIO else SHUTDOWN_SECONDS)
		shutdownDeadline = deadline
		for player in sessions do
			task.spawn(PlayerDataService.releaseSession, player)
		end
		while next(sessions) ~= nil and os.clock() < deadline do
			task.wait(0.1)
		end
		for player in sessions do
			warn(PREFIX, ("Shutdown: profile release unconfirmed for %s"):format(player.Name))
		end
	end)
end

return PlayerDataService
