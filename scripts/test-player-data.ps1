param([string]$LuauPath = 'luau')
# PlayerDataService against its REAL source: confirmed saves, one write at a time, the profile lock
# between servers (handoff, takeover, refused late saves) and BindToClose. The DataStore, the task
# scheduler, the clock, players and InventoryService are small mocks; several "servers" share one
# mock DataStore.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $repo 'src/server/PlayerDataService.luau') -Raw

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
local store = { latency = 1, failNext = 0, writes = 0, inFlight = {}, maxInFlight = 0 }
function store:UpdateAsync(key, transform)
	self.inFlight[key] = (self.inFlight[key] or 0) + 1
	self.maxInFlight = math.max(self.maxInFlight, self.inFlight[key])
	task.wait(self.latency)
	self.inFlight[key] -= 1
	if self.failNext > 0 then
		self.failNext -= 1
		error("DataStore request failed")
	end
	local new = transform(deep(db[key]))
	if new == nil then return nil end
	self.writes += 1
	db[key] = deep(new)
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
local function newServer(name)
	local server = { name = name, profiles = {}, changed = {}, players = {}, loaded = 0 }
	local added, removing = signal(), signal()
	local inv = {}
	local function profile(p)
		server.profiles[p] = server.profiles[p] or { denarii = 0, aura = 0 }
		return server.profiles[p]
	end
	function inv.getAura(p) return profile(p).aura end
	function inv.getDenarii(p) return profile(p).denarii end
	function inv.load(p, saved, earnedAura, earnedDenarii)
		server.profiles[p] = { denarii = (saved and saved.denarii or 0) + earnedDenarii, aura = (saved and saved.auraPoints or 0) + earnedAura }
	end
	function inv.serialize(p) return { version = 12, denarii = profile(p).denarii, auraPoints = profile(p).aura } end
	function inv.onChanged(fn) table.insert(server.changed, fn) end
	function inv.forget(p) server.profiles[p] = nil end
	function inv.getPreference() return nil end
	function inv.setPreference() end
	function inv.unlockAll() end
	function server.earn(p, amount)
		profile(p).denarii += amount
		for _, fn in server.changed do task.spawn(fn, p) end
	end
	local mocks = {
		["Shared/Config"] = { DataStatusAttribute = "DataStatus", IntroSeenAttribute = "IntroSeen" },
		["Shared/EnvironmentConfig"] = { get = function() return { DataStoreName = "Store" } end, useMockData = function() return false end, describe = function() return "test" end, name = function() return "DEV" end },
		["Shared/ExperienceConfig"] = { Studio = { UnlockAllGear = false }, Teleport = { TransitionHoldSeconds = 30 } },
		["Server/InventoryService"] = inv,
		["Server/PlayerDataResetConfig"] = { tokenFor = function() return nil end },
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
		added.fire(p)
		return p
	end
	function server.leave(p) p.Parent = nil removing.fire(p) end
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
r = call(A.data.beginTransfer, p)
check(not A.data.isReady(p), "frozen while the transfer flush runs")
after(3)
check(r.value == true and db.player_1.denarii == 170 and db.player_1.lock == nil and A.data.getStatus(p) == "Transferring", "transfer: flushed, lock released")
local pB = B.join(1)
after(3)
check(B.data.getStatus(pB) == "Loaded" and B.profiles[pB].denarii == 170 and db.player_1.lock.server:find("^B%-") ~= nil, "the destination loads the flushed profile without waiting")
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
check(r.value == false and A.data.getStatus(q) == "Loaded" and db.player_2.lock ~= nil, "no teleport without a confirmed flush")

-- 7. TWO SERVERS AT ONCE: a profile held by a live server is not read; after the wait it is taken
--    over, and the first server can no longer write (no overwrite, the player is sent out)
A.earn(q, 2)
local qB = B.join(2)
after(10)
check(B.data.getStatus(qB) == "Loading", "the second server waits for the lock")
after(25)
check(B.data.getStatus(qB) == "Loaded" and db.player_2.lock.server:find("^B%-") ~= nil, "after the wait the second server takes the profile over")
local taken = B.profiles[qB].denarii
B.earn(qB, 500)
after(12)
check(db.player_2.denarii == taken + 500, "the new holder saves")
A.earn(q, 9999)
r = call(A.data.flush, q)
after(4)
check(r.value == false and db.player_2.denarii == taken + 500, "the old holder's save is refused and reported as NOT saved")
check(q.kicked ~= nil and A.data.getStatus(q) == "Unsaved" and not A.data.canPersist(q), "the old holder stops saving and sends the player out")
writes = store.writes
A.leave(q)
after(5)
check(store.writes == writes and db.player_2.denarii == taken + 500, "nothing written on leave either")
B.leave(qB)
after(4)

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
local l = A.join(5)
after(1)
A.leave(l)
after(12)
check(db.player_5 ~= nil and db.player_5.lock == nil, "leaving during the load releases the lock")
store.latency = 1

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
