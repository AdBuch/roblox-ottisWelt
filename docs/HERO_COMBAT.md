# Shared hero foundation

Otti, Krokero (Kroko) and Schilibitzli (Schili) use one procedural 3D rig contract and one server attack executor. These are editable Roblox primitives with Motor6D joints, not SVG sprites or imported skinned meshes. Elbows and knees supplement the existing torso, shoulders, hips, neck and six tail joints. Lower limbs carry their hand/foot accessories and weapons.

- `HeroSkeleton`: builds the shared articulated limbs for both model builders.
- `HeroCombatDefinitions`: small species profiles for movement and companion attack variants. Otti retains his existing gladiator move data; all three use `BossAttackService` for execution and validation.
- `OttiAnimator`: common gait/pose blending with species stances and club, staff, shell-guard and upright rush poses.
- `CompanionBossAI`: personality-based role selection. The server supplies real attack timing and recent block information.

Kroko closes distance aggressively, rushes in a straight line, uses a long crocodile tail and gains a club/shield combination in phase two. A missed rush leaves a recovery window. Schili stays upright, moves more slowly, guards and counters, feints into a staff thrust, and sweeps with the staff instead of an invisible long tail. Otti keeps his otter gait, gladius, shield, tail and varied gladiator sequences. Wind-ups stop tracking during their final portion so lateral evasion remains possible.

The interrupted flag now clears when stagger recovery finishes. Previously it stayed true and the executor rejected every subsequent attack. Guards have a real expiry; retreat movement is no longer overwritten in the same AI tick. Attack results record actual damaging contacts so hit-dependent follow-ups can run.

Explicitly selecting `Otti` now also runs his entrance. Previously the non-empty selection string skipped the entrance and left his spectator root anchored on the tribune. Entrance selection now uses the constructed boss's species instead of the request string.

Visual reference: the canonical descriptions supplied in chat and `CHARACTER_DESIGN.md`. Original reference pictures were not available in this checkout. The Studio review covers front/back silhouettes, face readability, necklace visibility, shell placement and articulated limbs; it does not establish an exact match to missing pictures.

## Tests

Run `scripts/test-hero-combat.ps1 -LuauPath ../phase1-tools/luau.exe` for source-based profile, cooldown, AI pressure and stagger regressions. Existing combat animation, team-pad and momentum suites remain applicable.

Run `scripts/build-boss-qa.ps1`, open `build/BossQA.rbxlx` in Studio, then Play. The isolated QA scripts start a real local boss match and verify actual Humanoid health loss, attacks after stagger, reach, solid cover, cancelled wind-ups, rush/sweep/feint damage, guard/retreat persistence and limb joints. `[HeroQA] COMPLETE` in Output confirms completion; a failure raises an error. Finally the three models are displayed together for visual inspection. QA scripts are absent from the normal Hub/Arena projects.

In the normal Arena Studio test, use the bottom `Otti / Kroko / Schili` buttons. Switching restarts the local match after up to 14 seconds, followed by the normal intro. Published servers never expose or accept these Studio test controls. The match HUD and result use the selected hero's name.

Rojo: `places/hub.project.json` on port 34872; `places/arena.project.json` on port 34873. Normal builds: `scripts/build-places.ps1`.
