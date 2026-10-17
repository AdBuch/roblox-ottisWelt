--!strict
-- The six fixed rounds and variant selection.

local ZombieDefinitions = require(script.Parent.ZombieDefinitions)

type ZombieDefinition = ZombieDefinitions.ZombieDefinition

local RoundDefinitions = {
	Counts = table.freeze({ 1, 2, 4, 8, 16, 32 }),
	FirstRoundDelay = 3, -- "GET READY" countdown before Round 1
	IntermissionSeconds = 4, -- countdown between rounds
	SpawnInterval = 0.25, -- seconds between individual zombie spawns
	VictoryReturnSeconds = 12, -- fireworks/summary time before returning to the lobby
}

function RoundDefinitions.totalRounds(): number
	return #RoundDefinitions.Counts
end

function RoundDefinitions.zombieCount(round: number, cap: number): number
	return math.min(RoundDefinitions.Counts[round] or 0, cap)
end

-- Picks a variant available in this round; weights of available types are normalized.
function RoundDefinitions.pickVariant(round: number, rng: Random): ZombieDefinition
	local available: { ZombieDefinition } = {}
	local total = 0
	for _, def in ZombieDefinitions.Ordered do
		if round >= def.AvailableFromRound and def.SpawnWeight > 0 then
			table.insert(available, def)
			total += def.SpawnWeight
		end
	end
	if total <= 0 then
		return ZombieDefinitions.ById.LegionRemnant
	end
	local roll = rng:NextNumber() * total
	for _, def in available do
		roll -= def.SpawnWeight
		if roll <= 0 then
			return def
		end
	end
	return available[#available]
end

return RoundDefinitions
