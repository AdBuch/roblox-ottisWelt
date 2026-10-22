--!strict
-- Only active gathering areas are built: one co-op mosaic and the two opposing teams.
export type Wing = "Single" | "Multi"
export type Kind = "Solo" | "Group"
export type PadAction = { Id: string, Label: string }
export type PadDefinition = {
	Id: string,
	Wing: Wing,
	Kind: Kind,
	Title: string,
	Subtitle: string,
	Enabled: boolean,
	Mode: string?,
	Actions: { PadAction }?,
	Emblem: string?,
	Team: string?,
	Color: Color3,
}
local function pad(def: PadDefinition): PadDefinition
	return table.freeze(def) :: any
end
local LobbyPadDefinitions = {
	SoloCountdown = 3,
	UpdateInterval = 0.25,
	MaxGroup = 4,
	Pads = table.freeze({
		pad({
			Id = "ZombieCoop", Wing = "Single", Kind = "Group", Title = "OTTI CO-OP",
			Subtitle = "Fight the legions together · 1-4 players", Enabled = true, Emblem = "Otti",
			Actions = { { Id = "StartCoop", Label = "START" }, { Id = "COOP_ZOMBIES", Label = "FIND PLAYERS" } },
			Color = Color3.fromRGB(128, 26, 30),
		}),
		pad({
			Id = "TeamSchili", Wing = "Multi", Kind = "Group", Title = "TEAM SCHILI",
			Subtitle = "Blue team · patience, then surprise", Enabled = true, Emblem = "Schili", Team = "Blue",
			Actions = { { Id = "ConfirmTeam", Label = "READY" } }, Color = Color3.fromRGB(55, 100, 112),
		}),
		pad({
			Id = "TeamKrokero", Wing = "Multi", Kind = "Group", Title = "TEAM KROKERO",
			Subtitle = "Red team · a big grin and bigger courage", Enabled = true, Emblem = "Krokero", Team = "Red",
			Actions = { { Id = "ConfirmTeam", Label = "READY" } }, Color = Color3.fromRGB(150, 64, 44),
		}),
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
