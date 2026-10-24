# Combat animation Phase 1

Implemented on 24 October 2026 (Europe/Zurich).

Local branch: `feature/combat-animation-phase1`.

## Working copy and starting state

The supplied workspace was an artifact folder, not a Git checkout. The source repository was
found at `D:\roblox\ottisWelt`, on `feature/combat-encounter`, with existing uncommitted edits.
The repository and its local source edits were copied into
`C:\Users\adria\Documents\ChatGPT\OttisWelt\combat-phase1`; the feature branch was created
there. The original checkout is unchanged. Existing changes remain present in the new checkout;
they are not all Phase 1 changes.
No applicable `AGENTS.md` was found in the source tree or its ancestors.
The referenced chat exposed the user's messages, but its assistant responses were only content
reference markers. The explicit Phase 1 requirements in the current request define this scope.

## Changed files for this task

- `src/client/PlayerAnimator.luau`: larger, distinct slash/backhand/overhead/thrust/low/rising/
  retreat/wide/air/dive/flurry/ultimate poses; coverage for every animation name emitted by
  SpecialMoveDefinitions, including slide variants. Shoulders, waist and hips share the same
  timing, with bounded elbow and knee flexion. Active block raises the left arm; full brace
  raises it overhead and crouches. Directional hit reactions use arms and legs as well as torso.
  Charge does not add movement to the shield shoulder. Short exponential crossfades cover
  interruptions and recovery. Previous additive transforms are removed in PreAnimation and
  fresh layers are applied in PreSimulation, preventing accumulation on joints skipped by Animator.
- `src/server/PlayerCombatService.luau`: fixed hand-local weapon, shield and offhand grips.
  Removed attack/block/brace/parry weld tweens that moved props away from their hands. Body
  joints now carry the props. Dagger parry publishes a body cue. Delayed trail work checks
  character, attack timestamp and equipment identity so an older attack cannot alter a newer one.
- `scripts/test-combat-animation.ps1`: syntax, behavior, animation-name coverage and grip checks.
- `scripts/combat-animation-harness.luau`: mocked Roblox animation and trail lifecycle tests.
- This report.
- `src/arena/client/.gitkeep`: preserves the empty folder referenced by the Arena Rojo project,
  so building a fresh checkout does not fail on the missing path.

An isolated patch against the imported working state is saved alongside this checkout as
`combat-animation-phase1.patch`. It excludes unrelated pre-existing changes.

On 25 October 2026 the user authorized committing and pushing this feature branch. The Phase 1
commit is based on Claude's `5ed2393` brace commit and includes the Phase 1 files and the build
folder placeholder listed above.
Unrelated imported local edits remain uncommitted. No merge or place publication is performed.

The user subsequently authorized rebase, push and merge on 25 October 2026. The feature was
rebased without conflicts onto `main` at `f048dc0`, retaining the brace feature because it was
not yet present on remote `main`. The clean rebased checkout passed all 204 checks (68 animation,
85 momentum, 51 team-pad) and both Rojo place builds before push and merge.

## Preserved behavior

The active block remains a toggle and still slows walking, with the existing brace slowdown.
Attack and a fired special lower block. Starting a special charge can leave block active until
release. Damage, hitboxes, cooldowns, charge costs, input controls and server authority are unchanged.
Source comparison confirmed unchanged bodies for updateWalkSpeed, braceLevel, cancelCharge,
receiveHit, runMove, chooseNormal, startSpecial, releaseSpecial and onActionRequest.
No blood, gore, dismemberment or new violent effects were added.

## Verification

- Luau compilation of both modified runtime modules: passed.
- Animation regression harness: **68 behavior checks passed**, including 30/60/144 FPS block
  settling and attack interruption, block plus charge, overhead brace, directional recoil,
  additive cleanup, a changed base Animator transform, missing-character handling, and stale
  trail callbacks after new attacks, equipment replacement and character removal.
- All emitted move animation names have a body pose or alias; no equipment weld tweens remain.
- Existing passive momentum suite: **85 checks passed**.
- Existing team-pad suite: **51 checks passed**.
- Rojo builds for Hub and Arena: passed; outputs in `build/OttiHub.rbxlx` and `build/OttiArena.rbxlx`.
- `git -c core.autocrlf=false diff --check`: passed.

Before commit, the isolated staged files were exported without unrelated local changes. The
68 animation checks and both Rojo builds also passed against that exact source snapshot.
The momentum and team-pad suites above were run against the imported working state; those
unrelated local features and test scripts are not included in this commit.

Run from this checkout with official Luau CLI tools on PATH:

```powershell
.\scripts\test-combat-animation.ps1
.\scripts\test-passive-momentum.ps1
.\scripts\test-pad-teams.ps1
.\scripts\build-places.ps1
```

The task-local CLI executables used here are in `..\phase1-tools`; pass their paths with
`-LuauPath` and, for the animation test, `-CompilePath` when they are not on PATH.

## Limits and Studio acceptance pass

These are procedural R15 poses, using the existing R15 Motor6D layout. The inspected equipment
attachment code retains its R6 hand fallback, but this task does not implement R6 body animation.
The test doubles validate timing and state/lifecycle behavior; their CFrame implementation stores
translation and angle channels rather than reproducing Roblox rotation matrices. They do not
prove visual quality, shield face orientation, foot planting, weapon-to-hitbox alignment, or
collision-free poses on every avatar body/package. No Studio or live multiplayer playtest was run.
This is not full-body IK or a new library of uploaded animation assets. The bow remains the
existing right-hand bow/shield equipment design; bowstring IK is outside this phase.

In Studio, preview both built places with default R15 and short/tall avatars, every weapon and
shield, stationary and moving. Check directional slashes, overhead, thrust, aerial and slide
variants; repeatedly toggle block; hold block through charge then release; interrupt combos;
take left/right/heavy hits; swap equipment, die and respawn. With two clients, confirm matching
presentation and trail cleanup. Confirm hands stay at grips, shields protect the intended visible
area, feet do not clip excessively, and the unchanged control rules still feel responsive.
