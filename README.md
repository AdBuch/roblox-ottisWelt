# Otti Arena – Combat

A small Roblox combat encounter built with VS Code + Rojo: a walled Roman arena, a
pathfinding Roman gladiator zombie, and a server-validated sword and shield.
Plain Luau, no packages, no Toolbox assets, no uploaded asset IDs. Everything is generated from Parts at runtime.

## Project structure

```
default.project.json              Rojo mapping (+ ReplicatedStorage.Remotes)
src/
  shared/  -> ReplicatedStorage.Shared
    Config.luau                   arena/shell values and remote names
    CombatConfig.luau             all combat numbers (damage, cooldowns, ranges, sounds)
  server/  -> ServerScriptService.Server
    Main.server.luau              entry point, startup checks, leaderstats, equipment
    Arena.luau                    floor, 28-stud walls, closed gate, columns, spawn, sign
    ArenaSafetyService.luau       returns players who end up outside the arena to the spawn
    Shells.luau                   3 golden shells (bonus), server-validated pickup
    Remotes.luau                  resolves the RemoteEvents (warns and creates them if missing)
    CombatUtil.luau               distance, facing and line-of-sight helpers
    ZombieModel.luau              builds the gladiator zombie rig (Parts + Motor6D + Humanoid)
    ZombieService.luau            zombie AI: detect, chase, telegraph, attack, respawn
    SwordService.luau             "Roman Sword" tool + swing validation and damage
    ShieldService.luau            "Roman Shield" tool + block state and block validation
  client/  -> StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau              HUD updates, state display, shell hiding
    Hud.luau                      HUD built from code
    ToolInput.luau                forwards sword/shield clicks to the server
    ZombieAnimator.luau           client-side walk cycle for the zombie
```

Remotes (created by `default.project.json`, in `ReplicatedStorage.Remotes`):

| RemoteEvent | Direction | Payload |
|---|---|---|
| `SwordAttack` | client → server | nothing (all arguments are ignored) |
| `ShieldBlock` | client → server | `true` / `false` (a request; the server decides) |
| `CombatFeedback` | server → client | `Swing`, `SwordHit`, `Block`, `PlayerHit` messages for the HUD |

## Start Rojo

From this folder:

```bash
rojo serve
```

It should print `Rojo server listening` on port `34872`.
If it says the port is in use, an older `rojo serve` is still running: stop it with Ctrl+C in its window.

## Connect Roblox Studio

1. If the Rojo plugin isn't installed yet: `rojo plugin install`, then restart Studio.
2. Open your place (or a new **Baseplate**).
3. Plugins → **Rojo** → **Connect** (`localhost:34872`).
4. Explorer should show `ServerScriptService.Server`, `StarterPlayer.StarterPlayerScripts.Client`,
   `ReplicatedStorage.Shared` and `ReplicatedStorage.Remotes` with `SwordAttack`, `ShieldBlock`, `CombatFeedback`.

## Studio test

Open **View → Output**, then press **Play** (F5).

| # | Do this | Expected |
|---|---|---|
| 1 | Try to jump over or walk through the wall and the gate | Impossible (walls 28 studs high, 6 thick, no gaps). If you get out anyway (e.g. via Studio tools) you are put back at the spawn within half a second |
| 2 | Walk toward the zombie in the middle | It turns, walks toward you (pathfinding around columns) |
| 3 | Stand still next to it, no shield | It raises its sword for ~0.35 s, then hits: **Health −10**, red screen flash, state **HIT**. Repeats every 1.4 s |
| 4 | Press **2** (shield), face the zombie and **hold left mouse** | **BLOCKING** label appears. A hit now does **−2**, the shield flashes, a sound plays and the zombie is pushed back |
| 5 | Block with your back to the zombie | Not blocked: full −10 |
| 6 | Step away during the wind-up | The swing misses (reach is re-checked when the blow lands) |
| 7 | Press **1** (sword), face the zombie and click | Slash motion; on a hit the zombie flashes and sparks. 15 damage per hit, max one hit per 0.65 s |
| 8 | Hit it 4 times (60 HP) | Zombie is defeated, state **VICTORY**, banner **"SETUP COMPLETE — Otti Arena combat works!"** |
| 9 | Wait 5 s | The zombie respawns in the middle with 60 HP |
| 10 | Walk over the golden shells | `Shells: X / 3` goes up (bonus) |

The block is held for at most 4 s (server safeguard); click again to raise it again.

## Expected output

```
[OttiArena][Server] Server script started
[OttiArena][Server] Disabled 1 SpawnLocation(s) outside the arena for this session
[OttiArena][Server] Arena ready (walls 28 studs high, gate closed)
[OttiArena][Server] Combat remotes ready (SwordAttack, ShieldBlock, CombatFeedback)
[OttiArena][Server] Zombie spawned (60 HP)
[OttiArena][Server] Ready
[OttiArena][Server] Equipment granted to <you>: Roman Sword, Roman Shield
[OttiArena][Client] Client script started for <you>
[OttiArena][Client] Ready: HUD created, sword/shield input bound
[OttiArena][Server] First sword request received from <you> (RemoteEvent works)
[OttiArena][Server] Roman Zombie defeated, respawning in 5s
[OttiArena][Server] <you> completed the combat check (zombie defeated)
[OttiArena][Client] SETUP COMPLETE — Otti Arena combat works!
[OttiArena][Server] Zombie spawned (60 HP)
```

"Disabled … SpawnLocation" only appears if the place has its own spawn (the Baseplate template does).

## What the server validates

- **Sword:** sword tool equipped (one the server created), player alive, not blocking, 0.65 s cooldown,
  zombie alive, within 7 studs, zombie within ~72° of where the player faces, no wall in between. Damage is always 15.
- **Zombie attack:** target alive and inside the arena, in range when the attack starts and still within 6.5 studs when it lands,
  line of sight, 1.4 s cooldown, zombie alive. Damage is always 10.
- **Shield:** shield equipped, player alive, block raised (max 4 s), zombie within 60° in front and within 10 studs.
  Blocked damage = 10 × 20 % = 2.

## Checklist

- [ ] Rojo sync works – the modules and the 3 remotes appear in Explorer; saving a file in VS Code updates Studio.
- [ ] Server runs – the "Arena ready", "Zombie spawned", "Combat remotes ready" and "Equipment granted" lines appear.
- [ ] Client runs – the HUD shows health, zombie HP, hints and the state.
- [ ] RemoteEvents work – "First sword request received … (RemoteEvent works)" after the first click.
- [ ] Arena is escape-proof – tests 1 above.
- [ ] Zombie AI – tests 2, 3, 6.
- [ ] Shield – tests 4, 5.
- [ ] Sword – tests 7, 8 (exactly four hits).
- [ ] Respawn – test 9.

## Troubleshooting

- **Plugin can't connect** – make sure `rojo serve` is running in this folder and the port matches (34872).
- **"Version mismatch" in the plugin** – `rojo plugin install`, then restart Studio.
- **Warning: `ReplicatedStorage.Shared … is missing`** – Rojo isn't connected (or connected after pressing Play). Connect first, then Play.
- **Warning: `Remotes.X is missing … creating it at runtime`** – the Remotes mapping didn't sync; the game still works, but check `default.project.json`.
- **Sword clicks do nothing** – you must hold the sword (key 1), face the zombie and be within 7 studs. Clicks on UI are ignored.
- **Shield never blocks** – hold the shield (key 2), keep the mouse button down and face the zombie. Holding longer than 4 s drops the block.
- **Zombie doesn't move** – it only chases players inside the arena within 60 studs. Check the Output for warnings.
- **No sounds** – the sounds are built-in Studio placeholders (`rbxasset://sounds/...`); replace the IDs in `CombatConfig.luau` if you want your own.
- **Build check** – `rojo build -o OttiArena.rbxlx` should finish without errors.

## Limitations

- Sword and shield are two separate Roblox Tools, and Roblox lets you hold only one Tool at a time.
  Switch with **1** / **2**, so you can't attack while blocking.
- Facing uses the direction your character faces. With the default camera your character turns when you walk;
  Shift Lock makes aiming easier.
- The zombie's walk cycle is client-side (each player animates it locally); the attack pose comes from the server.
- The slash and shield-raise motions move the tool, not the player's arm (no uploaded animations).
- Only one zombie exists at a time; when several players fight it, everyone who hit it gets the victory.

## Optional: VS Code autocomplete

With the Luau Language Server extension, generate a sourcemap so `require(script.Parent.X)` resolves:

```bash
rojo sourcemap default.project.json --output sourcemap.json --watch
```
