# Prompt: own choreography for every special move

Written 29 October 2026 for branch `feature/combat-movements`. Language of the game texts: English;
this prompt and the report to the user: German.

## Role and goal

You are working in the Roblox/Rojo project `D:\roblox\ottisWelt` (plain Luau `--!strict`, no packages).
Give **every special move** of the eight weapons its **own, readable body choreography**, so a viewer can
tell from the motion alone which special is played. Today every special plays a *chain of generic library
poses* (`SpecialAnimationDefinitions` recipes such as `{ "Guard", "Low", "SlashLR", "Spin", "Thrust" }`):
the timing is right, but the moves look alike, "Spin" only twists the torso about 125°, and aerial
specials hold one pose for the whole fall.

## Starting point (read before you change anything)

- `src/shared/SpecialAnimationDefinitions.luau` builds one **track** per `<Prefix>:<MoveId>` from
  `WeaponSpecialDefinitions` (families Right = tier I, Left = II, Down = III, Ultimate, Up = air release
  from level 5, Circle = release while holding BLOCK from level 9) and `SpecialMoveDefinitions` (WindUp,
  Duration, `Hits[i].Delay`).
- `src/client/PlayerAnimator.luau` plays it: `specialPose()` reads the character attributes
  `SpecialAnimation` (`"<Prefix>:<MoveId>"`), `SpecialAnimationStart` and, for aerials,
  `SpecialLandingStart` (set by `SpecialMoveService.executeAerial` at the real landing). It also adds a
  per-style modifier (heavy, spear, daggers) and the failed-special fall (`SpecialFallStart`).
- The server already owns hit timing (`SpecialMoveService`): melee hits at `WindUp + Hits[i].Delay`,
  aerials hop 0.28 s when started on the ground, then descend until the measured landing, projectiles
  and volleys release after `WindUp`.
- Practice, unlocks and failure rate (`SpecialPracticeDefinitions`, `InventoryService.practiceSpecial`,
  schema v7) are finished and **not part of this task**; keep them working.
- Rules that stay: the weapon never leaves the hand (no weld animation), the server stays
  authoritative, PlayerAnimator only layers additive offsets, no blood, works with Motor6D and
  AnimationConstraint joints.

## What to build

1. **Keyframe tracks instead of recipes.** Each track is a list of keys `{ t, pose }` in seconds from
   the special's start. Key times are written against the server timing (`wind`, `hit(i)`, `dur`) so
   they stay in sync when a weapon's tempo changes. A pose sets any of: waist, both shoulders, both
   hips (degrees), crouch (studs), elbow bends, wrists, and **spin** (whole-body yaw).
2. **Real spins.** `spin` turns the whole body through the `Root` joint (360° = one full turn). Spins are
   sampled directly from the track (not through the crossfade) and wrap at 360°, so the body never
   unwinds backwards. Every track ends on a whole turn.
3. **Aerial phases.** Aerial tracks have `Main` (gather, jump, air pose: the last key is held until the
   landing), and `Land` (impact and recovery, from `SpecialLandingStart`), each authored per special.
4. **Style.** Heavy (Morning Star, Axe) is slower with more body weight; spears (Trident, Hoplite) thrust
   in line from the hip; daggers use **both** hands; the bow (in the right hand) aims with the right arm
   and draws with the left. Shared moves (GLADIATOR CLEAVE, HEAVY DESCENT, ARENA SPIN, RISING ATTACK,
   the melee Ultimate) get one variant per style.
5. Every key pose must stay **natural**: elbows 0-120°, wrists within about ±95°, knees follow the hips,
   the shield arm guards instead of hanging, feet plant on strikes (front hip forward, back hip back).

## The moves and what the player must visibly do

Times: `wind` = end of the wind-up, `hit(n)` = the n-th server hit.

| Special (weapons) | Choreography |
|---|---|
| REBELLION COMBO (Gladius I) | Shield up in a crouched counter stance (until hit 1) → low cut across the shins → rising cut from the upper left → full 360° shoulder turn → lunging thrust, back leg extended |
| LEGION'S FURY (Legion I) | Cut from the upper right → shield slams forward as cover → full spin cut at chest height → thrust with a long lunge |
| GLADIATOR COMBINATION (Morning Star I) | Heavy swing right to left → backhand left to right with the hips → shove the head of the mace forward |
| RETIARIUS FURY (Trident I) | Low guard, trident at the hip → two fast thrusts with short steps → low sweep turning the whole body → long lunging thrust |
| PHALANX BREAKER (Hoplite I) | Long gather: weight back, spear drawn far back at shoulder height, shield in front → explosive lunge, the whole body behind the point |
| VIPER DANCE (Daggers I) | Right dagger cut → evasive spin backwards → three alternating stabs (right, left, right) → spin with both blades out |
| COLOSSEUM BREAKER (Axe I) | Guard, axe low → hooking swing from the left → body turn (full spin) → axe high over the head → crushing blow into the ground, deep crouch |
| GLADIATOR CLEAVE (II, six weapons) | Sword: wind up far out to the right and behind, wide flat sweep right to left (the server sweep runs from +100° to -120°). Spear: shaft swept wide at hip height. Heavy: two-handed feel, long wind-up behind the right shoulder, the whole body turns through. Daggers: both blades sweep outward in a scissor cut |
| CHAIN TEMPEST (Morning Star II) | Swing → backhand → full spin with the arm stretched (the chain whirls) → overhead blow into the sand |
| HEAVY DESCENT (III, five weapons) | Rise on the toes, weapon high behind the head → drop into a deep crouch while slamming down, hold the impact, then stand up. Spear: point driven down from above. Daggers: both blades stab down together |
| FALLING METEOR (Morning Star III) | Crouch and jump, mace whirled above the head in the air → land with a two-handed slam, deep crouch |
| THUNDER OF MARS (Axe III) | Crouch, jump, axe held high behind the head, legs tucked → land with a massive overhead blow, knees bent |
| RISING ATTACK (Up: Gladius, Morning Star, Axe) | Low crouch → jump with an upward cut from low left to high right → land in a guard |
| EAGLE OF ROME (Legion Up) | Jump with the arms spread like wings → sword above the head in the air → land with a downward cut |
| SEA EAGLE DIVE (Trident Up) | Jump, trident pulled back → dive with the point first, body stretched → land with a lunge |
| SPARTAN VAULT (Hoplite Up) | Spear planted low, vault upward, legs swing up → point straight down in the air → land on the thrust |
| RIVER SHADOW (Daggers Up) | Jump with a full spin in the air, blades out → land low in a crouch, both blades crossed |
| ARENA SPIN (Circle, all melee) | Two complete 360° spins with the weapon arm stretched out at chest height, knees bent, shield arm tucked in |
| Ultimate, melee (REBEL'S FINALE, IMPERIAL VERDICT, COMET OF ROME, NEPTUNE'S JUDGEMENT, SPARTAN THUNDER, RIVER STORM, WRATH OF MARS) | Deep gather crouch with the weapon raised, big jump, a full spin in the air with the weapon high, land with an all-out blow and a deep impact crouch; style variants (sword, heavy, spear, daggers) |
| EAGLE SHOT (Bow I) | Short hop, aim from the air, full draw to the cheek, release |
| VOLLEY FAN (Bow II) | Aim left, draw, release while sweeping the bow from left to right |
| ARROW RAIN (Bow III) | Step back, bow raised steeply to the sky, full draw, release, follow the arrows |
| PIERCING SHOT (Bow Up) | Low stance, long, slow full draw, release with a recoil step back |
| ARROW STORM CIRCLE (Bow Circle) | A full spin with the bow drawn, releasing around the circle |
| STORM OF ARROWS (Bow Ultimate) | Kneel, two draws straight up into the sky, rise and release a final arrow |

## Acceptance

- `scripts/test-specials.ps1` checks: all 48 weapon/family assignments have a track; keys are ordered;
  every multi-hit track has a key within 0.15 s before each server hit; every aerial track has `Main`
  and `Land`; every spin ends on a whole turn; Circle tracks spin at least twice; joint angles stay in
  natural limits.
- `scripts/test-combat-animation.ps1` checks the animator: tracks play, spins drive the `Root` joint and
  wrap without unwinding, aerials hold the air pose until the landing and then play `Land`, and every
  joint returns to the untouched pose afterwards.
- All existing suites still pass (animation, specials, momentum, team pads), both places build with
  Rojo, the strict `luau-lsp` analysis is clean (fix the two `string?` errors in
  `ComboFeedbackController.luau`).
- README describes the special choreographies. No commit unless the user asks; report what could not be
  verified (the look in Studio).
