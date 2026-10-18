--!strict
-- Round counts per zombie mode and weighted variant picking.

local GameModeDefinitions = require(script.Parent.GameModeDefinitions)
local ZombieDefinitions = require(script.Parent.ZombieDefinitions)

type ZombieDefinition = ZombieDefinitions.ZombieDefinition

local RoundDefinitions = {
	TotalRounds = 6,
	FirstRoundDelay = 3, -- "GET READY" countdown before Round 1
	IntermissionSeconds = 4, -- countdown between rounds
	SpawnInterval = 0.25, -- seconds between individual zombie spawns
}

-- Zombies in a round for a mode; Co-op scales with the number of participating players.
function RoundDefinitions.zombieCount(modeId: string, round: number, playerCount: number): number
	if modeId == "Coop" then
		local base = GameModeDefinitions.Coop.BaseRoundCounts[round] or 0
		local scale = GameModeDefinitions.Coop.PlayerScaling[math.clamp(playerCount, 1, 4)]
		return math.ceil(base * scale)
	end
	return GameModeDefinitions.Solo.RoundCounts[round] or 0
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
