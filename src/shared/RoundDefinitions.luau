--!strict
-- Round counts per zombie mode, weighted variant picking and archer caps. Rounds 1-6 are zombie
-- waves; Round 7 is the Otti boss encounter (OttiBossService).

local GameModeDefinitions = require(script.Parent.GameModeDefinitions)
local ZombieDefinitions = require(script.Parent.ZombieDefinitions)

type ZombieDefinition = ZombieDefinitions.ZombieDefinition

local RoundDefinitions = {
	TotalRounds = 6, -- zombie wave rounds
	BossRound = 7, -- final boss: OTTI — CHAMPION OF THE COLOSSEUM
	DisplayRounds = 7, -- shown as "ROUND n / 7"
	-- Undead Sagittarius: at most this many alive at once (by participating players, 1-4)
	MaxArchersByPlayers = table.freeze({ 3, 4, 5, 6 }),
	FirstRoundDelay = 3, -- "GET READY" countdown before Round 1
	IntermissionSeconds = 4, -- countdown between rounds
	SpawnInterval = 0.25, -- seconds between individual zombie spawns
}

-- Zombies in a round for a mode; Co-op scales with the number of participating players.
function RoundDefinitions.zombieCount(modeId: string, round: number, playerCount: number, stage: number?): number
	if stage == 2 then
		return math.min(round + 1, 4)^2 + math.max(round - 3, 0) * 2
	end
	if modeId == "Coop" then
		local base = GameModeDefinitions.Coop.BaseRoundCounts[round] or 0
		local scale = GameModeDefinitions.Coop.PlayerScaling[math.clamp(playerCount, 1, 4)]
		return math.ceil(base * scale)
	end
	return GameModeDefinitions.Solo.RoundCounts[round] or 0
end

-- Picks a variant available in this round; weights of available types are normalized.
function RoundDefinitions.maxArchers(playerCount: number): number
	return RoundDefinitions.MaxArchersByPlayers[math.clamp(playerCount, 1, 4)]
end

-- `exclude` skips variants (e.g. archers at their cap).
function RoundDefinitions.pickVariant(round: number, rng: Random, exclude: { [string]: boolean }?): ZombieDefinition
	local available: { ZombieDefinition } = {}
	local total = 0
	for _, def in ZombieDefinitions.Ordered do
		if round >= def.AvailableFromRound and def.SpawnWeight > 0 and not (exclude and exclude[def.Id]) then
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

-- Later chapters use dedicated rosters. Cavalry reinforces the sixteen legionaries
-- after round three. Ninja waves open with distinct roles as their numbers grow.
local ninjaOrder = { "ZombieNinja", "NunchakuNinja", "NinjaArcher", "TerracottaSamurai", "ZombieNinja", "NunchakuNinja" }
function RoundDefinitions.campaignVariant(stage: number, round: number, index: number): ZombieDefinition?
	if stage == 2 then
		if round > 3 and index > 16 then
			return ZombieDefinitions.ById.MountedPraetorian
		end
		return ZombieDefinitions.ById.TestudoLegionary
	elseif stage == 3 then
		local offset = if round == 2 then 1 else 0
		return ZombieDefinitions.ById[ninjaOrder[(index + offset - 1) % #ninjaOrder + 1]]
	end
	return nil
end

return RoundDefinitions
