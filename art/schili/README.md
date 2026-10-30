# Schilibitzli — Schili, the little arena mentor

A new tortoise design, anatomy and animation set. Inspired by the compact,
expressive mentor archetype, youthful turtle agility and quiet wisdom.
Schili remains a childlike, funny tortoise in the Otti gladiator world.

Visual anchors: oversized round head, short beak, large brown eyes, asymmetrical
brows, sage skin, cream plastron, domed brown/amber/olive shell with seven bold
scutes, golden rim and sun spiral. Teal scarf, ochre cloth, narrow leather strap,
small bronze bracers and a wooden staff. No full robe; the shell stays visible.

`reference/Schili-concept-v1.png` is the generated modeling target. The actual
game model is `Schili.blend`, with independent rendered views in `previews/`.
The concept's finer surface detail is simplified in the playable mesh.

## Editable deliverables

- Four actual skinned meshes: connected body, facial/equipment details, shell, staff.
- 21 bones, including independent shell, scarf, jaw, elbows and knees.
- One shared 2048² color/metalness/roughness atlas; at most four normalized weights.
- Nine authored clips: Idle, Walk, StaffStrike, Feint, StaffSweep, ShellGuard,
  Rush, Stagger and Bow. No legacy Motor6D poses are used for this character.
- FBX bind model and individual animation exports in `exports/`.
- Studio import in `exports/Schili_Studio.rbxmx`, runtime copy in
  `assets/characters/Schili.rbxmx`.

## Regeneration

Run `source/build_schili.py` using Blender 5.2 background mode. Import the bind
FBX in Studio as Custom, retain zero-influence bones, set model ScaleTo(3.2),
and save the selection to `exports/Schili_Studio.rbxmx` as Roblox XML.
Then run `source/export_roblox_motion.py` in Blender to regenerate
`src/shared/SchiliMotion.luau` against the actual imported bone axes.
The modeling/material-bake and motion-calibration helpers are shared with Kroko;
the tortoise anatomy, shell topology, proportions and choreography are new.

`source/validate_schili.py` verifies topology, UVs, budgets, weights, deformation
through all clips and FBX round trips. `verification.json` records 30 passes.
Maximum imported-bone calibration error: 0.00000063 studs.

Studio regression: 51 combat checks passed across all three bosses; Schili's
standard staff strike removed 12 actual HP. Client checks found 21 bones with
11 animated in an idle sample (Kroko: 25 / 17). A separate visual check exposed
that writing Bone.Transform during Stepped could leave the rendered skin in a
previous pose. Both skinned heroes now update during PreRender; the actual
shell guard and club wind-up were checked visually after that correction.

Build the interactive local test with `scripts/build-hero-test.ps1 -Hero Schili`;
open `build/SchiliArenaTest.rbxlx` and press F5. The bottom selector still offers
Otti, Kroko and Schili. `scripts/build-boss-qa.ps1` builds the separate automated
combat regression place; QA scripts never enter normal place builds.

Roblox meshes: body `121860672871224`, details `80812229328984`, shell
`82348099533412`, staff `86238861571316`. Local Studio rendering is verified;
asset availability in a published experience must still be checked before release.
