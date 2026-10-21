# Combat System, Mobile Controls & Progression V2: report

Branch `feature/combat-encounter`. The work is in 9 local commits (`c106b06` .. `d5fefac`), plus this report.
**Not pushed, deployed or published, and no player data was deleted.**

## 1. Implemented

**Classic only**
- Wild mode removed, together with the gesture pad and Special gestures. Removed files: `GesturePadController`,
  `GestureDefinitions`, `GestureValidationService`, and the server's `Gesture` action. The CAMERA pill is the only
  setting left. The saved `ControlMode` preference is dropped on load.
- Slide input is removed. Mobile has four buttons, and PvP must not favour one platform. `SlideService` stays on the
  server (dodge timing, contextual chains) but receives no input.

**Mobile controls**
- Left: Roblox's own thumbstick (camera-relative); the camera turns by dragging on free screen space.
- Right, around Roblox's own jump button (JUMP, so there is no second jump button):
  - **ATTACK** is the largest button, left of JUMP.
  - **SPECIAL** sits above JUMP; hold it to charge, and it fills in three colours.
  - **BLOCK** sits diagonally; it toggles and is lit ON while active.
- Separate phone and tablet layouts (`UiConfig`).

**Combat states** (`PlayerCombatService`)
- Defense (block), attack (busy / cooldowns) and special charge are separate states, so block and charge can coexist.
  - **Attack:** lowers the block first; no attacks while charging.
  - **Special release:** lowers the block, then fires.
  - **Interruptions:** death, respawn, knockdown, grab, match reset, or a heavy hit that was not blocked.

**Special charge** (`SpecialChargeDefinitions`)
- Tiers: I below 0.5 s, II 0.5–1.5 s, III from 1.5 s, full at 2.5 s. The hold time is measured on the server.
- One shared cooldown and the busy state prevent spam.
- Walking slows to 75 % while charging; with the block up the stronger slow applies.
- A full charge with 100 Momentum fires the Ultimate.
- Display: `SpecialChargeHudController` plus the charge pose in `PlayerAnimator`, which combines cleanly with the
  block pose.
- `specialFor(characterId, weapon, family)` is prepared for personal specials (Otti, Schili, Krokero, …).

**Block** (`ShieldDefenseConfig`)
- Toggle without a timeout; walk speed about 65 %.
- Damage reduction by hit direction, computed on the server:

  | Zone | Passive | Active block |
  |---|---|---|
  | Front | 0 % | 70 % |
  | Shield side | 15 % | 40 % |
  | Weapon side | 0 % | 0 % |
  | Back | 0 % | 0 % |

- Each shield scales the values by its quality. Perfect block and guard break only happen in front.
- When the server refuses a block, the client toggle is synced back. Block is reset on death and respawn.

**Attack and hit reactions**
- Soft Targeting turns the character smoothly (at most 40° over 0.1 s), never through obstacles.
- Heavy unblocked hits cause a brief loss of balance (0.4 s, at most every 1.5 s), on top of knockback and the stumble
  pose.
- Limb loss is switched off, and there is no blood.

**Progression**
- **Aura** is experience and is never spent.
- **Gladiator levels:** 7 levels with titles (`GladiatorLevelDefinitions`). They unlock gear (`LevelRequired`), and the
  HUD shows the level, title and progress.
- **Denarii** are the money; they are never negative.
- **Round reward:** +10 Aura and +15 Denarii, paid once per match, round and player.

**PvE / PvP** (`WeaponBalanceConfig`)
- PvE: damage grows with the weapon's level (+8 % per level).
- PvP: each weapon's basic DPS is normalized to 22, with a small tax for reach and for the bow.
- Matchmaking: team battles group entries within a level window (±1, widening by 1 every 15 s, up to ±6).
  `MatchRatingService` is prepared for a later skill-based rating.

**Data**
- Schema v6; no data change is needed from v5.
- `PlayerDataResetConfig` prepares a controlled one-time reset. It is off, DEV only, needs a new token, runs at most
  once per profile and never after a failed load.

## 2. Changed files (`git diff --stat 2bdb395..HEAD`)

**New**
- `src/shared/SpecialChargeDefinitions.luau`, `ShieldDefenseConfig.luau`, `GladiatorLevelDefinitions.luau`,
  `WeaponBalanceConfig.luau`
- `src/client/SpecialChargeHudController.luau`
- `src/hub/server/MatchRatingService.luau`
- `src/server/PlayerDataResetConfig.luau`
- `docs/COMBAT_V2_PLAN.md`, this report

**Deleted**
- `src/client/GesturePadController.luau`, `src/shared/GestureDefinitions.luau`,
  `src/server/GestureValidationService.luau`

**Changed**
- Server: `PlayerCombatService`, `SpecialMoveService`, `InventoryService`, `AuraService`, `MatchService`,
  `PlayerDataService`, `EquipmentShopService`, `MatchmakingService`
- Client: `InputController`, `MobileControlsController`, `CombatSettingsController`, `Main.client`, `PlayerAnimator`,
  `MomentumHudController`, `AuraDisplayController`, `ShopController`, `ComboFeedbackController`
- Shared: `ControlModeDefinitions`, `UiConfig`, `CombatConfig`, `CurrencyConfig`, `DamageEffectsConfig`,
  `PlayerDataSchema`, `WeaponDefinitions`, `ShieldDefinitions`, `ArmorDefinitions`, `WeaponSpecialDefinitions`
- Docs: `README.md`, `docs/CHARACTER_DESIGN.md`

## 3. Tests

**Run**
- luau-lsp strict analysis for Hub and Arena after every step: 0 errors. The only remaining lint is an old
  `LocalShadow` in OttiAnimator.
- `rojo build` for Hub, Arena and `default.project.json`: all pass.
- Code review of every changed path (state transitions, remote validation, reward deduplication). It found and fixed
  one desync of the block toggle (`d25d95c`).

**Not run (no Roblox runtime available here)**
- Play sessions in Studio, real devices (phone / tablet), multiplayer and PvP.
- Frame times, and the feel of joystick, buttons and charge.
- DataStore access against real servers.

## 4. Open issues

1. **Touch button positions** depend on where Roblox draws its jump button. The offsets in `UiConfig` follow Roblox's
   usual layout, but they need checking on real phones and tablets (including notch / safe-area devices).
2. **Slide** has no input any more. If it should come back, every platform needs it (a fifth button or a gesture on
   ATTACK).
3. **Special moves per tier** reuse the weapon families: tier I = Right, II = Left, III = Down. Some weapons may want a
   different mapping; this is configurable in `SpecialChargeDefinitions.Tiers`.
4. **Ultimate** is fired by tier III at full Momentum. Players need to learn this; the HUD shows ULTIMATE READY.
5. **Old Aura-unlock data:** v5 profiles keep their Aura. Since levels now start at different thresholds, a test
   player's level may differ from what they expect. The controlled reset is prepared for that, but it is not enabled.
6. **Disabled limb-loss code** (`ZombieDismembermentService`, gameplay consequences in `ZombieService`) is still in the
   project behind the switch. It can be deleted completely in a later clean-up after checking its dependencies.

## 5. Balancing recommendations (starting values)

**PvP normalization factors** (calculated from the current moves, reference DPS 22)

| Weapon | Basic PvP DPS before | Factor | PvE factor |
|---|---|---|---|
| Rusty Gladius | 24.5 | 0.90 | 1.00 |
| Legion Sword | 28.0 | 0.79 | 1.08 |
| Hunter Bow | 18.7 | 1.00 | 1.08 |
| Morning Star | 19.1 | 1.14 | 1.16 |
| Trident | 20.8 | 1.00 | 1.24 |
| Hoplite Spear | 19.1 | 1.05 | 1.24 |
| Twin Daggers | 28.0 | 0.79 | 1.32 |
| Battle Axe | 16.9 | 1.29 | 1.32 |

**Recommendations**
- Watch the Battle Axe in PvP (factor 1.29 on big single hits); `PvPOverride` can cap it.
- If tier III feels too strong or too slow, adjust `DamageMultiplier` 1.7 and `Cooldown` 6 s first.
- Shield values: front 70 % with a perfect block on top can make blocking dominant against zombies. If fights become
  too passive, lower `Active.Front` to 0.6 or raise `BlockWalkFactor` slightly.
- Gladiator levels: with zombie kills at about 8–25 Aura plus round rewards, level 3 comes after roughly 2–3 solo runs.
  Check this against real playtime.

## 6. Manual Roblox Studio tests (still to do)

**Mobile and tablet** (device emulator plus real devices)
- The thumbstick moves relative to the camera, and the camera turns on free screen space.
- There is exactly one JUMP button, and the buttons don't overlap each other or the health bar / HUD.

**Block**
- Toggle on and off; walk speed drops to about 65 %; jump works while blocking.
- ATTACK lowers the block, and it does not come back on its own.
- Block survives a special charge, can be toggled during the charge, and is lowered when the special fires.
- Zombie hits from the front, the shield side, the weapon side and behind give different damage.
- Block is reset after death and respawn.

**Special**
- Release at 0.3 s, 1.0 s and 2.5 s+ gives tiers I, II and III. The bar shows three phases and MAX.
- Spamming the key fires once per cooldown.
- A heavy zombie / Otti hit through a lowered guard cancels the charge, while a blocked one does not.

**Progression**
- Kills and rounds pay Aura and Denarii exactly once. The level-up notice appears.
- Locked gear shows LOCKED · LV n; buying reduces Denarii only.
- Data is saved after rejoining.

**PvP**
- A two-player Team Battle: the weapons feel even, and the level window groups close levels.

**Regression**
- Solo and Co-op zombie runs, Otti round 7, archers, the lobby pads, the armory, spectating and the Hub ↔ Arena
  teleports all still work.

**Data reset** (DEV only, with explicit approval)
- Set a test token for one UserId → the profile is reset once; a rejoin does not reset it again.
