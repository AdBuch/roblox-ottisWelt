param([string]$LuauPath = 'luau')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = @'
local checks = 0
local function check(ok, text) assert(ok, text) checks += 1 end
local function deep(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, entry in v do out[k] = deep(entry) end
	return out
end
local names = setmetatable({}, { __index = function(_, name) return name end })
local script = { Parent = names }
local modules = {}
local function require(name) return assert(modules[name], name) end
local game = { GetService = function() return { Shared = names } end }
local maps = {}
local refuse = false
modules.MemoryStoreAdapter = {
	newId = function() return "ticket-id" end,
	map = function(name)
		maps[name] = maps[name] or {}
		local data = maps[name]
		return {
			set = function(key, value) data[key] = deep(value) return true end,
			get = function(key) return true, deep(data[key]) end,
			remove = function(key) data[key] = nil return true end,
			update = function(key, fn)
				local nextValue = fn(deep(data[key]))
				if nextValue and not refuse then data[key] = nextValue end
				return true, deep(data[key])
			end,
		}
	end,
}
'@
foreach ($entry in @('shared/PlayerDataSchema','shared/GameProtocol','shared/ExperienceConfig','shared/MatchDefinitions','shared/MatchTypes','server/MatchRecordService','server/AdmissionTicketService')) {
    $name = Split-Path -Leaf $entry
    $body = Get-Content -LiteralPath (Join-Path $repo "src/$entry.luau") -Raw
    $source += "`nmodules.$name = (function()`n$body`nend)()`n"
}
$source += @'
local protocol = modules.GameProtocol
local records = modules.MatchRecordService
local tickets = modules.AdmissionTicketService
local current = protocol.describe()
check(protocol.Version == 2 and protocol.isCompatible(2) and not protocol.isCompatible(1)
	and not protocol.isCompatible(3) and not protocol.isCompatible(2.1), "protocol range is explicit and integral")
check(protocol.canExchange(current), "equal-version Hub and Arena agree on profile writes")
local oldHub = { protocol = 1 }
check(not protocol.isRecordCompatible(oldHub), "Hub N -> Arena N+1 rejects a legacy ticket/record")
local function legacyArenaAccepts(version)
	-- Release-basis policy in GameProtocol v1, minimum 1 and maximum 1.
	return type(version) == "number" and version >= 1 and version <= 1
end
check(not legacyArenaAccepts(current.protocol), "Hub N+1 -> Arena N is rejected by the release-basis protocol gate")
local future = deep(current)
future.protocol, future.minProtocol, future.maxProtocol = 3, 2, 3
check(not protocol.canExchange(future), "protocol 2 does not speculate about future wire versions")
local oldWriter = deep(current)
oldWriter.write = 13
check(not protocol.canExchange(oldWriter), "same wire protocol does not authorize an older profile writer")
local unreadable = deep(current)
unreadable.maxRead = 13
check(not protocol.canExchange(unreadable), "a peer must be able to read this server's output")
check(not protocol.canExchange({ protocol = 2 }) and not protocol.canExchange(nil), "missing capabilities are refused")
local record = {
	matchId = "match", protocol = 2, compatibility = current, mode = "SOLO_ZOMBIES",
	privateServerId = "reserved", fighters = { { userId = 1, team = "", partyId = "" } },
	policy = "PUBLIC", createdAt = os.time(), createdBy = "test",
}
check(records.saveMatch(record), "compatible match records persist")
check(records.getMatch("match").matchId == "match", "compatible match record loads")
local oldRecord = deep(record)
oldRecord.protocol, oldRecord.compatibility = 1, nil
check(not records.saveMatch(oldRecord), "new code cannot create a legacy-protocol record")
maps.Matches.match = oldRecord
local incompatible, problem = records.getMatch("match")
check(incompatible == nil and problem == "UPDATE", "incompatible match returns an update reason")
maps.Matches.match = deep(record)
local ticket = tickets.issue("match", 1, "FIGHTER", "", "SOLO_ZOMBIES")
check(ticket and ticket.compatibility.write == 14, "tickets carry explicit profile capabilities")
local consumed, rejection = tickets.consume("match", 1, record)
check(consumed and consumed.consumed and rejection == nil, "matching ticket and record admit once")
check(select(2, tickets.consume("match", 1, record)) == "CONSUMED", "consumed ticket cannot admit twice")
ticket = tickets.issue("match", 1, "FIGHTER", "", "SOLO_ZOMBIES")
maps.Tickets["match:1"].compatibility.write = 13
check(select(2, tickets.consume("match", 1, record)) == "PROTOCOL" and not maps.Tickets["match:1"].consumed,
	"older writer ticket is refused without consumption")
ticket = tickets.issue("match", 1, "FIGHTER", "", "SOLO_ZOMBIES")
maps.Tickets["match:1"].compatibility.minRead = 1
check(select(2, tickets.consume("match", 1, record)) == "PROTOCOL", "ticket and match must carry the same contract")
ticket = tickets.issue("match", 1, "FIGHTER", "", "SOLO_ZOMBIES")
maps.Tickets["match:1"].mode = "COOP_ZOMBIES"
check(select(2, tickets.consume("match", 1, record)) == "WRONG_MATCH", "mode cannot differ from the match record")
tickets.issue("match", 1, "FIGHTER", "", "SOLO_ZOMBIES")
refuse = true
check(tickets.consume("match", 1, record) == nil and not maps.Tickets["match:1"].consumed, "a refused consume write is not admission")
check(select(2, tickets.consume("match", 1, oldRecord)) == "PROTOCOL", "an incompatible match cannot authorize a compatible ticket")
print("PASS: " .. checks .. " profile/protocol compatibility and admission checks")
'@
$path = Join-Path ([IO.Path]::GetTempPath()) ('otti-versions-' + [guid]::NewGuid() + '.luau')
try {
    [IO.File]::WriteAllText($path, $source)
    & $LuauPath $path
    if ($LASTEXITCODE -ne 0) { throw 'Version compatibility tests failed' }
} finally {
    Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
}
