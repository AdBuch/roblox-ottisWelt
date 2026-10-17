# Otti Arena – Setup Check

A tiny playable Roblox game that proves VS Code + Rojo + Roblox Studio work together.
Plain Luau, no packages, no Toolbox assets. All geometry is generated from Parts at runtime.

## Project structure

```
default.project.json          Rojo mapping
src/
  shared/  -> ReplicatedStorage.Shared
    Config.luau               shared constants (names, damage, ranges)
  server/  -> ServerScriptService.Server
    Main.server.luau          entry point, leaderstats, startup checks
    Arena.luau                floor, wall, columns, spawn, sign
    Shells.luau               3 golden shells, server-validated pickup
    Dummy.luau                Roman Zombie training dummy (30 HP, respawns after 5 s)
    Combat.luau               validates attack requests (cooldown, range, state)
  client/  -> StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau          input, HUD updates, hides collected shells locally
    Hud.luau                  HUD built from code
```

`default.project.json` also creates `ReplicatedStorage.Remotes.Attack` (RemoteEvent).

## Start Rojo

From this folder:

```bash
rojo serve default.project.json
```

It should print `Rojo server listening` on port `34872`.

## Connect Roblox Studio

1. If the Rojo Studio plugin isn't installed yet, run `rojo plugin install` once and restart Studio.
2. Open Studio, create a new **Baseplate** place.
3. Plugins tab → **Rojo** → **Connect** (default `localhost:34872`).
4. In the Explorer you should now see `ServerScriptService.Server`, `StarterPlayer.StarterPlayerScripts.Client`,
   `ReplicatedStorage.Shared` and `ReplicatedStorage.Remotes.Attack`.

## Run the playtest

1. Open the Output window (View → Output).
2. Press **Play** (F5).
3. Walk onto the three glowing golden shells.
4. Walk up to the Roman Zombie in the middle and left-click until it's defeated (3 hits).

## Expected output

```
[OttiArena][Server] Server script started
[OttiArena][Server] Disabled 1 SpawnLocation(s) outside the arena for this session
[OttiArena][Server] Roman Zombie respawned
[OttiArena][Server] Ready: arena built with 3 shells and a 30 HP training zombie
[OttiArena][Client] Client script started for <you>
[OttiArena][Client] Ready: HUD created and left-click attack bound
[OttiArena][Server] <you> collected shell 1 (1/3)
...
[OttiArena][Server] First attack request received from <you> (RemoteEvent works)
[OttiArena][Server] Roman Zombie defeated, respawning in 5s
[OttiArena][Server] <you> completed the setup check (3 shells + zombie defeated)
[OttiArena][Client] Setup successful — Rojo, client and server are working!
```

The "Disabled … SpawnLocation" line only appears if the place has its own spawn (the Baseplate template does).
"Roman Zombie respawned" also appears at startup because the dummy spawns through the same code path.

On screen: a HUD bottom-left with `Shells: X / 3`, zombie HP and an attack counter, and a green banner
at the top when both goals are complete.

## Checklist

- [ ] **Rojo sync works** – `Server`, `Client`, `Shared` and `Remotes.Attack` appear in Studio's Explorer after connecting; editing a `.luau` file in VS Code updates the script in Studio.
- [ ] **Server script runs** – Output shows `[OttiArena][Server] Server script started` and the arena appears in `Workspace.GeneratedArena`.
- [ ] **Client script runs** – Output shows `[OttiArena][Client] Client script started` and the HUD is visible.
- [ ] **RemoteEvent works** – after the first left-click, Output shows `First attack request received … (RemoteEvent works)`.
- [ ] **UI updates** – `Shells: X / 3` and `Zombie HP` change as you collect and hit.
- [ ] **Player input works** – the "sent: N" counter in the HUD goes up on left-click and the zombie flashes white when hit in range.

## Troubleshooting

- **Plugin can't connect** – make sure `rojo serve` is still running, and the port in the plugin matches (34872). Check a firewall isn't blocking localhost.
- **"Version mismatch" in the plugin** – reinstall the plugin from your CLI version: `rojo plugin install`, then restart Studio.
- **Scripts don't appear in Studio** – run `rojo serve` from the folder that contains `default.project.json`.
- **Warning: `ReplicatedStorage.Shared.Config is missing`** – Rojo isn't connected (or was connected after pressing Play). Connect first, then Play.
- **Warning: `Remotes … creating it at runtime`** – the Rojo mapping for `Remotes` didn't sync; the game still works, but check `default.project.json`.
- **Clicks don't damage the zombie** – you must be within 8 studs and there's a 0.5 s cooldown. Clicks on UI are ignored.
- **Shell won't collect** – each shell counts once per player; collected shells turn invisible only for you.
- **Build check** – `rojo build default.project.json -o OttiArena.rbxlx` should finish without errors.

## Optional: VS Code autocomplete

With the Luau Language Server extension, generate a sourcemap so `require(script.Parent.X)` resolves:

```bash
rojo sourcemap default.project.json --output sourcemap.json --watch
```
