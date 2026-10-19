--!strict
-- Thin, failure-tolerant wrapper around MemoryStore sorted maps (server only). Every map name is
-- prefixed with the environment namespace (ExperienceConfig: OttiMatches_DEV / OttiMatches_PROD),
-- so DEV and PROD never share registry, queues or tickets.
--   get(key)                      -> ok, value
--   set(key, value, ttl)          -> ok
--   update(key, fn, ttl)          -> ok, newValue   fn(old) returns the new value, or nil to abort
--                                                   (atomic: MemoryStore retries on conflicts)
--   remove(key)                   -> ok
--   list(max)                     -> ok, { { key, value } }   (ascending, paginated)
-- Calls never throw: failures are retried a little and then reported as ok = false, so an
-- outage can never crash an active match. In Studio (ExperienceConfig.Studio.UseMockMemoryStore)
-- an in-memory implementation with the same semantics (copies, expiration) is used instead.

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)

local PREFIX = "[OttiArena][Memory]"
local ATTEMPTS = 2
local PAGE = 200
local MAX_PAGES = 5

export type Entry = { key: string, value: any }

export type SortedMap = {
	name: string,
	get: (key: string) -> (boolean, any),
	set: (key: string, value: any, ttl: number) -> boolean,
	update: (key: string, fn: (old: any) -> any, ttl: number) -> (boolean, any),
	remove: (key: string) -> boolean,
	list: (max: number?) -> (boolean, { Entry }),
}

local MemoryStoreAdapter = {}

local maps: { [string]: SortedMap } = {}
local warned: { [string]: number } = {}

local function report(name: string, operation: string, err: any)
	local key = name .. operation
	local now = os.clock()
	if (warned[key] or 0) + 10 < now then
		warned[key] = now
		warn(PREFIX, ("%s.%s failed: %s"):format(name, operation, tostring(err)))
	end
end

local function attempt<T>(name: string, operation: string, call: () -> T): (boolean, T?)
	local lastError: any = nil
	for i = 1, ATTEMPTS do
		local ok, result = pcall(call)
		if ok then
			return true, result
		end
		lastError = result
		if i < ATTEMPTS then
			task.wait(0.3 * i)
		end
	end
	report(name, operation, lastError)
	return false, nil
end

local function copy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	return HttpService:JSONDecode(HttpService:JSONEncode(value)) -- same limits as the real store
end

------------------------------------------------------------------------------------------
-- In-memory map (Studio mock)
------------------------------------------------------------------------------------------

local function mockMap(name: string): SortedMap
	local data: { [string]: { value: any, expires: number } } = {}
	local function live(key: string): any
		local entry: { value: any, expires: number }? = data[key]
		if entry and entry.expires <= os.clock() then
			data[key] = nil
			entry = nil
		end
		return if entry then copy(entry.value) else nil
	end
	return {
		name = name,
		get = function(key: string)
			return true, live(key)
		end,
		set = function(key: string, value: any, ttl: number)
			data[key] = { value = copy(value), expires = os.clock() + ttl }
			return true
		end,
		update = function(key: string, fn: (old: any) -> any, ttl: number)
			local result = fn(live(key))
			if result == nil then
				return true, nil
			end
			data[key] = { value = copy(result), expires = os.clock() + ttl }
			return true, copy(result)
		end,
		remove = function(key: string)
			data[key] = nil
			return true
		end,
		list = function(max: number?)
			local keys = {}
			for key in data do
				if live(key) ~= nil then
					table.insert(keys, key)
				end
			end
			table.sort(keys)
			local result: { Entry } = {}
			for i, key in keys do
				if max and i > max then
					break
				end
				table.insert(result, { key = key, value = live(key) })
			end
			return true, result
		end,
	}
end

------------------------------------------------------------------------------------------
-- Real MemoryStore sorted map
------------------------------------------------------------------------------------------

local function realMap(name: string): SortedMap
	local store: any = (MemoryStoreService :: any):GetSortedMap(name)
	return {
		name = name,
		get = function(key: string)
			local ok, value = attempt(name, "get", function()
				return store:GetAsync(key)
			end)
			return ok, value
		end,
		set = function(key: string, value: any, ttl: number)
			local ok = attempt(name, "set", function()
				return store:SetAsync(key, value, math.max(1, math.floor(ttl)))
			end)
			return ok
		end,
		update = function(key: string, fn: (old: any) -> any, ttl: number)
			local ok, value = attempt(name, "update", function()
				return store:UpdateAsync(key, function(old: any)
					return fn(old)
				end, math.max(1, math.floor(ttl)))
			end)
			return ok, value
		end,
		remove = function(key: string)
			local ok = attempt(name, "remove", function()
				return store:RemoveAsync(key)
			end)
			return ok
		end,
		list = function(max: number?)
			local result: { Entry } = {}
			local limit = max or PAGE * MAX_PAGES
			local lower: any = nil
			for _ = 1, MAX_PAGES do
				local count = math.min(PAGE, limit - #result)
				if count <= 0 then
					break
				end
				local ok, page = attempt(name, "list", function()
					return store:GetRangeAsync(Enum.SortDirection.Ascending, count, lower)
				end)
				if not ok or typeof(page) ~= "table" then
					return #result > 0, result
				end
				for _, item in page :: { any } do
					table.insert(result, { key = item.key, value = item.value })
				end
				if #(page :: { any }) < count then
					break
				end
				lower = { key = (page :: { any })[#(page :: { any })].key }
			end
			return true, result
		end,
	}
end

-- The map `<namespace>_<suffix>` of the current environment.
function MemoryStoreAdapter.map(suffix: string): SortedMap
	local name = EnvironmentConfig.get().MemoryStoreNamespace .. "_" .. suffix
	local existing = maps[name]
	if existing then
		return existing
	end
	local created = if EnvironmentConfig.useMockMemoryStore() then mockMap(name) else realMap(name)
	maps[name] = created
	return created
end

function MemoryStoreAdapter.newId(prefix: string): string
	return prefix .. "_" .. HttpService:GenerateGUID(false):gsub("-", ""):lower():sub(1, 20)
end

return MemoryStoreAdapter
