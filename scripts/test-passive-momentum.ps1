param([string]$LuauPath = 'luau')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $repo 'src/shared/MomentumConfig.luau') -Raw
$defs = Get-Content -LiteralPath (Join-Path $repo 'src/shared/SpecialChargeDefinitions.luau') -Raw
$service = Get-Content -LiteralPath (Join-Path $repo 'src/server/MomentumService.luau') -Raw
$ui = Get-Content -LiteralPath (Join-Path $repo 'src/shared/UiConfig.luau') -Raw
$harness = @'
local checks = 0
local function check(ok, label)
	assert(ok, label)
	checks += 1
end
local now = 0
local os = { clock = function() return now end }
local threads = {}
local task = {
	wait = function() coroutine.yield() end,
	spawn = function(fn)
		local thread = coroutine.create(fn)
		table.insert(threads, thread)
		assert(coroutine.resume(thread))
	end,
}
local function signal() return { Connect = function() end } end
local humanoid = { Health = 100 }
local context = "Zombies"
local attributes = {}
local player = {
	Parent = true,
	Character = { FindFirstChildOfClass = function() return humanoid end },
	GetAttribute = function(_, key) return attributes[key] end,
	SetAttribute = function(_, key, value) attributes[key] = value end,
}
local players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return { player } end }
local shared = { Config = "Config", MomentumConfig = "MomentumConfig" }
local services = { Players = players, ReplicatedStorage = { Shared = shared } }
local game = { GetService = function(_, name) return services[name] end }
local script = { Parent = { CombatRules = "CombatRules", WeaponAttackDefinitions = "Attacks", WeaponSpecialDefinitions = "Specials" } }
local modules = {
	Config = { MomentumAttribute = "Momentum" },
	CombatRules = { getContext = function() return context end },
	Attacks = { prefixOf = function() return "Gladius" end },
	Specials = { forPrefix = function() return { Right = "I", Left = "II", Down = "III", Ultimate = "ULT" } end },
}
local require = function(key) return assert(modules[key], "unmapped require") end
local Vector2 = { new = function(x,y) return { X=x, Y=y } end }
local Color3 = { fromRGB = function(...) return {...} end, new = function(...) return {...} end }
local Enum = setmetatable({}, { __index = function() return setmetatable({}, { __index = function(_, key) return key end }) end })
'@
$harness += "`nlocal function configModule()`n$config`nend`nmodules.MomentumConfig = configModule()`n"
$harness += "`nlocal function definitionsModule()`n$defs`nend`nlocal definitions = definitionsModule()`n"
$harness += "`nlocal function serviceModule()`n$service`nend`nlocal momentum = serviceModule()`n"
$harness += "`nlocal function uiModule()`n$ui`nend`nlocal ui = uiModule()`n"
$harness += @'
local function near(actual, expected, label) check(math.abs(actual - expected) < 0.00001, label .. ": " .. tostring(actual)) end
local function tick(seconds)
	now += seconds
	for _, thread in threads do
		local ok, err = coroutine.resume(thread)
		assert(ok, err)
	end
end
momentum.init()
momentum.init()
check(#threads == 1, "initialization is idempotent")
near(momentum.get(player), 0, "initial pool")
tick(5)
near(momentum.get(player), 25, "five seconds unlock tier I")
check(momentum.trySpend(player, 25), "tier I can spend exact available energy")
near(momentum.get(player), 0, "tier I exact debit")
check(not momentum.trySpend(player, 25), "repeated request cannot overspend")
tick(20)
near(momentum.get(player), 100, "full regeneration")
tick(20)
near(momentum.get(player), 100, "energy capped; no idle decay")
check(momentum.trySpend(player, 25), "quick move at full energy")
near(momentum.get(player), 75, "quick move preserves unused energy")
check(momentum.trySpend(player, 50), "tier II debit")
near(momentum.get(player), 25, "tier II preserves remainder")
check(not momentum.trySpend(player, 75), "unaffordable tier rejected")
near(momentum.get(player), 25, "failed spend leaves energy unchanged")
for _, invalid in { -1, math.huge, 0/0 } do check(not momentum.trySpend(player, invalid), "invalid cost rejected") end
momentum.reset(player, 0)
humanoid.Health = 0
tick(10)
near(momentum.get(player), 0, "dead players do not charge")
humanoid.Health = 100
context = nil
tick(10)
near(momentum.get(player), 0, "spectators and noncombat lobby do not charge")
context = "Training"
tick(2)
near(momentum.get(player), 10, "training charges over time")
context = "PvP"
tick(3)
near(momentum.get(player), 25, "PvP uses same rate")
check(momentum.trySpend(player, 25), "pool remains valid after paused contexts")
momentum.reset(player, 24.99)
check(attributes.Momentum == 24, "UI never rounds up to an unaffordable tier")
local cases = {
	{0,0,nil,false,0}, {0,24.99,nil,false,0}, {0,25,1,false,25},
	{0,100,1,false,25}, {0.49,100,1,false,25},
	{0.5,50,2,false,50}, {1.49,100,2,false,50},
	{1.5,75,3,false,75}, {1.5,100,3,false,75},
	{2.49,100,3,false,75}, {2.5,100,3,true,100},
	{2.5,99,3,false,75}, {2.5,50,2,false,50}, {2.5,25,1,false,25},
}
for i, case in cases do
	local tier, ultimate, cost = definitions.forRelease(case[1], case[2])
	check((if tier then tier.Tier else nil) == case[3], "release case "..i.." tier")
	check(ultimate == case[4], "release case "..i.." ultimate")
	check(cost == case[5], "release case "..i.." cost")
end
check(definitions.availableTier(24) == nil, "tier I locked below cost")
check(definitions.availableTier(50).Tier == 2, "availability follows stored energy")
local function distance(a,b) return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2) end
for _, positions in { ui.TouchLayoutPhone, ui.TouchLayoutTablet } do
	check(positions.Attack.X < positions.Special.X, "Attack is on screen right of Special")
	check(positions.Block.Y > positions.Attack.Y, "Block above Attack")
	check(positions.Block.Y > positions.Special.Y, "Block above Special")
	for _, pair in { {positions.Attack,positions.Special}, {positions.Attack,positions.Block}, {positions.Special,positions.Block} } do
		check(distance(pair[1],pair[2]) > ui.TouchButtonSize, "combat buttons do not overlap")
	end
end
for _, data in { {ui.TouchLayoutPhone,{X=60,Y=55},35}, {ui.TouchLayoutTablet,{X=110,Y=150},60} } do
	for _, button in { data[1].Attack, data[1].Special, data[1].Block } do
		check(distance(button,data[2]) > ui.TouchButtonSize/2+data[3], "combat button clears native jump nominal bounds")
	end
end
print("PASS: " .. checks .. " checks against actual Luau sources (mock Roblox services/clock).")
'@
$target = Join-Path ([System.IO.Path]::GetTempPath()) ("OttiMomentum-" + [guid]::NewGuid().ToString() + ".luau")
[System.IO.File]::WriteAllText($target, $harness, [System.Text.UTF8Encoding]::new($false))
try {
    & $LuauPath $target
    $testExit = $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
}
exit $testExit
