--!strict
-- Blocking and parrying (server: PlayerCombatService.receiveHit; client: block poses).
--   Pose      chosen from the incoming attack: High (overheads, jump attacks, falling weapons),
--             Low (slides, tail sweeps, low zombie cuts), Left / Right (attacker beside the
--             shield arm side), else Front. Published on the character as BlockPose / BlockImpactAt
--             / BlockImpactHeavy so every client shows the matching pose and impact.
--   Perfect   the block was raised at most PerfectWindow seconds before a valid hit: no damage,
--             the attacker recoils, a short counter window opens (next attack = PARRY COUNTER),
--             big Momentum gain. Server time only; clients never report a parry.
--   Heavy     heavy attacks (Brute, Otti tail slam, Axe, Morning Star, heavy specials) push the
--             blocker back a little and briefly prevent slides / attacks (no ragdoll).
--   Brace     holding BLOCK longer builds a brace (0 -> 1 over BraceSeconds): the shield climbs
--             until it lies flat over the head, the player crouches, walking slows down and the
--             front protection grows. Server computes all of it; the client only shows BraceLevel.

export type Pose = "Front" | "Left" | "Right" | "High" | "Low"

local BlockDefinitions = {
	PerfectWindow = 0.2,
	BraceSeconds = 1.8, -- holding the guard this long reaches the full brace
	BraceTick = 0.1, -- how often the server updates the brace (shield, walk speed, BraceLevel)
	BraceReductionBonus = 0.2, -- extra front protection at full brace (before shield quality)
	BraceWalkFactor = 0.4, -- walk speed share at full brace, of the normal guard walk speed
	CounterWindow = 1.0, -- seconds the PARRY COUNTER stays available
	PerfectRecoil = 0.45, -- attacker (player) busy / zombie stagger after a perfect block
	SideThresholdDot = 0.45, -- |dot(right, toAttacker)| above this = side block
	HeavyReactionSeconds = 0.45,
	HeavyKnockback = 14,
	HeavyWeapons = table.freeze({ MorningStar = true, BattleAxe = true }) :: { [string]: boolean },
	ArrowEmbedSeconds = 2,
}

return table.freeze(BlockDefinitions)
