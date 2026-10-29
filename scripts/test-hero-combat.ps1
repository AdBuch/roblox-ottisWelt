param([string]$LuauPath = 'luau')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
function Source($path) { Get-Content -LiteralPath (Join-Path $repo $path) -Raw }
$preamble = @'
local modules = {}
local clock = 10
local os = { clock = function() return clock end }
local task = { wait = function(seconds) clock += seconds end }
local Workspace = { GetServerTimeNow = function() return clock end }
local script = { Parent = { OttiMoveDefinitions = "Moves", CompanionBossDefinitions = "Personalities", OttiModel = "Model", CombatUtil = "Util" } }
local storage = { Shared = { CompanionBossDefinitions = "Personalities", OttiBossConfig = "Config" } }
local game = { GetService = function(_, name) return if name == "Workspace" then Workspace else storage end }
local require = function(name) return modules[name] or {} end
local checks = 0
local function check(condition, name) assert(condition, name); checks += 1 end
'@
$body = $preamble
foreach ($entry in @(@('Moves','src/shared/OttiMoveDefinitions.luau'), @('Personalities','src/shared/CompanionBossDefinitions.luau'), @('Profiles','src/shared/HeroCombatDefinitions.luau'), @('AI','src/server/CompanionBossAI.luau'), @('Animation','src/server/OttiAnimationService.luau'))) {
    $body += "`nmodules.$($entry[0]) = (function()`n$(Source $entry[1])`nend)()`n"
}
$body += @'
local profiles = modules.Profiles
for _, hero in { "Kroko", "Schili" } do
    for _, role in { "Strike", "Charge", "Sweep", "Feint", "Roar" } do
        local move = profiles.move(hero, role, 2)
        check(move ~= nil and move.Id == hero .. role, hero .. role .. " unique move")
        check(move.Cooldown == modules.Personalities.get(hero).Roles[role].Cooldown, "role cooldown used")
        check(move.Stance == "Biped", "companions keep their own stance")
        check(move.WindUp >= 0.2 and move.Recovery >= 0.3, "readable attack and punish window")
        if move.Steps then
            local damage = 0
            for _, step in move.Steps do damage += step.Damage end
            check(damage > 0 and #move.Steps >= 2, "feint/combo has real follow-up damage")
        end
    end
    check(profiles.move(hero, "Guard", 1) == nil, "guard isn't a damaging attack")
end
check(profiles.move("Schili", "Sweep", 1).Kind == "Melee", "short-tailed Schili uses staff sweep")
check(profiles.move("Kroko", "Sweep", 1).Kind == "TailSweep", "long-tailed Kroko uses tail sweep")
check(profiles.move("Kroko", "Strike", 1).Steps == nil, "Kroko phase one single strike")
check(#profiles.move("Kroko", "Strike", 2).Steps == 2, "Kroko phase two adds shield follow-up")
check(modules.Moves.GladiusSlash.Id == "GladiusSlash" and modules.Moves.GladiusSlash.Steps == nil, "profiles never mutate shared Otti moves")
local attrs = {}
local boss = { model = { SetAttribute = function(_, k, v) attrs[k] = v end, GetAttribute = function(_, k) return attrs[k] end }, humanoid = { MoveTo = function() end }, root = { Position = 0 }, lockedUntil = 0, defeated = false, interrupted = true, stance = "Biped" }
modules.Animation.react(boss, "STAGGER", 0.5)
check(boss.interrupted == false and boss.loco == "BIPED_IDLE", "recovered boss can attack again")
boss.interrupted, boss.defeated = true, true
modules.Animation.react(boss, "STAGGER", 0.5)
check(boss.interrupted and boss.loco == "STAGGER", "defeated boss is never re-enabled")
local rngState = 123
local rng = { NextNumber = function() rngState = (rngState * 48271) % 2147483647; return rngState / 2147483647 end }
for _, hero in { "Kroko", "Schili" } do
    local personality = modules.Personalities.get(hero)
    local offensive = 0
    for _ = 1, 500 do
        local result = modules.AI.choose(personality, { now = 10, distance = 4, bossHealth = 1, readyAt = {}, targetAttacking = false, recentlyBlocked = false, surrounded = false }, rng)
        if result.role == "Strike" or result.role == "Feint" or result.role == "Sweep" then offensive += 1 end
    end
    check(offensive > 180, hero .. " keeps meaningful attack pressure")
    local readyAt = {}
    for role in personality.Roles do readyAt[role] = 99 end
    check(modules.AI.choose(personality, { now = 10, distance = 4, bossHealth = 1, readyAt = readyAt, targetAttacking = false, recentlyBlocked = false, surrounded = false }, rng).role == nil, "AI respects every role cooldown")
end
print("PASS: " .. checks .. " hero combat checks against real source")
'@
New-Item -ItemType Directory -Force (Join-Path $repo 'build') | Out-Null
$output = Join-Path $repo 'build/hero-combat-tests.luau'
[System.IO.File]::WriteAllText($output, $body, [System.Text.UTF8Encoding]::new($false))
& $LuauPath $output
if ($LASTEXITCODE -ne 0) { throw 'Hero combat regression tests failed' }
