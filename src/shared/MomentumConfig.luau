--!strict
-- ARENA MOMENTUM (0-100): earned by varied, skilful combat, spent on Specials. Server only
-- (MomentumService); clients only display the "Momentum" player attribute. Never saved.
-- Gains are reduced for repeating the same attack slot (diminishing returns); misses, invalid
-- targets and blocking without being attacked give nothing.

local MomentumConfig = {
	Max = 100,
	Gains = table.freeze({
		BasicHit = 3,
		Diversity = 3, -- a different slot / direction than the previous attack
		Sequence = 4, -- e.g. a thrust or overhead right after a side slash
		AerialHit = 8,
		SlideDodge = 10,
		SlideHit = 8,
		Block = 2, -- a real attack blocked
		PerfectBlock = 15,
		CounterHit = 15,
		VariedKill = 6, -- an enemy defeated after a varied sequence
		SpecialHit = 0, -- specials spend Momentum, they never refund it
	}),
	RepeatFactor = 0.55, -- each repeat of the same slot multiplies the gain by this
	DecayDelay = 4, -- seconds without meaningful action before decay
	DecayPerSecond = 5,
	-- Starting Momentum per mode (match start; Elimination: every round)
	Start = table.freeze({
		Solo = 0,
		Coop = 0,
		TeamBattle = 0,
		EliminationRound = 20,
		Training = 0,
	}),
}

return table.freeze(MomentumConfig)
