--!strict
-- Blocking and parrying (server: PlayerCombatService.receiveHit; client: block poses).
--   Pose      chosen from the incoming attack: High (overheads, jump attacks, falling weapons),
--             Low (slides, tail sweeps, low zombie cuts), Left / Right (attacker beside the
--             shield arm side), else Front. Published on the character as BlockPose / BlockImpactAt
--             / BlockImpactHeavy so every client shows the matching pose and impact.
--   Perfect   the block was raised at most PerfectWindow seconds before a valid hit: no damage,
--             the attacker recoils, a short counter window opens (next attack = PARRY COUNTER).
--             Server time only; clients never report a parry.
--   Heavy     heavy attacks (Brute, Otti tail slam, Axe, Morning Star, heavy specials) push the
--             blocker back a little and briefly prevent slides / attacks (no ragdoll).
--   Stages    BLOCK is held, not toggled. The longer it is held, the higher the stage: more front
--             protection, slower steps. BraceLevel (0 -> 1 over BraceSeconds) drives the pose: the
--             player sinks slowly into a crouch while the shield climbs until it lies over the head.
--             Server computes all of it; clients only show BraceLevel / BlockStage.

export type Pose = "Front" | "Left" | "Right" | "High" | "Low"

export type Stage = {
	Stage: number,
	Name: string,
	From: number, -- seconds BLOCK has been held
	ReductionBonus: number, -- extra front protection (before shield quality)
	WalkFactor: number, -- share of the normal guard walk speed
}

local function stage(def: Stage): Stage
	return table.freeze(def) :: any
end

local BlockDefinitions = {
	PerfectWindow = 0.2,
	BraceSeconds = 1.5, -- holding the guard this long reaches the full brace (last stage)
	BraceTick = 0.1, -- how often the server updates the brace (walk speed, BraceLevel, BlockStage)
	Stages = table.freeze({
		stage({ Stage = 1, Name = "I", From = 0, ReductionBonus = 0, WalkFactor = 1 }),
		stage({ Stage = 2, Name = "II", From = 0.6, ReductionBonus = 0.1, WalkFactor = 0.7 }),
		stage({ Stage = 3, Name = "III", From = 1.5, ReductionBonus = 0.2, WalkFactor = 0.4 }),
	}) :: { Stage },
	CounterWindow = 1.0, -- seconds the PARRY COUNTER stays available
	PerfectRecoil = 0.45, -- attacker (player) busy / zombie stagger after a perfect block
	SideThresholdDot = 0.45, -- |dot(right, toAttacker)| above this = side block
	HeavyReactionSeconds = 0.45,
	HeavyKnockback = 14,
	HeavyWeapons = table.freeze({ MorningStar = true, BattleAxe = true }) :: { [string]: boolean },
	ArrowEmbedSeconds = 2,
}

-- The stage reached after holding BLOCK for `seconds`.
function BlockDefinitions.stageFor(seconds: number): Stage
	local reached = BlockDefinitions.Stages[1]
	for _, def in BlockDefinitions.Stages do
		if seconds >= def.From then
			reached = def
		end
	end
	return reached
end

return table.freeze(BlockDefinitions)
