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
$intro = [regex]::Match((Source 'src/server/OttiBossService.luau'), '(?ms)^local function runIntro\(.*?^end').Value
if (-not $intro) { throw 'Missing boss intro function' }
$body += @'

local Config = {}
local OttiBossConfig = { SilenceTextAt = 1, PreIntroSeconds = 2, WalkSpeedBiped = 10 }
local CrowdReactionService = { react = function() end, setBaseLight = function() end }
local Arena = { setGates = function() end }
local token, arenaFolder, boss = 1, {}, nil
local options = { companion = "Otti", participants = function() return {} end }
local rig = { companion = nil, model = { SetAttribute = function() end }, humanoid = {} }
local function takeOverSpectator() return rig end
local function introWait() return true end
local function setAttr() end
task.delay = function(_, callback) callback() end
local entrances = 0
local OttiEntranceService = { play = function() entrances += 1; return true end }
'@
$body += "`n$intro`n"
$body += @'
check(runIntro(1) and entrances == 1, "explicit Otti selection enters arena and releases spectator anchor")
options.companion, rig.companion = "Schili", "Schili"
check(runIntro(1) and entrances == 1, "companion keeps its own grounded entrance")
'@
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
'@
$playerHit = [regex]::Match((Source 'src/server/OttiBossService.luau'), '(?ms)^function OttiBossService.applyPlayerHit\(.*?^end').Value
if (-not $playerHit) { throw 'Missing boss hit handler' }
$body += @'

local OttiBossService = {}
local BossPhaseDefinitions = { Phases = { {} }, forShare = function() return { Index = 1 } end }
local OttiBossConfig = { PoiseMax = math.huge, RangedAttackerDistance = 15 }
local CombatEffects = { burst = function() end }
local Color3 = { fromRGB = function() end }
local DamageEffectsService = { hit = function() end }
local phaseChanging = false
local function publishHealth() end
local attacker = { UserId = 1 }
local impulse
local attackerRoot = { Position = 4, AssemblyMass = 2, ApplyImpulse = function(_, force) impulse = force end }
local right = setmetatable({ Dot = function(_, offset) return offset end }, { __mul = function(_, factor) return factor end })
local CombatUtil = {
    isFacing = function(_, from) return from > 0 end,
    flatDistance = function(a, b) return math.abs(a-b) end,
    flat = function(offset) return offset end,
    getLivingCharacter = function() return nil, nil, attackerRoot end,
}
local hitAttrs = { Pose = "StaffParry", PoseStart = clock }
local model = { GetAttribute = function(_, key) return hitAttrs[key] end }
local OttiAnimationService = {
    setGuard = function() end,
    setPose = function(_, pose) hitAttrs.Pose = pose end,
}
local boss = {
    companion = "Schili", phase = 1, fighting = true, model = model, guardUntil = clock + .68,
    root = { Position = 0, CFrame = { RightVector = right } }, rig = { shieldFace = { Position = 0 } },
    health = 1000, maxHealth = 1000, poise = 0, damageBy = {}, threat = {}, rangedAt = {},
    vulnerableUntil = 0,
}
'@
$body += [Environment]::NewLine + $playerHit + [Environment]::NewLine
$body += @'
local function hit(from, projectile, breaksGuard)
    return OttiBossService.applyPlayerHit(attacker, 25, from, projectile, 0, 1, breaksGuard)
end
local dealt, blocked = hit(4, false, false)
check(dealt == 25 and not blocked, "staff is vulnerable during the parry wind-up")
clock += .2
dealt, blocked = hit(-4, false, false)
check(dealt == 25 and not blocked, "staff parry does not catch rear attacks")
dealt, blocked = hit(4, false, false)
check(dealt == 0 and blocked and impulse == 22 and hitAttrs.Pose == "StaffDeflect", "staff redirects a frontal melee attacker sideways")
dealt, blocked = hit(4, false, false)
check(dealt == 25 and not blocked, "staff parry is spent after one hit")
hitAttrs.Pose, hitAttrs.PoseStart, boss.guardUntil = "StaffParry", clock - .2, clock + .4
impulse = nil
dealt, blocked = hit(4, true, false)
check(dealt == 0 and blocked and impulse == nil, "staff deflects a frontal projectile without moving its shooter")
hitAttrs.Pose, boss.inActive = "ShellRoll", true
dealt, blocked = hit(-4, false, false)
check(dealt == 10 and blocked, "rolling shell absorbs most of a rear hit")
dealt, blocked = hit(4, false, true)
check(dealt == 25 and not blocked, "guard breaker bypasses rolling shell protection")
hitAttrs.Pose, boss.inActive = "Recover", false
dealt, blocked = hit(4, false, false)
check(dealt == 25 and not blocked, "Schili is exposed again after the shell roll")
print("PASS: " .. checks .. " hero combat checks against real source")
'@
New-Item -ItemType Directory -Force (Join-Path $repo 'build') | Out-Null
$output = Join-Path $repo 'build/hero-combat-tests.luau'
[System.IO.File]::WriteAllText($output, $body, [System.Text.UTF8Encoding]::new($false))
& $LuauPath $output
if ($LASTEXITCODE -ne 0) { throw 'Hero combat regression tests failed' }
