# Otti Colosseum

A multiplayer-ready Roblox arena game built with VS Code + Rojo: an underground gladiator complex,
three game modes (Solo Arena, Co-op Legions, Team Battle), eight weapons with special attacks and combos,
eight shields, six zombie types with their own AI personalities (incl. the archer **Undead Sagittarius**),
progressive zombie damage states and stylized limb loss, healing shells, **Aura** (progress that unlocks gear), **Denarii** (money) and a final boss:
**OTTI — CHAMPION OF THE COLOSSEUM** (Round 7).

Otti's procedural boss model (`OttiModel`) follows the Otti the Gladiator reference art.

Plain Luau (strict), no packages, no Toolbox assets, no uploaded asset IDs. Everything is generated from Parts,
built-in materials, built-in SpecialMesh shapes, ParticleEmitters and lights. The server decides every
gameplay outcome (damage, hits, combos, Aura, ownership, scores, victories, boss state, projectiles, AI).

> **Two Places, one Experience.** The **OTTI HUB** (start place) is the Colosseum basement: armory, archive,
> training, parties, mode selection, matchmaking and the live-battle menu. Every match runs on its **own
> reserved server of the COLOSSEUM ARENA place**, so any number of matches run at the same time, each with
> up to 8 fighters and 20 live spectators. See [Multi-place architecture](#multi-place-architecture).

## Project structure

```
default.project.json                 = the Hub (start place); kept so `rojo serve` keeps working
places/hub.project.json              OTTI HUB  (shared code + src/hub, PlaceRole "Hub")
places/arena.project.json            COLOSSEUM ARENA (shared code + src/arena, PlaceRole "Arena")
scripts/build-places.ps1 / .sh       builds build/OttiHub.rbxlx and build/OttiArena.rbxlx
src/hub/PlaceRole, src/arena/PlaceRole   -> ReplicatedStorage.Shared.PlaceRole (build-time role)
src/hub/server/   -> ServerScriptService.Server.Place  (Hub only)
  Main.server                        builds the basement, starts data, armory, training, Hub matchmaking
  HubMatchService                    MatchRequest dispatch (rate limited), Solo / Co-op start, basement prompts, live board
  PartyService                       parties 1-4 (create, invite, accept, ready, lock while queued)
  MatchmakingService                 cross-server queues (Co-op, Time, First to, Elimination), lease, claims, assignments
  ArenaReservationService            match id + ReserveServerAsync + match record + connection record + fighter tickets
  HubTeleportService                 flush/freeze profile -> TeleportAsync to the reserved Arena, failure recovery
  LiveBattlesService                 LIVE IN THE COLOSSEUM sections, policies, featured, filters, WATCH RANDOM weights, Studio mock battles
  FriendBattleService                server-side Roblox friend lists (cached)
  SpectatorJoinService               WATCH / WATCH RANDOM: atomic slot reservation, spectator ticket, teleport
src/hub/client/   -> StarterPlayerScripts.Client.Place  (Hub only)
  GameModeMenuController             PLAY menu: ZOMBIE BATTLES / TEAM BATTLES / WATCH LIVE, party panel
  ActiveBattlesController            the LIVE IN THE COLOSSEUM overlay
src/arena/server/ -> ServerScriptService.Server.Place  (Arena only)
  Main.server                        builds the Colosseum, starts combat, zombies, Otti, team rules, admission
  ArenaAdmissionService              ticket validation + consumption, roles, capacity, rejections
  ArenaMatchService                  waits for fighters, starts the one match, ends it, return flow, Studio mock matches
  ArenaRegistryHeartbeat             public registry record every 12 s (+ on changes), spectator slots
  ArenaSpectatorService              spectator role, tribune spawn, "Spectators" collision group
  ArenaReturnService                 flush rewards -> TeleportAsync back to the Hub, retries, emergency button
  TimeBattleService / FirstToKillsService / EliminationService   the three Team Battle rule sets
src/shared/   -> ReplicatedStorage.Shared
  ExperienceConfig                   Place IDs (DEV/PROD), DataStore + MemoryStore names, teleport, registry, matchmaking, capacity, Studio mock
  EnvironmentConfig                  DEV / PROD resolution (server-side), place role, mock mode
  GameProtocol                       cross-place protocol version (admission compatibility)
  PlayerDataSchema                   saved profile schema version, statistics, preference whitelist
  MatchDefinitions / TeamModeDefinitions   the 5 match types / Time, First to, Elimination rules
  MatchTypes                         registry record, match record, connection record, ticket, teleport payload, message codes
  Config                             names, tags, attributes, remotes, shells
  CombatConfig                       player/crowd/shield/parry/combo tuning, rate limits, feedback kinds
  GameStates                         player + match states (LOBBY … CLEANUP)
  GameModeDefinitions                Solo / Co-op / Team Battle rules
  WeaponDefinitions                  8 weapons (instant basic attack + aerial attack each)
  ShieldDefinitions                  8 shields (reduction, angle, speed, raise time, bash, arrows, armory class)
  ArmorDefinitions                   4 armor sets (damage reduction, movement penalty, gladiator level unlock, price in Denarii)
  DamageConfig                       player damage pipeline: minimum damage, PvE / PvP armor effectiveness
  SpecialMoveDefinitions             every basic, aerial and combination move as data (nothing charged)
  WeaponAttackDefinitions / WeaponSpecialDefinitions   contextual attack chains / Special gesture families and tiers
  ControlModeDefinitions / SpecialChargeDefinitions / ShieldDefenseConfig / MomentumConfig / BlockDefinitions   Classic controls / special charge tiers / shield defense by direction / Momentum / block poses
  GladiatorLevelDefinitions / WeaponBalanceConfig   gladiator levels, titles, matchmaking gap / separate PvE and PvP weapon values
  CombatEffectsConfig / ZombieAttackDefinitions / SpectatorZoneDefinitions / CrowdQualityConfig   hit effects (no blood) / zombie attack sequences / tribune zones and quality
  CurrencyConfig                     Aura (progress, unlocks gear) and Denarii (money, buys gear)
  InputDefinitions / PvPBalanceConfig   input timing and mapping / PvP caps for specials and aerials
  OttiEntranceConfig                 imperial box behaviour and the jump into the arena
  ZombieDefinitions                  6 zombie types (stats, Aura, availability, weights, looks)
  ZombieAIProfiles                   6 AI personalities + Wounded/Critical behaviour modifiers
  RoundDefinitions                   round sizes per mode, weighted variant picking, archer caps, Round 7
  DamageEffectsConfig                sparks and dust (no blood), condition thresholds, limb-loss chances
  ProjectileDefinitions              player bow range + falloff, enemy arrows, arrow pool limit
  UiConfig / UiStateDefinitions / NotificationDefinitions   HUD sizes, breakpoints, limits / per-state and per-mode groups / notification priorities
  AudioConfig                        optional crowd/boss sound IDs (empty = visual fallback)
  OttiBossConfig                     Otti: health per player count, rewards, intro, speeds, safety values
  OttiMoveDefinitions                Otti's 11 attacks as data (wind-up, active, recovery, ranges, warnings)
  BossPhaseDefinitions               3 phases: names, accent colors, pacing, move weights
src/server/   -> ServerScriptService.Server   (shared server library: both places include it, each
                                     Main starts only what its place needs)
  Arena / LobbyService               Colosseum + tribunes + elimination box + camera points / underground complex
  MatchService                       the one match of an Arena server: Solo/Co-op/Team flow, rewards once, combat rules
  PlayerMatchStateService / MatchSpawnService   authoritative per-player match state / every (re)spawn by spawn zone
  TeamBattleService                  Team Battle core (teams, kill credit, alive state, result); rules injected
  MemoryStoreAdapter / RateLimiter / TeleportUtil   failure-tolerant MemoryStore (+ Studio mock) / remote cooldowns / TeleportAsync + retries
  AdmissionTicketService / MatchRecordService / MatchRegistryService / SpectatorSlotService   tickets / server-only records / public registry / atomic spectator slots
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
  InventoryService / AuraService     Aura (unlocks), Denarii (money), weapons/shields/armor, preferences, purchases, migration / rewards (Aura + Denarii)
  PlayerDataService                  DataStore load/save (Aura, Denarii, owned + equipped gear, preferences), autosave, BindToClose
  EquipmentShopService / EquipmentModels   Gladiator Armory displays / procedural weapons, shields, armor, arrows, nets
  PlayerCombatService                hands, blocking/parry, incoming damage, action requests
  SpecialMoveService                 move execution (melee steps, projectiles, aerials, arrow rain)
  AttackSequenceService / GestureValidationService / SlideService / MomentumService   contextual moves / gesture re-classification / slides / Arena Momentum
  ZombieAttackSequenceService / SpectatorPlacementService   zombie attack sequences / tribune zones and groups
  JumpAttackService                  server-side jump detection, one aerial per jump
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
  AuraDisplayController              lobby Aura and Denarii counters, +n rewards in combat
  MobileControlsController           touch ATTACK / SPECIAL (charge fill) / BLOCK (toggle) around Roblox's jump button
  SpecialChargeHudController         three-phase special charge bar
  CombatSettingsController           CLASSIC / WILD and CAMERA pills (saved preferences)
  SlideController / MomentumHudController   own-character slide / the ARENA MOMENTUM bar
  CombatEffectsController / CombatCameraController   hit presentation by category (sparks, dust, no blood), camera impulses
  InfoPanelController / SpectatorController   optional i panel / Arena spectator bar + camera modes
  TeleportStatusController           travel / queue chip, START WITH CURRENT PARTY, emergency RETURN TO HUB
  InputController                    Classic input for mouse/keyboard, gamepad and touch (attack, block toggle, special hold, soft targeting); sends intent only
  ComboFeedbackController            tiny input chips, TRAINING board (both modes, Momentum, specials)
  PlayerAnimator                     procedural whole-body attack motion (additive, replaceable)
  OttiEntranceController             local camera for the entrance, landing shake, skip
  ShopController                     armory info card (LOCKED / BUY / EQUIP / EQUIPPED, INFO), focus highlight, equipped outline
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
Lobby interactions use server-side ProximityPrompts. Multi-place remotes: `MatchRequest` (RemoteFunction,
client → server requests only, rate limited per action) and `MatchEvent` (server → client: party, queue,
teleport status, open overlay).

## Start Rojo and connect Studio

Each Place is its own Studio window with its own Rojo server (two ports):

```bash
rojo serve places/hub.project.json --port 34872
```

```bash
rojo serve places/arena.project.json --port 34873
```

(`rojo serve` without arguments serves `default.project.json` = the Hub.) In each Studio window: Plugins →
**Rojo** → enter the port → **Connect**, **View → Output**, **F5**. For multiplayer tests:
**Test → Clients and Servers → Local Server** with 2 or more players.

Build both place files (git-ignored `build/`):

```bash
powershell -File scripts/build-places.ps1
```

## Controls (Classic, the only control mode)

The same combat everywhere: PvE, PvP and boss fights. The PLAY menu and the HUD work on phones, tablets and desktops.

| | Keyboard & mouse | Gamepad | Touch |
|---|---|---|---|
| Move (camera-relative, turns the character) | WASD | left stick | Roblox thumbstick (left) |
| Camera | mouse | right stick | drag on free screen space |
| **Attack** (tap again = combo chain) | Left click | R2 | ATTACK (largest button, left of JUMP) |
| **Block** on / off (toggle) | Right click | L2 | BLOCK (lit ON while active) |
| **Special** (hold to charge, release to fire) | hold **Q** | hold **X** | hold SPECIAL (above JUMP, fills while charging) |
| Jump (allowed while blocking) | Space | A | Roblox's own jump button (no second one) |
| Interact (shop, doors, pads) | **F** | D-pad up | tap the prompt |
| HUD mode (Full / Minimal / Hidden) | **H** or eye button | eye button | eye button |

The touch buttons are positioned per device (`UiConfig.TouchLayoutPhone` / `TouchLayoutTablet`) around Roblox's
jump button, away from the thumbstick and the health bar. **Soft Targeting:** an attack turns the character smoothly,
at most 40° over 0.1 s, toward the enemy in a 75° cone in front. Only targets with a clear line of sight count; never
teammates, spectators or lobby players. With the bow and a mouse the cursor aims instead.

## Combat (V2)

Server-authoritative: clients send intent only (an attack, the block toggle, special start / release, an aim point).
Damage, reach, hits, cooldowns, block results, charge time, rewards and progress are decided on the server. Details:
[docs/COMBAT_V2_PLAN.md](docs/COMBAT_V2_PLAN.md).

- **Separate combat states** (`PlayerCombatService`): defense (block), attack (busy and cooldowns) and special charge
  are independent. Block and charge may be active together.
  - **Attack:** lowers an active block first and does not raise it again. No attacks while charging.
  - **Special release:** lowers the block, then fires; the block is not raised again.
  - **Interruptions:** death and respawn, a knockdown, Otti's grab, a match reset, or a heavy hit that was **not**
    blocked cancel the charge. Block and charge are always reset on death and respawn.
- **Attack chains:** contextual (standing, moving, after the previous attack, in the air, after a perfect block).
  Chains reset after 1.1 s.
- **Special charge** (`SpecialChargeDefinitions`): the hold time is measured on the server; holding longer than 2.5 s
  adds nothing. While charging, walking slows to 75 %; with the block up as well, the stronger slow (block) applies.
  Spam is stopped by one shared cooldown and the busy state. A three-phase bar and the SPECIAL button show the charge.

  | Tier | Hold | Move (weapon family) | PvE damage | PvP damage | Cooldown |
  |---|---|---|---|---|---|
  | I | under 0.5 s | quick special (Right family) | × 1.0 | × 1.0 | 2.5 s |
  | II | 0.5–1.5 s | strengthened (Left family) | × 1.3 | × 1.1 | 4 s |
  | III | 1.5 s or more, full at 2.5 s | maximum (Down family) | × 1.7 | × 1.25 | 6 s |
  | ULTIMATE | tier III with a full Momentum bar | the weapon's Ultimate | own | own | 8 s |

  `specialFor(characterId, weapon, family)` is the one place that picks the move, so Otti, Schili, Krokero and later
  characters can get their own specials without changing the combat code.
- **Block and shield defense** (`ShieldDefenseConfig`, by hit direction computed on the server). The shield is on the
  left arm:

  | Zone | Passive (shield carried) | Active block |
  |---|---|---|
  | Front (the shield's block angle) | 0 % | 70 % (perfect block / guard break only here) |
  | Shield side (left) | 15 % | 40 % |
  | Weapon side (right) | 0 % | 0 % |
  | Back | 0 % | 0 % |

  - **Toggle:** block stays up until it is pressed again (no timeout). Walk speed is about 65 %.
  - **Per shield:** values scale with the shield's quality; arrows use its projectile ratio.
  - **Perfect block:** raising the block at most 0.2 s before a valid hit stops it and opens a 1 s counter.
  - **Heavy hits on the block** push the blocker back briefly.
  - **Twin daggers** parry instead of blocking.
- **Hit reactions:** knockback, a short stumble pose, and on heavy unblocked hits a brief loss of balance (55 % walk
  speed for 0.4 s, at most every 1.5 s). Control loss stays short.
- **Effects:** sparks and dust only. **No blood and no loss of body parts** (Roblox family standards).
- **Momentum (0-100):** varied attacks, aerial hits, blocks and perfect blocks fill it. A full bar turns the next tier III
  special into the Ultimate.
- **Removed in V2:** the Wild mode, the gesture pad and Special gestures (`GesturePadController`, `GestureDefinitions`,
  `GestureValidationService`). Slide input is removed too, because mobile has four buttons and PvP must not favour a
  platform; `SlideService` stays on the server, unused.

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
- **Aura and Denarii:** two capsules top-right in the lobby (and so while shopping): gold Aura orb, silver
  Denarii coin. In combat only short `+10` / `+10 DENARII` notifications (rapid rewards merged); the results
  banner shows the match totals.
- **Notifications:** one queue, at most 3 small messages; priorities Critical > Result > Round > Heal > Aura / Denarii > Info.
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


## The lobby: the gladiator dungeon under the Colosseum

Details, coordinates and how to add a mode: [docs/LOBBY_LAYOUT.md](docs/LOBBY_LAYOUT.md). Seen from the spawn (looking
north at the large **Otti statue** in the middle of the central hall):
- **Front:** the **ARENA** gate. A corridor lined with zombie and gladiator cages (the **ZOMBIE ARCHIVE**) rises gently
  to a portcullis; the sunlit arena is visible behind it. Hold F at the portcullis to open the **PLAY** menu.
- **Back:** the closed **GATE TO ROME** (later the way into the open Roman world).
- **Left:** **MULTIPLAYER**: four large group rooms with walk-on carpet pads and floor mosaics (Otti / Schili).
  Stepping on a carpet joins its group, the board lists the members, the leader (★) presses **START** or a queue
  button. ZOMBIE CO-OP (START, FIND PLAYERS) and TEAM DEATHMATCH (TIME BATTLE, FIRST TO 20, ELIMINATION) are live;
  BOSS FIGHT CO-OP and ARENA CO-OP are built and signed COMING SOON.
- **Right:** **SINGLEPLAYER**: four pads right at the entrance. Stand on **ZOMBIE SURVIVAL** for 3 s (or press START
  NOW) to start a solo run; BOSS FIGHT, ARENA FIGHT and CHAOS GAMES are COMING SOON. The **TRAINING** yard is behind.
- **Sides:** stone stairs in the front corners up to the **TRIBUNES** doors (WATCH LIVE), the LIVE IN THE COLOSSEUM
  board on the floor.
- **Back-left:** a side passage with a forge to the **GLADIATOR ARMORY** (and a closed UPGRADES door for later).
Colour-coded floor strips lead from the spawn: blue to multiplayer, gold to singleplayer, red to the arena. The PLAY
menu (right edge) offers every action too. The lobby is a safe zone: no damage, no PvP, no blood. Attacks only hit the
training dummies.

### GLADIATOR ARMORY

A separate vaulted sandstone chamber (100 × 76 studs) at the end of the side passage behind the hall's south-west
corner, marked `GLADIATOR ARMORY`. Thick columns, torches, red banners, bronze section signs, wooden racks, storage
shelves, crates and barrels.
- **BLADES** (north wall): Rusty Gladius, Legion Sword, Twin Arena Daggers.
- **HEAVY & REACH** (west wall): Morning Star, Trident, Hoplite Spear, Battle Axe (wider spacing).
- **RANGED & SPECIAL** (east wall): Hunter Bow with quiver and arrows; future ranged / special weapons.
- **SHIELDS** (south wall): LIGHT · BALANCED · HEAVY. **ARMOR** (centre dais): four mannequins.
Rows come from `WeaponDefinitions` (`Row`) and `ShieldDefinitions.classOf`, so new items appear automatically.
Each display has only a small name plate; walking up highlights it and opens a compact card (stats, gladiator level unlock,
price in Denarii, OWNED / EQUIPPED, **LOCKED** / **BUY** / **EQUIP**, optional `i` details). F / gamepad X / the card
button use the same server prompt, which checks: lobby state, inside the armory, close to the display, data loaded,
unlocked by Aura, owned / affordable in Denarii. Safe zone like the
whole lobby: no damage, PvP, projectiles or rewards.

## Game modes

| Mode | Players | Rules |
|---|---|---|
| **Solo Arena** | 1 | Rounds 1, 2, 4, 8, 16, 32 zombies, then **Round 7: Otti** (1,200 HP, +500 Aura). Death ends the run. 8 shells. |
| **Co-op Legions** | 1-4 | Base rounds 2, 4, 8, 12, 20, 32 × 0.75 / 1.0 / 1.25 / 1.5 (1-4 players, rounded up), max 48 active at once. Shared rounds; the dead wait on the tribune and return with 60 % health after a completed round; a full wipe ends the run. Killer +100 %, assists +30 % of the zombie's Aura (once per player per zombie). 4 + 2 per player shells (max 12). **Round 7: Otti** (1,200 / 1,850 / 2,450 / 3,000 HP for 1-4 players): +400 Aura per survivor, +250 for defeated players who damaged him. |
| **Time Battle** | 1v1 - 4v4 | Red vs Blue, no friendly fire, respawn after 4 s with 2 s protection (no attacks while protected). 8 minutes; more eliminations wins; a tie goes to **Sudden Death** (next valid opposing elimination wins). HUD `RED 8 — 7 BLUE  04:12`. |
| **First to 20** | 1v1 - 4v4 | Respawn as above. Target by team size: 1v1 10, 2v2 15, 3v3 / 4v4 20. 12-minute safety timeout: higher score wins, tie = Sudden Death. HUD `FIRST TO 20  RED 13 — 11 BLUE`. |
| **Elimination** | 1v1 - 4v4 | One life per player per round, Best of 5 (first to 3 round wins). A round ends when a team has no living fighter; both wiped within 0.75 s = draw; 150 s round limit (more alive wins). Eliminated players wait in a closed room and can only follow living teammates. Between rounds the loadout is shown and locked (6 s), then a 5 s countdown at the team spawns. HUD `ELIMINATION  RED 2 — 1 BLUE  ALIVE 3 — 2`. |

All Team Battles: winners +80 Aura, losers +25, draw +40; shells off by default (`TeamModeDefinitions.Common`).

**Co-op:** SOLO / START WITH CURRENT PARTY start at once on a new reserved Arena server (no waiting for 4
players). Parties: CREATE PARTY, invite players of the same Hub server (or friends via Roblox invite, then invite
them here), ACCEPT, READY. The lobby's group pads form public groups: stepping on the carpet joins, stepping off leaves,
the leader (★) presses START (only READY members fight; nobody ready = everybody). **FIND PLAYERS** queues the group for
co-op matchmaking.

**Team Battles:** choose a submode (post or menu); the party queues together. Teams are formed by the matchmaker
(equal sizes only, see below), never by clients. In the Arena: one match id, protected team spawns behind closed
barriers, 5 s countdown, FIGHT. Results, rewards (exactly once) and the return to the Hub follow automatically.

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
(block button: 0.4 s window, −70 % damage, 1.2 s cooldown). The armory card and HUD say so.

**Hunter Bow:** arrows fly 145 studs/s up to 150 studs (server-simulated, never through walls); damage 100 % up to
100 studs, 90 % to 125, 75 % to 150. A short fixed draw, no holding, consistent arrow power; a subtle crosshair shows
while the bow is equipped (no aim assistance). Its special shots come from combos (ARROW RAIN, EAGLE SHOT).

## Specials and PvP balance

Each weapon's Special families (Left, Right, Up, Down, Circle, Ultimate) are listed in `WeaponSpecialDefinitions`; the
charge tiers that pick a family are described in *Combat (V2)* above.

**PvE / PvP weapon values** are configured separately (`WeaponBalanceConfig`, applied in `SpecialMoveService`):
- **PvE:** a weapon's damage grows with its gladiator level (+8 % per level above 1), so progress shows against zombies
  and bosses. Starter weapons keep their base damage, so beginners can still win.
- **PvP:** every weapon's basic-attack DPS is normalized to one reference (22). Long reach and bows pay a small tax.
  Weapons still differ in reach, speed, arc and style, so higher levels bring more choice, not more power.

**PvP balance** (`PvPBalanceConfig`): per-move PvP multipliers (0.35-0.75) and target caps, no single hit above 45 % and
no whole special or aerial move above 50 % of a player's max health, knockdowns capped, no repeated stagger within
2.5 s, guard breaks drop the shield for 1.2 s (half protection) instead of ignoring it, counter windows only for the
first 0.3-0.35 s.

**Training:** the TRAINING board in the training yard explains the controls, the block directions, the special charge
tiers with the equipped weapon's moves and Momentum. The sparring dummy answers attacks; there is no Aura in training.

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

Shields are shown in the armory by class: **Light** (Wooden Buckler, Parma Equestris, Thraex), **Balanced** (Legion,
Champion), **Heavy** (Tower, Scutum, Hoplon). Several can be owned, one is equipped (unused with the Twin Daggers).

## Armor (4)

| Armor | Price | Damage reduction (PvE) | PvP (× 0.75) | Movement |
|---|---|---|---|---|
| Recruit Leather | free, owned by default | 5 % | ≈ 4 % | – |
| Murmillo Armor | 180 | 15 % | ≈ 11 % | −2 % |
| Hoplite Bronze | 320 | 25 % | ≈ 19 % | −6 % |
| Champion Armor | 520 | 35 % | ≈ 26 % | −10 % |

Exactly one set is worn; it is bought / changed only in the armory while in the lobby, never during a match. Procedural
pieces on torso, shoulders, arms and legs (no helmet, the avatar stays recognisable); cloth pieces take the team
color in Team Battle. Values: `ArmorDefinitions`, PvP effectiveness and caps: `DamageConfig`.

## Player damage pipeline

Every hit on a player (zombie blows, enemy arrows, Otti, PvP melee / arrows / combos / aerials) goes through
`PlayerCombatService.receiveHit`, so no weapon can skip the shield or the armor:
1 validate target, protection and enemy rules · 2 base damage · 3 mode multiplier (the attack's PvP multiplier) ·
4 shield block / parry · 5 armor · 6 temporary effects (combo counter window) · 7 minimum damage and PvP caps ·
8 Humanoid damage · 9 HUD / visual feedback.
`afterBlock = base × shieldMultiplier`, `afterArmor = afterBlock × (1 − armor × effectiveness)`,
`final = max(1, round(afterArmor))` (0 only when a shield stops the blow completely).

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

### Limb and armor loss: switched off

The game shows no loss of body parts (Roblox family standards): `DamageEffectsConfig.ZombieDismembermentEnabled = false`.
The old stylized code (`ZombieDismembermentService`) stays unused behind that switch and is never called with it off.
Zombie condition states (darker skin, scratches, torn cloth) still show damage.

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
- **Damage effects** (`DamageEffectsConfig`): child-friendly, no blood. Every validated hit shows brief orange sparks and
  sand dust (zombies, players and Otti alike). `ZombieDismembermentEnabled` switches the stylized limb / armor loss of
  zombies. Player hits: red edge flash (never the whole screen), a directional indicator and a tiny burst.

## Shells, Aura, archive and training

- **Shells:** 12 symmetric spots. Solo uses 8, Co-op 4 + 2 per player (max 12), Team Battle none by default.
  Each heals exactly **+10** (`Config.ShellHealAmount`, never above max, not used at full health), only for the collector, and respawns after 12 s (never right under a player).
- **Aura, gladiator levels and Denarii** (`CurrencyConfig`, `GladiatorLevelDefinitions`):
  - **Aura** is experience. It comes from zombie kills, assists, completed rounds (+10), Otti and Team Battle results;
    it is never spent and keeps adding up.
  - **Gladiator levels** come from total Aura. Each has a title, and the HUD shows the level, title and progress to the
    next one. Levels unlock gear (`LevelRequired`) and are a matchmaking factor.

    | LV | Title | Aura |
    |---|---|---|
    | 1 | TIRO | 0 |
    | 2 | NOVICIUS | 100 |
    | 3 | GLADIATOR | 300 |
    | 4 | VETERANUS | 650 |
    | 5 | PRIMUS PALUS | 1200 |
    | 6 | CHAMPION | 2000 |
    | 7 | LEGEND OF THE ARENA | 3200 |

  - **Denarii** (the Roman silver coin) are the money. Combat rewards pay Denarii too (1 per Aura point by default), and
    every completed round pays +15. Gear that your level has unlocked is bought with Denarii (`Price`); the balance
    never goes negative.
  - **Rewards are paid exactly once,** on the server: once per zombie, once per round and player, once per match.
- **Zombie Archive:** six barred cages with the real arena models (anchored, tagged `ZombieDisplay`, never targets, no AI)
  and a plaque each: name, role, health, damage, ability, reward and first round. Otti is not in the archive.
- **Training yard:** two straw dummies with damage numbers. Specials and combos work, there's no Aura or eliminations, and they refill after 3 s.

## Saving (DataStore)

`PlayerDataService` (both places) stores per UserId in the environment store (`OttiPlayerData_DEV_v1` /
`OttiPlayerData_PROD_v1`, see [Environments and saved data](#environments-and-saved-data)): Aura, Denarii, owned weapons /
shields / armor, the equipped item of each kind, statistics and preferences (HUD mode, Otti intro seen). Studio uses
mock data unless `StudioMockData = false`. Loaded data always goes through
`InventoryService.migrateProfile` (legacy `coins`, missing armor, unknown ids are dropped, starter items guaranteed).
- **Load** on join with 3 retries. While loading (`DataStatus = Loading`) the armory refuses purchases.
- **Load failed / no API access:** a fresh profile marked `Unsaved` — it is never written, so saved progress can't be wiped.
- **Save:** 8 s after a change (purchase, equip, Aura reward, preference), every 120 s if dirty, on leave and on
  shutdown (`BindToClose`) via `UpdateAsync`; a newer save from another server is kept.
- **Preferences:** the client may only send whitelisted values (`SavePreference` remote, rate limited).
- **Schema v6:** Aura is experience; levels are derived, not stored. The old `ControlMode` / `BloodFx` preferences are
  dropped on load. Moving from v5 to v6 needs no data change.
- **Controlled test-data reset** (`src/server/PlayerDataResetConfig.luau`): **off by default.**
  - To use it, set `Enabled = true` and a **new** `Token`, optionally list the test players' `UserIds`, then publish
    to **DEV** only.
  - Each listed profile is replaced by a fresh one on its next join, exactly once per token. The token is saved, so the
    reset never repeats on a server start.
  - It never runs after a failed load, is logged, and needs explicit approval before any production use.

## Multi-place architecture

```
OTTI HUB (start place, public servers)                COLOSSEUM ARENA (one reserved server per match)
 basement, armory, archive, training                    Colosseum, tribunes, imperial box, Otti
 parties, PLAY menu, posts                              ArenaAdmissionService (tickets, roles, capacity)
 MatchmakingService ──┐                                 ArenaMatchService (wait -> start -> end)
 HubMatchService ─────┼─ ArenaReservationService ──┐    MatchService / TeamBattleService + rules
 SpectatorJoinService ┘   ReserveServerAsync        │    ArenaRegistryHeartbeat (every 12 s)
 LiveBattlesService ◄── MemoryStore registry ◄──────┼─── public record, spectator slots
 HubTeleportService ──── TeleportAsync(access code) ┴──► ArenaReturnService ── TeleportAsync ──► Hub
            both places: same PlayerDataService / InventoryService / schema / environment DataStore
```

### Creator Dashboard setup (manual)

1. Publish the Hub place (`build/OttiHub.rbxlx` or Rojo-synced Studio) as the **start place** of the Experience.
2. In the same Experience, **Create → Add a Place**, publish the Arena place (`build/OttiArena.rbxlx`) into it.
3. Copy both **Place IDs** (Creator Dashboard → Experience → Places → the number in each place URL) into
   `src/shared/ExperienceConfig.luau`: `Environments.DEV.HubPlaceId / ArenaPlaceId` for the private dev Experience
   and `Environments.PROD.*` for the live Experience (until then they are `0` = local mock mode). Rebuild and
   publish **both** places after changing them.
4. Arena place → Settings → **Max Players = 28** (`Capacity.RecommendedServerSize`). Hub: as large as you like.
5. Game Settings → Security: **Enable Studio Access to API Services** (for Studio data tests with
   `StudioMockData = false`). Third-party teleports are not needed (both places are in one Experience).
6. Optional: turn off "Allow direct join" for the Arena place if your Dashboard offers it; public Arena servers
   reject everybody anyway (no ticket for a non-reserved server) and send them to the Hub.

### Environments and saved data

`EnvironmentConfig` decides on the server: **Studio is always DEV**; a live server is **PROD only when
`game.PlaceId` equals a configured PROD Place ID**; everything else is DEV. Client data is never used.
| | DEV | PROD |
|---|---|---|
| DataStore | `OttiPlayerData_DEV_v1` | `OttiPlayerData_PROD_v1` |
| MemoryStore maps | `OttiMatches_DEV_*` | `OttiMatches_PROD_*` |
| Studio | mock player data (`StudioMockData`), mock MemoryStore | never used in Studio |

The store names never change for normal updates. `PlayerDataSchema.Version` (now 5) only moves forward;
`InventoryService.migrateProfile` keeps Aura and owned items, adds missing fields (armor, statistics, Denarii), drops
unknown ids and re-validates equipped items. A pre-multi-place save (`OttiColosseum_PlayerData_v1`) is imported
once if the environment store has no profile yet. Persisted: Aura, Denarii, owned + equipped weapon / shield / armor,
statistics (zombie kills, Otti defeats, runs, victories, team matches / wins, eliminations, deaths, spectated
matches), HUD mode, intro seen. Never persisted: health, round, scores, match id, cooldowns, projectiles, buffs,
positions. Before every cross-place teleport the profile is **flushed and frozen** (`beginTransfer`: no
purchases, no late overwrite); the destination loads it again from the DataStore (never from TeleportData);
after a match the rewards are flushed before the return teleport. If loading fails, the session is `Unsaved`
and never written, so saved progress can't be replaced by empty defaults.

### Match creation and admission security

1. Hub validates the request (mode, party leadership, lobby state, data loaded, equipment) — MatchRequest is
   rate limited per action and accepts only actions, never ids of places, teams, roles, rewards or scores.
2. `ArenaReservationService`: unique match id, `TeleportService:ReserveServerAsync`, then three server-only
   MemoryStore records: **MatchRecord** (mode, fighters + teams + party ids, policy, protocol, the reserved
   server's `PrivateServerId`), **ConnectionRecord** (the access code) and one **AdmissionTicket** per fighter
   (`<matchId>:<userId>`, role, team, mode, issued / expires (120 s), consumed, protocol).
3. `HubTeleportService` freezes each profile and calls `TeleportAsync` with `ReservedServerAccessCode`. The access
   code exists only in server memory, MemoryStore and `TeleportOptions` — never in LocalScripts, GUIs,
   attributes, remotes or TeleportData. TeleportData = `{ kind, matchId, role, mode }` (hints only).
4. The Arena re-checks everything: the match record exists, belongs to **this** reserved server
   (`game.PrivateServerId`) and has a compatible protocol; the ticket is consumed atomically (UpdateAsync: exists,
   not expired / consumed, same user + match, valid role, compatible protocol); fighters must be listed in the record
   and arrive before the start; spectators need a joinable match and free capacity. Otherwise: compact message
   (ADMISSION REJECTED / BATTLE HAS ENDED / MATCH IS ALREADY FULL / GAME UPDATE IN PROGRESS) and back to the Hub.
5. `GameProtocol.Version` (1): Hub writes it into tickets and records; the Arena publishes its own; the Hub lists
   only compatible arenas; mismatches are rejected safely. Running matches finish on their version.

### Match registry and heartbeat

`ArenaRegistryHeartbeat` writes the public record (mode, status, round, Otti phase, scores, target, time, alive
counts, fighters, spectators, joinable, start time, public participant ids, party ids, policy, protocol) every
**12 s** and right after round / boss / score changes (throttled to 3 s), with a **50 s expiration**: crashed or
stale arenas disappear by themselves. Completed matches are **removed at once** (non-joinable immediately), the
spectator slot record is closed and the server-only records are deleted shortly after. Registry failures are
logged and ignored; they never affect the match.

### Parties and matchmaking

* **Solo / Co-op start now:** one reserved Arena per start, no waiting for other players.
* **Queues:** MemoryStore map per mode (`Queue_COOP_ZOMBIES`, `Queue_TIME_BATTLE`, `Queue_FIRST_TO`,
  `Queue_ELIMINATION`), one entry per party with a server-generated token, expiring (90 s) unless the home server
  refreshes it (20 s); no duplicate queueing; parties are locked while queued; leaving removes the entry.
* **Matchmaker:** every Hub server ticks every 3 s; a short **lease** per mode lets one server match at a time.
  Entries are **claimed atomically**; if a claim or the Arena reservation fails, all claims are released and the
  entries are matched later. Assignments (`Assign` map) are picked up by each entry's home server, which teleports
  its players together.
* **Co-op:** oldest entry first, filled to 4; starts at 4 or after 45 s; after 20 s the chip offers
  **START WITH CURRENT PARTY**.
* **Teams:** only equal sizes (4v4 at once, 3v3 after 15 s, 2v2 after 30 s, 1v1 after 45 s waiting), never 3v1,
  parties are never split and never face themselves (a party is one entry).
* **Gladiator level as a factor:** each entry carries its average level (`MatchRatingService`). Team battles only match
  entries within a level window around the oldest entry. The window starts at ±1 and widens by 1 every 15 s, up to ±6.
  A skill-based rating can be added in `MatchRatingService` later.
* **Partial teleport failure:** failed players get a message, their profile unfreezes and the party unlocks; the
  Arena waits up to 25 s; Co-op starts with whoever arrived, a team match with unequal teams is **cancelled**
  (MATCH CANCELLED, no rewards) and everybody returns.

### Spectators

* Join through **WATCH** / **WATCH RANDOM** (Hub): the slot is reserved atomically in the match's slot record
  (connected + live reservations < 20); a SPECTATOR ticket is issued; on failure the reservation is released (and
  expires after 60 s anyway). The Arena consumes the reservation on arrival.
* In the Arena they spawn on lower / middle tribune spots (never the floor, never the imperial box), use the
  **Spectators** collision group (walk through each other, never touch zombies or Otti), have no combat context
  (no damage dealt or taken, no shells, no Aura, no objectives, no boss / zombie targeting, no crowd slots, no
  fighter scaling), and the podium barrier + safety net keep them out of the arena. They can return any time.
* Capacities (configurable): 8 fighters, 20 spectators, server size 28; admission counts admitted fighters,
  spectators and admissions in progress.
* **Camera** (local only): WALK (tribunes), FOLLOW fighter (◀ ▶), OVERVIEW (5 fixed points), OTTI. Desktop: **Q**
  previous, **E** next, **C** camera mode; touch: ◀ · CAM · ▶ · HUB. **Elimination:** eliminated players wait in a
  closed room and can only FOLLOW living teammates (no overview, no free camera, no enemy cameras).

### LIVE IN THE COLOSSEUM overlay

Opens from **WATCH LIVE** (PLAY menu), the WATCH LIVE door or the live board; it never teleports by itself.
Sections in this order: **FRIENDS IN BATTLE** (only when a Roblox friend fights; up to 3 portraits + "+N"),
**FEATURED BATTLES** (server rules: Otti active / Phase 3, final zombie round, close finish, sudden death,
Elimination match point, 10+ spectators), **ALL LIVE BATTLES**. Sorted by friends, featured, free slots,
spectators, start time. Filters: All, Friends, Zombies, Otti, Time Battle, First to 20, Elimination. Refreshes when
opened, on ⟳ and every 12 s while open; stops when closed; a closed overlay is invisible and catches no input.
Friend lists come from `Players:GetFriendsAsync` on the server, cached 5 minutes per player (prefetched on join).
Spectator policies PUBLIC / FRIENDS_ONLY / PARTY_ONLY / PRIVATE are applied before anything is listed.

**WATCH RANDOM:** joinable matches only; weights friend 5, featured 3, normal 1; when several apply they combine by
`Spectating.WeightRule` (default **Max**: a featured friend battle weighs 5; `Sum` = 8, `Product` = 15). A
weighted random roll, so the busiest match is not always chosen. Nothing joinable: **NO LIVE BATTLES RIGHT NOW**
with REFRESH and MODE SELECTION.

### Teleport failures and the return

Reservation / destination / capacity / expiry / protocol problems keep or return the player to the Hub with one of:
ARENA COULD NOT BE REACHED · MATCH IS ALREADY FULL · BATTLE HAS ENDED · TELEPORT FAILED — TRY AGAIN ·
GAME UPDATE IN PROGRESS. Reservations and tickets are released, queue / party locks are lifted, Aura and equipment are
untouched, matches are created only after all claims succeeded. After the result sequence the Arena flushes the
rewards, removes itself from the registry and teleports everybody to the Hub (retried every 15 s; a failed return
shows **RETURN TO HUB**). Spectators arrive next to the live board; nobody gets a duplicate reward.

### Studio local mode (mock)

With Place IDs = 0 or in Studio nothing is teleported (and nothing pretends to be):
* **Hub:** mock player data, mock MemoryStore, 4 fake live battles (one with a "Studio Friend", see
  `ExperienceConfig.Studio`). SOLO / CO-OP / queues create real match records and tickets in the mock store and
  report `STUDIO MOCK: ... match created — no teleport`. WATCH reserves and releases a mock slot.
* **Arena:** opened directly, it runs `Studio.ArenaMockMode` (default COOP_ZOMBIES) with the local players a few
  seconds after the first one joins; extra players become spectators; after the end a fresh match starts on
  the same server (stale-state test). Team modes need an even number of players (Local Server).

## Studio test steps

**Local Studio mock mode**
1. Hub window (`rojo serve places/hub.project.json`): F5. Output shows `Hub DEV ... MOCK`. PLAY → ZOMBIE BATTLES →
   SOLO: `STUDIO MOCK: SOLO_ZOMBIES match ... created`. TEAM BATTLES → TIME BATTLE: SEARCHING chip, after 45 s
   (1 player) a mock match is created (lower `TeamSizeWaitSeconds` for faster tests).
2. PLAY → WATCH LIVE: FRIENDS IN BATTLE (Studio Friend), FEATURED (Otti Phase 2, Elimination match point), ALL.
   Filters, ⟳, close (the screen is clickable again), WATCH RANDOM (mock message).
3. Arena window (`rojo serve places/arena.project.json --port 34873`): set `ArenaMockMode`, F5 / Local Server.
   Fight, die, watch: spectator bar (Q / E / C, CAM, HUB), result, a fresh match after ~10 s.

**Private published DEV test** (DEV Place IDs filled in, both places published, 2+ test accounts)
* **Solo reserved Arena:** Hub → SOLO → `TRAVELLING` → Arena (Output: `admitted as FIGHTER`) → play → result →
  back in the Hub with the Aura earned; open a second Solo from another account at the same time: two arenas.
* **Four-player Co-op:** 4 accounts: CREATE PARTY, INVITE, ACCEPT, START WITH CURRENT PARTY → all in one arena.
  Or FIND PLAYERS from separate parties → grouped up to 4.
* **1v1 Time Battle:** two accounts queue TIME BATTLE → after 45 s (1v1 wait) one arena, RED vs BLUE, clock 08:00.
* **4v4 First to 20:** 8 accounts (e.g. two 4-parties) queue FIRST TO 20 → `FIRST TO 20`, ends at 20.
* **Elimination:** 2-8 accounts; die → closed room, camera follows teammates only; next round everyone fights;
  first to 3 rounds wins.
* **Friend spectating:** befriend a fighter's account; WATCH LIVE shows FRIENDS IN BATTLE first → WATCH → tribune.
* **Random spectating:** WATCH RANDOM several times with several matches: different matches are picked.
* **Returning to the Hub:** after the result everyone is back in the basement (spectators next to the live
  board); HUB button / RETURN TO HUB door work any time for spectators.
* **Persistence after an update:** buy something, leave, change code, publish both places, rejoin: Aura, gear,
  HUD mode and statistics are still there (same `OttiPlayerData_DEV_v1`).

**Gladiator Armory, armor and saving (Hub)** (Game Settings → Security → *Enable Studio Access to API Services* for saving)
1. F5. From the spawn go to the back-left corner of the hall: the side passage marked GLADIATOR ARMORY leads past the forge; the armory door is at its end (right).
2. Walk along BLADES (north), HEAVY & REACH (west), RANGED & SPECIAL (east, bow + quiver), SHIELDS LIGHT / BALANCED / HEAVY
   (south) and the ARMOR mannequins (centre). Near a display: gold outline + card with stats, level unlock, price in Denarii and LOCKED / BUY / EQUIP / EQUIPPED; `i` shows details.
3. With too little Aura the card shows LOCKED and the button does nothing. Unlocked but too few Denarii: NOT ENOUGH DENARII
   and nothing changes. Recruit Leather is EQUIPPED from the start.
4. After a Solo run (Aura and Denarii earned): buy Murmillo Armor once you are level 3 → Denarii drop by its price, Aura
   stays the same; it appears on your character, walk speed drops by 2 %. Pressing again says Already equipped.
5. Take a zombie hit with and without armor: damage numbers are lower with armor (e.g. 20 → 17 with Murmillo).
   Team Battle: Champion Armor reduces player damage by about 26 % instead of 35 %; armor cloth shows the team color.
6. Shells now heal +10.
7. Change the HUD mode (H), leave and rejoin: Aura, owned/equipped gear and the HUD mode are restored.

**Solo (Arena gameplay: Arena place in Studio with `ArenaMockMode = "SOLO_ZOMBIES"`, or a real Solo start)**
1. Hub F5. You spawn behind the Otti statue in the central hall, facing the ARENA gate: the Aura and Denarii capsules top-right show 0, Rusty Gladius + Wooden Buckler in your hands, touch: ATTACK, SPECIAL and BLOCK around Roblox's jump button, thumbstick left.
2. Follow the gold strip right to SINGLEPLAYER, walk to the TRAINING yard at the far end and hit a dummy (tap ATTACK for combos, toggle BLOCK, hold Q / X / SPECIAL and watch the three charge phases).
3. Walk north into the arena corridor: the ZOMBIE ARCHIVE cages line both walls (6 zombies with plaques; the Undead Sagittarius draws its bow at you). Hold F at the portcullis: the PLAY menu opens.
4. Stand on the ZOMBIE SURVIVAL pad (SINGLEPLAYER, right) for 3 s, press START NOW, or use PLAY → SOLO: a reserved Arena server (Studio: open the Arena place). GET READY, then ROUND 1 / 7. Kill zombies: a short `+10` with the Aura orb (no permanent counter in combat).
5. Die or win: you return to the Hub and keep your Aura and Denarii. Buy something in the GLADIATOR ARMORY (e.g. the
   Legion Sword: unlocked at level 2, costs 80 Denarii).

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
5. Win: Otti drops his sword and raises a paw, fireworks, `+500`, back to the Hub after 12 s.
   Start again: the intro now has a SKIP INTRO button, and no boss state is left over.

**Two-player co-op** (Arena place, `ArenaMockMode = "COOP_ZOMBIES"`, Test → Local Server, 2 players; live: a 2-player party)
1. Both players fight in the same reserved arena.
2. Round 1 has 2 zombies (2 × 100 %). Both players are targeted, damage gives assist Aura (`+3`).
3. Let one player die: they wait on the tribune and return with 72 HP after the round. If both die, the run ends.
4. Round 7: Otti has 1,850 HP and switches targets; he never grapples the same player twice in a row.

**Four-player co-op** (4 players)
1. Party of 4, START WITH CURRENT PARTY. Round 1 = 3 zombies (2 × 1.5), Round 6 = 48. 12 shells are active. At most 6 archers.
2. Zombies spread across all four players; no player has more than 4 attackers at once.
3. Round 7: 3,000 HP; tail sweeps can hit several players; surround him and he sweeps or dashes out.

**One-versus-one Time Battle** (Arena place `ArenaMockMode = "TIME_BATTLE"`, Local Server with 2 players; live: queue TIME BATTLE)
1. Teams are assigned (Red / Blue), 5 s at the protected spawns.
2. In the arena: `RED 0 — 0 BLUE`, `TIME 08:00`. Hits work only on the opponent, with damage caps. The defeated player respawns at their team spawn after 4 s with a force field.
3. To test sudden death, temporarily set `TeamModeDefinitions.TIME_BATTLE.DurationSeconds` to 30 and leave the score tied.

**Four-versus-four First to 20** (8 players; live: two parties of 4 or 8 players queue FIRST TO 20)
1. Equal teams only: a 5th player waits for the next match; 5 + 3 never starts.
2. Ready up, fight: friendly fire does nothing, eliminations/assists/deaths show in the right panel and the kill feed.
3. First to 20 wins: result screen, fireworks, +80 / +25 Aura, everyone back in the Hub, and a new match can start at once.

## Limitations

- Real teleports, reserved servers, cross-server matchmaking and spectating can only be tested in a published Experience (Studio = mock mode).
- Matchmaking has no skill rating yet and no region preference beyond Roblox's own server placement; the registry lists at most 1,000 matches (5 pages).
- A fighter who disconnects can't rejoin the running match (tickets are one-time); Co-op continues without them.
- Eliminated players are held in a closed room and their camera is restricted on the client; a modified client could still move its own camera (Roblox replicates character positions to every client).
- Parties are per Hub server; friends in other servers are invited with the Roblox invite and join the Hub first.
- Saving needs DataStore access (published place, or Studio with "Enable Studio Access to API Services"); without it progress is session-only and never written.
- Swings, thrusts, spins and parries move the equipment, not the player's arms (no uploaded animations).
- Otti's animation is procedural (client `OttiAnimator`); authored animations can be plugged in via `OttiBossConfig.AnimationIds`.
- Dashes, lunges, knockback and knockdowns on players are applied by the player's own client (Roblox gives it physics ownership); the server validates the hits. During Otti's throw the server anchors and moves the player itself.
- Arrows are simulated on the server and may look slightly choppy on high-latency clients.
- The arena floor is flat, so archers pick edge positions instead of elevated ones.
- Team Battle eliminations count every valid kill; Aura is only paid at the end of a match, so farming idle players gives no Aura.
- No crowd audio ships with the project (see `AudioConfig`). Balance (zombie damage, boss tuning, PvP multipliers) hasn't been play-tested yet; tune it in the shared definitions.

## Troubleshooting

- **Old modules still in Explorer** (`GameStateService`, `CoinService`, `HudController`, `WaveConfig`): disconnect and reconnect Rojo.
- **Prompts don't react to E:** interactions use **F** (E is the spectator "next" key).
- **"Attack … rejected: …" warnings:** temporary diagnostics, switch off with `DebugRejectedAttacks = false` in `CombatConfig`.
- **Build check:** `scripts/build-places.ps1` must build both `build/OttiHub.rbxlx` and `build/OttiArena.rbxlx`.
- **"This place was not built as the Hub / Arena":** the Studio window is synced with the wrong project file (each place needs its own `rojo serve` port).
- **Everything says STUDIO MOCK in a published place:** the Place IDs in `ExperienceConfig` are still 0 or belong to another environment.
- **Players land in a public Arena server:** they are sent back to the Hub automatically (matches only run on reserved servers).
