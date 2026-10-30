# Otti — agile otter gladiator

Chocolate brown fur, cream muzzle/throat/chest, broad dark nose, little round
ears, expressive eyes and whiskers. Webbed paws and a long flattened tapering
tail preserve an otter silhouette. Leather, bronze, gold chains, red skirt tabs,
a wooden gladius and a round red wooden shield match the established hero.

The playable character is a real skinned model: five meshes, 26 bones, flexible
lumbar/spine/chest/neck, elbows, knees, jaw and six tail joints. Body skin is one
connected surface. All meshes use a packed 2048px PBR atlas and at most four
normalized bone influences per vertex. Each mesh stays under 10,000 triangles.

25 authored 60fps clips cover biped idle/walk, quadruped idle/walk/bounding run,
rise, slash/backslash/thrust, shield bash, sweep/trip/slam, bite, grapple, guard,
stagger, sitting, cheering, leap/landing, surrender, roar, feint and sword draw.
Analytic two-bone IK places all four paws during quadruped movement. The tail
counterbalances turns through six joints. The sword is sheathed on four paws.

## Rebuild and import

Run `source/build_otti.py` with Blender 5.2. It saves `Otti.blend`, the bind FBX,
an FBX containing every animation, atlas maps, previews and mesh metadata.
Import `exports/Otti_Bind.fbx` into Roblox Studio as Custom, retain zero-influence
bones, call ScaleTo(3.4), PivotTo(CFrame.identity), and save selection as XML to
`exports/Otti_Studio.rbxmx`. Copy it to `assets/characters/Otti.rbxmx`.
Run `source/export_roblox_motion.py` in Blender after importing to calibrate the
authored actions to actual Studio bone axes and regenerate `OttiMotion.luau`.
Motion is sampled every two frames; no separately published AnimationIds needed.

`SkinnedOttiAnimator` updates bones in PreRender. Server pose start and attack
durations retime anticipation, contact and recovery independently. Light attacks
and the three-strike combination are faster; damage and long heavy telegraphs
retain the existing rules. Server collision and damage remain authoritative.

## Verification

`source/validate_otti.py` checks connected topology, weights, deformation across
all clips, and bind/animation FBX round trips (50 checks). Calibration error is
recorded in `roblox-motion-validation.json`. `verification.json` contains bounds.
`scripts/build-hero-test.ps1 -Hero Otti` builds the local playable arena.
`scripts/build-boss-qa.ps1` builds isolated damage/range/cover/cancellation and
three-character regression checks. Neither command publishes the experience.
