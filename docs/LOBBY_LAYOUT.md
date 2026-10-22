# Lobby: the gladiator dungeon under the Colosseum

Hub place only (`places/hub.project.json`). Built at runtime by `src/server/LobbyService.luau`. All parts are
anchored, use built-in materials and need no asset ids. The lobby is a safe zone: no damage, no PvP, no blood.

## 1. Existing functions and dependencies (kept)

| Function | Module | Change in the redesign |
|---|---|---|
| Arrival / respawn (`LobbyArrivalSpawn` / `LobbyRespawn`) and the fall-out safety net | `LobbyService`, `hub/server/Main.server` | Direct joins face the clear arena route; later respawns use the side of the hall. `isInside` now checks a list of walkable zones. |
| GLADIATOR ARMORY: displays, buying, equipping | `EquipmentShopService`, `ShopController`, `InventoryService` | Unchanged. The chamber is moved as a whole (`ARMORY_OFFSET`) to the end of a new side passage, and its display lines move with it. |
| ZOMBIE ARCHIVE: six caged display zombies | `ZombieDisplayService` | The cages now line the main arena corridor (3 per side). The slots and plaques use the same API. |
| Training dummies and the training board | `TrainingService`, `ComboFeedbackController` | Moved to the far end of the singleplayer wing. The board keeps its name `ComboTrainingBoard`. |
| Solo start | `HubMatchService.playSolo` | Called by the ZOMBIE SURVIVAL pad. The old solo gate prompt is removed. |
| Co-op start | `HubMatchService.startCoop` | Called by the START button of the ZOMBIE CO-OP pad. |
| Matchmaking (Co-op, Time Battle, First to 20, Elimination) | `MatchmakingService` | Called by the pad queue buttons; a second press stops the search. |
| Parties | `PartyService` | Pad parties: one public group per pad (`joinPadParty`, `leavePadParty`, `padParty`). The post party `togglePostParty` is replaced. |
| WATCH LIVE and the live board | `HubMatchService` | Two tribune doors at the top of the side stairs. The live board stands on the hall floor. |
| PLAY menu, live overlay, travel status | `GameModeMenuController`, `ActiveBattlesController`, `TeleportStatusController` | Unchanged. The main arena entrance starts Solo Zombies directly; other modes remain available from the wings and PLAY menu. |

Removed: the old mode posts (JOIN / READY / START / FIND PLAYERS / TIME / FIRST TO / ELIMINATION / LEAVE QUEUE), the
solo gate, the barred prison corridor and the east archive annex. Their functions now run through the pads, the
arena corridor and the PLAY menu.

## 2. Layout (floor at y = -80, front = -Z)

```
                         sunlit ARENA (view only)
                               ║ portcullis  (z -112, walk in = SOLO ZOMBIES)
                               ║ ramp +6 studs (z -88 .. -104)
            gladiator cell ┌───╫───┐ gladiator cell
              zombie cage  │ ARENA │ zombie cage        ZOMBIE ARCHIVE (6 cages)
              zombie cage  │ CORR. │ zombie cage
              zombie cage  └───╫───┘ zombie cage
  TRIBUNE ◄stairs ┌──────────── ARENA gate ────────────┐ stairs► TRIBUNE
  ┌───────────────┤                                    ├────────────────────┐
  │ MULTIPLAYER   │                                    │   SINGLEPLAYER     │
  │ [Co-op][Boss] ◄══    CENTRAL HALL  ( OTTI )      ══► [Survival][Arena]  │
  │ [Team ][Arena]│               spawn                │ [Boss ][Chaos] TRAIN│
  └───────────────┤                                    ├────────────────────┘
       ARMORY ◄── side passage + forge    GATE TO ROME (closed)
```

| Area | Extent (x, z) | Notes |
|---|---|---|
| Central hall | -40..40, -36..36, height 26 | Otti statue (`LobbyStatue`, scale 1.7) on a pedestal beside the central route at (-18, 0), 4 braziers, direct-arrival spawn at (0, 28) facing north; respawns and Arena returns at (18, 12), signpost, two light shafts, guide strips |
| Arena corridor | -10..10, -38..-112 | 3 zombie cages and 1 gladiator cell per side, ramp, landing, portcullis, arena view beyond (not walkable) |
| Multiplayer wing | -42..-154, -34..34 | Four group rooms around a central aisle. Pads 24 × 16 with a 15 × 15 floor mosaic. Board, banners and start pedestals per room |
| Singleplayer wing | 42..124, -28..28 | Four pads of 14 × 11 at x 58 / 84, training yard at x 98..122 |
| Tribune stairs | front corners, landings at y +12 | 12 steps each; tribune doors in the north wall at x ±36 |
| Side passage | -34..-20, 38..88 | Forge, weapon racks, closed UPGRADES door at the end; the armory door is on its west side |
| Gladiator Armory | -136..-36, 42..118 | The original chamber, moved by `ARMORY_OFFSET` (42, 0, 80) |

## 3. Matchmaking pads

Configuration: `src/shared/LobbyPadDefinitions.luau`. Builder: `LobbyService.buildPad`. Logic: `src/hub/server/LobbyPadService.luau`.

- **Detection is server-side.** Every 0.25 s the server checks which pad each player in the lobby state stands on,
  using the character position inside the pad's area. Clients never report it.
- **Solo pads:** stepping on starts a 3-second countdown, shown on the board and in a message. Stepping off cancels
  it. START NOW starts at once.
- **Group pads:** stepping on joins the pad's group (max 4); stepping off leaves it, except while the group is queued
  or travelling. The board lists the members (★ = leader) and the state. START (Co-op) and the queue buttons only
  work while the player stands on the pad. Leader, loadout, data and queue are checked by `HubMatchService` and
  `MatchmakingService`. A private party (PLAY menu) can start from any pad, and a single player alone can too.
- **Disabled pads** are built and signed COMING SOON; stepping on them only shows a note.

| Pad | Wing | State | Action |
|---|---|---|---|
| ZOMBIE SURVIVAL | Single | live | `SOLO_ZOMBIES` |
| BOSS FIGHT | Single | coming soon | needs a boss-only match mode |
| ARENA FIGHT | Single | coming soon | needs a mode |
| CHAOS GAMES (FFA) | Single | coming soon | needs a mode |
| ZOMBIE CO-OP (Otti mosaic) | Multi | live | START (`COOP_ZOMBIES` with the group), FIND PLAYERS (queue) |
| TEAM DEATHMATCH (Schili mosaic) | Multi | live | queue TIME BATTLE / FIRST TO 20 / ELIMINATION |
| BOSS FIGHT CO-OP (Otti mosaic) | Multi | coming soon | needs a mode |
| ARENA CO-OP (Schili mosaic) | Multi | coming soon | needs a mode |

**Adding a mode later:**
1. Add the mode to `MatchDefinitions` and the Arena place.
2. Set `Enabled = true` on its pad.
3. Give the pad its `Mode` (Solo pads) or `Actions` (Group pads). Queued modes work as soon as `MatchmakingService`
   knows them; a direct-start mode needs a handler in `LobbyPadService.startSolo` / `HubMatchService`.

## 4. Atmosphere and performance

- **Look:** massive stone walls, vault ribs, columns, iron bars, wooden doors, cages, chains, torches, braziers,
  light shafts, sandy worn floors, SPQR banners and the bright arena behind the portcullis.
- **Lighting:** warm and dim (`Lighting.Ambient` and related settings in `LobbyService.applyLighting`).
- **Mosaics** use fine 29 x 29 patterns with individual slate tesserae, visible grout and subtle stone-colour variation. Otti uses 463 parts and Schili 407 (including the two base slabs); the panel width stays 13.5 studs. All four group-pad mosaics total 1,740 anchored, non-colliding parts.
- **Decoration** never collides, is never queried or touched, and small pieces cast no shadow.
- **Lights:** about 70 in the whole lobby. Each torch has 1 PointLight and 1 Fire; braziers, cage lamps, light
  shafts and the arena sun add the rest. No shadow-casting lights, no physics constraints.
- **Not measured:** there was no Studio run, so frame times, memory and part counts are not measured yet.

## 5. Open points

- **Schili mosaic:** a green turtle with a segmented shell, head, four feet and tail, inside a gold ring. Both Schili and Otti use a finer tessera grid.
- **Missing modes:** BOSS FIGHT, ARENA FIGHT, CHAOS GAMES, BOSS FIGHT CO-OP and ARENA CO-OP have no match mode yet.
  Open PvP arenas and level-based matchmaking are still to be decided.
- **Gate to Rome:** closed. It can later teleport to the open Roman world.
- **Public arena world:** the tribunes and the public arena are planned as part of the connected Roman world.
  Regular matches stay on separate Arena servers.

## 6. Studio test checklist

1. Direct join: Otti is to your left and the ZOMBIE SOLO entrance is straight ahead. Walk straight to enter a solo run; reset your character to check the separate side-hall respawn.
2. Multiplayer: two players step on ZOMBIE CO-OP. The board shows ★ and both names. The leader presses START, a
   non-leader gets a message. Stepping off leaves the group.
3. Team Deathmatch: the leader presses FIRST TO 20 → the board shows SEARCHING; a second press stops the search.
4. Singleplayer: stand on ZOMBIE SURVIVAL for 3 s → the solo run starts. Stepping off before that cancels it.
5. COMING SOON pads only show a note.
6. Armory: buying and equipping work, and the cards appear only inside the chamber.
7. Archive: 6 zombies in the corridor cages.
8. Training: the dummies take hits and the training board text appears.
9. Tribune doors: WATCH LIVE opens the live overlay. The portcullis starts Solo Zombies directly, with no mode picker. The Gate to Rome shows its
   message.
10. Fall out of the level: you are sent back to the spawn.
11. Check on a phone: readability of the pads, prompts and signs, and the frame rate.

## Direct arrival and default arena entrance

- Otti's entire monument stands west of the centre line so the statue remains visible beside the unobstructed route to the games.
- A direct Hub join starts at (0, 28), facing north toward ZOMBIE SOLO. Character placement is also applied to players already present during initialization.
- Later character respawns and fighter returns from the Arena use (18, 12). Returning spectators retain their position near the live board.
- Walking straight along the red guide into the main arena gate starts the existing Solo Zombies countdown on a 14 x 6 pad, at height +6 and z -108. Stepping off cancels it.
- The gate prompt is an optional immediate Solo Zombies start. It never opens the mode picker. Existing side-wing modes and the PLAY menu remain available.
- Studio checks required: fresh join camera/sightline, unobstructed walk to Solo Zombies, step-off cancellation, death/reset spawn, fighter/spectator returns, existing-player initialization and phone controls.
