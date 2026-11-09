--!strict
-- THE ORACLE OF ROME (Hub · Tempel am Forum). A priest in a toga offers a prophecy for a small
-- offering. The text is atmospheric, but its hint is real: the exact Aura still missing for the
-- next gladiator title (GladiatorLevelDefinitions), or a fitting saying at the highest rank.
-- No random reward is ever given; only the flavour line rotates. New texts (missions, secrets of
-- the world's edge) can be added to Sayings later.

local GladiatorLevelDefinitions = require(script.Parent.GladiatorLevelDefinitions)

local OracleDefinitions = {
	Price = 5, -- Denarii per prophecy, shown before the player confirms
	UseDistance = 16, -- the priest must be this close (server check, studs)
	OfferSeconds = 60, -- an offer token stays valid this long
	Sayings = table.freeze({
		"Der Rauch steigt gerade auf, die Flamme brennt ruhig.",
		"Die heiligen Hühner fressen gierig, das ist ein gutes Zeichen.",
		"Ein Adler kreist über dem Kolosseum.",
		"Das Wasser im Becken liegt still wie Bronze.",
	}),
}

export type Prophecy = { saying: string, hint: string, isMax: boolean, remaining: number, nextTitle: string? }

-- The prophecy for a player with `aura` total Aura. `turn` picks the flavour line.
function OracleDefinitions.prophecy(aura: number, turn: number): Prophecy
	local progress = GladiatorLevelDefinitions.progressFor(aura)
	local sayings = OracleDefinitions.Sayings
	local saying = sayings[(math.max(0, math.floor(turn)) % #sayings) + 1]
	if progress.isMax or not progress.nextLevel then
		return {
			saying = saying,
			hint = ("Die Götter verneigen sich vor dir, %s. Kein Titel steht mehr über deinem. Jetzt wachsen nur noch dein Ruhm und deine Legende."):format(progress.level.Title),
			isMax = true,
			remaining = 0,
			nextTitle = nil,
		}
	end
	local nextLevel = progress.nextLevel :: GladiatorLevelDefinitions.Level
	local hint = ("Noch %d Aura, dann nennt man dich %s."):format(progress.remaining, nextLevel.Title)
	local rank = progress.nextRank
	if rank and rank.Level ~= nextLevel.Level then
		hint ..= (" Bis zum Rang %s fehlen dir %d Aura."):format(rank.Group, math.max(0, rank.Aura - math.floor(aura)))
	end
	return { saying = saying, hint = hint, isMax = false, remaining = progress.remaining, nextTitle = nextLevel.Title }
end

return table.freeze(OracleDefinitions)
