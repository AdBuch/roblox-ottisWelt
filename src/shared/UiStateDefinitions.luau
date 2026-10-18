--!strict
-- Which HUD groups each UI state and each HUD mode may show. A group is visible only if the state
-- allows it, the mode allows it and the group itself currently has something to show.

export type UiState = "Lobby" | "Solo" | "Coop" | "TeamBattle" | "Boss" | "Spectator" | "Results"
export type Group =
	"Health" -- compact player health
	| "Round" -- compact round / zombies line
	| "Teammates" -- co-op teammate strip
	| "TeamScore" -- RED n — n BLUE + time
	| "Boss" -- slim Otti bar
	| "Specials" -- desktop special cards (touch buttons are "Controls")
	| "Controls" -- touch Attack / Block / Specials
	| "Context" -- world-space health bars
	| "Aura" -- permanent Aura counter
	| "Hints" -- short control hints
	| "Roster" -- lobby party / team rosters
	| "Spectator" -- watching bar
	| "Notifications" -- small queued messages

local function set(list: { Group }): { [Group]: boolean }
	local result = {}
	for _, group in list do
		result[group] = true
	end
	return table.freeze(result) :: any
end

local UiStateDefinitions = {
	States = table.freeze({
		Lobby = set({ "Aura", "Hints", "Roster", "Specials", "Controls", "Context", "Notifications" }),
		Solo = set({ "Health", "Round", "Specials", "Controls", "Context", "Notifications", "Hints" }),
		Coop = set({ "Health", "Round", "Teammates", "Specials", "Controls", "Context", "Notifications", "Hints" }),
		TeamBattle = set({ "Health", "TeamScore", "Specials", "Controls", "Context", "Notifications", "Hints" }),
		Boss = set({ "Health", "Boss", "Teammates", "Specials", "Controls", "Context", "Notifications" }),
		Spectator = set({ "Spectator", "Round", "TeamScore", "Boss", "Notifications" }),
		Results = set({ "Notifications" }),
	}) :: { [UiState]: { [Group]: boolean } },

	-- Groups each HUD mode allows (critical warnings, results, prompts and touch combat buttons are
	-- never optional; the low-health warning shows the health bar even in Hidden mode).
	Modes = table.freeze({
		Full = set({ "Health", "Round", "Teammates", "TeamScore", "Boss", "Specials", "Controls", "Context", "Aura", "Hints", "Roster", "Spectator", "Notifications" }),
		Minimal = set({ "Health", "Controls", "Boss", "TeamScore", "Spectator", "Notifications" }),
		Hidden = set({ "Controls", "Spectator" }),
	}) :: { [string]: { [Group]: boolean } },

	ModeOrder = table.freeze({ "Full", "Minimal", "Hidden" }),
}

return table.freeze(UiStateDefinitions)
