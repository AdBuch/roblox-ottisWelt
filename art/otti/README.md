# Otti — agile otter gladiator

Chocolate brown fur, cream muzzle/throat/chest, broad dark nose, little round
ears, expressive eyes and whiskers. Webbed paws and a long flattened tapering
tail preserve an otter silhouette. Leather, bronze, gold chains, red skirt tabs,
a wooden gladius and a round red wooden shield match the established hero.

The playable character is a real skinned model: seven meshes, 26 bones, flexible
lumbar/spine/chest/neck, elbows, knees, jaw and six tail joints. Body skin is one
connected surface. All meshes use a packed 2048px PBR atlas and at most four
normalized bone influences per vertex. Each mesh stays under 10,000 triangles.

28 authored 60fps clips cover biped idle/walk, quadruped idle/walk/bounding run,
rise, slash/backslash/thrust, shield bash, sweep/trip/slam, bite, grapple, guard,
stagger, sitting, cheering, leap/landing, surrender, roar, feint, sword draw,
trident ready/thrust and a left-handed casting-net throw.
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
all clips, and bind/animation FBX round trips (61 checks). Calibration error is
recorded in `roblox-motion-validation.json`. `verification.json` contains bounds.
`scripts/build-hero-test.ps1 -Hero Otti` builds the local playable arena.
`scripts/build-boss-qa.ps1` builds isolated damage/range/cover/cancellation and
three-character regression checks. Neither command publishes the experience.

## Trident and net

The revised head is lower and wider, with smaller ears and fuller cream whisker
pads. The Retiarius loadout adds a wooden trident and a folded weighted rope net.
Grip wraps, curled digits and opposing thumbs are rigidly bound to the same hand
bone as each weapon, including the existing sword and shield. The thrust uses
two-bone arm IK and a separate wrist alignment, keeping the shaft in the palm.
Walking blends the ready upper body with the biped leg cycle.

The server switches loadouts for each attack, hiding the alternative equipment.
NetCast commits to a marked location before its 0.9 second anticipation. A
0.14 second hand release precedes the 0.55 second arc. Solid cover intercepts
the flight; moving out of the 2.8 stud landing radius evades the net. A facing
shield stops it. On a valid hit the local rope lattice falls over the player,
and movement becomes 35% for 2.4 seconds. No full control lock is applied.
The independent snare expires or releases on interruption/encounter end/death,
preserving unrelated slows. A successful cast can lead into a trident thrust.
