# Lobby: the Colosseum's gathering hall

The Hub is a Roman fantasy gladiator complex built by `src/server/LobbyService.luau`. The player sees one clear destination on arrival: Solo Zombies straight ahead. Otti's monument is beside the path, not across it.

## Four active entry areas

| Area | Position | Behavior |
|---|---|---|
| SOLO ZOMBIES | Main arena gate | Walk straight in; three-second countdown. Step off to cancel. The gate prompt starts directly, with no mode picker. |
| OTTI CO-OP | Right wing, near the entrance | One Otti mosaic for a group of 1–4. START plays together; FIND PLAYERS uses the existing co-op queue. Training is beyond it. |
| TEAM SCHILI | North side of the left team hall | Blue team, 1–4 players. Step onto the mosaic to join; captain presses READY. |
| TEAM KROKERO | South side of the same team hall | Red team, 1–4 players. Opposing group, with its own captain and READY button. |

The duplicate solo carpet and the unused Boss Fight, Arena Fight, Chaos Games, Boss Co-op and Arena Co-op carpets are removed. No COMING SOON pads are built. Existing implemented match types remain available through the PLAY menu, but the physical team hall starts one default: Time Battle.

## Team-versus-team flow

`PadTeamBattleService` reads the two public pad parties and server-side character positions. Both teams must have the same size, from 1v1 to 4v4; all players must be alive, loaded, on their own mosaic, equipped and outside matchmaking queues.

Each captain confirms the current rosters. Confirmations expire after 30 seconds. Entering/leaving a team mosaic clears readiness; a changed roster also invalidates the recorded confirmation signature. One captain cannot start both groups alone.

Once both confirm, the parties lock, Hub actions are blocked by COUNTDOWN, and one reserved TIME_BATTLE Arena is created with the actual chosen sides: Schili = Blue, Krokero = Red. Positions are checked again after reservation. Failure releases the groups; a live teleport has a 25-second recovery timer for players still in the Hub. Studio reports a mock start and unlocks both parties without teleporting.

Private parties must be left before joining these explicit local teams. Co-op and menu matchmaking retain their existing party behavior.

## Architecture and presentation

- Left: one compact shared team hall, x -42 to -114, z -34 to 34. Two opposing mosaics at (-78, -18) and (-78, 18), with a clear central aisle. No four-room partitions.
- Right: one co-op mosaic at (62, 0), facing the hall. Training remains at the far end.
- Panels use limestone with bronze edging instead of bright fabric carpets and neon borders. Board headings, team banners, warm torches and fine mosaics provide orientation.
- Mosaics are 29 x 29 patterns, 13.5 studs wide. Individual anchored slate tiles retain grout and subtle color variation; decoration is non-colliding and casts no shadows.
- Otti's monument remains west of the unobstructed approach. Direct joins spawn at (0, 28), facing the games; later respawns and fighter returns use (18, 12). Returning spectators appear near the live board.
- The archive corridor, forge/armory, tribune access and closed Gate to Rome remain part of the complex.

## Character identity

Schili is a younger adult tortoise: thoughtful, patient and quietly playful, with kind eyes, an open expression, an upright long neck and a scroll. The mosaic uses green shell tones, cream highlights and a terracotta tunic. His team motto is “Patience, then surprise.”

Krokero is a confident crocodile with a long snout, warm grin and sturdy terracotta equipment. His team motto is “A big grin and bigger courage.” Both portraits belong to Otti's Roman fantasy world.

## Validation

- Both Rojo places and strict type analysis.
- `scripts/test-pad-teams.ps1 -LuauPath <path-to-luau.exe>` exercises the actual team module using mocked services: captain checks, rosters, equal sizes, queue/data/gear checks, confirmations, side assignment, reservation failure, changed positions, mock cleanup and transport recovery.
- Studio/device checks: first arrival sightline, all four entry areas, mosaic visibility and direction, two captains through a real published teleport, co-op and spectators, phone frame times and crowding.

The Schili/Krokero personality notes describe the lobby identity and future dialogue direction; no speaking NPC or autonomous character behavior is introduced by the mosaics.
