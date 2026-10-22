--!strict
-- Passive special energy, owned by the server. Hits, kills, blocks and dodges never change it.
-- Regenerates while alive in combat or training; no idle decay and no persistent storage.
local MomentumConfig = {
	Max = 100,
	RegenPerSecond = 5,
	UpdateSeconds = 0.1,
	Start = table.freeze({
		Solo = 0,
		Coop = 0,
		TeamBattle = 0,
		EliminationRound = 0,
		Training = 0,
	}),
}
return table.freeze(MomentumConfig)
