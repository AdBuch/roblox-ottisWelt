# Skinned Kroko prototype

`Kroko.rbxmx` is the real Blender/FBX import: four skinned MeshParts, 25 bones,
one material atlas, wooden club and shield. It replaces the procedural Kroko
when `ServerStorage.HeroAssets.Kroko` is available. Otti and Schili retain their
existing models. All three Rojo projects include this folder.

The server adapter adds one collision root and a Humanoid. Existing combat
validation, damage, boss selection and phase logic remain authoritative.
`SkinnedKrokoAnimator` drives the imported Bone.Transform values from the
authored Blender idle, walk, club strike and stagger actions in `KrokoMotion`.
The strike is retimed to the server's wind-up, active and recovery windows.
Dash and sweep still use the existing encounter movement; dedicated authored
dash/sweep clips are future animation work.

Source assets are tracked in `art/krokero`.
Run `source/export_roblox_motion.py` in Blender to regenerate motion data from
the actual imported rest skeleton. Maximum bone-position calibration error
for this import: 0.000001 studs. FBX exports and Blender sources remain there.

Build a local arena with Kroko preselected using `scripts/build-kroko-test.ps1`.
Open `build/KrokoArenaTest.rbxlx` in Studio and press F5. The bottom boss selector
can also switch to Otti and Schili. This does not publish a place.

Mesh asset IDs: body 116040529984270, details 118954805577487,
shield 75281390347092, club 134993227892638. Studio imported the texture assets
with the FBX. The local arena rendered these successfully. Studio reported
that automatic experience permission grants failed during import; access in
a published experience still needs verification before release.
