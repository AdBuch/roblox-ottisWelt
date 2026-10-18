--!strict
-- Otti's three health-based phases. OttiBossAI reads pauses, stance preference and move weights;
-- the HUD reads names and accent colors.

export type BossPhase = {
	Index: number,
	Name: string,
	Above: number, -- the phase applies while health share > Above
	Accent: Color3,
	PauseMin: number, -- breathing room between attack sequences
	PauseMax: number,
	StudySeconds: number, -- circles/observes before committing to a new target
	QuadChance: number, -- chance per decision to drop to all fours while repositioning
	GuardChance: number, -- reaction to predictable frontal attacks
	CounterEnabled: boolean,
	MoveWeights: { [string]: number },
}

local function phase(def: BossPhase): BossPhase
	return table.freeze(def) :: any
end

local BossPhaseDefinitions: { BossPhase } = {
	phase({
		Index = 1,
		Name = "ARENA DUEL",
		Above = 0.7,
		Accent = Color3.fromRGB(240, 196, 80),
		PauseMin = 1.2,
		PauseMax = 2.0,
		StudySeconds = 1.6,
		QuadChance = 0,
		GuardChance = 0.7,
		CounterEnabled = false,
		MoveWeights = { GladiusSlash = 4, GladiatorCombination = 2, ShieldBash = 2, TailSweep = 1.5 },
	}),
	phase({
		Index = 2,
		Name = "RIVER FURY",
		Above = 0.35,
		Accent = Color3.fromRGB(90, 190, 230),
		PauseMin = 0.7,
		PauseMax = 1.3,
		StudySeconds = 0.8,
		QuadChance = 0.55,
		GuardChance = 0.5,
		CounterEnabled = false,
		MoveWeights = {
			GladiusSlash = 2, GladiatorCombination = 2, ShieldBash = 1.5, TailSweep = 1.5, TailTrip = 2.5,
			OtterBite = 2.5, GrappleThrow = 1.2, RiverDash = 2.5, TailSlam = 1,
		},
	}),
	phase({
		Index = 3,
		Name = "CHAMPION UNLEASHED",
		Above = -1,
		Accent = Color3.fromRGB(235, 70, 60),
		PauseMin = 0.45,
		PauseMax = 0.9,
		StudySeconds = 0.4,
		QuadChance = 0.45,
		GuardChance = 0.6,
		CounterEnabled = true,
		MoveWeights = {
			GladiusSlash = 2, GladiatorCombination = 2.5, ShieldBash = 1.8, TailSweep = 2, TailTrip = 2,
			OtterBite = 2, GrappleThrow = 1, RiverDash = 2, TailSlam = 2.5, BattleCry = 0.4,
		},
	}),
}

-- The phase for a health share (0..1).
local function forShare(share: number): BossPhase
	for _, def in BossPhaseDefinitions do
		if share > def.Above then
			return def
		end
	end
	return BossPhaseDefinitions[#BossPhaseDefinitions]
end

return table.freeze({
	Phases = BossPhaseDefinitions,
	forShare = forShare,
})
