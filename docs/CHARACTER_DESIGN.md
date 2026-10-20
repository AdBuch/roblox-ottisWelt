# Otti Colosseum: character design reference (zombies and Otti)

This document describes exactly how the six arena zombies and the boss **Otti the Gladiator**
look in the game today. All of them are built in code from plain Roblox Parts. There are no
meshes and no asset IDs. Use this document as the brief for an external redesign (Blender,
Maya, ZBrush, concept art). The last section lists what an imported model must keep so the
game systems keep working.

Sources: `src/server/ZombieFactory.luau`, `src/shared/ZombieDefinitions.luau`,
`src/server/ZombieDamageStateService.luau`, `src/server/ZombieDismembermentService.luau`,
`src/server/OttiModel.luau`, `src/server/OttiTailService.luau`, `src/shared/OttiBossConfig.luau`.

Units: 1 stud ≈ 28 cm. A default Roblox avatar is about 5 studs tall.

---

## 1. The overall style

- **Friendly, stylized and cartoonish, not horror.** The models use rounded shapes: sphere torsos,
  "Head"-mesh limbs and ball fists. Heads are big, with glowing amber eyes, angry brows and a
  toothy, almost goofy grin.
- **Roman gladiators who came back from the dead.** They wear bronze helmets with green
  oxidation (patina), leather harnesses, pteruges skirts made of leather strips, sandals and greaves.
- **Damage is stylized only.** It shows as scratches, cracks and torn cloth, never as wounds or
  gore. There is no blood at all: the game is meant for children, hits show sparks and dust only.
- **Readability comes first.** Players must be able to tell each type apart from its silhouette
  and weapon alone, even at mobile resolution and distance.

## 2. The shared zombie palette

| Role | RGB | Hex |
|---|---|---|
| Skin (moss green) | 112, 150, 84 | `#709654` |
| Skin dark (brows) | 78, 108, 58 | `#4E6C3A` |
| Skin, Wounded state | 92, 118, 74 | `#5C764A` |
| Skin, Critical state | 78, 92, 66 | `#4E5C42` |
| Eyes (glowing amber, Neon plus a PointLight) | 255, 176, 40 | `#FFB028` |
| Pupil | 70, 30, 10 | `#461E0A` |
| Mouth | 44, 30, 26 | `#2C1E1A` |
| Teeth | 232, 222, 196 | `#E8DEC4` |
| Bronze | 176, 125, 60 | `#B07D3C` |
| Bronze dark | 126, 86, 42 | `#7E562A` |
| Gold (elite trim) | 230, 185, 80 | `#E6B950` |
| Oxide / patina | 96, 150, 122 | `#60967A` |
| Crack / stitch lines | 52, 38, 24 | `#342618` |
| Leather | 110, 70, 40 | `#6E4628` |
| Leather dark | 74, 46, 26 | `#4A2E1A` |
| Wood | 122, 84, 50 | `#7A5432` |
| Shield red | 128, 40, 32 | `#802820` |
| Steel (blades) | 186, 186, 180 | `#BABAB4` |
| Net / bowstring | 196, 182, 150 | `#C4B696` |
| Cloth: legion red | 116, 24, 30 | `#74181E` |
| Cloth: retiarius blue-grey | 84, 98, 120 | `#546278` |
| Cloth: champion purple | 88, 30, 110 | `#581E6E` |
| Cloth: archer faded blue | 78, 98, 132 | `#4E6284` |

Materials in use: SmoothPlastic for skin, CorrodedMetal for bronze armor, Metal for studs and blades,
Leather, Fabric, Wood, WoodPlanks (shield faces) and Neon (eyes).

## 3. The base zombie body that all types share

- **Proportions:** a big round head that is almost as wide as the torso, an egg-shaped torso,
  short thick arms ending in ball fists, and short legs. The style is chibi-like gladiators.
- **Face:**
  - two large glowing amber eyes with small dark pupils, plus a warm PointLight on the head
  - slanted dark-green angry brows
  - a wide dark mouth with three upper teeth and one crooked lower tooth
  - a stitched scar of a vertical line with two cross-stitches on the left cheek
- **Belt:** a dark leather belt with a bronze disc buckle. The buckle is gold on heavily armored types.
- **Skirt:** a cloth skirt in the type's colour under 10 alternating light and dark leather
  strips (pteruges). The three front strips carry bronze studs.
- **Arms:** leather bracers on both forearms.
- **Legs:** bronze greaves with patina, dark bronze knee guards, leather sandal soles with two
  straps, and three green toes visible at the front of each foot.
- **Helmet and shoulder armor:** these can detach in combat as stylized armor loss.

### 3.1 Condition states (appearance changes with health)

| State | HP | Look |
|---|---|---|
| Healthy | > 65 % | as described |
| Wounded | 65–30 % | darker skin, scratches on chest, head and arms, torn cloth flaps on the skirt; the scarf tail, some strips and the chest discs fall off; slight hunch |
| Critical | < 30 % | even darker skin, large cracks on the chest and head, scratches on the legs, more armor lost, strong hunch and limp |

**Dismemberment (stylized, non-graphic):** an arm or a leg can come off. The head never comes
off, and both legs are never lost. A dark cap covers the joint. The falling copy fades out after
about 5 s. The helmet and each shoulder plate can also be knocked off.

---

## 4. The six zombie types

The approximate height is to the top of the head, not counting crests.

### 4.1 Legion Remnant: balanced fighter, the most common type

- **Size:** scale 1.0, about 6.3 studs tall. Torso 2.6 × 2.4 × 1.7, head 2.0 × 1.9 × 1.8.
- **Helmet: "Crested".** A rounded bronze dome with a dark bronze brow ridge, a nose guard, two
  cheek guards, two hairline cracks and patina spots. A **red horsehair crest** runs front to back
  on a bronze holder.
- **Armor: "Harness".** One diagonal leather strap across the chest with a bronze disc (phalera).
- **Shoulder:** a single bronze plate of two layers on the sword side (right), with a rivet and patina.
- **Cloth:** a red scarf around the neck with one tail hanging down the front, and a red skirt.
- **Weapon:** a gladius in the right hand with a leather grip, a bronze pommel and guard, and a
  short steel blade.
- **Shield:** a **round red wooden shield** (diameter 2.6) with a bronze rim and boss, two dark
  plank lines and a patina spot.
- **Personality:** disciplined. It blocks now and then. It is the "standard legionary".

### 4.2 Rotten Velite: fast skirmisher

- **Size:** scale 0.88, about 4.9 studs tall. It is the smallest and slimmest type, with a torso of 2.2 × 2.1 × 1.5.
- **Helmet: "Cap".** A small open bronze cap with a brim, a knob on top and a patina spot.
- **Armor: "Vest".** A leather vest over the upper torso with front lacing.
- **Shoulders:** only a small leather shoulder pad on the right.
- **Cloth:** a red scarf and a red skirt.
- **Weapon:** a **long spear** of 5.6 studs, wooden shaft and a bronze leaf tip with a leather
  binding. Its visible length matches the attack reach of 11.
- **Shield:** a small **buckler** (diameter 1.5).
- **Personality:** quick jabs, then it runs off. The silhouette should read as light, lean and spiky.

### 4.3 Arena Brute: heavy attacker

- **Size:** scale 1.18, about 7.4 studs tall. It is very wide, with a torso of 3.4 × 2.6 × 2.3 and thick arms of 1.35.
- **Helmet: "Damaged".** A dome with a deep dent and a big crack. It has **only one cheek guard**
  (the left one) and a short torn stub of a red crest.
- **Armor: "Straps".** Two crossed leather straps in an X over the bare chest, with a large bronze
  disc at the crossing.
- **Shoulders:** heavy bronze plates on **both** sides.
- **Belt:** an extra-thick belt.
- **Cloth:** a red skirt and no scarf.
- **Weapon:** a **huge wooden club** with a cylinder head, two bronze bands, a bronze stud and a crack.
- **Shield:** none.
- **Personality:** a slow tank that is barely knocked back. The silhouette is broad, top-heavy and gorilla-like.

### 4.4 Zombie Retiarius (Net Fighter): tactical controller

- **Size:** scale 0.98, about 5.9 studs tall. Average build.
- **Helmet: "OpenFace".** A lower dome with no nose guard, a dent and a big crack, and both cheek guards.
- **Armor: "Light".** A blue-grey sash across the chest and one bronze chest disc with patina.
- **Shoulders:** a small leather pad on the right.
- **Cloth:** a **blue-grey** scarf and skirt. It is the only type that is not red.
- **Weapon:** a gladius in the right hand.
- **Left hand:** a **folded net** shaped like a pale bundle, with two dark cords and a metal
  weight. It throws the net to slow players.
- **Note:** historically the retiarius carries a trident and a net. A redesign could add a small
  trident without changing gameplay. The attacks are validated by range, not by mesh.

### 4.5 Zombie Arena Champion: rare elite

- **Size:** scale 1.3, about 8.6 studs tall. It is the biggest zombie, with a torso of 3.2 × 2.7 × 2.2.
- **Helmet: "Ornate".**
  - a gold brow ridge and a gold crest holder
  - a **tall purple crest**
  - gold rosettes on both temples, a dent, a nose guard and cheek guards
- **Armor: "Heavy".** A full **bronze cuirass** with a gold trim band, a gold medallion and a patina patch. The buckle is gold.
- **Shoulders:** heavy plates on both sides with gold rivets.
- **Cloth:** a **purple** scarf and skirt. Its eye glow is twice as bright as the others'.
- **Weapon:** a **large sword**, 1.45 times the size of the gladius, with a gold pommel and guard.
- **Shield: "Ornate".**
  - large (diameter 3.0), with a gold rim, a bronze face and an inner bronze ring
  - six gold studs and a gold boss
  - a hidden golden **GuardGlow** light that turns on while it guards
- **Personality:** an elite that raises its shield and blocks frontal hits. It should read as a
  "fallen arena champion": regal, gold and purple.

### 4.6 Undead Sagittarius: ranged archer

- **Size:** scale 0.92, about 5.5 studs tall. Slim.
- **Head: "Wrap".** A faded-blue **cloth head wrap** with a knot and a hanging tail at the back,
  and a thin bronze browband. It has no metal helmet.
- **Armor: "Vest".** A leather vest with lacing.
- **Cloth:** a faded blue scarf and skirt.
- **Weapon:** a **Roman recurve bow held vertically in the LEFT hand**, with a leather grip, two
  curved wooden limbs, bronze tips and a pale bowstring. The right hand wears a leather draw glove.
- **Back:** a **leather quiver** tilted about 20° with a strap across the chest and three visible
  arrows. One arrow has red fletching and two have pale fletching.
- **Bow arm:** a long dark leather wrist guard.
- **Personality:** it keeps a distance of 55–85 studs and draws visibly for 0.75 s before every
  shot, with occasional double and aimed shots. When cornered it makes a weak close-range strike.

---

## 5. Otti the Gladiator (boss)

**Concept:** a heroic otter champion, not a monster. He stands on his hind legs about
**9.5–10 studs** tall (rig scale 1.15), which makes him clearly bigger than players but "a
champion, not a giant". He is defeated, never killed. He enters from the tribune, draws his
sword, fights in phases and can also drop to all fours.

### 5.1 Palette

| Role | RGB | Hex |
|---|---|---|
| Fur (chocolate brown) | 92, 58, 38 | `#5C3A26` |
| Fur dark (paws, feet, brows, inner ears) | 66, 40, 26 | `#42281A` |
| Cream (muzzle, cheeks, chin, throat, chest, belly, claws) | 232, 214, 178 | `#E8D6B2` |
| Nose / mouth | 40, 28, 24 | `#281C18` |
| Eyes (glossy, Glass material) | 26, 18, 14 | `#1A120E` |
| Whiskers | 240, 232, 214 | `#F0E8D6` |
| Bronze | 170, 122, 62 | `#AA7A3E` |
| Bronze dark | 122, 86, 44 | `#7A562C` |
| Patina | 92, 146, 118 | `#5C9276` |
| Leather / leather dark | 104, 66, 40 / 70, 44, 28 | `#684228` / `#462C1C` |
| Worn dark-red cloth | 118, 26, 30 | `#761A1E` |
| Shield red | 122, 30, 28 | `#7A1E1C` |
| Shield wood | 110, 76, 46 | `#6E4C2E` |
| Blade steel / chips | 178, 176, 168 / 120, 118, 112 | `#B2B0A8` / `#787670` |
| Necklace black | 28, 24, 22 | `#1C1816` |

### 5.2 Body

- **Build:** a solid, barrel-chested otter. He has a rounded pelvis, a tall oval chest and a
  broad round head. His arms are fairly short and thick, and his legs are short and sturdy with
  large flat webbed feet.
- **Head and face:**
  - a broad otter face with a large **cream muzzle**, chin and puffy cheeks
  - a **broad dark nose** with a small highlight and a thin mouth line
  - **small glossy dark eyes** with a white catch-light and short dark brows that slope slightly
  - **short rounded ears** set high on the sides, with darker insides
  - **three long pale whiskers** on each side
- **Fur pattern:** chocolate brown overall, with a **cream throat, chest and belly** running
  down the front in a single cream bib.
- **Paws:** dark, webbed, each with **three small cream claws**.
- **Feet:** large, flat and dark, with a visible web between four toes and small cream claws.
- **Tail:**
  - long, thick at the base and **tapering in 6 segments** that are slightly flattened like an otter's
  - widths from base to tip are 1.35, 1.15, 0.95, 0.78, 0.60 and 0.42
  - total length is about 8.4 studs before scale
  - it rests curving down to the sand with the tip slightly lifted, and the tip is a little darker
  - it is fully animated (walk, balance, swipes) but is **not** a damage hitbox; tail attacks use server volumes

### 5.3 Signature accessories

- **Braided necklace:** a double ring of alternating **black and cream beads** (16 + 16) around
  the neck. It is his trademark and must stay recognizable.
- **Worn dark-red cloth drape** around the shoulders with a jagged, tattered front edge.
- **Asymmetric bronze shoulder armor** on the sword side (right) only: three overlapping
  pauldron layers getting smaller toward the elbow, with patina and two rivets.
- **Diagonal leather chest strap** with a bronze disc and boss.
- **Belt** with a large bronze disc buckle and a patina-green boss.
- **Skirt:** a dark-red cloth skirt under alternating leather pteruges strips with studs. The
  back is open for the tail, and a few cloth tatters hang below the front.
- **Bronze bracers** with a rim and patina on both forearms.
- **Bronze shin guards** with a central ridge and patina on both legs.

### 5.4 Weapons

- **Chipped gladius** (right paw):
  - leather grip, bronze ball pommel and bronze crossguard
  - a steel blade about 2.6 long with **three visible chips in the edge** and a patina spot
  - before the intro it is sheathed: a leather scabbard sits at the left hip at 60°, with only a bronze hilt showing
- **Battered round wooden shield** (left paw):
  - large (diameter 3.6), with **dark-red panels** and three vertical wooden plank lines
  - a bare, worn wood patch, a crack and a dark bronze rim with 10 studs
  - a big **oxidized bronze boss** with patina
  - a hidden golden **GuardGlow** light that turns on while he guards

### 5.5 Character notes for the redesign

- He is the colosseum's hero and showman. He is proud and playful, not evil. His expression should
  be confident with a slight smirk, not snarling.
- He is battle-worn but cared for: chipped sword, cracked shield, oxidized bronze and torn cloth.
- He must read instantly at a distance through his warm brown colour, cream bib, necklace, red
  shield and the large single pauldron.

---

## 6. Rules an imported model must follow for compatibility

If the redesigned models are imported as MeshParts, the following must stay the same or be
mapped one to one. Otherwise animation, damage states, dismemberment or hit detection break.

**Zombies** (`ZombieFactory`):
- Part names `HumanoidRootPart` (invisible and colliding, about torso-sized), `Torso`, `Head`,
  `RightArm`, `LeftArm`, `RightLeg`, `LeftLeg`.
- Motor6D joints `RootJoint`, `Neck`, `RightShoulder`, `LeftShoulder`, `RightHip`, `LeftHip`, in
  rest pose standing with the feet at y = 0 and facing -Z.
- Every visible part carries the attribute **`Limb`** naming the limb it hangs on.
- Detachable armor carries **`Detach`** = `Helmet`, `ShoulderR` or `ShoulderL`.
- Hidden damage overlays carry **`DamageDetail`** = `Wounded` or `Critical` and start with Transparency 1.
- Skin parts carry **`Skin` = true** so they can be recoloured by condition.
- The break-off pieces are found by name: `ScarfTail`, `Strip`, `Phalera`, `ChestDisc` and
  others in `ZombieDamageStateService`.
- The champion shield needs a `PointLight` named `GuardGlow`.
- The torso needs the `HitSparks` and `DeathPuff` emitters.
- Weapon length should match the gameplay reach. For example, the spear is visibly long because
  its reach is 11.

**Otti** (`OttiModel`):
- Parts `HumanoidRootPart`, `Pelvis`, `Chest`, `Head`, `RightArm`, `LeftArm`, `RightLeg`, `LeftLeg`.
- Motors `RootJoint`, `Waist`, `Neck`, `RightShoulder`, `LeftShoulder`, `RightHip`, `LeftHip` and
  `Tail1` to `Tail6`, with segment parts `Tail1` to `Tail6`.
- Separate sword parts in the paw (shown when drawn) and sheathed parts at the hip (hidden by default).
- `ShieldFace` with a `PointLight` named `GuardGlow`.
- The body parts are on the collision group `OttiBoss`, and only the root collides.
- `Humanoid` with an `Animator`. Authored animation IDs can be plugged into
  `OttiBossConfig.AnimationIds` later.

**Budget suggestions:**
- zombies: 2–4k triangles each with one shared texture atlas, since up to about 20 are on screen
- Otti: 8–12k triangles
- Keep it stylized with flat colours and a light hand-painted texture. Avoid realistic gore.
