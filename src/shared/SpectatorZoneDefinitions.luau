--!strict
-- Explicit tribune zones for the animal crowd (SpectatorPlacementService). Angles follow the arena
-- oval (Arena.frameAt): 0° = East, 90° = South (player gate), 180° = West, 270° = North (imperial box,
-- Otti's entrance). Seating tiers (Arena): tier 1 top = LOWER real-player walkway, tier 3 top =
-- MIDDLE real-player walkway; the animal crowd only sits on tiers 2 and 4, so walkways, camera
-- platforms and real-spectator spawn spots always stay free.
--   Level "Lower"  tier 2 (front + back row)       close view
--   Level "Middle" tier 4 front row                wider view
--   Level "Upper"  tier 4 back row                 top seats, sparse
-- Each zone: centre angle, angular span, level, base density (share of seats used), whether it
-- is "popular" (more groups) and exclusions (staircases, return door, imperial box).

export type Level = "Lower" | "Middle" | "Upper"

export type Zone = {
	Name: string,
	CenterDegrees: number,
	SpanDegrees: number,
	Level: Level,
	Density: number, -- 0..1 share of seats filled at "Normal" importance
	SeatSpacing: number, -- studs between seat centres along the row
}

export type Exclusion = { CenterDegrees: number, HalfWidthDegrees: number, Levels: { Level } }

local function zone(z: Zone): Zone
	return table.freeze(z) :: any
end

local SpectatorZoneDefinitions = {
	Zones = table.freeze({
		zone({ Name = "Lower East Tribune", CenterDegrees = 0, SpanDegrees = 50, Level = "Lower", Density = 0.6, SeatSpacing = 2.7 }),
		zone({ Name = "Lower South Tribune", CenterDegrees = 90, SpanDegrees = 70, Level = "Lower", Density = 0.7, SeatSpacing = 2.7 }),
		zone({ Name = "Lower West Tribune", CenterDegrees = 180, SpanDegrees = 50, Level = "Lower", Density = 0.6, SeatSpacing = 2.7 }),
		zone({ Name = "Lower North Tribune", CenterDegrees = 270, SpanDegrees = 60, Level = "Lower", Density = 0.55, SeatSpacing = 2.7 }),
		zone({ Name = "Middle East Tribune", CenterDegrees = 0, SpanDegrees = 60, Level = "Middle", Density = 0.55, SeatSpacing = 2.8 }),
		zone({ Name = "Middle South Tribune", CenterDegrees = 90, SpanDegrees = 70, Level = "Middle", Density = 0.6, SeatSpacing = 2.8 }),
		zone({ Name = "Middle West Tribune", CenterDegrees = 180, SpanDegrees = 60, Level = "Middle", Density = 0.55, SeatSpacing = 2.8 }),
		zone({ Name = "Middle North Tribune", CenterDegrees = 270, SpanDegrees = 70, Level = "Middle", Density = 0.45, SeatSpacing = 2.8 }),
		zone({ Name = "Upper North Tribune", CenterDegrees = 270, SpanDegrees = 80, Level = "Upper", Density = 0.3, SeatSpacing = 3.0 }),
		zone({ Name = "Upper South Tribune", CenterDegrees = 90, SpanDegrees = 60, Level = "Upper", Density = 0.35, SeatSpacing = 3.0 }),
		zone({ Name = "Imperial-side Tribune", CenterDegrees = 225, SpanDegrees = 40, Level = "Upper", Density = 0.4, SeatSpacing = 3.0 }),
		zone({ Name = "Opposite Imperial Tribune", CenterDegrees = 135, SpanDegrees = 40, Level = "Upper", Density = 0.4, SeatSpacing = 3.0 }),
		zone({ Name = "Upper East Corner", CenterDegrees = 315, SpanDegrees = 40, Level = "Upper", Density = 0.25, SeatSpacing = 3.0 }),
		zone({ Name = "Upper West Corner", CenterDegrees = 45, SpanDegrees = 40, Level = "Upper", Density = 0.25, SeatSpacing = 3.0 }),
	} :: { Zone }),

	-- Never seat an animal here
	Exclusions = table.freeze({
		{ CenterDegrees = 30, HalfWidthDegrees = 9, Levels = { "Lower" } }, -- staircase
		{ CenterDegrees = 210, HalfWidthDegrees = 9, Levels = { "Lower" } }, -- staircase
		{ CenterDegrees = 0, HalfWidthDegrees = 9, Levels = { "Lower" } }, -- RETURN TO HUB door
		{ CenterDegrees = 270, HalfWidthDegrees = 16, Levels = { "Lower", "Middle", "Upper" } }, -- imperial box / Otti
	} :: { Exclusion }),

	-- Row radial offsets as a share of the tier depth (front / back row)
	FrontRow = 0.28,
	BackRow = 0.74,

	-- Group shape
	MinGroup = 2,
	MaxGroup = 7,
	MinGap = 1, -- empty seats between groups
	MaxGap = 4,
	SecondSpeciesChance = 0.45, -- a group mixes in a second species
	MinSeatSpacing = 2.2, -- validated distance between any two animals
}

-- Smallest signed angle difference in degrees (-180..180).
function SpectatorZoneDefinitions.angleDelta(a: number, b: number): number
	return ((a - b + 180) % 360) - 180
end

function SpectatorZoneDefinitions.isExcluded(degrees: number, level: Level): boolean
	for _, exclusion in SpectatorZoneDefinitions.Exclusions do
		if table.find(exclusion.Levels, level) and math.abs(SpectatorZoneDefinitions.angleDelta(degrees, exclusion.CenterDegrees)) <= exclusion.HalfWidthDegrees then
			return true
		end
	end
	return false
end

return table.freeze(SpectatorZoneDefinitions)
