--!strict
-- GLADIATOR LEVELS: derived from the player's total Aura (experience, never spent). Each level has a
-- visible title, unlocks gear (WeaponDefinitions / ShieldDefinitions / ArmorDefinitions:
-- LevelRequired) and is one factor of battle matchmaking (MatchmakingService). Thresholds and titles
-- are balancing proposals and live only here. Nothing is stored: the level is computed from Aura.

export type Level = {
	Level: number,
	Title: string,
	Aura: number, -- total Aura needed to reach this level
}

local function level(def: Level): Level
	return table.freeze(def) :: any
end

local GladiatorLevelDefinitions = {
	Levels = table.freeze({
		level({ Level = 1, Title = "TIRO", Aura = 0 }), -- recruit
		level({ Level = 2, Title = "NOVICIUS", Aura = 100 }),
		level({ Level = 3, Title = "GLADIATOR", Aura = 300 }),
		level({ Level = 4, Title = "VETERANUS", Aura = 650 }),
		level({ Level = 5, Title = "PRIMUS PALUS", Aura = 1200 }),
		level({ Level = 6, Title = "CHAMPION", Aura = 2000 }),
		level({ Level = 7, Title = "LEGEND OF THE ARENA", Aura = 3200 }),
		level({ Level = 8, Title = "ARENA MASTER", Aura = 4800 }),
		level({ Level = 9, Title = "ELITE", Aura = 7000 }),
	}) :: { Level },

	-- Matchmaking: team battles only group entries whose gladiator levels differ by at most this
	-- (the window widens while the oldest entry waits, so nobody waits forever).
	MatchLevelGap = table.freeze({ Start = 1, PerSecond = 1 / 15, Max = 6 }),
}

-- The level reached with `aura`, the next level (nil at the top) and the progress toward it (0..1).
function GladiatorLevelDefinitions.levelFor(aura: number): (Level, Level?, number)
	local levels = GladiatorLevelDefinitions.Levels
	local current = levels[1]
	local nextLevel: Level? = nil
	for i, def in levels do
		if aura >= def.Aura then
			current = def
			nextLevel = levels[i + 1]
		end
	end
	local progress = 1
	if nextLevel then
		progress = math.clamp((aura - current.Aura) / math.max(1, nextLevel.Aura - current.Aura), 0, 1)
	end
	return current, nextLevel, progress
end

function GladiatorLevelDefinitions.get(levelNumber: number): Level?
	return GladiatorLevelDefinitions.Levels[levelNumber]
end

-- The allowed level difference after waiting `seconds` in a queue.
function GladiatorLevelDefinitions.matchGap(seconds: number): number
	local gap = GladiatorLevelDefinitions.MatchLevelGap
	return math.min(gap.Max, gap.Start + math.max(0, seconds) * gap.PerSecond)
end

return table.freeze(GladiatorLevelDefinitions)
