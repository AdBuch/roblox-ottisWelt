# Combat redesign: status and handover

Last updated: 2026-10-19 · branch `feature/combat-encounter`

> **Superseded (2026-10-27):** this handover is historical. Everything below was finished and committed
> (client wiring in `0bf196f` / `2d725ca`), then reworked by Combat V2: Classic-only controls (Wild mode and the
> gesture pad were removed), hold-to-charge specials, and shield and block stages. The current state lives on branch
> `feature/combat-movements`; see [COMBAT_V2_REPORT.md](COMBAT_V2_REPORT.md) and the README.

> **Update 2026-10-20:** all blood was removed again so the game is suitable for children
> (`BloodConfig`, `BloodEffectsController`, `SandStainController`, the BLOOD setting and the stain epoch are gone;
> hits show sparks and dust only). Mentions of blood and stains below describe the earlier state.

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

## Client side (done, analysis clean for both places)

- `Main.client` wires CombatSettings, GesturePad, the new InputController, SlideController, MomentumHudController and the
  effects chain (CombatEffects, BloodEffects, SandStains, CombatCamera). Dispatches `DamageFx(position, kind, scale,
  direction, extra)`, `Dodge`, `PerfectBlock`, `Slide` and the `Special` label.
- `InputController` rewritten (Classic / Wild, Soft Targeting, slide, Special Mode, gamepad stick gestures); it sends
  intent only (`Basic`, `Gesture`, `Slide`, block hold).
- `PlayerAnimator`: aliases for the new anim names, a block pose layer (Front / Left / Right / High / Low) with impact
  recoil, slide posture and hit reactions, all summed into one write per joint.
- `SandStainController`: pooled, capped by quality, merging, epoch fade, lifetime fade.
- `BloodEffectsController`, `CombatCameraController`, `CombatEffectsController` (sparks / dust by category, bow arrows
  pooled in shields, perfect-block flash, camera impulses scaled by the CameraShake preference).
- `MobileControlsController`: ATK / BLOCK / SLIDE / SPECIAL; ATK and BLOCK hidden in Wild.
- `ComboFeedbackController` is now the TRAINING board (both modes, Momentum, specials); `ShopController` lists specials.
- `ComboDefinitions` removed; comments and lobby texts updated; `README.md` controls, combat and structure sections updated.

## Builds and analysis

- `rojo build` succeeded for `places/hub.project.json`, `places/arena.project.json` and `default.project.json`.
- luau-lsp strict analysis: 0 errors, 0 warnings for the Hub and the Arena place.

## Not verified yet (needs Roblox Studio playtest)

- Feel and tuning: slide distance and steering, Soft Targeting turn, Wild gesture thresholds, Momentum rates.
- Animation look: footwork poses, block layers and hit reactions on real R15 rigs.
- Mobile layout of the new buttons and the pad on phone and tablet; the edge column height (198 arena / 250 hub).
- Blood and stains: performance with many zombies, stain cap per quality, cleanup between matches.
- Tribune zones and the crowd centre after the fix.

## Not committed

Nothing is committed for the client part. The last pushed commit is `5943307`.
