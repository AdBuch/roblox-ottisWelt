--!strict
-- GLADIATOR CAREER: exactly 150 levels, derived from the player's total Aura (experience, never
-- spent). Nothing is stored: the level is always computed from Aura, so a change of this table
-- can never take Aura, Denarii or items away (InventoryService keeps owned gear usable).
--
-- RANK GROUPS (each with sub-ranks I, II, III ...), from beginner to the highest rank:
--   TIRO 1-5 · NOVICIUS 6-10 · AUCTORATUS 11-18 · GLADIATOR 19-28 · VETERANUS 29-40
--   PRIMUS PALUS 41-52 · ARENACHAMPION 53-66 · HELD DES KOLOSSEUMS 67-80 · LEGENDE DER ARENA 81-95
--   RUDIARIUS 96-110 · MEISTER DER ARENA 111-124 · TRIUMPHATOR 125-137 · IMPERATOR 138-149
--   CÄSAR 150 (only level 150)
--
-- CURVE: the Aura needed from level L to L+1 (k = L - 1) is
--     step(k) = round5(StepBase + StepLinear * k + StepQuadratic * k^2)
-- Early levels need 100-250 Aura (a few zombie rounds), later steps grow steadily up to about
-- 10 400 Aura (about eight full solo runs) for 149 -> 150. docs/GLADIATOR_CAREER.md lists every
-- level, title and threshold, the total and example play-throughs.
--
-- MATCHMAKING: team battles group entries whose levels are within a window around the oldest
-- entry's level. The window scales with the level (3 levels apart means far less at level 120
-- than at level 3) and widens with waiting time until anybody may meet (MatchLevelGap).

export type Level = {
	Level: number,
	Title: string,
	Group: string, -- rank group (e.g. "GLADIATOR")
	SubRank: number, -- 1.. within the group (0 for CÄSAR)
	Aura: number, -- total Aura needed to reach this level
}

export type RankGroup = {
	Name: string,
	First: number,
	Last: number,
	Description: string,
}

local MAX_LEVEL = 150

local CURVE = table.freeze({
	StepBase = 100,
	StepLinear = 25,
	StepQuadratic = 0.3,
})

local GROUPS: { RankGroup } = {
	{ Name = "TIRO", First = 1, Last = 5, Description = "Rekrut der Gladiatorenschule" },
	{ Name = "NOVICIUS", First = 6, Last = 10, Description = "Neuling mit ersten Arenasiegen" },
	{ Name = "AUCTORATUS", First = 11, Last = 18, Description = "Unter Vertrag genommener Kämpfer" },
	{ Name = "GLADIATOR", First = 19, Last = 28, Description = "Vollwertiger Kämpfer der Arena" },
	{ Name = "VETERANUS", First = 29, Last = 40, Description = "Erfahrener Gladiator vieler Kämpfe" },
	{ Name = "PRIMUS PALUS", First = 41, Last = 52, Description = "Bester Kämpfer seiner Schule" },
	{ Name = "ARENACHAMPION", First = 53, Last = 66, Description = "Gefeierter Sieger der Arena" },
	{ Name = "HELD DES KOLOSSEUMS", First = 67, Last = 80, Description = "Liebling der Tribünen" },
	{ Name = "LEGENDE DER ARENA", First = 81, Last = 95, Description = "Ein Name, den ganz Rom kennt" },
	{ Name = "RUDIARIUS", First = 96, Last = 110, Description = "Mit dem Holzschwert geehrter Meisterkämpfer" },
	{ Name = "MEISTER DER ARENA", First = 111, Last = 124, Description = "Lehrmeister der Champions" },
	{ Name = "TRIUMPHATOR", First = 125, Last = 137, Description = "Gefeiert mit einem Triumphzug" },
	{ Name = "IMPERATOR", First = 138, Last = 149, Description = "Feldherr der Arena" },
	{ Name = "CÄSAR", First = 150, Last = 150, Description = "Höchster Rang des Kolosseums" },
}

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV" }

-- Aura from level L to L+1 (L = 1 .. 149)
local function stepFor(levelNumber: number): number
	local k = levelNumber - 1
	local raw = CURVE.StepBase + CURVE.StepLinear * k + CURVE.StepQuadratic * k * k
	return math.floor(raw / 5 + 0.5) * 5
end

local levels: { Level } = {}
local groups: { RankGroup } = {}
do
	local aura = 0
	for _, group in GROUPS do
		table.insert(groups, table.freeze(group) :: any)
		for levelNumber = group.First, group.Last do
			local single = group.First == group.Last
			local sub = levelNumber - group.First + 1
			local def: Level = {
				Level = levelNumber,
				Title = if single then group.Name else ("%s %s"):format(group.Name, ROMAN[sub]),
				Group = group.Name,
				SubRank = if single then 0 else sub,
				Aura = aura,
			}
			table.insert(levels, table.freeze(def) :: any)
			if levelNumber < MAX_LEVEL then
				aura += stepFor(levelNumber)
			end
		end
	end
	assert(#levels == MAX_LEVEL, "GladiatorLevelDefinitions must define exactly 150 levels")
end

local GladiatorLevelDefinitions = {
	MaxLevel = MAX_LEVEL,
	Curve = CURVE,
	Levels = table.freeze(levels) :: { Level },
	Groups = table.freeze(groups) :: { RankGroup },

	-- Team-battle matchmaking: allowed level difference to the oldest entry =
	--   Start + Relative * anchorLevel + PerSecond * waited   (anybody after OpenSeconds)
	-- e.g. level 10: ±6 at once, ±18 after 60 s; level 100: ±15 at once, ±27 after 60 s.
	MatchLevelGap = table.freeze({ Start = 5, Relative = 0.1, PerSecond = 0.2, OpenSeconds = 180 }),
}

-- The level reached with `aura` (binary search), the next level (nil at 150) and the progress
-- toward it (0..1; 1 at the top).
function GladiatorLevelDefinitions.levelFor(aura: number): (Level, Level?, number)
	local list = GladiatorLevelDefinitions.Levels
	local value = if aura == aura then math.max(0, aura) else 0
	local low, high = 1, #list
	while low < high do
		local middle = (low + high + 1) // 2
		if list[middle].Aura <= value then
			low = middle
		else
			high = middle - 1
		end
	end
	local current = list[low]
	local nextLevel = list[low + 1]
	local progress = 1
	if nextLevel then
		progress = math.clamp((value - current.Aura) / math.max(1, nextLevel.Aura - current.Aura), 0, 1)
	end
	return current, nextLevel, progress
end

export type Progress = {
	level: Level,
	nextLevel: Level?, -- nil at level 150
	share: number, -- 0..1 toward the next level (1 at the top)
	inLevel: number, -- Aura earned inside the current level (0 at the top)
	needed: number, -- Aura the current level needs in total (0 at the top)
	remaining: number, -- exact Aura still missing for the next level (0 at the top)
	nextRank: Level?, -- the first level of the next rank group (nil in the last group)
	isMax: boolean,
}

-- Everything the profile / career view needs, from one Aura value.
function GladiatorLevelDefinitions.progressFor(aura: number): Progress
	local value = if aura == aura then math.max(0, math.floor(aura)) else 0
	local current, nextLevel, share = GladiatorLevelDefinitions.levelFor(value)
	local nextRank: Level? = nil
	for levelNumber = current.Level + 1, MAX_LEVEL do
		local def = GladiatorLevelDefinitions.Levels[levelNumber]
		if def.Group ~= current.Group then
			nextRank = def
			break
		end
	end
	return {
		level = current,
		nextLevel = nextLevel,
		share = share,
		inLevel = if nextLevel then value - current.Aura else 0,
		needed = if nextLevel then nextLevel.Aura - current.Aura else 0,
		remaining = if nextLevel then nextLevel.Aura - value else 0,
		nextRank = nextRank,
		isMax = nextLevel == nil,
	}
end

function GladiatorLevelDefinitions.get(levelNumber: number): Level?
	return GladiatorLevelDefinitions.Levels[levelNumber]
end

function GladiatorLevelDefinitions.groupOf(levelNumber: number): RankGroup?
	for _, group in GladiatorLevelDefinitions.Groups do
		if levelNumber >= group.First and levelNumber <= group.Last then
			return group
		end
	end
	return nil
end

-- The allowed level difference after waiting `seconds` in a queue, around `anchorLevel`.
function GladiatorLevelDefinitions.matchGap(seconds: number, anchorLevel: number?): number
	local gap = GladiatorLevelDefinitions.MatchLevelGap
	local waited = math.max(0, seconds)
	if waited >= gap.OpenSeconds then
		return MAX_LEVEL - 1
	end
	local anchor = math.clamp(anchorLevel or 1, 1, MAX_LEVEL)
	return math.min(MAX_LEVEL - 1, gap.Start + gap.Relative * anchor + gap.PerSecond * waited)
end

return table.freeze(GladiatorLevelDefinitions)
