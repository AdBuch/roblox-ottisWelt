--!strict
-- The walk-on matchmaking pads of the Hub lobby (the gladiator dungeon under the Colosseum).
-- LobbyService builds one pad per entry (order = position in its wing), LobbyPadService (Hub
-- server) runs them. Adding a mode later = enable its entry and give it an action.
--   Wing   "Single"  right of the spawn: one player, walk on and wait SoloCountdown seconds
--          "Multi"   left of the spawn: large group rooms. Stepping on joins the pad's group, the
--                    board lists the members, the leader presses a start button
--   Kind   "Solo" | "Group"
--   Actions (Group pads) start buttons on pedestals at the pad's front edge:
--          "StartCoop"     start Co-op with everybody in the group (or alone)
--          "<MatchMode>"   queue the group for that mode (MatchmakingService; press again = stop)
--   Mode   (Solo pads) the match mode started when the countdown ends
--   Enabled false = the pad is built and signed "COMING SOON" but starts nothing yet
--   Emblem the floor mosaic in the middle of a group pad ("Otti" | "Schili", LobbyMosaics)
-- Every start is validated on the server (lobby state, data loaded, loadout, party leader,
-- queue state) by the same functions the PLAY menu uses.

export type Wing = "Single" | "Multi"
export type Kind = "Solo" | "Group"

export type PadAction = {
	Id: string, -- "StartCoop" or a queued MatchMode
	Label: string,
}

export type PadDefinition = {
	Id: string,
	Wing: Wing,
	Kind: Kind,
	Title: string,
	Subtitle: string,
	Enabled: boolean,
	Mode: string?, -- Solo pads
	Actions: { PadAction }?, -- Group pads
	Emblem: string?,
	Color: Color3, -- carpet / sign accent
}

local function pad(def: PadDefinition): PadDefinition
	return table.freeze(def) :: any
end

local RED = Color3.fromRGB(128, 26, 30)
local BLUE = Color3.fromRGB(40, 70, 130)
local GREEN = Color3.fromRGB(46, 104, 62)
local PURPLE = Color3.fromRGB(86, 40, 110)

local LobbyPadDefinitions = {
	SoloCountdown = 3, -- seconds on a solo pad before the match starts (step off = cancel)
	UpdateInterval = 0.25, -- server check of who stands on which pad
	MaxGroup = 4,

	Pads = table.freeze({
		-- SINGLEPLAYER (right)
		pad({ Id = "ZombieSurvival", Wing = "Single", Kind = "Solo", Title = "ZOMBIE SURVIVAL", Subtitle = "6 rounds, then Otti · alone", Enabled = true, Mode = "SOLO_ZOMBIES", Color = RED }),
		pad({ Id = "BossFight", Wing = "Single", Kind = "Solo", Title = "BOSS FIGHT", Subtitle = "face Otti alone", Enabled = false, Color = PURPLE }),
		pad({ Id = "ArenaFight", Wing = "Single", Kind = "Solo", Title = "ARENA FIGHT", Subtitle = "gladiator duels", Enabled = false, Color = BLUE }),
		pad({ Id = "ChaosGames", Wing = "Single", Kind = "Solo", Title = "CHAOS GAMES", Subtitle = "free-for-all", Enabled = false, Color = GREEN }),
		-- MULTIPLAYER (left)
		pad({
			Id = "ZombieCoop", Wing = "Multi", Kind = "Group", Title = "ZOMBIE CO-OP", Subtitle = "1-4 players · shared waves", Enabled = true,
			Actions = { { Id = "StartCoop", Label = "START" }, { Id = "COOP_ZOMBIES", Label = "FIND PLAYERS" } }, Emblem = "Otti", Color = RED,
		}),
		pad({
			Id = "TeamBattle", Wing = "Multi", Kind = "Group", Title = "TEAM DEATHMATCH", Subtitle = "equal teams · 1v1 to 4v4", Enabled = true,
			Actions = { { Id = "TIME_BATTLE", Label = "TIME BATTLE" }, { Id = "FIRST_TO", Label = "FIRST TO 20" }, { Id = "ELIMINATION", Label = "ELIMINATION" } }, Emblem = "Schili", Color = BLUE,
		}),
		pad({ Id = "BossCoop", Wing = "Multi", Kind = "Group", Title = "BOSS FIGHT CO-OP", Subtitle = "Otti against your group", Enabled = false, Emblem = "Otti", Color = PURPLE }),
		pad({ Id = "ArenaCoop", Wing = "Multi", Kind = "Group", Title = "ARENA CO-OP", Subtitle = "fight side by side", Enabled = false, Emblem = "Schili", Color = GREEN }),
	}) :: { PadDefinition },
}

function LobbyPadDefinitions.get(id: string): PadDefinition?
	for _, def in LobbyPadDefinitions.Pads do
		if def.Id == id then
			return def
		end
	end
	return nil
end

return table.freeze(LobbyPadDefinitions)
