# Combat redesign: status and handover

Last updated: 2026-10-19 · branch `feature/combat-encounter`

This document hands over the combat redesign in progress. Slide, Classic and Wild controls,
gestures, Momentum, specials, blocks and parries, zombie sequences, blood and stains, crowd zones
and the training mode are in scope. **The server side is complete; the client side is partly done.**
The current commit is a work-in-progress snapshot: both places build with Rojo, but the client is
not yet wired to the new combat API.

## Project facts

- **Game:** Roblox/Rojo "Otti Colosseum" in `D:\roblox\ottisWelt`.
- **Places:** two places, the Hub and the Arena.
  - project files `places/hub.project.json` and `places/arena.project.json`
  - DEV IDs: Experience 10771565873, Hub 127694690386807, Arena 70661230851944
- **Place-specific code:** `src/hub/*` and `src/arena/*`. It is mounted at `Server.Place` and
  `Client.Place` and reaches shared server modules via `script.Parent.Parent`.
- **Builds:**
  - `rojo build places/hub.project.json -o build/OttiHub.rbxlx`
  - `rojo build places/arena.project.json -o build/OttiArena.rbxlx`
- **Publishing:** `scripts/publish-places.ps1`. The API key is asked for securely; never paste it in chat.
- **Strict analysis:** use luau-lsp with a sourcemap built using `--absolute`:
  ```
  rojo sourcemap places/<p>.project.json --absolute -o sm_<p>.json
  luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sm_<p>.json src/shared src/server src/client src/<p>
  ```
  The only accepted leftover is a pre-existing LocalShadow lint in OttiAnimator.
- **Working rules:**
  - continue on the branch
  - inspect before editing
  - preserve existing systems and refactor rather than duplicate
  - stay server-authoritative: never trust client hits, damage, direction, target, Momentum,
    block, parry or combo success
  - never expose reserved-server access codes
  - commit or push only when asked

## Done (server and shared)

- **Shared definitions:**
  - `GestureDefinitions`, `ControlModeDefinitions`, `MomentumConfig`, `SlideDefinitions`, `BlockDefinitions`
  - `BloodConfig`, `CombatEffectsConfig`, `ZombieAttackDefinitions`
  - `WeaponAttackDefinitions` (contextual chains and slots), `WeaponSpecialDefinitions` (families,
    tiers 25/50/75/100, damage 100/155/205 %, separate PvP multipliers)
  - `SpectatorZoneDefinitions`, `CrowdQualityConfig`
  - the template generator in `SpecialMoveDefinitions`
  - Category in `WeaponDefinitions`
  - preferences ControlMode, BloodFx and CameraShake in `PlayerDataSchema`
- **Server:**
  - `GestureValidationService`: re-classifies gestures from normalized samples on the server.
  - `AttackSequenceService`: contextual move choice.
  - `MomentumService`: diversity gains, decay after 4 s at 5/s, Elimination rounds start at 20.
  - `SlideService`: slide and slide dodge.
  - `ZombieAttackSequenceService`: per-type sequences, archer shots, heavy-blow spacing.
  - `SpectatorPlacementService`: tribune zones, groups of 2–7, importance.
  - `SpecialMoveService`: sweep and line hitboxes along the animation path, plus `onLanded` Momentum hooks.
  - `PlayerCombatService`:
    - `CombatAction` remote: `"Basic"` (aim point), `"Gesture"` (`{points, seconds, special, aim}`) and `"Slide"`
    - perfect block and parry using server time, with a counter window
    - block poses and heavy block reactions
  - `DamageEffectsService`: broadcasts `DamageFx(position, kind, scale, direction, extra)`.
  - `CrowdReactionService`: crowd-centre bug fixed through the server `BaseCFrame` attribute.
  - Changes in `ZombieService`, `ZombieArcherAI`, `OttiBossService`, `MatchService`, `TrainingService`
    (sparring dummy) and the arena `EliminationService`.
  - `ComboValidationService` deleted.
- **Character attributes published by the server for presentation:**
  - attack: `AttackAnim/AttackStart/AttackWind/AttackLength/AttackTier`
  - block: `Blocking/BlockPose/BlockImpactAt/BlockImpactHeavy/BlockPerfect`
  - slide: `SlideStart/SlideLength`
  - hit reaction: `HitReactAt/HitReactScale/HitReactSide`
  - player attribute `Momentum`
- **Client (done):**
  - `CrowdEffectsController`: fixed; signature is `start(arena, notify, getDevice)`.
  - `CombatSettingsController` (new): mode, blood and camera pills.
  - `GesturePadController` (new): Wild pad, Special Mode and the gesture trace.
  - `InputController`: rewritten for Classic and Wild, Soft Targeting, slide, Special Mode and
    gamepad stick gestures. Its new `init(options)` signature is not yet called by `Main.client`.

## Still to do (client and finish)

1. **`Main.client` wiring:**
   - create CombatSettings, GesturePad and the new InputController options (the `slideButton`,
     `specialButton`, `pad` and `getMode` callbacks)
   - set the edge frame size to about 198 in the arena and 250 in the hub
   - handle the Feedback events `Dodge`, `PerfectBlock` and `Slide` and the Action label `"Special"`
   - route `DamageFx(position, kind, scale, direction, extra)`
   - update the info-panel control texts
2. **`SlideController`:**
   - on `Feedback.Slide`, move the own character with raycast stops and small steering, with no upward velocity
   - lower the camera by `SlideDefinitions.CameraLower`
3. **`MomentumHudController`:** a narrow bar in the UiState group `"Momentum"`. Tier marks sit at
   25, 50 and 75, plus Ultimate; the bar turns red when a special is unaffordable.
4. **`PlayerAnimator`:**
   - new anim poses with footwork, matching the server sweep paths
   - a block pose layer (Front, Left, Right, High, Low), the slide posture and hit reactions
5. **Effects:** `CombatEffectsController`, `BloodEffectsController`, `SandStainController` and `CombatCameraController`.
   - category effects (Blade, Blunt, Heavy, Pierce, Bow)
   - zombie-only blood following the `BloodConfig` mode
   - pooled, capped and merging sand stains at FloorTop, which fade by `StainEpoch`
   - block sparks, embedded arrows (pooled, max 12), a perfect-block flash and camera impulses
     scaled by the CameraShake setting
6. **`MobileControlsController`:**
   - SLIDE and SPECIAL replace COMBO; the code still uses `positions.Combo`, which was removed
     from `UiConfig`, so switch it to `positions.Slide` and `positions.Special`
   - in Wild mode, hide ATK and BLOCK and show the pad
7. **`ComboFeedbackController`:**
   - rewrite it as the training board with Classic and Wild tutorials, Momentum and specials
   - show the gesture trace only in the training area
8. **`ShopController`:** list specials instead of combos.
9. **Remove `shared/ComboDefinitions.luau`:**
   - delete its references in `ComboFeedbackController`, `ShopController` and `Main.client`, and
     in the required list in the arena `Main.server`
   - fix the comments in `WeaponDefinitions`, `Config` and `SpecialMoveDefinitions`
10. **Checks:** run the hub, arena and default Rojo builds and strict analysis for both places, and fix every error.
11. **Docs:** update the README, then write the final report:
    - the crowd-centre root cause: the client cached `GetPivot()` before PrimaryPart replicated,
      which returned the arena centre
    - the files changed, the controls and the Studio test instructions
    - the known limitations

Related document: `docs/CHARACTER_DESIGN.md` contains the zombie and Otti appearance brief for an external redesign.
