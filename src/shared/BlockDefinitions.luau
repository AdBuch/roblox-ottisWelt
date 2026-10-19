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

export type Pose = "Front" | "Left" | "Right" | "High" | "Low"

local BlockDefinitions = {
	PerfectWindow = 0.2,
	CounterWindow = 1.0, -- seconds the PARRY COUNTER stays available
	PerfectRecoil = 0.45, -- attacker (player) busy / zombie stagger after a perfect block
	SideThresholdDot = 0.45, -- |dot(right, toAttacker)| above this = side block
	HeavyReactionSeconds = 0.45,
	HeavyKnockback = 14,
	HeavyWeapons = table.freeze({ MorningStar = true, BattleAxe = true }) :: { [string]: boolean },
	ArrowEmbedSeconds = 2,
}

return table.freeze(BlockDefinitions)
