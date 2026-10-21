--!strict
-- Battle rating of a queue entry (a party or a solo player). Today: the average GLADIATOR LEVEL
-- (from total Aura, GladiatorLevelDefinitions). Prepared for a later skill-based rating: add a
-- `skill` value here (e.g. from saved match results) and let MatchmakingService weigh both; the
-- queue entries already carry the rating table.

local Server = script.Parent.Parent
local InventoryService = require(Server.InventoryService)

export type Rating = {
	level: number, -- average gladiator level of the group
	skill: number?, -- reserved for a later skill-based rating (unused)
}

local MatchRatingService = {}

function MatchRatingService.ratingOf(players: { Player }): Rating
	local total, count = 0, 0
	for _, player in players do
		total += InventoryService.getLevel(player)
		count += 1
	end
	return { level = if count > 0 then total / count else 1, skill = nil }
end

return MatchRatingService
