# Otti Colosseum

A multiplayer-ready Roblox arena game built with VS Code + Rojo: an underground gladiator complex,
three game modes (Solo Arena, Co-op Legions, Team Battle), eight weapons with special attacks and combos,
eight shields, five zombie types with their own AI personalities, healing shells and **Aura Points**.

Plain Luau (strict), no packages, no Toolbox assets, no uploaded asset IDs. Everything is generated from Parts,
built-in materials, built-in SpecialMesh shapes, ParticleEmitters and lights. The server decides every
gameplay outcome (damage, hits, combos, Aura, ownership, scores, victories).

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
  WeaponDefinitions                  8 weapons (basic + 2 specials each)
  ShieldDefinitions                  8 shields (reduction, angle, speed, raise time, bash, arrows)
  SpecialMoveDefinitions             every basic attack and special move as data
  ComboDefinitions                   2-3 combos per weapon
  ZombieDefinitions                  5 zombie types (stats, Aura, availability, weights, looks)
  ZombieAIProfiles                   5 AI personalities for the shared zombie AI
  RoundDefinitions                   round sizes per mode, weighted variant picking
src/server/   -> ServerScriptService.Server
  Main.server                        builds the world, starts services
  Arena / LobbyService               Colosseum + tribunes / underground complex
  MatchService                       match state machine, Solo/Co-op flow, cleanup, combat rules, prompts
  PartyService / TeamBattleService   co-op party lobby / team lobby + PvP match runtime
  WaveService                        six-round zombie runs (mode-aware, simultaneous cap)
  InventoryService / AuraService     Aura Points, items, purchases, migration / rewards
  EquipmentShopService / EquipmentModels   shop pedestals / procedural weapons, shields, arrows, nets
  PlayerCombatService                hands, blocking/parry, incoming damage, action requests
  SpecialMoveService / ComboService  move execution / server-side combo recognition
  CombatTargets / CombatRules        hittable targets (zombies, enemies, dummies) / who may hit whom
  ProjectileService / CombatEffects  server-simulated arrows / sparkles, glows, rings, nets
  ZombieService / ZombieFactory      shared zombie AI / zombie models
  ZombieThreatService / ZombieCrowdService   threat + target distribution / melee slots, 4-attacker cap
  ZombieDisplayService               ZOMBIE ARCHIVE cages
  TrainingService                    training dummies
  ShellService / VictoryService      healing shells / fireworks
  ArenaSafetyService / PlayerTagService   out-of-bounds safety / overhead name + health tags
src/client/   -> StarterPlayer.StarterPlayerScripts.Client
  Main.client                        wiring, header/banners, feedback, target bar
  CombatHudController                HUD (AURA bar, specials with cooldowns, combo popup, kill feed)
  InputController                    mouse/keyboard, gamepad and touch input (incl. mobile buttons)
  PartyController                    co-op / team roster panel, Team Battle scoreboard
  ShopController                     per-player shop plaques, prompt text, equipped outline
  EffectsController                  damage numbers, dash/lunge/knockback on your own character
  ZombieAnimator                     client walk cycle for arena zombies
src/character/ -> StarterCharacterScripts
  Health.server                      empty override: no automatic health regeneration
```

Remotes: `CombatAction` (client → server: action + aim point), `ShieldBlock` (client → server: true/false),
`CombatFeedback` (server → client: HUD messages). Both client remotes are rate-limited (10/s per player).
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
| Basic attack | Left click | R2 | ATTACK |
| Block / parry (hold) | Right click | L2 | BLOCK |
| Special 1 | Q | X | SPECIAL 1 card |
| Special 2 | E | Y | SPECIAL 2 card |
| Interact (shop, doors, posts) | **F** | D-pad up | tap prompt |

The HUD shows the detected control scheme. Interactions use **F** because Q and E are special attacks.

## The basement (lobby)

About twice the old lobby, with wide open floors: arrival hall with the welcome board (spawn), **WEAPONS** wall (west),
**SHIELDS** wall (south), mode area (north) with **SOLO ARENA**, **CO-OP LEGIONS** and **TEAM BATTLE** gates,
**ZOMBIE ARCHIVE** gallery (east annex), **TRAINING** yard (south-west), **TRIBUNES** door (east), a barred prison
corridor and storage corners. The lobby is a safe zone: no damage, no PvP. Attacks only hit the training dummies.

## Game modes

| Mode | Players | Rules |
|---|---|---|
| **Solo Arena** | 1 | Rounds 1, 2, 4, 8, 16, 32 zombies. Death ends the run. 8 shells. |
| **Co-op Legions** | 1-4 | Base rounds 2, 4, 8, 12, 20, 32 × 0.75 / 1.0 / 1.25 / 1.5 (1-4 players, rounded up), max 48 active at once. Shared rounds; the dead wait on the tribune and return with 60 % health after a completed round; a full wipe ends the run. Killer +100 %, assists +30 % of the zombie's Aura (once per player per zombie). 4 + 2 per player shells (max 12). |
| **Team Battle** | 1v1 - 4v4 | Red vs Blue, no zombies, no friendly fire, respawn after 4 s at the team spawn with 2 s protection. First to 20 eliminations, or more eliminations after 8 minutes; a tie goes to sudden death. Winners +80 Aura, losers +25. Shells off by default (`ShellsEnabled`). |

**Co-op lobby:** hold F at **JOIN / LEAVE PARTY**, then **READY** (needs a valid loadout). The leader (★) holds F at
**START**. Only ready members fight. The roster shows on the board and in the right-side panel.

**Team lobby:** hold F on the **RED** or **BLUE** pad (max 4 each), then **READY**. **AUTO BALANCE** evens the teams,
**LEAVE TEAM** leaves. With at least one ready player per team, a 15 s countdown starts; it cancels if that stops being true.

## Weapons (8)

| Weapon | Price | Basic | Special 1 (Q) | Special 2 (E) |
|---|---|---|---|---|
| Rusty Gladius | free | 18 dmg, 0.55 s, 7 | QUICK THRUST (22, lunge, 4 s) | SHIELD COUNTER (16 + shield bash, 7 s) |
| Legion Sword | 80 | 28, 0.65 s, 7.5 | LEGION COMBO (3 strikes, 6 s) | RISING SLASH (34, big stagger, 8 s) |
| Hunter Bow | 130 | arrow 24, 0.9 s, 90 | TRIPLE SHOT (3 × 16, 7 s) | PIERCING ARROW (34, pierces 3, 9 s) |
| Gladiator Morning Star | 190 | 40, 1.15 s, 8, wide | HEAVY CRUSH (55, 9 s) | CHAIN SWEEP (30, up to 3, 11 s) |
| Gladiator Trident | 260 | 24, 0.75 s, 10 | TRIDENT RUSH (2 thrusts, 2nd ×1.25, lunge, 6 s) | NET AND STRIKE (net slow + auto thrust 26, 11 s) |
| Hoplite Spear | 300 | 27, 0.85 s, 12 | PHALANX THRUST (36, big knockback, 7 s) | SPEAR SWEEP (22, up to 3 / 2 PvP, 12 s) |
| Twin Arena Daggers | 340 | 14, 0.35 s, 5.5 | VIPER FLURRY (4 strikes while a target stays near, 8 s) | SHADOW STEP (dash, never through walls, + 24, 10 s) |
| Arena Battle Axe | 380 | 44, 1.3 s, 8 | EXECUTION ARC (50, ×2 vs zombies under 30 %, 9 s) | WHIRLWIND (32, up to 4 / 3 PvP at 40 %, 14 s) |

**Twin Arena Daggers are two-handed:** no shield, a second dagger in the left hand and a built-in **parry**
(block button: 0.4 s window, −70 % damage, 1.2 s cooldown). The shop plaque and HUD say so.

**PvP balance:** every move has its own PvP multiplier (0.4-0.75) and target cap, and no single PvP hit removes more
than 45 % of max health, so nothing one-shots a full-health player. Slow moves have long, glowing wind-ups.

## Combos (input window 0.8 s after the previous move ends)

| Weapon | Combos |
|---|---|
| Rusty Gladius | Basic → Basic → Q **GLADIATOR'S POINT** ×1.4 · Block → E **IRON REPLY** ×1.5 · Q → Basic **SAND STEP** ×1.25 |
| Legion Sword | Basic → Basic → E **TESTUDO BREAKER** ×1.4 · Q → Basic → E **CENTURION'S ORDER** ×1.6 |
| Hunter Bow | Basic → Basic → Q **VOLLEY** ×1.3 · Block → E **STEADY AIM** ×1.4 |
| Morning Star | Basic → Q **MACE AND THUNDER** ×1.3 · Basic → E **IRON STORM** ×1.3 |
| Trident | Basic → Basic → Q **SEA STORM** ×1.3 · E → Basic **CAUGHT IN THE NET** ×1.5 |
| Hoplite Spear | Block → Q **SHIELD WALL** ×1.4 · Basic → Basic → E **HOPLITE CIRCLE** ×1.3 |
| Twin Daggers | Basic → Basic → Q **VIPER'S NEST** ×1.2 · Block → E **SHADOW COUNTER** ×1.5 · E → Basic → Basic **TWIN FANGS** ×1.3 |
| Battle Axe | Basic → Q **HEADSMAN** ×1.3 · Basic → Basic → E **ARENA STORM** ×1.3 |

The client only sends its input; the server records **accepted** actions with server time and recognizes combos itself.
Inputs during a running move are rejected (macros can't skip attack timing), cooldowns still apply, and the history is
cleared on death, stun, state changes or after a combo.

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

| Type | HP | Dmg | Aura | From | Weight | Personality |
|---|---|---|---|---|---|---|
| Legion Remnant | 60 | 10 | 10 | 1 | 40 | **Disciplined**: direct approach, nearest player, occasionally raises its shield, keeps formation |
| Rotten Velite | 40 | 7 | 8 | 2 | 25 | **Skirmisher**: circles and changes direction, hunts low-health/exposed players, retreats after attacking, goes around big raised shields |
| Arena Brute | 100 | 18 | 18 | 3 | 17 | **Tank**: prefers nearby damage dealers, won't chase far, roars before heavy hits, its attacks ignore half of a shield's protection |
| Zombie Retiarius | 55 | 8 | 14 | 3 | 13 | **Controller**: keeps medium distance until its net is used (slows moving players 25 % for 2 s), steps aside for brutes/champions |
| Arena Champion | 130 | 15 | 25 | 4 | 5 | **Elite**: glowing guard blocks frontal hits (side/rear and arrows from the side get through), picks dangerous or well-equipped players, shield-bashes blockers, is exposed after a missed attack |

All five run on **one** shared AI with per-type profiles (`ZombieAIProfiles`).

**Multiplayer target distribution:** each zombie scores every living arena fighter: threat (damage dealt to it, blocks,
nearby healing; decays over time), proximity, missing health, movement, gear value and exposure, weighted by its
personality. Players already chased by more than their fair share (living zombies ÷ living players) score lower, and the
current target gets a small bonus. Targets are re-evaluated about every 1.2 s, not every frame.

**Crowd and separation:** each player has 10 melee slots and at most 4 attackers at once. The others circle, wait or
pick another player. Solid torso-sized collision (`Zombies` group), separation steering, spawn spacing over 7 gates,
stuck detection, staggered AI ticks and a global pathfinding budget (12 requests/s) keep 48 zombies stable.
Corpses stop colliding immediately.

## Shells, Aura, archive and training

- **Shells:** 12 symmetric spots. Solo uses 8, Co-op 4 + 2 per player (max 12), Team Battle none by default.
  Each heals exactly **+3** (never above max, not used at full health), only for the collector, and respawns after 12 s (never right under a player).
- **Aura Points** replace coins everywhere. `AURA: n` is always shown at the top. Profiles are kept per UserId for
  the server session. Old profiles with `coins` are migrated once (`coins` is added to `auraPoints` and cleared in the same step).
- **Zombie Archive:** five barred cages with the real arena models (anchored, tagged `ZombieDisplay`, never targets, no AI)
  and a plaque each: name, role, health, damage, ability, reward and first round.
- **Training yard:** two straw dummies with damage numbers. Specials and combos work, there's no Aura or eliminations, and they refill after 3 s.

## Studio test steps

**Solo**
1. F5. You spawn in the arrival hall: `AURA: 0`, Rusty Gladius + Wooden Buckler in your hands, Q/E cards bottom right.
2. Walk to the TRAINING yard (south-west), hit a dummy, then try Basic → Basic → Q: you should see a `GLADIATOR'S POINT!` popup.
3. Visit the ZOMBIE ARCHIVE (east): 5 caged zombies with plaques, idling and rattling bars.
4. Hold F at the SOLO ARENA gate (north-west). GET READY, then ROUND 1 / 6. Kill zombies: `+10 AURA`.
5. Die or win: you return to the lobby and keep your Aura. Buy something with F at a pedestal (e.g. Legion Sword for 80).

**Two-player co-op** (Test → Local Server, 2 players)
1. Both hold F at JOIN / LEAVE PARTY, then READY. The leader (★) holds F at START.
2. Round 1 has 2 zombies (2 × 100 %). Both players are targeted, damage gives assist Aura (`+3 AURA (ASSIST)`).
3. Let one player die: they wait on the tribune and return with 72 HP after the round. If both die, the run ends.

**Four-player co-op** (4 players)
1. Join, ready, start as above. Round 1 = 3 zombies (2 × 1.5), Round 6 = 48. 12 shells are active.
2. Zombies spread across all four players; no player has more than 4 attackers at once.

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
- Dashes, lunges and knockback on players are applied by the player's own client (Roblox gives it physics ownership); the server validates the hits afterwards.
- Arrows are simulated on the server and may look slightly choppy on high-latency clients.
- Team Battle eliminations count every valid kill; Aura is only paid at the end of a match, so farming idle players gives no Aura.
- Sounds are built-in placeholders. Balance (zombie damage, PvP multipliers) hasn't been play-tested yet; tune it in the shared definitions.

## Troubleshooting

- **Old modules still in Explorer** (`GameStateService`, `CoinService`, `HudController`, `WaveConfig`): disconnect and reconnect Rojo.
- **Prompts don't react to E:** interactions use **F** now (E is Special 2).
- **"Attack … rejected: …" warnings:** temporary diagnostics, switch off with `DebugRejectedAttacks = false` in `CombatConfig`.
- **Build check:** `rojo build -o OttiArena.rbxlx` must succeed.
