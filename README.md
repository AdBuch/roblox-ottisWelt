# Otti Colosseum

A complete Roblox prototype game loop built with VS Code + Rojo:

**underground prison lobby → buy/choose equipment → enter the arena → survive six zombie rounds
(1, 2, 4, 8, 16, 32) → earn coins → fireworks and victory → back to the lobby.**

Plain Luau (strict), no packages, no Toolbox assets, no uploaded asset IDs. Everything is generated
from Parts, built-in materials, built-in SpecialMesh shapes, ParticleEmitters and lights at runtime.
The server makes every gameplay decision.

> **One fighter at a time.** This prototype runs one arena run per server. While someone is
> fighting, the arena gate shows **ARENA BUSY** and other players can watch from the tribune.
> The code keeps fighter data in a `run` object so multiple runs can be added later.

## Project structure

```
default.project.json                Rojo mapping (+ Remotes, + Health override)
src/
  shared/      -> ReplicatedStorage.Shared
    Config.luau                     names, attributes, remotes, shell healing/respawn
    CombatConfig.luau               player/shield/crowd tuning, zombie cap (32), sounds, debug switch
    GameStates.luau                 per-player states (LOBBY, ROUND_ACTIVE, VICTORY, …)
    WeaponDefinitions.luau          4 weapons: stats and prices
    ShieldDefinitions.luau          4 shields: reduction and prices
    ZombieDefinitions.luau          5 zombie types: stats, coins, availability, weights, looks
    RoundDefinitions.luau           six rounds, countdowns, weighted variant picking
  server/      -> ServerScriptService.Server
    Main.server.luau                entry point: builds the world, starts the services
    Arena.luau                      Colosseum + accessible tribune walkways and stairs
    LobbyService.luau               underground lobby (cells, torches, gate, tribune door, shop wall)
    EquipmentShopService.luau       pedestals with models, plaques and BUY/EQUIP prompts
    EquipmentModels.luau            procedural weapon/shield/arrow models
    InventoryService.luau           coins, owned/equipped items, purchases (session storage)
    CoinService.luau                kill rewards (exactly once per zombie death)
    GameStateService.luau           state machine: lobby/arena/tribune/defeat/victory, run lifecycle
    WaveService.luau                six fixed rounds, intermissions, victory trigger
    VictoryService.luau             fireworks and fanfare
    PlayerCombatService.luau        weapons in hand, melee/bow attacks, blocking, hits on the player
    ZombieFactory.luau              builds a zombie rig for any type
    ZombieService.luau              per-zombie AI, specials, damage, death, cleanup
    ZombieCrowdService.luau         melee slots and the 4-attacker limit around the player
    ArenaSafetyService.luau         returns anyone/anything out of bounds to a valid place
    ShellService.luau               healing shells (+3, respawn after 12 s)
    CombatUtil.luau                 distance, facing, line-of-sight helpers
    Remotes.luau                    resolves the RemoteEvents
  client/      -> StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau                wires everything, HUD state, target bar
    HudController.luau              HUD built from code
    InputController.luau            LMB attack / RMB block, touch ATTACK/BLOCK buttons
    ShopController.luau             per-player shop plaques, prompt text, equipped highlight
    EffectsController.luau          floating damage numbers
    ZombieAnimator.luau             client-side walk cycle for all zombies
  character/   -> StarterPlayer.StarterCharacterScripts
    Health.server.luau              empty override: no automatic health regeneration
```

Remotes (`ReplicatedStorage.Remotes`):

| RemoteEvent | Direction | Payload |
|---|---|---|
| `WeaponAttack` | client → server | aim point (only used by the bow; validated) |
| `ShieldBlock` | client → server | `true` / `false` (a request; the server owns the block state) |
| `CombatFeedback` | server → client | `Swing`, `Hit`, `Block`, `PlayerHit`, `Heal`, `Coins`, `Shop`, `Slowed` |

Shop and doors use server-side **ProximityPrompts**, no remotes.

## Start Rojo and connect Studio

```bash
rojo serve
```

1. Run it in this folder; it should print `Rojo server listening` on port `34872`.
   If the port is in use, a `rojo serve` is already running: reuse it or stop it with Ctrl+C.
2. Studio: open your place, Plugins → **Rojo** → **Connect**.
3. Explorer should show `ServerScriptService.Server` (GameStateService, LobbyService, …),
   `StarterPlayer.StarterPlayerScripts.Client` (HudController, …), `StarterCharacterScripts.Health`
   and `ReplicatedStorage.Remotes` with `WeaponAttack`, `ShieldBlock`, `CombatFeedback`.
4. **View → Output**, then **Shift+F5** (stop) and **F5** (play).

## Controls

| Input | Action |
|---|---|
| Left mouse button | Attack with the equipped weapon (the character turns toward the cursor; the bow shoots at the cursor) |
| Right mouse button (hold) | Block with the shield; you keep facing where the camera looks |
| E (hold) at a pedestal | Buy or equip that item |
| E (hold) at a door | ENTER ARENA / TRIBUNE / RETURN TO LOBBY |
| Touch: **ATTACK** / hold **BLOCK** | Mobile fallback |

Weapon (right hand) and shield (left hand) are always visible together. Attacks only work in the arena.
Clicking while blocking does nothing. A block lasts at most 4 s (server safeguard): release and press again.

## Game loop

1. **Lobby (spawn and respawn point):** a safe underground hall below the Colosseum. Nothing can hurt you here.
2. **Equipment wall (west):** 4 weapons and 4 shields on pedestals. Starter items are owned. Buy with coins, then equip.
3. **ENTER ARENA (north gate):** checks your loadout, closes the gate and puts you on the arena floor. Round 1 starts after a 3 s countdown.
4. **Rounds:** 1, 2, 4, 8, 16 and 32 zombies. The next round starts only when every zombie is dead: `ROUND COMPLETE` → 4 s countdown.
   No healing between rounds; shells are the only healing.
5. **Death:** the run ends, all zombies are removed and you respawn in the lobby. Coins and items are kept.
6. **Victory (Round 6 cleared):** `COLOSSEUM CONQUERED`, fireworks, fanfare and a summary (kills, coins earned), then `GAME COMPLETE`.
   After about 12 s you are returned to the lobby and the arena is ready for another run.
7. **TRIBUNE (east door):** spectator stands with a lower and a middle walkway, two staircases, a railing, two viewing platforms
   and a RETURN TO LOBBY door. Spectators can't attack and can't be attacked.

## Weapons

| Weapon | Price | Damage | Cooldown | Range | Notes |
|---|---|---|---|---|---|
| Rusty Gladius | free | 18 | 0.55 s | 7 | starter |
| Legion Sword | 80 | 28 | 0.65 s | 7.5 | polished bronze and steel |
| Hunter Bow | 130 | 24 | 0.9 s | 90 | arrows at 110 studs/s, stopped by walls |
| Gladiator Morning Star | 190 | 40 | 1.15 s | 8 | wide arc, short stagger |

Melee hits the **closest valid zombie** in range and arc (one target per swing). Range is measured to the zombie's body.

## Shields

| Shield | Price | Frontal reduction | Notes |
|---|---|---|---|
| Wooden Buckler | free | 50 % | starter, small |
| Legion Shield | 60 | 65 % | red wood, bronze rim |
| Arena Tower Shield | 120 | 78 % | large, slower while blocking |
| Champion Shield | 200 | 88 % | ornate bronze, double stagger on blocked attackers |

Blocking only works when the attacker is within 60° in front of you; hits from the side or behind deal full damage.

## Zombies

| Type | HP | Damage | Speed | Attack cooldown | Coins | From round | Weight |
|---|---|---|---|---|---|---|---|
| Legion Remnant (balanced) | 60 | 10 | 12 | 1.4 s | 10 | 1 | 40 |
| Rotten Velite (fast) | 40 | 7 | 15 | 0.95 s | 8 | 2 | 25 |
| Arena Brute (strong) | 100 | 18 | 8.5 | 2.1 s | 18 | 3 | 17 |
| Zombie Net Fighter (tactical) | 55 | 8 | 11.5 | 1.3 s | 14 | 3 | 13 |
| Zombie Arena Champion (elite) | 130 | 15 | 9 | 1.6 s | 25 | 4 | 5 |

Unavailable types are filtered out and the remaining weights normalized, so Round 1 is only Legion Remnants.

- **Net Fighter:** every 7 s it may raise its net (0.7 s telegraph) and throw it from up to 13 studs.
  If it lands, you are 25 % slower for 2 s (refreshes, never stacks).
- **Arena Champion:** raises its glowing ornate shield for 1.6 s, then must wait 4.5 s. It is also exposed right after attacking.
  While raised, attacks from the front are **BLOCKED**; attacks from the side or behind (including arrows) still hit.

## Fairness and crowd control

- Every zombie attack has a visible wind-up (0.3–0.6 s) and is re-checked when it lands: reach, line of sight, target still fighting.
- At most **4 zombies** attack at the same time, and new wind-ups start at least 0.25 s apart.
- After a landed zombie hit you are immune for **0.35 s**, so several zombies can't remove your health in one burst.
- Player health is **120** and never regenerates on its own.

## Zombie separation

- **Solid bodies:** each zombie's HumanoidRootPart is sized to its torso and collides (collision group `Zombies`
  collides with `Default` and itself). Players can't walk through living zombies and zombies can't overlap.
- **Melee slots:** `ZombieCrowdService` puts 10 slots on a 4.4-stud ring around the player. A nearby zombie claims the free
  slot closest to it; zombies without a slot circle on an 11-stud ring and wait for a free one.
- **Separation steering:** each zombie adds a push away from neighbours closer than 3.8 studs to its movement goal.
- **Spawn spacing:** zombies spawn spread over 7 gates, offset sideways and in depth, 0.25 s apart.
- **Stuck detection:** a zombie that wants to move but doesn't first sidesteps, then is moved to a free spot.
- **Corpses** are anchored, stop colliding, fade for 1 s and are removed.

## Coins, items and storage

- Coins come only from zombie kills, awarded by the server to the killing player exactly once per death
  (`CoinService` builds a reward event so assists or shared rewards can be added later).
- `InventoryService` keeps one profile per **UserId** in server memory: coins, owned weapons/shields,
  equipped weapon/shield. It survives death, returning to the lobby and rejoining the **same** server.
  There is no DataStore yet; `serialize()` and the profile constructor are the hook points for it.
- Purchases check ownership and balance (never negative, no duplicates). Equipping requires ownership.
  The equipment in the hands is always rebuilt from the server inventory, so clients can't fake items.

## Expected output (start)

```
[OttiArena][Server] Server script started
[OttiArena][Server] Disabled 1 SpawnLocation(s) outside the arena for this session
[OttiArena][Server] Arena ready: Colosseum 140x110 studs, 7 zombie gates, tribune walkways
[OttiArena][Server] Lobby ready: underground hall, equipment wall, ENTER ARENA gate, TRIBUNE door
[OttiArena][Server] Combat remotes ready (WeaponAttack, ShieldBlock, CombatFeedback)
[OttiArena][Server] Ready: one fighter at a time, 6 rounds (1, 2, 4, 8, 16, 32 zombies)
[OttiArena][Server] Equipment granted to <you>: Rusty Gladius + Wooden Buckler
[OttiArena][Client] Ready: HUD, LMB attack / RMB block, shop displays
```

During a run: `Run 1: <you> entered the arena`, `Round 1/6 started: 1 zombie(s)`, `Round 1 complete…`, …,
`All rounds complete: COLOSSEUM CONQUERED`, `Run 1 ended: victory`.
Rejected attacks print a short warning (at most every 2 s per reason); switch off with `DebugRejectedAttacks = false`.

## Studio test steps

1. **Spawn:** press F5. You stand in the torch-lit underground hall facing the `OTTI COLOSSEUM` board.
   HUD: `OTTI COLOSSEUM`, `COINS 0`, `WEAPON Rusty Gladius`, `SHIELD Wooden Buckler`. A sword and buckler are in your hands.
2. **Shop:** walk to the west wall. 4 weapons + 4 shields on pedestals. The starter items say EQUIPPED (green outline),
   the rest LOCKED with prices. Holding E on a locked item shows `Not enough coins…`.
3. **Safety:** left click in the lobby does nothing. Hold right click: the shield rises (`BLOCKING`).
4. **Tribune:** hold E at the east door. You arrive on the lower walkway. Walk around, take a staircase to the middle walkway,
   visit a viewing platform. Hold E at `RETURN TO LOBBY` to go back.
5. **Arena:** hold E at the north `ENTER ARENA` gate. You appear on the arena floor, `GET READY`, then `ROUND 1 / 6 · ZOMBIES 1 / 1`.
6. **Fight:** left click at the zombie: damage numbers, flash, `+10 COINS` when it dies. Hold right click facing it: hits do 5 instead of 10.
   Turn your back while blocking: full 10.
7. **Shells:** when hurt, touch a golden shell: exactly `+3 HEALTH`; it reappears after 12 s. At full health it isn't used.
8. **Rounds:** check `ZOMBIES 2/2`, `4/4`, `8/8`, `16/16`, `32/32`. Zombies surround you instead of stacking, at most 4 attack at once.
   From Round 3 Net Fighters (blue-gray, net) and Brutes appear, from Round 4 the rare purple-crested Champion.
9. **Defeat:** let the zombies win. `DEFEATED`, all zombies vanish, you respawn in the lobby with your coins.
10. **Buy:** with ≥ 80 coins buy the Legion Sword (coins drop by 80 immediately, it becomes EQUIPPED in your hand).
11. **Bow:** buy/equip the Hunter Bow; arrows fly to the cursor and stop at walls.
12. **Victory:** clear Round 6. `COLOSSEUM CONQUERED`, fireworks, summary, `GAME COMPLETE`, back to the lobby after ~12 s.
    Enter again: a fresh run starts at Round 1.

## Troubleshooting

- **Plugin can't connect / port in use** – only one `rojo serve` can run; reuse it or stop it.
- **Old scripts in Explorer** (e.g. `SwordService`, `Hud`, `CombatInput`) – disconnect and reconnect Rojo.
- **`ReplicatedStorage.Shared.X is missing`** – connect Rojo before pressing Play.
- **Health regenerates** – `StarterCharacterScripts.Health` must exist (from Rojo); the server also removes any `Health` script.
- **Attack rejected: invalid facing direction** – aim at the zombie with the mouse; the character turns toward the cursor.
- **Too hard / too easy** – `ZombieDamageMultiplier`, `MaxSimultaneousAttackers` and `HitImmunitySeconds` in `CombatConfig.luau`.
- **Build check** – `rojo build -o OttiArena.rbxlx` must succeed.

## Limitations

- One active fighter per server (explicit in the HUD: "Arena busy: … watch from the TRIBUNE").
- Coins and items are kept only for the current server session (no DataStore yet).
- Weapon swings, the bow draw and the shield raise move the equipment, not the player's arms (no uploaded animations).
- Zombie walk cycles are animated on each client; attack, net and guard poses come from the server.
- Arrows are simulated and moved on the server, so they look slightly less smooth on high-latency clients.
- Sounds are built-in Studio placeholders (`rbxasset://sounds/...`); the fanfare is a pitched placeholder chime.
- The tribune is reached by a teleport door (physical stairs in the lobby are decorative), for reliability.
- Balance hasn't been play-tested yet; tune it in `CombatConfig`, `ZombieDefinitions` and `WeaponDefinitions`.

## Optional: VS Code type checking

With the Luau Language Server extension:

```bash
rojo sourcemap default.project.json --output sourcemap.json --watch
```
