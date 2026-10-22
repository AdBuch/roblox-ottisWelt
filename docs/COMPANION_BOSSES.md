# Companion bosses: Krokero (Kroko) and Schilibitzli (Schili)

Status: **step 1 done** (personalities and fighter AI as separate modules, tests). **Step 2 open**: the boss
selection menu and the integration into the fight. Otti keeps his own AI (`OttiBossAI`) and is not changed.

## 1. Characters

Otti's old companions. Kroko acts first, Schili thinks first, Otti brings them together. They are important,
recognisable characters, not background animals. Friendly and never frightening: no blood, wounds, gore or
realistic violence.

### Kroko: the fearless protector
- **Personality:** bold, energetic, impulsive, competitive, extremely loyal. Loves dramatic entrances, teases his
  friends like an older brother and protects them at once when danger comes. His weakness is stubborn overconfidence.
- **Look:** a stylised young crocodile, broad head, athletic torso, short powerful legs, strong arms, long muscular
  tail. Jungle-green skin, yellow-green lower jaw, chest and belly, darker rounded ridges on back and tail. Large
  amber-gold eyes, thick eyebrows, broad snout, friendly crooked grin with a few small rounded teeth.
- **Equipment:** brown leather shoulder harness, one prominent bronze shoulder guard with green patina, leather wrist
  guards, belt with a round bronze emblem, optional worn dark-red cloth. Round wooden shield or a chunky wooden
  training weapon.
- **Silhouette:** broad, energetic, instantly recognisable at icon size.

### Schili: the calm strategist
- **Personality:** observant, patient, intelligent, compassionate, quietly brave. Prefers timing and teamwork to brute
  force. Cautious but never cowardly; very persistent after a decision. Dry, subtle humour about Kroko's plans.
- **Look:** a small stylised tortoise, short sturdy limbs, friendly rounded head, low centre of gravity, large domed
  shell. Warm olive or sage skin, cream-green muzzle, throat and belly. Large dark-brown eyes with bright catchlights,
  soft eyebrows, gentle smile.
- **Shell:** the central feature. Warm earthy brown with amber and olive geometric plates, bronze-gold rim, a few
  subtle scratches from experience, and a simple spiral, sun or protective emblem that reads at small size. Strong and
  cherished, not damaged or aggressive.
- **Equipment:** narrow leather chest strap, small utility pouches or scroll cases, compact bronze bracers, soft bronze
  forehead band or small open helmet, dark-teal or ochre cloth. Short wooden staff, training spear or defensive tool.

### Group dynamic
Kroko protects the group physically, Schili protects it through wisdom and emotional balance. Their contrast is
affectionate and funny, never hostile.

## 2. Personality model (data, `src/shared/CompanionBossDefinitions.luau`)

Traits from 0 to 1 drive the decisions, not the look:

| Trait | Kroko | Schili | Meaning |
|---|---|---|---|
| Boldness | 0.90 | 0.35 | how eagerly it closes in and starts attacks |
| Patience | 0.25 | 0.85 | how long it waits for a good moment |
| Caution | 0.15 | 0.70 | how much it guards and retreats when hurt |
| Stubborn | 0.85 | 0.75 | how much it keeps pushing after damage |
| Cunning | 0.30 | 0.90 | how often it feints or waits after a block |

Moves are **roles**, not attacks: `Strike`, `Charge`, `Sweep`, `Guard`, `Feint`, `Roar`, `Retreat`. Each role has a
base weight, range, cooldown, readable telegraph, recovery and relative damage. The integration maps roles onto real
moves, so the personalities don't depend on any move existing yet.

**Kroko** prefers strikes and charges, repeats his favourite moves (`RepeatPenalty` 1.1), roars sometimes, and turns
**reckless** below a third of his health: attacks more, guards less, pauses shorter.

**Schili** avoids repeating a move (`RepeatPenalty` 0.4), guards when the target winds up an attack, feints after a
blocked hit, and below a third of his health becomes cautious: retreats more, guards more.

## 3. Fighter AI (`src/server/CompanionBossAI.luau`)

A **pure decision module**: it reads a snapshot of the fight and returns the next role (or waits). It moves nothing,
deals no damage and changes no state. The integration runs the chosen role through `BossAttackService`, so all
validation, hits and cooldowns stay on the server.

Decision per call:
1. Candidates: roles in range (distance) and off cooldown.
2. Weight = base × personality × situation × repetition.
3. Weighted random choice with the caller's `Random`.

`pause()` gives the pause between sequences. `cooldownEnds()` gives the time a role is ready again.

## 4. Tests

Pure logic is tested with the local Luau interpreter by stubbing the Roblox services (not part of the project).
Result: **9 of 9 passed**:

- no charge at close range
- cooldowns respected
- Schili guards when the target attacks
- Schili feints after a block
- Kroko turns reckless below the threshold
- Kroko's reckless pause is shorter
- Schili doesn't speed up when hurt
- the boss waits when nothing is in range
- both personalities exist

Not tested yet: how the fight feels, balance, and the real moves (needs Studio).

## 5. Step 2 (next prompt, not done here)

1. **Boss selection menu:** choose Otti, Kroko or Schili before a boss fight (menu, saved choice per match).
2. **Integration:** a companion boss spawn (model, health by player count), `CompanionBossAI` decisions run through
   `BossAttackService`, a role-to-move mapping per companion.
3. **Models:** the two characters built from the briefs above (Part-based like Otti, or MeshParts later).
4. **Balance:** health, damage and cooldowns checked in play.

## 6. Notes on the working setup

Other agents work on the same branch and workspace. For the integration step I suggest a **separate git worktree**,
so the changes don't mix with theirs.
