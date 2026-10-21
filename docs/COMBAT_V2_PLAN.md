# Combat System, Mobile Controls & Progression V2: technical plan

Status: implemented on `feature/combat-encounter` (local commits). No push, deploy or publish without approval.

## Current state (analysis)

**Input**
- `InputController` has Classic and Wild modes and uses `GesturePadController`, which draws the Wild pad and the
  Special gesture.
- The CLASSIC / WILD pill lives in `CombatSettingsController`.
- The server re-classifies gestures in `GestureValidationService` (`CombatAction "Gesture"`).

**Combat (server)**
- `PlayerCombatService` owns block, hits, cooldowns and moves.
- `AttackSequenceService` picks the contextual chains.
- Specials cost Momentum by gesture tier (`WeaponSpecialDefinitions`).
- Block is held, times out after 4 s, and reduces damage only inside the shield's front angle.

**Effects**
- No blood any more.
- Zombies can still lose limbs (`ZombieDismembermentService`).

**Economy and saved data**
- Aura is progress and unlocks gear per item (`AuraRequired`).
- Denarii are the money.
- Saved profile: schema v5.

**Matchmaking**
- Team sizes only.

## Decisions

1. **Classic only.**
   - Delete `GesturePadController`, `GestureDefinitions`, `GestureValidationService` and the `Gesture` action.
   - Remove the mode pill and the `ControlMode` preference.
   - Slide input is removed. Mobile has 4 buttons only, and PvP must not favour one platform. `SlideService` stays
     on the server, unused.
2. **Mobile controls.**
   - Left: Roblox's own thumbstick (camera-relative); the camera turns by dragging free screen space.
   - Right: ATTACK, SPECIAL (hold), BLOCK (toggle), and Roblox's own jump button as JUMP, so there is no second jump
     button.
   - Phone and tablet layouts in `UiConfig`.
3. **Separate combat states.** Defense (block), Attack (busy / cooldowns) and SpecialCharge are independent fields on
   the server (`PlayerCombatService`). Block and charging may run at the same time.
   - **Transitions:** ATTACK drops the block, then attacks. Special RELEASE drops the block, then fires. Block toggles
     freely while charging.
   - **Interruptions:** death, knockdown, a grab, or a heavy unblocked hit cancels the charge.
4. **Special charge (`SpecialChargeDefinitions`).**
   - Tiers: I below 0.5 s, II 0.5–1.5 s, III from 1.5 s, capped at 2.5 s. Each tier has its own damage, PvP damage,
     recovery and cooldown.
   - Held time is measured on the server between `SpecialStart` and `SpecialRelease`. A shared cooldown and the busy
     state stop spam.
   - The moves come from the weapon's special families: tier I → Right, tier II → Left, tier III → Down. A full charge
     with 100 Momentum fires the weapon's Ultimate and spends the 100 Momentum.
   - `specialFor(characterId, weapon, tier)` is a resolver so Otti, Schili, Krokero and others can get their own
     specials later.
5. **Shield defense (`ShieldDefenseConfig`)**, by hit direction on the server:
   - Passive shield side: 15 %.
   - Active block from the front: 70 %.
   - Active block from the shield side: 40 %.
   - From behind: 0 %.
   - Each shield scales these values by its quality.
   - Toggle block: no 4 s timeout, walk speed about 65 %. During a charge the stronger slow-down applies.
6. **Hit reactions.** Knockback, a short stumble and a short loss of balance (a brief slow) on heavy unblocked hits.
   Limb loss is switched off (`ZombieDismembermentEnabled = false`).
7. **Progression.**
   - `GladiatorLevelDefinitions` holds the levels, titles and Aura thresholds.
   - Items get `LevelRequired` instead of `AuraRequired`.
   - HUD shows the level, title and progress, plus Denarii.
   - New reward for each completed round, paid once per round and player.
8. **PvE / PvP.**
   - `WeaponBalanceConfig`: a PvE multiplier per weapon, so progression is noticeable.
   - PvP: each weapon's damage is normalized to the same basic DPS, so weapons differ in reach, speed and style.
   - Matchmaking: a team match only groups entries within a level window that widens with waiting time.
   - Prepared for a later skill-based rating.
9. **Data.** Schema v6, no complex migration. A one-time test-data reset (`PlayerDataResetConfig`): off by default, DEV
   only, needs a token change, runs at most once per profile. Nothing is reset automatically.

## Commits (local only)

1. Plan and server special charge.
2. Classic-only client, mobile layout and charge HUD.
3. Block toggle and directional shield defense.
4. Facing, hit reactions, no limb loss.
5. Gladiator levels, Denarii rewards and HUD.
6. PvE / PvP weapon values and level matchmaking.
7. Schema v6 and the controlled test-data reset.
8. Fixes and report.
