# Otti Colosseum

A multiplayer-ready Roblox arena game built with VS Code + Rojo: an underground gladiator complex,
three game modes (Solo Arena, Co-op Legions, Team Battle), eight weapons with special attacks and combos,
eight shields, six zombie types with their own AI personalities (incl. the archer **Undead Sagittarius**),
progressive zombie damage states and stylized limb loss, healing shells, **Aura Points** and a final boss:
**OTTI — CHAMPION OF THE COLOSSEUM** (Round 7).

Otti's procedural boss model (`OttiModel`) follows the Otti the Gladiator reference art.

Plain Luau (strict), no packages, no Toolbox assets, no uploaded asset IDs. Everything is generated from Parts,
built-in materials, built-in SpecialMesh shapes, ParticleEmitters and lights. The server decides every
gameplay outcome (damage, hits, combos, Aura, ownership, scores, victories, boss state, projectiles, AI).

> **One arena match per server.** While a match runs, the arena gates are closed. Everyone else can shop,
> train, visit the Zombie Archive or watch from the TRIBUNES. The code keeps per-match data in one `Match`
> record, so parallel arenas can be added later.

## Project structure

```
default.project.json                 Rojo mapping (+ Remotes, + Health override)
src/shared/   -> ReplicatedStorage.Shared
  Config                             names, tags, attributes, remotes, shells
  CombatConfig                       player/crowd/shield/parry/combo tuning, rate limits, feedback kinds
  GameStates                         player + match states (LOBBY … CLEANUP)
  GameModeDefinitions                Solo / Co-op / Team Battle rules
  WeaponDefinitions                  8 weapons (instant basic attack + aerial attack each)
  ShieldDefinitions                  8 shields (reduction, angle, speed, raise time, bash, arrows)
  SpecialMoveDefinitions             every basic, aerial and combination move as data (nothing charged)
  ComboDefinitions                   5 shared A/B/J patterns + 2 named combos per weapon
  InputDefinitions / PvPBalanceConfig   combo buffer timing, input mapping / PvP caps for combos and aerials
  OttiEntranceConfig                 imperial box behaviour and the jump into the arena
  ZombieDefinitions                  6 zombie types (stats, Aura, availability, weights, looks)
  ZombieAIProfiles                   6 AI personalities + Wounded/Critical behaviour modifiers
  RoundDefinitions                   round sizes per mode, weighted variant picking, archer caps, Round 7
  DamageEffectsConfig                stylized blood/sparks switches, condition thresholds, limb-loss chances
  ProjectileDefinitions              player bow range + falloff, enemy arrows, arrow pool limit
  UiConfig / UiStateDefinitions / NotificationDefinitions   HUD sizes, breakpoints, limits / per-state and per-mode groups / notification priorities
  AudioConfig                        optional crowd/boss sound IDs (empty = visual fallback)
  OttiBossConfig                     Otti: health per player count, rewards, intro, speeds, safety values
  OttiMoveDefinitions                Otti's 11 attacks as data (wind-up, active, recovery, ranges, warnings)
  BossPhaseDefinitions               3 phases: names, accent colors, pacing, move weights
src/server/   -> ServerScriptService.Server
  Main.server                        builds the world, starts services
  Arena / LobbyService               Colosseum + tribunes / underground complex
  MatchService                       match state machine, Solo/Co-op/Team flow, cleanup by match id, combat rules, prompts
  PlayerMatchStateService / MatchSpawnService   authoritative per-player match state / every (re)spawn by spawn zone
  PartyService / TeamBattleService   co-op party lobby / team lobby + PvP match runtime
  WaveService                        six zombie rounds (mode-aware, simultaneous + archer caps), then Round 7
  OttiBossService                    Round 7 encounter: intro, health, phases, guard/poise, defeat
  OttiBossAI / BossAttackService     boss targeting + decisions / validated attack execution
  BossGrappleService                 grapple + safe deterministic throw, always restores control
  OttiModel / OttiTailService        procedural Otti / 6-segment Motor6D tail + validated tail volumes
  OttiAnimationService               locomotion state machine (quad/biped), published as attributes
  CrowdReactionService               animal spectators, crowd moods, optional audio, arena light
  DamageEffectsService               broadcasts validated hit effects
  ZombieDamageStateService           Healthy / Wounded / Critical looks + behaviour modifiers
  ZombieDismembermentService         stylized limb/armor loss (zombies only)
  ZombieArcherAI                     Undead Sagittarius ranged AI
  InventoryService / AuraService     Aura Points, items, purchases, migration / rewards
  EquipmentShopService / EquipmentModels   shop pedestals / procedural weapons, shields, arrows, nets
  PlayerCombatService                hands, blocking/parry, incoming damage, action requests
  SpecialMoveService                 move execution (melee steps, projectiles, aerials, arrow rain)
  ComboValidationService / JumpAttackService   server combo buffer / server-side jump detection, one aerial per jump
  OttiSpectatorService / OttiEntranceService   Otti in the imperial box / his jump into the arena
  CombatTargets / CombatRules        hittable targets (zombies, Otti, enemies, dummies) / who may hit whom
  ProjectileService / CombatEffects  server-simulated player + enemy arrows / sparkles, glows, rings, nets, markers
  ZombieService / ZombieFactory      shared zombie AI / zombie models
  ZombieThreatService / ZombieCrowdService   threat + target distribution / melee slots, 4-attacker cap
  ZombieDisplayService               ZOMBIE ARCHIVE cages
  TrainingService                    training dummies
  ShellService / VictoryService      healing shells / fireworks
  ArenaSafetyService                 out-of-bounds safety (players, zombies, Otti)
src/client/   -> StarterPlayer.StarterPlayerScripts.Client
  Main.client                        wiring: feedback, attributes, input -> HUD
  ResponsiveHudController            the one HUD: layout/scale, compact health, round line, hints, hit flash
  HudVisibilityController / HudStateController   Full/Minimal/Hidden modes / UI state per situation
  NotificationController             single notification queue + short banners (pooled)
  ContextHealthController            contextual world-space health bars (pooled BillboardGuis)
  TeamStatusController               team score + time, co-op teammate strip, lobby rosters
  AuraDisplayController              lobby Aura counter, +n rewards in combat
  MobileControlsController           touch buttons around the jump button, desktop special cards
  InfoPanelController / SpectatorController   optional i panel / tribune watching bar
  InputController                    mouse/keyboard, gamepad and touch input (Attack, Block, Jump, Execute)
  ComboFeedbackController            tiny input chips, COMBO TRAINING board
  PlayerAnimator                     procedural whole-body attack motion (additive, replaceable)
  OttiEntranceController             local camera for the entrance, landing shake, skip
  ShopController                     per-player shop plaques, prompt text, equipped outline
  EffectsController                  damage numbers, dash/lunge/knockback on your own character
  ZombieAnimator                     client walk cycle for arena zombies (limp, crawl)
  OttiAnimator                       procedural Otti animation (gaits, stance changes, tail, attack poses)
  BossHudController                  slim Otti bar, phase, short warnings, skip intro
  DamageEffectsController            stylized hit particles, directional hit indicator
  CrowdEffectsController             spectator animation, crowd texts, arena light
  BowController                      subtle crosshair while the Hunter Bow is equipped
src/character/ -> StarterCharacterScripts
  Health.server                      empty override: no automatic health regeneration
```

Remotes: `CombatAction` (client → server: action + aim point), `ShieldBlock` (client → server: true/false),
`CombatFeedback` (server → client: HUD messages, hit effects, knockdowns). `CombatAction` also carries
`"SkipIntro"` (only accepted once every participant has seen the boss intro this session). Both client remotes are rate-limited (10/s per player).
Lobby interactions use server-side ProximityPrompts.

## Start Rojo and connect Studio

```bash
rojo serve
```

Then in Studio: Plugins → **Rojo** → **Connect**, **View → Output**, **Shift+F5**, **F5**.
For multiplayer tests: **Test → Clients and Servers → Local Server** with 2 or more players.

## Controls

| | Keyboard & mouse | Gamepad | Touch |
|---|---|---|---|
| Basic attack | Left click | R2 | ATK |
| Block / parry (hold) | Right click | L2 | BLOCK |
| Jump (also the combo input J) | Space | A | Roblox jump button |
| Aerial attack | Space, then left click | A, then R2 | jump, then ATK |
| Execute combo | Enter | Y | COMBO |
| Interact (shop, doors, posts) | **F** | D-pad up | tap prompt |
| HUD mode (Full / Minimal / Hidden) | **H** or eye button | eye button | eye button |
| Info panel | i button | i button | i button |

A **block tap** (press and release) also counts as the combo input **B**; holding Block keeps defending. Nothing is
charged: every attack starts when its input arrives. Interactions use **F**.

## HUD (responsive, mobile first)

One HUD (`ResponsiveHudController`) replaces the old desktop panels. The upper-left corner and the
centre of the screen stay free; everything is small, anchored to an edge and scaled per device
(`UiConfig`, `ScreenInsets = CoreUISafeInsets` keeps it below Roblox's top bar and notches).

| Device class | Rule | Scale |
|---|---|---|
| Phone | touch and the shortest side < 500 px | 0.80 portrait / 0.85 landscape |
| Tablet | touch and larger | 1.0 |
| Desktop | mouse/keyboard | 1.0 × viewport height / 900 (0.85-1.25) |
| Console | ten-foot interface / gamepad | 1.15 |

- **Health:** heart + slim bar bottom-left (phones: above the thumbstick, 25 % of the width; the
  `82 / 120` number disappears below 400 px width); green → amber → red, pulse on damage, glow on heal.
  Below 25 % it stays visible in every HUD mode.
- **Enemy health:** world-space bars only when relevant (you hit it, it hit you, you aim at it, or a zombie
  is very close); gone ~3 s after the last interaction and immediately on death; never through walls; at most
  4 bars on phones and 8 on desktop, nearest relevant first; zombie names are omitted on phones.
- **Team Battle:** `RED 8 — 6 BLUE   04:12` capsule at the top; teammates get a bar with a team-coloured
  outline and short name; opponents only after a hit either way or while aimed at.
- **Co-op:** collapsible teammate strip on the left edge (initial, tiny bar, ✕ when down, red pulse below 25 %).
- **Round line:** one slim line at the top (`ROUND 4 / 7   •   7 LEFT`), shown for a few seconds on every
  change; short `ROUND 4` / `ROUND COMPLETE` / countdown banners in the upper third.
- **Otti:** slim bar at the top (~60 % width on phones, 45 % on desktop): `OTTI` and `P1`-`P3`; short
  warnings `JUMP!`, `TAIL SLAM!`, `GRAPPLE!` right below it; `CHAMPION OF THE COLOSSEUM` only in the intro.
- **Aura:** orb + number top-right in the lobby (and so while shopping); in combat only short `+10`
  notifications with the orb (rapid rewards merged); the results banner shows the match total.
- **Notifications:** one queue, at most 3 small messages; priorities Critical > Result > Round > Heal > Aura > Info.
- **Controls:** touch ATK / BLOCK / two specials in an arc around Roblox's jump button (50-56 px, cooldown
  overlay); desktop special cards bottom-right; a one-line control hint in the lobby that fades once you fight.
- **HUD modes** (👁 button on the right edge, **H** on keyboard, remembered for the session):
  **Full** everything relevant · **Minimal** health, controls, boss bar, team score, critical warnings ·
  **Hidden** only touch combat buttons, critical/low-health warnings, results, respawn info and prompts.
- **Info panel** (`i` button): mode, full controls, weapon, shield, specials, combos, round details, rosters,
  Aura rewards; scrolls; closes with ✕ or a tap outside; closes itself when a phone enters combat.
- **States:** Lobby (Aura, hints, rosters) · Solo / Co-op (health, round line, context bars, strip) ·
  Team Battle (score + time, context bars) · Boss (Otti bar, warnings) · Spectator (watched player, ◀ ▶, EXIT) ·
  Results (summary banner).


## The basement (lobby)

About twice the old lobby, with wide open floors: arrival hall with the welcome board (spawn), **WEAPONS** wall (west),
**SHIELDS** wall (south), mode area (north) with **SOLO ARENA**, **CO-OP LEGIONS** and **TEAM BATTLE** gates,
**ZOMBIE ARCHIVE** gallery (east annex), **TRAINING** yard (south-west), **TRIBUNES** door (east), a barred prison
corridor and storage corners. The lobby is a safe zone: no damage, no PvP. Attacks only hit the training dummies.

## Game modes

| Mode | Players | Rules |
|---|---|---|
| **Solo Arena** | 1 | Rounds 1, 2, 4, 8, 16, 32 zombies, then **Round 7: Otti** (1,200 HP, +500 Aura). Death ends the run. 8 shells. |
| **Co-op Legions** | 1-4 | Base rounds 2, 4, 8, 12, 20, 32 × 0.75 / 1.0 / 1.25 / 1.5 (1-4 players, rounded up), max 48 active at once. Shared rounds; the dead wait on the tribune and return with 60 % health after a completed round; a full wipe ends the run. Killer +100 %, assists +30 % of the zombie's Aura (once per player per zombie). 4 + 2 per player shells (max 12). **Round 7: Otti** (1,200 / 1,850 / 2,450 / 3,000 HP for 1-4 players): +400 Aura per survivor, +250 for defeated players who damaged him. |
| **Team Battle** | 1v1 - 4v4 | Red vs Blue, no zombies, no friendly fire, respawn after 4 s at the team spawn with 2 s protection. First to 20 eliminations, or more eliminations after 8 minutes; a tie goes to sudden death. Winners +80 Aura, losers +25. Shells off by default (`ShellsEnabled`). |

**Co-op lobby:** hold F at **JOIN / LEAVE PARTY**, then **READY** (needs a valid loadout). The leader (★) holds F at
**START**. Only ready members fight. The roster shows on the board and in the right-side panel.

**Team lobby:** hold F on the **RED** or **BLUE** pad (max 4 each), then **READY**. **AUTO BALANCE** evens the teams,
**LEAVE TEAM** leaves. With at least one ready player per team, a 15 s countdown starts; it cancels if that stops being true.

**Team Battle / one-versus-one start (one authoritative lifecycle, also for 1v1):** the ready players are taken out of
the lobby lists atomically → one match id → `CurrentMatchId`, `CurrentGameMode`, `SelectedTeam`, `ExpectedSpawnZone`
(`RED_TEAM` / `BLUE_TEAM`) → `COUNTDOWN` → everyone stands at their protected team spawn behind closed barriers → 5 s
arena countdown → `MATCH_ACTIVE`, barriers open. A defeated player respawns after 4 s at their own team spawn
(equipment restored, 2 s visible protection, no attacks meanwhile) and keeps match id, score and stats. Players only
return to the lobby after the result, when leaving or on cancellation; a delayed cleanup only touches players who still
belong to the match id that scheduled it.

## Weapons (8)

| Weapon | Price | Basic (instant) | Aerial (Jump → Attack) | Combo moves |
|---|---|---|---|---|
| Rusty Gladius | free | 18 dmg, 0.55 s, 7 | FALLING SLASH (24, short recovery) | REBELLION COMBO · SAND VIPER |
| Legion Sword | 80 | 28, 0.65 s, 7.5 | EAGLE DESCENT (34 + small shockwave) | LEGION'S FURY · EAGLE OF ROME |
| Hunter Bow | 130 | arrow 24, 0.9 s, 150 (145 studs/s) | AIR SHOT (22, less accurate) | ARROW RAIN · EAGLE SHOT |
| Gladiator Morning Star | 190 | 40, 1.15 s, 8, wide | FALLING COMET (48 + impact, long recovery) | CHAIN TEMPEST · FALLING METEOR |
| Gladiator Trident | 260 | 24, 0.75 s, 10 | DIVING TRIDENT (30, reach 11) | RETIARIUS FURY · SEA EAGLE DIVE |
| Hoplite Spear | 300 | 27, 0.85 s, 12 | SKY SPEAR (38, narrow) | PHALANX BREAKER · SPARTAN VAULT |
| Twin Arena Daggers | 340 | 14, 0.35 s, 5.5 | OTTER DIVE (2 × 12) | VIPER DANCE · RIVER SHADOW |
| Arena Battle Axe | 380 | 44, 1.3 s, 8 | ARENA CRASH (52 + shockwave, punishable) | COLOSSEUM BREAKER · THUNDER OF MARS |

An aerial attack needs a real jump (the server checks the character, not the client), works once per jump, starts
within 1.2 s of leaving the ground, descends at a fixed speed (no flying, no repeated acceleration) and ends with a
landing recovery based on the weapon's weight. Attacks use the whole body (torso twist, shoulders, steps, follow-through,
weapon trails, sand on strong landings) through a procedural animation layer that authored animations can replace later.

**Twin Arena Daggers are two-handed:** no shield, a second dagger in the left hand and a built-in **parry**
(block button: 0.4 s window, −70 % damage, 1.2 s cooldown). The shop plaque and HUD say so.

**Hunter Bow:** arrows fly 145 studs/s up to 150 studs (server-simulated, never through walls); damage 100 % up to
100 studs, 90 % to 125, 75 % to 150. A short fixed draw, no holding, consistent arrow power; a subtle crosshair shows
while the bow is equipped (no aim assistance). Its special shots come from combos (ARROW RAIN, EAGLE SHOT).

## Combos (Attack A · Block tap B · Jump J, then Execute)

Tap the inputs, then press **Enter** (gamepad **Y**, touch **COMBO**). Gaps of at most 0.65 s, the whole sequence within
2.8 s, at most 6 inputs. No match: a tiny `NO COMBO`, nothing else happens. On cooldown: `NOT READY`. Basic attacks never
need a combo.

| Pattern | Shared move (any weapon) | Weapon moves (replace the shared one) |
|---|---|---|
| B → A → B → A | COUNTER COMBINATION (0.35 s counter window, 3 strikes) | Gladius REBELLION COMBO · Trident RETIARIUS FURY · Axe COLOSSEUM BREAKER |
| A → A → J → A | JUMP FINISHER (aerial finisher, small shockwave) | Gladius SAND VIPER · Trident SEA EAGLE DIVE · Axe THUNDER OF MARS |
| B → B → A | GUARD BREAK (breaks a raised guard, heavy stagger) | Spear PHALANX BREAKER |
| A → B → A → A | ARENA SPIN (two full spins, up to 4 zombies / 2 players) | Legion LEGION'S FURY · Morning Star CHAIN TEMPEST · Daggers VIPER DANCE |
| B → J → A | RISING ATTACK (rising strike + landing) | Legion EAGLE OF ROME · Morning Star FALLING METEOR · Daggers RIVER SHADOW |
| B → A → A | – | Bow ARROW RAIN (marked circle, arrows from above, roofs protect) |
| A → J → A | – | Bow EAGLE SHOT (jump + fast accurate arrow) · Spear SPARTAN VAULT |

**Server validation:** only accepted inputs are recorded with server time (A = attack request, B = block press,
J = jump request that the server confirms as a real jump). Execute checks the timing, the equipped weapon, the cooldown
(it starts when the move executes), alive / not knocked down / not spawn-protected; every hit phase checks a legal target
(opponent team, never teammates, spectators or lobby players), range, arc and line of sight, once per target per phase.
The buffer clears after Execute, on death, knockdown, leaving combat and weapon changes.

**PvP balance** (`PvPBalanceConfig`): per-move PvP multipliers (0.35-0.75) and target caps, no single hit above 45 % and
no whole combo or aerial move above 50 % of a player's max health, knockdowns capped, no repeated combo stagger within
2.5 s, guard breaks drop the shield for 1.2 s (half protection) instead of ignoring it, counter windows only for the
first 0.3-0.35 s.

**Training:** the COMBO TRAINING board in the training yard lists the equipped weapon's moves; hits on the dummies show
`COMBO SUCCESS · name`; no Aura there.

## Shields (8)

| Shield | Price | Block | Arrows | Angle | Move while blocking | Raise |
|---|---|---|---|---|---|---|
| Wooden Buckler | free | 50 % | 50 % | 60° | 100 % | 0.10 s |
| Legion Shield | 60 | 65 % | 60 % | 60° | 100 % | 0.12 s |
| Arena Tower Shield | 120 | 78 % | 85 % | 70° | 80 % | 0.20 s |
| Parma Equestris | 180 | 60 % | 60 % | 53° | 110 % | 0.05 s |
| Champion Shield | 200 | 88 % | 80 % | 60° | 100 % | 0.15 s (×2 stagger) |
| Scutum | 250 | 82 % | 95 % | 76° | 75 % | 0.20 s |
| Hoplon | 280 | 72 % | 75 % | 66° | 85 % | 0.15 s (strongest bash) |
| Thraex Shield | 320 | 84 % | 80 % | 49° | 115 % | 0.04 s |

## Zombies and their AI personalities

| Type | HP | Dmg | Aura | From | Weight | Reach | Personality |
|---|---|---|---|---|---|---|---|
| Legion Remnant | 60 | 10 | 10 | 1 | 40 | 8 | **Disciplined**: direct approach, nearest player, occasionally raises its shield, keeps formation |
| Rotten Velite | 40 | 7 | 8 | 2 | 25 | 11 (spear) | **Skirmisher**: circles and changes direction, hunts low-health/exposed players, retreats after attacking, goes around big raised shields |
| Arena Brute | 100 | 18 | 18 | 3 | 17 | 9 | **Tank**: prefers nearby damage dealers, roars before heavy hits, its attacks ignore half of a shield's protection |
| Zombie Retiarius | 55 | 8 | 14 | 3 | 13 | 8 (net 16) | **Controller**: keeps medium distance until its net is used (slows moving players 25 % for 2 s), steps aside for brutes/champions |
| Arena Champion | 130 | 15 | 25 | 4 | 5 | 9 | **Elite**: glowing guard blocks frontal hits (side/rear and arrows from the side get through), picks dangerous or well-equipped players, shield-bashes blockers, is exposed after a missed attack |
| **Undead Sagittarius** | 45 | 8 (bow) / 5 (strike) | 12 | 3 | 10 | 140 detect | **Marksman**: keeps 55-85 studs, seeks firing spots with a clear line of sight near the arena edge and away from melee crowds, relocates when a player comes closer than 25 studs, draws its bow visibly (glow + aim line) before every shot (about 2.2 s cooldown), leads moving targets only slightly, can miss, strikes weakly when cornered and then retreats |

All six run on **one** shared AI with per-type profiles (`ZombieAIProfiles`); the archer adds a ranged layer
(`ZombieArcherAI`). Detection: 90 studs for melee zombies, 140 for archers. Melee reach (above) matches the visible
weapons (the spear is longer now), and long weapons stop farther out on the crowd ring.

**Archers:** at most 3 / 4 / 5 / 6 alive for 1-4 players; only a few may draw at the same time; each prefers players
other archers aren't already aiming at. Arrows are server-simulated (95 studs/s, orange trail), stop at walls, gates,
floor and the barrier, never hit lobby players or spectators, can be blocked by a facing shield (its arrow protection),
and deal no damage if the archer died while they were in flight. At most 60 arrows exist at once.

**Multiplayer target distribution:** each zombie scores every living arena fighter: threat (damage dealt to it, blocks,
nearby healing; decays over time), proximity, missing health, movement, gear value and exposure, weighted by its
personality. Players already chased by more than their fair share (living zombies ÷ living players) score lower, and the
current target gets a small bonus. Targets are re-evaluated about every 1.2 s, not every frame.

**Crowd and separation:** each player has 10 melee slots and at most 4 attackers at once. The others circle, wait or
pick another player. Solid torso-sized collision (`Zombies` group), separation steering, spawn spacing over 7 gates,
stuck detection, staggered AI ticks and a global pathfinding budget (12 requests/s) keep 48 zombies stable.
Corpses stop colliding immediately.

### Zombie condition states

| State | Health | Looks | Behaviour (per type) |
|---|---|---|---|
| Healthy | > 65 % | normal | normal |
| Wounded | 65-30 % | darker skin, scratches, torn cloth, scarf/strips/discs gone, hunched | Legion blocks less + attacks more · Velite more aggressive · Brute enraged (faster attacks) · Retiarius nets sooner · Champion bashes more · Archer fires faster, less accurately |
| Critical | < 30 % | heavy cracks, crest/cheek guard/greave gone, limp (client), leaning | Legion slower, desperate combos · Velite fast bursts, long rests · Brute much slower, last heavy swings · Retiarius retreats, avoids fighting · Champion loses its guard, aggressive combos · Archer slow, inaccurate, may strike up close |

Nothing is rebuilt: prepared detail parts are shown and a few pieces are hidden (`ZombieDamageStateService`).

### Stylized limb loss (zombies only)

Strong hits a zombie survives may remove a **weapon arm, shield arm, leg, helmet or shoulder armor**
(`ZombieDismembermentService`). Chance = weapon (Battle Axe 50 %, Morning Star 45 %, Legion Sword 28 %, Gladius 22 %,
Trident/Spear 20 %, Daggers 6 %, Bow 5 %) × 1.5 for specials × hit strength (18+ damage) × remaining health. Projectiles
use the impact height (head → helmet, low → leg), melee the attacker's side; spinning attacks favour legs. Never the head,
never both legs, at most 2 limbs. The removed part falls as a harmless, non-colliding, anchored copy that fades after 5 s;
a dark cap covers the joint (no anatomy). Consequences: **no weapon arm** → weak bites/kicks (55 % damage, shorter
reach); **no shield arm** → no guard, no shield bash, no net; **lost leg** → 45 % speed, crawling pose, shorter reach;
**lost armor** → +15 % damage taken per piece (max +30 %). Aura is still paid exactly once per zombie.

## Round 7: OTTI — CHAMPION OF THE COLOSSEUM

After the last Round 6 zombie, corpses and projectiles are cleared and the dead co-op players return (a round was
completed). About 6 s of silence follow: the arena darkens slightly, every portcullis drops and the crowd falls silent
(`THE CROWD FALLS SILENT...`). Then the **same model** that watched from the imperial box becomes the boss: Otti stands
up, draws his gladius, climbs onto the railing, the crowd goes quiet, and he jumps into the arena on a deterministic
bezier arc (anchored, server-driven, fixed landing point inside the arena): sand ring, warm light pulse, cheer, a short
distance-based camera shake. No damage either way until his landing recovery ends; then the boss bar appears and the
fight starts. Every client's camera looks up at the box and follows the leap; after seeing it once per session a small
**SKIP** button returns the camera at once (the server entrance always plays). Otti remembers combos a player repeats and
sometimes raises his shield against them, and takes extra damage while recovering from a missed grapple or a tail slam.

**During the zombie rounds (`OTTI_SPECTATING`)** Otti sits in the **imperial box** above the north side (stone
balustrade, columns with bronze capitals, red canopy with gold fringe, banners, cushioned stone throne; players can't
enter it). He sits like an otter, tail beside the throne, gladius sheathed, follows the fighting with his head, leans in
now and then and gets impatient in the late rounds. With a cooldown he reacts only to meaningful moments: combos (leans
forward), named weapon combos (strikes the railing or raises a paw), big aerial finishers (stands up briefly), heavy hits
on players (surprised), completed rounds (claps), player defeats (sits back). No AI, can't be targeted, never blocks
projectiles, never a zombie.

Otti is a living otter, not a zombie: own tag `OttiBoss`, no zombie tags, damage states,
limb loss or archive logic, no blood (sparks and sand only).

**Health:** 1,200 (solo) · 1,850 / 2,450 / 3,000 for 2-4 co-op players. His damage never scales with players.

| Phase | Health | Behaviour |
|---|---|---|
| 1 ARENA DUEL (gold) | 100-70 % | mostly two legs, sword and shield, measured circling, studies new targets, raises his shield against predictable frontal attacks, basic tail sweep |
| 2 RIVER FURY (blue) | 70-35 % | switches between four and two legs, circles, tail trips, bite (→ throw), River Dash, tail slam, harder to surround |
| 3 CHAMPION UNLEASHED (red) | < 35 % | shorter pauses, shield bash → tail sweep, shield-and-tail counter, battle cries, more slams; still telegraphed, never immune |

Phase changes: Otti strikes his shield, sand bursts outward, the crowd reacts, the boss bar changes its accent color
(he takes half damage during the 2 s show). Heavy or repeated hits break his poise: a short stagger, every third break
within 25 s a knockdown (never during an attack's active window or a grapple).

| Attack | Damage | Telegraph / rules |
|---|---|---|
| Gladius Slash | 14 | 0.45 s wind-up (glow); 7.5 studs; blockable |
| Gladiator Combination | 8 → 10 → 14 | shield feint, horizontal slash, backhand, thrust (9.5 studs); each step validated once |
| Shield Bash | 8 | short range, strong push (also through a block) + 0.6 s stagger; never out of the arena |
| Broad Tail Sweep | 12 | crouch, look over the shoulder, tail pulled aside, sand stirs, ring; **TAIL SWEEP — JUMP!**; 360°, 10.5 studs, several players once each; jump over it; a shield reduces damage but not the push |
| Tail Trip | 6 | low 220° sweep; **TAIL TRIP — JUMP!**; at most 1 s controlled knockdown + recovery protection |
| Tail Slam | 20 / 10 | tail rises over his head, red + orange ground markers; **TAIL SLAM — MOVE!**; shockwave falls off with distance, cover blocks it |
| Otter Bite | 16 | drops low, head back, short lunge (not through walls); a facing shield stops it completely; a miss leaves him open |
| Grapple and Arena Throw | 18 | paws open, growl, glow; **GRAPPLE — DODGE!**; see below |
| River Dash | 8 | curved four-legged run behind/beside a player; contact damage only while dashing; often followed by a tail trip |
| Shield-and-Tail Counter | 11 | Phase 3: a blocked frontal hit → quick 200° tail sweep (9 s cooldown) |
| Battle Cry | – | Phase 3, occasional; crowd cheers |

**Tail rig and validated tail hitboxes:** the tail is six Motor6D segments (thick → thin, slightly flattened) chained
from the pelvis; it never collides, can't detach and never deals damage by touch. Tail attacks are checked on the server
every step: during a sweep the body turns, and the tail volume is the sector swept behind Otti between two server steps
(radius 10.5, angular margin for body width); players whose root is 1.8+ studs above standing height (jumping) are
skipped. The client animator plays the same timeline, so what you see is what is validated.

**Grapple and throw:** validated grab (range, facing, line of sight) → movement locked → Otti turns to a safe landing
spot (at least 9 studs inside the wall, on the sand, nothing solid in between, no other player within 7 studs) →
deterministic arc (max 7 studs high, 13-20 studs far) → landing: 18 damage once, 0.8 s knockdown, 1.5 s immunity,
crowd roar + `WHAT A THROW!` + brief light boost (once). Control is restored on every path (success, dodge, Otti
defeated, player died/left, cleanup) and after a 4 s safety timeout. If no safe spot exists, Otti lets go.

**Targeting (1-4 players):** recent damage to Otti, distance, healing nearby, attacking from range (over 22 studs or
arrows), minus a penalty for having just been attacked by him and for being focused for more than 7 s. Grapples never
pick the same player twice in a row when others are available; when two or more players surround him he prefers a tail
sweep or a River Dash out. Sword attacks hit only their target; tail attacks can hit several players once each.

**Defeat:** at 0 health all attacks stop, a held player is released, Otti drops his sword, sits back on his tail and
raises a paw: `OTTI DEFEATED` / `CHAMPION OF THE COLOSSEUM`, fireworks, the crowd celebrates. Rewards are paid once:
solo 500 Aura; co-op 400 per survivor, 250 for defeated players who damaged him. After 12 s everyone returns to the lobby.

## Crowd, audio and damage effects

- **Crowd** (`CrowdReactionService`): about 70 animal spectators (otters, mice, rabbits, squirrels) in the upper stands
  react: silent before the boss, cheering when he enters, a louder roar after a throw, a gasp after a heavy hit on a
  player, celebration after his defeat.
- **Audio** (`AudioConfig`): crowd and battle-cry IDs are empty by default; put only Roblox-owned, project-owned or
  licensed IDs there. Without them everything still works (visual crowd + HUD), with one warning in Studio.
- **Damage effects** (`DamageEffectsConfig`): `BloodEnabled`, `ReducedEffectsMode`, `PlayerBloodEnabled`,
  `ZombieDismembermentEnabled`. Brief dark-red particles (no pools, no wounds), sparks/dust in reduced mode and always on
  Otti. Player hits: red edge flash (never the whole screen), a directional indicator and a tiny burst. The boss HUD
  shows the active mode.

## Shells, Aura, archive and training

- **Shells:** 12 symmetric spots. Solo uses 8, Co-op 4 + 2 per player (max 12), Team Battle none by default.
  Each heals exactly **+3** (never above max, not used at full health), only for the collector, and respawns after 12 s (never right under a player).
- **Aura Points** replace coins everywhere. `AURA: n` is always shown at the top. Profiles are kept per UserId for
  the server session. Old profiles with `coins` are migrated once (`coins` is added to `auraPoints` and cleared in the same step).
- **Zombie Archive:** six barred cages with the real arena models (anchored, tagged `ZombieDisplay`, never targets, no AI)
  and a plaque each: name, role, health, damage, ability, reward and first round. Otti is not in the archive.
- **Training yard:** two straw dummies with damage numbers. Specials and combos work, there's no Aura or eliminations, and they refill after 3 s.

## Studio test steps

**Solo**
1. F5. You spawn in the arrival hall: the Aura orb top-right shows 0, Rusty Gladius + Wooden Buckler in your hands, touch: ATK, BLOCK and COMBO around the jump button.
2. Walk to the TRAINING yard (south-west), hit a dummy, then try Basic → Basic → Q: you should see a short `GLADIATOR'S POINT!` notification.
3. Visit the ZOMBIE ARCHIVE (east): 6 caged zombies with plaques; the Undead Sagittarius draws its bow at you.
4. Hold F at the SOLO ARENA gate (north-west). GET READY, then ROUND 1 / 7. Kill zombies: a short `+10` with the Aura orb (no permanent counter in combat).
5. Die or win: you return to the lobby and keep your Aura. Buy something with F at a pedestal (e.g. Legion Sword for 80).

**Zombie damage, limbs, archers** (buy the Battle Axe or Morning Star for quick results)
1. From Round 3: hit a zombie below 65 %: darker skin, scratches, torn cloth; below 30 % it limps and hunches.
2. Use heavy specials (HEAVY CRUSH, EXECUTION ARC, WHIRLWIND): sometimes an arm, leg, helmet or shoulder plate falls off,
   fades after about 5 s and never blocks you. A zombie without its sword arm only bites; without a leg it crawls slowly.
3. Undead Sagittarius (Round 3+): it keeps its distance, glows and shows an aim line before shooting. Hide behind cover
   or block with a shield facing it; walk up to it and it backs away.
4. Hunter Bow: shoot zombies 100-150 studs away (the crosshair helps): damage drops to 90 % / 75 %. PIERCING ARROW goes
   through up to two zombies, but stops at walls, shields and Otti.

**Otti (Round 7)**: to get there quickly, temporarily set `RoundCounts` in `GameModeDefinitions.Solo` to `{ 1, 1, 1, 1, 1, 1 }`.
1. After Round 6: about 6 s pause, darker arena, portcullises drop, `THE CROWD FALLS SILENT...`.
2. The north gate opens, `OTTI` / `CHAMPION OF THE COLOSSEUM`; he walks in on all fours, rises, draws, raises his shield,
   sweeps his tail. The boss bar appears (`ROUND 7 — FINAL BOSS`, PHASE 1 · ARENA DUEL).
3. Fight: on `TAIL SWEEP — JUMP!` jump over the tail; on `TAIL SLAM — MOVE!` leave the red/orange circle; block a bite
   with your shield facing him; on `GRAPPLE — DODGE!` sidestep. If caught, you land inside the arena and can move again.
4. Watch the bar turn blue (70 %) and red (35 %) with a shield strike and a sand burst.
5. Win: Otti drops his sword and raises a paw, fireworks, `+500`, back to the lobby after 12 s.
   Start again: the intro now has a SKIP INTRO button, and no boss state is left over.

**Two-player co-op** (Test → Local Server, 2 players)
1. Both hold F at JOIN / LEAVE PARTY, then READY. The leader (★) holds F at START.
2. Round 1 has 2 zombies (2 × 100 %). Both players are targeted, damage gives assist Aura (`+3`).
3. Let one player die: they wait on the tribune and return with 72 HP after the round. If both die, the run ends.
4. Round 7: Otti has 1,850 HP and switches targets; he never grapples the same player twice in a row.

**Four-player co-op** (4 players)
1. Join, ready, start as above. Round 1 = 3 zombies (2 × 1.5), Round 6 = 48. 12 shells are active. At most 6 archers.
2. Zombies spread across all four players; no player has more than 4 attackers at once.
3. Round 7: 3,000 HP; tail sweeps can hit several players; surround him and he sweeps or dashes out.

**One-versus-one** (2 players)
1. One holds F on the RED pad, the other on BLUE. Both READY → a 15 s countdown.
2. In the arena: `RED 0 — 0 BLUE`, `TIME 08:00`. Hits work only on the opponent, with damage caps. The defeated player respawns at their team spawn after 4 s with a force field.
3. To test sudden death, temporarily set `MatchSeconds` to 30 in `GameModeDefinitions` and leave the score tied.

**Four-versus-four** (8 players)
1. 4 on each pad (a 5th is told the team is full). Try AUTO BALANCE with 5 v 3.
2. Ready up, fight: friendly fire does nothing, eliminations/assists/deaths show in the right panel and the kill feed.
3. First to 20 wins: result screen, fireworks, +80 / +25 Aura, everyone back in the lobby, and a new match can start.

## Limitations

- One arena match per server; parallel matches would need a second arena instance.
- Aura and items are session-only (no DataStore yet; `InventoryService.serialize/migrateProfile` are the hooks).
- Swings, thrusts, spins and parries move the equipment, not the player's arms (no uploaded animations).
- Otti's animation is procedural (client `OttiAnimator`); authored animations can be plugged in via `OttiBossConfig.AnimationIds`.
- Dashes, lunges, knockback and knockdowns on players are applied by the player's own client (Roblox gives it physics ownership); the server validates the hits. During Otti's throw the server anchors and moves the player itself.
- Arrows are simulated on the server and may look slightly choppy on high-latency clients.
- The arena floor is flat, so archers pick edge positions instead of elevated ones.
- Team Battle eliminations count every valid kill; Aura is only paid at the end of a match, so farming idle players gives no Aura.
- No crowd audio ships with the project (see `AudioConfig`). Balance (zombie damage, boss tuning, PvP multipliers) hasn't been play-tested yet; tune it in the shared definitions.

## Troubleshooting

- **Old modules still in Explorer** (`GameStateService`, `CoinService`, `HudController`, `WaveConfig`): disconnect and reconnect Rojo.
- **Prompts don't react to E:** interactions use **F** now (E is Special 2).
- **"Attack … rejected: …" warnings:** temporary diagnostics, switch off with `DebugRejectedAttacks = false` in `CombatConfig`.
- **Build check:** `rojo build -o OttiArena.rbxlx` must succeed.
