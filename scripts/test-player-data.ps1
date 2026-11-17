param([string]$LuauPath = 'luau')
# PlayerDataService against its REAL source: confirmed saves, one write at a time, the profile lock
# between servers (handoff, takeover, refused late saves) and BindToClose. The DataStore, the task
# scheduler, the clock, players and InventoryService are small mocks; several "servers" share one
# mock DataStore.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $repo 'src/server/PlayerDataService.luau') -Raw
$purchaseSource = Get-Content -LiteralPath (Join-Path $repo 'src/server/PurchaseService.luau') -Raw
$teleportSource = Get-Content -LiteralPath (Join-Path $repo 'src/server/TeleportUtil.luau') -Raw
$arenaSource = Get-Content -LiteralPath (Join-Path $repo 'src/arena/server/ArenaReturnService.luau') -Raw

$harness = @'
local checks = 0
local function check(ok, message) if not ok then error("FAIL: " .. message, 2) end checks += 1 end
local warnings = {}
local function warn(...) table.insert(warnings, table.concat({ ... }, " ")) end
local realPrint = print
local print = function() end

-- a tiny scheduler: task.wait / task.spawn / task.delay on a simulated clock
local now = 0
local queue = {}
local order = 0
local function push(at, co, fn)
	order += 1
	table.insert(queue, { at = at, co = co, fn = fn, order = order })
end
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then error(tostring(err) .. "\n" .. debug.traceback(co), 0) end
end
local task = {}
function task.spawn(fn, ...) local co = coroutine.create(fn) resume(co, ...) return co end
function task.wait(t) push(now + (t or 0), coroutine.running(), nil) coroutine.yield() return t end
function task.delay(t, fn) push(now + t, nil, fn) end
function task.defer(fn, ...) local args = table.pack(...) task.delay(0, function() fn(table.unpack(args, 1, args.n)) end) end
local function run(untilTime)
	while true do
		local best, bestIndex = nil, nil
		for i, entry in queue do
			if entry.at <= untilTime and (best == nil or entry.at < best.at or (entry.at == best.at and entry.order < best.order)) then
				best, bestIndex = entry, i
			end
		end
		if not best then break end
		table.remove(queue, bestIndex)
		now = best.at
		if best.co then resume(best.co) else task.spawn(best.fn) end
	end
	now = untilTime
end
local function after(seconds) run(now + seconds) end
local realOs = os
local os = { clock = function() return now end, time = function() return 5000000 + math.floor(now) end }

-- the shared mock DataStore
local function deep(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in value do copy[k] = deep(v) end
	return copy
end
local db = {}
local store = { latency = 1, failNext = 0, rejectNext = 0, loseAck = 0, responseDelay = 0, writes = 0, inFlight = {}, maxInFlight = 0 }
function store:UpdateAsync(key, transform)
	self.inFlight[key] = (self.inFlight[key] or 0) + 1
	self.maxInFlight = math.max(self.maxInFlight, self.inFlight[key])
	task.wait(self.latency)
	if self.failNext > 0 then
		self.inFlight[key] -= 1
		self.failNext -= 1
		error("DataStore request failed")
	end
	local new = transform(deep(db[key]))
	if self.rejectNext > 0 and key == self.faultKey then
		self.rejectNext -= 1
		self.inFlight[key] -= 1
		return deep(db[key]) -- a successful request without our committed value
	end
	if new == nil then
		self.inFlight[key] -= 1
		return nil
	end
	self.writes += 1
	db[key] = deep(new)
	if self.responseDelay > 0 then task.wait(self.responseDelay) end
	self.inFlight[key] -= 1
	if self.loseAck > 0 and key == self.faultKey then
		self.loseAck -= 1
		error("Response lost after commit")
	end
	return deep(new)
end
function store:GetAsync(key) task.wait(self.latency) return deep(db[key]) end
local emptyStore = { GetAsync = function() return nil end }

local function signal()
	local handlers = {}
	return {
		Connect = function(_, fn) table.insert(handlers, fn) return { Disconnect = function() end } end,
		fire = function(...) for _, fn in handlers do task.spawn(fn, ...) end end,
	}
end

local guid = 0
local source
-- One "server": its own PlayerDataService, InventoryService mock, Players service and BindToClose.
local resetRequested = false
local function newServer(name, mockData)
	local server = { name = name, profiles = {}, changed = {}, players = {}, loaded = 0 }
	local added, removing = signal(), signal()
	local inv = {}
	local function profile(p)
		server.profiles[p] = server.profiles[p] or { denarii = 0, aura = 0, receipts = {} }
		return server.profiles[p]
	end
	function inv.getAura(p) return profile(p).aura end
	function inv.getDenarii(p) return profile(p).denarii end
	function inv.load(p, saved, earnedAura, earnedDenarii)
		server.profiles[p] = { denarii = (saved and saved.denarii or 0) + earnedDenarii, aura = (saved and saved.auraPoints or 0) + earnedAura, receipts = deep(saved and saved.receipts or {}) }
	end
	function inv.serialize(p)
		return { version = 13, denarii = profile(p).denarii, auraPoints = profile(p).aura, session = { aura = 17, denarii = 9 }, receipts = deep(profile(p).receipts) }
	end
	function inv.setMutationGuard(fn) server.canMutate = fn end
	function inv.onChanged(fn) table.insert(server.changed, fn) end
	function inv.forget(p) server.profiles[p] = nil end
	function inv.getPreference() return nil end
	function inv.setPreference() end
	function inv.unlockAll() end
	function server.earn(p, amount)
		if not server.canMutate(p, true) then return false end
		profile(p).denarii += amount
		for _, fn in server.changed do fn(p) end
		return true
	end
	function inv.applyPurchase(p, product, id)
		if not server.canMutate(p) then return false, false end
		local current = profile(p)
		if current.receipts[id] then return true, false end
		current.denarii += product.denarii
		current.receipts[id] = true
		for _, fn in server.changed do fn(p) end
		return true, true
	end
	server.inventory = inv
	local mocks = {
		["Shared/Config"] = { DataStatusAttribute = "DataStatus", IntroSeenAttribute = "IntroSeen" },
		["Shared/EnvironmentConfig"] = { get = function() return { DataStoreName = "Store" } end, useMockData = function() return mockData == true end, describe = function() return "test" end, name = function() return "DEV" end },
		["Shared/ExperienceConfig"] = { Studio = { UnlockAllGear = false }, Teleport = { TransitionHoldSeconds = 60, RecoveryTimeoutSeconds = 20 } },
		["Shared/PlayerDataSchema"] = { Version = 13 },
		["Server/InventoryService"] = inv,
		["Server/PlayerDataResetConfig"] = { tokenFor = function() return if resetRequested then "test-reset" else nil end },
		["Server/Remotes"] = { SavePreference = { OnServerEvent = signal() } },
	}
	local services = {
		DataStoreService = { GetDataStore = function(_, storeName) return if storeName == "Store" then store else emptyStore end },
		HttpService = { GenerateGUID = function() guid += 1 return name .. "-" .. guid end },
		Players = { PlayerAdded = added, PlayerRemoving = removing, GetPlayers = function() return {} end },
		RunService = { IsStudio = function() return false end },
		ReplicatedStorage = { Shared = setmetatable({}, { __index = function(_, k) return "Shared/" .. k end }) },
	}
	local game = { GetService = function(_, service) return assert(services[service], service) end }
	function game:BindToClose(fn) server.close = fn end
	local script = { Parent = setmetatable({}, { __index = function(_, k) return "Server/" .. k end }) }
	server.data = source(script, game, function(key) return assert(mocks[key], "unmapped require " .. tostring(key)) end)
	server.data.init(function() server.loaded += 1 end)
	function server.join(id)
		local p = { UserId = id, Name = "P" .. id, Parent = true, attrs = {} }
		function p:GetAttribute(k) return self.attrs[k] end
		function p:SetAttribute(k, v) self.attrs[k] = v end
		function p:GetAttributeChangedSignal() return signal() end
		function p:Kick(message) self.kicked = message end
		server.players[id] = p
		added.fire(p)
		return p
	end
	function server.leave(p)
		p.Parent = nil
		if server.players[p.UserId] == p then server.players[p.UserId] = nil end
		removing.fire(p)
	end
	return server
end
-- runs a yielding call and returns a box that holds its answer once it has finished
local function call(fn, ...)
	local box = { done = false }
	local args = { ... }
	task.spawn(function() box.value = fn(table.unpack(args)) box.done = true box.at = now end)
	return box
end
'@
$harness += "`nsource = function(script, game, require)`n$source`nend`n"
$harness += "`nlocal purchaseSource = function(script, game, require, Enum)`n$purchaseSource`nend`n"
$harness += "`nlocal arenaSource = function(script, game, require)`n$arenaSource`nend`n"
$harness += "`nlocal teleportSource = function(script, game, require, Enum, Instance)`n$teleportSource`nend`n"
$harness += @'

-- 1. JOIN: a new player gets the lock, nothing else is stored yet
local A = newServer("A")
local p = A.join(1)
check(A.data.getStatus(p) == "Loading" and not A.data.isReady(p), "loading until the DataStore answered")
after(3)
check(A.data.getStatus(p) == "Loaded" and A.loaded == 1, "loaded")
check(db.player_1.lock.server:find("^A%-") ~= nil and db.player_1.empty == true, "the load claimed the lock (no profile data yet)")

-- 2. CHANGE -> debounced save, confirmed
A.earn(p, 100)
after(12)
check(db.player_1.denarii == 100 and db.player_1.saveId ~= nil and db.player_1.empty == nil and db.player_1.lock.server:find("^A%-") ~= nil, "the change is written with a save id and the lock")
check(db.player_1.session.aura == 17 and db.player_1.session.denarii == 9, "lease metadata does not overwrite gameplay session earnings")
local writes = store.writes
local r = call(A.data.flush, p)
after(3)
check(r.done and r.value == true and store.writes == writes, "flush with nothing unsaved: confirmed without another write")

-- 3. SAVE FAILURE: not reported as saved, still dirty, written by the next try
A.earn(p, 50)
store.failNext = 3
r = call(A.data.flush, p)
after(7.8) -- three attempts with their pauses; the debounced save has not started yet
check(r.done and r.value == false and db.player_1.denarii == 100, "a failed save answers false and stores nothing")
check(#warnings > 0, "the failure is logged")
r = call(A.data.flush, p)
after(3)
check(r.value == true and db.player_1.denarii == 150, "the next flush writes the unsaved change")
store.failNext = 2 -- two failed attempts, the third works
A.earn(p, 1)
r = call(A.data.flush, p)
after(10)
check(r.value == true and db.player_1.denarii == 151, "retries inside one save")

-- 4. PARALLEL SAVES: one write at a time; the second waits and writes what the first missed
store.latency = 2
store.maxInFlight = 0
A.earn(p, 10)
local first = call(A.data.flush, p)
after(1)
A.earn(p, 5) -- while the first write is on its way
local second = call(A.data.flush, p)
check(not first.done and not second.done, "both saves are still running")
after(1.5)
check(first.done and first.value == true and db.player_1.denarii == 161 and not second.done, "the first save is confirmed; the second is still waiting / writing")
after(4)
check(second.done and second.value == true and db.player_1.denarii == 166, "the second save wrote the change made meanwhile")
check(store.maxInFlight == 1, "never two writes of one profile at the same time")
after(20) -- the debounced saves find nothing left
check(db.player_1.denarii == 166 and store.maxInFlight == 1, "debounced saves stay serialized")
store.latency = 1

-- 5. HANDOFF (teleport): the flush releases the lock, the destination loads at once
local B = newServer("B")
A.earn(p, 4)
local firstEpoch = db.player_1.leaseEpoch
r = call(A.data.beginTransfer, p)
local duplicateTransfer = call(A.data.beginTransfer, p)
check(not A.data.isReady(p), "frozen while the transfer flush runs")
check(not A.earn(p, 700), "mutations are rejected before a transfer can yield")
after(3)
check(r.value == true and duplicateTransfer.value == true and db.player_1.denarii == 170 and db.player_1.lock == nil and A.data.getStatus(p) == "Transferring", "both transfer callers wait for the same confirmed release")
local pB = B.join(1)
after(3)
check(B.data.getStatus(pB) == "Loaded" and B.profiles[pB].denarii == 170 and db.player_1.lock.server:find("^B%-") ~= nil, "the destination loads the flushed profile without waiting")
check(db.player_1.leaseEpoch == firstEpoch + 1, "destination allocates a new fence")
B.earn(pB, 30)
after(12)
check(db.player_1.denarii == 200, "the destination saves")
-- a late change on the old server must not overwrite the destination's data
A.earn(p, 1000)
A.leave(p)
after(6)
check(db.player_1.denarii == 200 and db.player_1.lock.server:find("^B%-") ~= nil, "the old server's late save is refused (lock held by the destination)")
B.leave(pB)
after(4)
check(db.player_1.lock == nil and db.player_1.denarii == 200, "leaving releases the lock")

-- 6. CANCELLED TRANSFER: the profile is normal again and the lock is taken back
local q = A.join(2)
after(3)
A.earn(q, 7)
r = call(A.data.beginTransfer, q)
after(3)
check(r.value == true and db.player_2.lock == nil, "transfer flushed")
A.data.cancelTransfer(q)
after(3)
check(A.data.getStatus(q) == "Loaded" and db.player_2.lock ~= nil and db.player_2.denarii == 7, "cancelled: Loaded, lock held again")
-- a transfer that can't be flushed is refused
store.failNext = 3
A.earn(q, 1)
r = call(A.data.beginTransfer, q)
after(12)
check(r.value == false and A.data.getStatus(q) == "Transferring" and db.player_2.lock ~= nil, "no teleport without a confirmed flush")
A.data.cancelTransfer(q)
after(2)
check(A.data.getStatus(q) == "Loaded", "recover the original lease after an unconfirmed transfer")

-- 7. TWO SERVERS AT ONCE: contention times out without revoking a live lease.
A.earn(q, 2)
local aEpoch = db.player_2.leaseEpoch
local qB = B.join(2)
after(10)
check(B.data.getStatus(qB) == "Loading", "the second server waits for the lock")
after(25)
check(B.data.getStatus(qB) == "Unsaved" and db.player_2.leaseEpoch == aEpoch and db.player_2.lock.server:find("^A%-") ~= nil, "waiting cannot steal a live lease")
check(not B.data.canPersist(qB), "the contending server has no persistence authority")
B.leave(qB)

-- Atomic takeover uses a new fence when the old lease has actually expired.
db.player_2.lock.expiresAt = os.time() - 1
qB = B.join(2)
after(3)
check(B.data.getStatus(qB) == "Loaded" and db.player_2.leaseEpoch == aEpoch + 1, "an expired lease can be acquired")
local taken = B.profiles[qB].denarii
B.earn(qB, 500)
after(12)
check(db.player_2.denarii == taken + 500, "the new holder saves")
B.leave(qB)
after(4)
check(db.player_2.lock == nil, "the newer owner already released its lease")
A.earn(q, 9999)
r = call(A.data.flush, q)
after(4)
check(r.value == false and db.player_2.denarii == taken + 500, "the old holder's save is refused and reported as NOT saved")
check(q.kicked ~= nil and A.data.getStatus(q) == "Unsaved" and not A.data.canPersist(q), "the old holder stops saving and sends the player out")
writes = store.writes
A.leave(q)
after(5)
check(store.writes == writes and db.player_2.denarii == taken + 500, "nothing written on leave either")

-- 8. CRASHED SERVER: an old lock is taken over at once
db.player_3 = { version = 12, denarii = 77, auraPoints = 0, lock = { server = "DEAD", at = os.time() - 31 * 60 } }
local c = A.join(3)
after(3)
check(A.data.getStatus(c) == "Loaded" and A.profiles[c].denarii == 77, "a stale lock doesn't hold the profile back")

-- 9. LOAD FAILURE: "Unsaved", never written, flush answers false
store.failNext = 3
local u = A.join(4)
after(12)
check(A.data.getStatus(u) == "Unsaved" and A.data.isReady(u) and not A.data.canPersist(u), "failed load: unsaved profile")
writes = store.writes
A.earn(u, 5)
r = call(A.data.flush, u)
after(12)
A.leave(u)
after(5)
check(r.value == false and store.writes == writes and db.player_4 == nil, "an unsaved profile is never written and never reported as saved")

-- 10. LEFT WHILE LOADING: the claimed lock is given back
store.latency = 4
store.responseDelay = 2
local l = A.join(5)
after(4.5) -- the lease was written, but Load is still waiting for the returned record
A.leave(l)
after(12)
check(db.player_5 ~= nil and db.player_5.lock == nil, "leaving during the load releases the lock")
store.latency = 1
store.responseDelay = 0

-- 11. SHUTDOWN: BindToClose waits for the leave saves and running writes, and releases the locks
local S = newServer("S")
local s1, s2, s3 = S.join(11), S.join(12), S.join(13)
after(3)
store.latency = 3
S.earn(s1, 1) S.earn(s2, 2) S.earn(s3, 3)
local running = call(S.data.flush, s3) -- a write already on its way when the server closes
after(1)
S.earn(s3, 30) -- changed after that write was taken
S.leave(s1) -- PlayerRemoving fires for the players as the server closes
local closed = call(S.close)
check(not closed.done, "BindToClose yields while saves run")
after(2.5)
check(not closed.done and running.done, "still waiting: the last save of the third profile comes after the running write")
after(6)
check(closed.done, "BindToClose returned")
check(db.player_11.denarii == 1 and db.player_12.denarii == 2 and db.player_13.denarii == 33, "every profile is stored with its latest state")
check(db.player_11.lock == nil and db.player_12.lock == nil and db.player_13.lock == nil, "shutdown releases every lock")
check(closed.at >= 6, "BindToClose did not return before the writes answered")
S.leave(s2) S.leave(s3)
after(5)
check(db.player_12.denarii == 2 and db.player_13.denarii == 33, "the leave events after the shutdown save change nothing")

-- A returned pre-write record is a refusal. A lost acknowledgement, in contrast, is
-- reconciled by the same operation's saveId in a subsequent UpdateAsync.
store.latency = 1
local R = newServer("R")
local rp = R.join(31)
after(3)
R.earn(rp, 11)
store.faultKey = "player_31"
store.rejectNext = 1
r = call(R.data.flush, rp)
after(2)
check(r.value == false and db.player_31.denarii == nil, "a returned pre-write record cannot acknowledge a save")
store.loseAck = 1
r = call(R.data.flush, rp)
after(7)
check(r.value == true and db.player_31.denarii == 11, "retry reconciles a committed write after the acknowledgement was lost")

-- PlayerRemoving waits behind a write, includes the intervening mutation, and freezes
-- the same Player instance before a reconnect can inherit its pending profile.
store.latency = 3
R.earn(rp, 10)
running = call(R.data.flush, rp)
after(0.5)
R.earn(rp, 20)
R.leave(rp)
local rpNew = R.join(31)
check(not R.earn(rp, 1000) and R.profiles[rp] ~= nil, "leave freezes and retains the pending profile")
after(4)
check(running.value == true and db.player_31.denarii == 21 and R.profiles[rp] ~= nil, "PlayerRemoving waits for both writes")
after(12)
check(db.player_31.denarii == 41 and R.profiles[rp] == nil, "the release commits the newer revision before forgetting it")
check(R.data.getStatus(rpNew) == "Loaded" and R.profiles[rpNew].denarii == 41, "a reconnect loads the committed profile under a fresh lease")
store.latency = 1
R.earn(rpNew, 8)
store.faultKey = "player_31"
store.rejectNext = 1
R.leave(rpNew)
after(3)
check(R.profiles[rpNew] ~= nil and db.player_31.denarii == 41 and db.player_31.lock ~= nil, "an unconfirmed leave keeps its frozen revision pending")
after(6)
check(R.profiles[rpNew] == nil and db.player_31.denarii == 49 and db.player_31.lock == nil, "a pending leave retries and commits before cleanup")

-- Cancellation after the destination already released its lease cannot resurrect the source.
local handoff = R.join(32)
after(3)
R.earn(handoff, 4)
store.faultKey = "player_32"
store.loseAck = 1
r = call(R.data.beginTransfer, handoff)
after(7)
check(r.value == true and db.player_32.lock == nil, "release acknowledgement can be reconciled too")
local destination = B.join(32)
after(3)
B.earn(destination, 19)
B.leave(destination)
after(4)
R.data.cancelTransfer(handoff)
after(4)
check(R.data.getStatus(handoff) == "Unsaved" and db.player_32.denarii == 23 and db.player_32.lock == nil, "cancel cannot reuse a release fence after the destination has finished")

-- A timed-out caller cannot report success or overlap the in-flight write. The worker
-- continues, and a later write commits the newer revision.
local timeout = R.join(33)
after(3)
store.latency = 19
R.earn(timeout, 3)
local timedOut = call(R.data.flush, timeout)
after(1)
R.earn(timeout, 7)
after(15)
check(timedOut.done and timedOut.value == false and db.player_33.denarii == nil and store.inFlight.player_33 == 1, "flush deadline is not a durable acknowledgement")
store.latency = 1
r = call(R.data.flush, timeout)
after(8)
check(r.value == true and db.player_33.denarii == 10 and store.inFlight.player_33 == 0, "the next flush waits and commits the newest revision")

local M = newServer("M", true)
local mocked = M.join(34)
after(1)
check(M.data.getStatus(mocked) == "Mock" and M.data.isReady(mocked) and not M.data.canPersist(mocked), "Studio mock is playable without persistence")
check(call(M.data.flush, mocked).value == false and call(M.data.beginTransfer, mocked).value == false and db.player_34 == nil, "Studio mock cannot claim a durable write or transfer")

db.player_35 = { version = 14, denarii = 99 }
local future = R.join(35)
after(3)
check(R.data.getStatus(future) == "Unsaved" and db.player_35.version == 14 and db.player_35.lock == nil, "an older schema cannot claim or overwrite a future profile")

-- Real TeleportUtil and ArenaReturnService against the deterministic scheduler and a fake engine.
local function newTransport(data)
	local api = { calls = {}, events = {}, failed = {} }
	local removing, initFailed = signal(), signal()
	local function options()
		local object = { ReservedServerAccessCode = "", ServerInstanceId = "" }
		function object:SetTeleportData(value) self.data = deep(value) end
		function object:GetTeleportData() return deep(self.data) end
		return object
	end
	local results = setmetatable({}, { __index = function(_, key) return key end })
	local engine = { TeleportInitFailed = initFailed }
	function engine:TeleportAsync(placeId, players, routing)
		local record = { placeId = placeId, players = table.clone(players), routing = routing, wire = routing:GetTeleportData() }
		table.insert(api.calls, record)
		if api.onCall then api.onCall(record) end
	end
	local names = setmetatable({}, { __index = function(_, name) return name end })
	local env = { canTeleport = function() return true end, get = function() return { HubPlaceId = 1, ArenaPlaceId = 2 } end }
	local config = { TeleportStateAttribute = "Travel", ArenaRoleAttribute = "Role" }
	local match = { Messages = { DATA_SAVE_FAILED = "Pending", TELEPORT_FAILED = "Failed", TELEPORT_TIMEOUT = "Timed out" } }
	local remotes = {
		CombatFeedback = { FireClient = function() end },
		MatchEvent = { FireClient = function(_, player, kind, value) api.events[player] = { kind, value } end },
	}
	local mocks = {
		Config = config, EnvironmentConfig = env, MatchTypes = match, PlayerDataService = data, Remotes = remotes,
		CombatConfig = { Feedback = { Shop = "Shop" } },
		ExperienceConfig = { Teleport = { TravelTimeoutSeconds = 40, ReturnRetries = 2, ReturnRetryDelaySeconds = 3, Retries = 2, RetryDelaySeconds = 2 } },
	}
	local services = {
		Players = { PlayerRemoving = removing }, ReplicatedStorage = { Shared = names }, TeleportService = engine,
		HttpService = { GenerateGUID = function() guid += 1 return "attempt-" .. guid end },
	}
	local fakeGame = { GetService = function(_, service) return services[service] end }
	local fakeRequire = function(name) return assert(mocks[name], name) end
	local util = teleportSource({ Parent = names }, fakeGame, fakeRequire, { TeleportResult = results }, { new = options })
	mocks.TeleportUtil = util
	api.arena = arenaSource({ Parent = { Parent = names } }, fakeGame, fakeRequire)
	api.util = util
	util.init()
	function api.failure(player, record, result, place, serverInstance)
		local retry = options() -- Roblox provides a different options instance for the callback
		retry:SetTeleportData(record.wire)
		retry.ServerInstanceId = serverInstance or ""
		retry.ReservedServerAccessCode = record.routing.ReservedServerAccessCode
		initFailed.fire(player, result, "mock failure", place or record.placeId, retry)
	end
	function api.leave(player)
		player.Parent = nil
		removing.fire(player)
	end
	function api.start(players)
		return util.toHub(players, { kind = "ToHub" }, function(player, code)
			api.failed[player] = (api.failed[player] or 0) + 1
			api.lastCode = code
		end)
	end
	return api
end

local live = newServer("Travel")
local refused, ongoing = live.join(40), live.join(41)
after(3)
local transport = newTransport(live.data)
live.earn(refused, 5)
store.faultKey, store.rejectNext = "player_40", 1
transport.arena.send({ refused })
after(3)
check(#transport.calls == 0 and transport.events[refused][1] == "ReturnFailed"
	and live.data.getStatus(refused) == "Loaded", "a refused write blocks the Arena teleport and recovers profile access")

store.latency = 3
live.earn(ongoing, 2)
local flushBeforeTravel = call(live.data.flush, ongoing)
after(1)
live.earn(ongoing, 7)
transport.arena.send({ ongoing })
after(1)
check(#transport.calls == 0 and not flushBeforeTravel.done and ongoing.attrs.Travel == "Preparing", "travel waits behind the running save")
after(7)
check(#transport.calls == 1 and db.player_41.denarii == 9 and db.player_41.lock == nil, "the native engine only sees the confirmed newest revision")
transport.leave(ongoing)
live.leave(ongoing)
store.latency = 1

local function travelPlayer(id)
	local p = { UserId = id, Parent = true, attrs = {}, cancellations = 0 }
	function p:GetAttribute(k) return self.attrs[k] end
	function p:SetAttribute(k, v) self.attrs[k] = v end
	return p
end
local fakeData = {
	getStatus = function() return "Loaded" end,
	beginTransfer = function(p) p.prepared = true return true end,
	isTransferPrepared = function(p) return p.prepared == true end,
	cancelTransfer = function(p) p.cancellations += 1 p.prepared = false end,
}
local a, b = travelPlayer(101), travelPlayer(102)
transport = newTransport(fakeData)
check(#transport.start({ a, b, a }) == 2 and #transport.start({ a }) == 0 and #transport.calls == 1, "one transfer owns each player even in overlapping group requests")
local group = transport.calls[1]
transport.failure(a, group, "Failure", 99)
after(3.1)
check(#transport.calls == 1, "failure for another place is ignored")
transport.failure(a, group, "Failure", nil, "hub-instance")
transport.failure(a, group, "Failure", nil, "hub-instance")
after(3.1)
check(#transport.calls == 2 and #transport.calls[2].players == 1 and transport.calls[2].players[1] == a
	and transport.calls[2].routing.ServerInstanceId == "hub-instance", "a repeated group failure retries only the failed player at the original destination")
local retry = transport.calls[2]
transport.failure(a, group, "Failure")
after(3.1)
check(#transport.calls == 2, "late failure from the previous attempt cannot spend the new retry")
transport.failure(a, retry, "Failure")
after(3.1)
transport.failure(a, transport.calls[3], "Failure")
after(1)
check(transport.failed[a] == 1 and a.cancellations == 1 and a.attrs.Travel == "Failed"
	and transport.util.isPending(b), "retry exhaustion restores only the failed group member")
transport.leave(b)

local left = travelPlayer(103)
transport.start({ left })
transport.failure(left, transport.calls[#transport.calls], "Failure")
local countBeforeLeave = #transport.calls
transport.leave(left)
after(4)
check(#transport.calls == countBeforeLeave and left.cancellations == 0 and not transport.util.isPending(left)
	and transport.lastCode == "LEFT", "leaving during retry stops attempts and clears source bookkeeping")

local throws = travelPlayer(107)
transport = newTransport(fakeData)
transport.onCall = function(record)
	transport.failure(throws, record, "Failure")
	error("native error for the same attempt")
end
transport.start({ throws })
after(8)
check(#transport.calls == 3 and transport.failed[throws] == 1, "a native throw and a failure event for the same attempt schedule only one retry")

local slow = travelPlayer(104)
transport = newTransport(fakeData)
transport.onCall = function() task.wait(50) end
transport.start({ slow })
local slowAttempt = transport.calls[1]
after(41)
check(transport.lastCode == "TELEPORT_TIMEOUT" and slow.cancellations == 1 and #transport.start({ slow }) == 0,
	"timeout restores local state without launching against a pending native call")
after(10)
check(#transport.start({ slow }) == 0 and #transport.calls == 1, "late success remains ambiguous without departure or definitive failure")
transport.failure(slow, slowAttempt, "Failure")
transport.onCall = nil
check(#transport.start({ slow }) == 1 and #transport.calls == 2, "definitive late failure clears only that attempt's quarantine")
transport.failure(slow, slowAttempt, "Failure")
check(transport.util.isPending(slow) and slow.cancellations == 1, "a definitive callback for an old attempt cannot cancel a new transfer")
transport.leave(slow)

local hint = travelPlayer(105)
function hint:GetJoinData() return { TeleportData = { kind = "ToArena", matchId = "match", role = "FIGHTER", reward = 999, accessCode = "untrusted", attemptId = "old" } } end
local clean = transport.util.joinPayload(hint)
check(clean.matchId == "match" and clean.role == nil and clean.reward == nil and clean.accessCode == nil and clean.attemptId == nil,
	"destination hints exclude roles, receipts, secrets and attempt correlation")
transport.util.markArrived(hint)
check(hint.attrs.Travel == "Arrived", "the destination marks arrival independently of source callbacks")

local outbound = travelPlayer(106)
transport = newTransport(fakeData)
transport.util.toReserved({ outbound }, function() return "server-only" end, {
	kind = "ToArena", matchId = "match", role = "FIGHTER", mode = "SOLO_ZOMBIES", accessCode = "injected",
}, function() end)
local reservedCall = transport.calls[1]
check(reservedCall.placeId == 2 and reservedCall.routing.ReservedServerAccessCode == "server-only"
	and reservedCall.wire.matchId == "match" and reservedCall.wire.accessCode == nil
	and reservedCall.wire.role == nil and reservedCall.wire.mode == nil, "outgoing reserved routing keeps credentials and roles out of TeleportData")
transport.leave(outbound)

local recovering = live.join(42)
after(3)
local committedTransfer = call(live.data.beginTransfer, recovering)
after(3)
check(committedTransfer.value == true, "the recovery timeout scenario starts with a released durable profile")
store.latency = 32
live.data.cancelTransfer(recovering)
after(21)
check(live.data.getStatus(recovering) == "Unsaved" and live.data.isReady(recovering) and not live.data.canPersist(recovering),
	"unavailable recovery restores session-only control within its deadline")
store.latency = 1
after(13)
check(live.data.getStatus(recovering) == "Unsaved", "late lease acknowledgement cannot restore persistence after recovery timed out")

-- A clean, idle profile still has an active lease after the heartbeat.
local H = newServer("H")
local idle = H.join(36)
after(3)
r = call(H.data.flush, idle)
after(3)
local oldExpiry, oldEpoch = db.player_36.lock.expiresAt, db.player_36.leaseEpoch
after(122)
check(r.value == true and db.player_36.lock.expiresAt > oldExpiry and db.player_36.leaseEpoch == oldEpoch, "autosave renews a clean lease without changing ownership")

-- Receipt handling uses the actual PurchaseService and PlayerDataService with a shared mock store.
local function receiptProcessor(server)
	local marketplace = {}
	local services = {
		MarketplaceService = marketplace,
		Players = { GetPlayerByUserId = function(_, id) return server.players[id] end },
		ReplicatedStorage = { Shared = { ForgeDefinitions = "Catalog" } },
	}
	local modules = {
		Catalog = { product = function(id) return if id == 1 then { denarii = 10 } else nil end },
		PlayerData = server.data, Inventory = server.inventory,
	}
	local script = { Parent = { PlayerDataService = "PlayerData", InventoryService = "Inventory" } }
	local game = { GetService = function(_, name) return services[name] end }
	local enum = { ProductPurchaseDecision = { PurchaseGranted = "Granted", NotProcessedYet = "Pending" } }
	local notified = 0
	local handler = purchaseSource(script, game, function(name) return modules[name] end, enum)
	handler.init(function() notified += 1 end)
	local callback = marketplace.ProcessReceipt
	handler.init()
	check(marketplace.ProcessReceipt == callback, "receipt callback registers once per server")
	return function(player, receiptId, productId)
		return call(callback, { PlayerId = player.UserId, ProductId = productId or 1, PurchaseId = receiptId })
	end, function() return notified end
end

local ShopA, ShopB = newServer("ShopA"), newServer("ShopB")
local shopA, notifications = receiptProcessor(ShopA)
local shopB = receiptProcessor(ShopB)
local client = ShopA.join(71)
local queuedReceipt = shopA(client, "during-load")
check(not queuedReceipt.done and db.player_71 == nil, "a receipt cannot complete before the profile loads")
after(4)
check(queuedReceipt.value == "Granted" and db.player_71.denarii == 10 and db.player_71.receipts["during-load"], "receipt on join can wait for a real load and commit")
check(shopA(client, "unknown-product", 2).value == "Pending" and shopA(client, "", 1).value == "Pending", "unknown products and invalid purchase IDs stay pending")
local unsavedShop = receiptProcessor(R)
local mockShop = receiptProcessor(M)
check(unsavedShop(future, "unsaved").value == "Pending" and mockShop(mocked, "mock").value == "Pending", "Unsaved and Mock cannot acknowledge a paid receipt")

store.faultKey, store.rejectNext = "player_71", 2
local failedOnce = shopA(client, "retry-save")
after(2)
local failedTwice = shopA(client, "retry-save")
after(2)
check(failedOnce.value == "Pending" and failedTwice.value == "Pending"
	and db.player_71.denarii == 10 and not db.player_71.receipts["retry-save"] and ShopA.profiles[client].denarii == 20,
	"failed writes leave no durable grant and an in-memory repeat cannot acknowledge or grant again")
local committed = shopA(client, "retry-save")
after(2)
check(committed.value == "Granted" and db.player_71.denarii == 20 and db.player_71.receipts["retry-save"]
	and notifications() == 2, "retry acknowledges the original grant only once it is durable")

store.latency = 3
local parallel1 = shopA(client, "concurrent")
local parallel2 = shopA(client, "concurrent")
check(not parallel1.done and not parallel2.done and ShopA.profiles[client].denarii == 30, "concurrent callbacks share the pending revision")
after(5)
check(parallel1.value == "Granted" and parallel2.value == "Granted" and db.player_71.denarii == 30
	and notifications() == 3, "concurrent callbacks confirm a single committed grant")
store.latency = 1

local disconnect = ShopA.join(72)
after(3)
local duringDisconnect = shopA(disconnect, "disconnected")
after(0.5)
ShopA.leave(disconnect)
after(4)
local reconnected = ShopB.join(72)
after(3)
local deliveredAgain = shopB(reconnected, "disconnected")
after(3)
check(duringDisconnect.value == "Granted" and deliveredAgain.value == "Granted" and db.player_72.denarii == 10
	and db.player_72.receipts.disconnected, "disconnect during commit and cross-place redelivery preserve one grant")

local beforeCrash = ShopA.join(73)
after(3)
store.latency = 9
local staleCallback = shopA(beforeCrash, "before-crash")
after(1)
check(not db.player_73.receipts and not db.player_73.denarii, "crash before UpdateAsync has persisted neither benefit nor evidence")
db.player_73.lock.expiresAt = os.time() - 1
store.latency = 1
local owner = ShopB.join(73)
after(3)
local recoveredReceipt = shopB(owner, "before-crash")
after(10)
check(recoveredReceipt.value == "Granted" and staleCallback.value == "Pending" and db.player_73.denarii == 10
	and db.player_73.receipts["before-crash"], "new owner commits once and an old callback cannot overwrite the new lease")

local afterCrash = ShopA.join(74)
after(3)
store.responseDelay = 19
local lostConfirmation = shopA(afterCrash, "after-crash")
after(2)
check(not lostConfirmation.done and db.player_74.denarii == 10 and db.player_74.receipts["after-crash"],
	"crash after commit and before acknowledgement leaves the paired data durable")
store.responseDelay = 0
db.player_74.lock.expiresAt = os.time() - 1
resetRequested = true
local nextOwner = ShopB.join(74)
after(3)
resetRequested = false
local replay = shopB(nextOwner, "after-crash")
after(16)
check(replay.value == "Granted" and lostConfirmation.value == "Pending" and db.player_74.denarii == 10
	and db.player_74.receipts["after-crash"], "lost acknowledgement and a requested test reset cannot duplicate or delete a paid grant")

-- 12. SHUTDOWN with a DataStore that doesn't answer: gives up before Roblox's 30 s
local T = newServer("T")
local t1 = T.join(21)
after(5)
store.latency = 500
T.earn(t1, 1)
local started = now
closed = call(T.close)
after(28)
check(closed.done and closed.at - started <= 26 and closed.at - started >= 24, "BindToClose stops waiting after 25 s")
check(warnings[#warnings]:find("release unconfirmed") ~= nil and db.player_21.denarii == nil, "shutdown logs the unconfirmed profile instead of claiming success")

realPrint("PASS: " .. checks .. " checks, PlayerDataService against the actual Luau source (mock DataStore, several servers).")
'@
$target = Join-Path ([System.IO.Path]::GetTempPath()) ("OttiData-" + [guid]::NewGuid().ToString() + ".luau")
[System.IO.File]::WriteAllText($target, $harness, [System.Text.UTF8Encoding]::new($false))
try {
    & $LuauPath $target
    $testExit = $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
}
exit $testExit
