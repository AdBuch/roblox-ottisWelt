--!strict
-- Player and match states (server-owned). Players carry "GameState" and "Location" attributes;
-- the arena folder carries the match-level "MatchState".
--
-- Player flow:
--   LOBBY ─ MODE_SELECTION ─ PARTY_FORMING / TEAM_SELECTION ─ READY_CHECK ─ COUNTDOWN
--         ─ MATCH_ACTIVE ⇄ ROUND_COMPLETE ─ PLAYER_DEFEATED ─ MATCH_COMPLETE / VICTORY ─ LOBBY
--   LOBBY ─ SPECTATING ─ LOBBY
-- Match flow (arena): LOBBY (idle) ─ COUNTDOWN ─ MATCH_ACTIVE ⇄ ROUND_COMPLETE ─ VICTORY /
--   MATCH_COMPLETE ─ CLEANUP ─ LOBBY

export type GameState =
	"LOBBY"
	| "MODE_SELECTION"
	| "PARTY_FORMING"
	| "TEAM_SELECTION"
	| "READY_CHECK"
	| "COUNTDOWN"
	| "MATCH_ACTIVE"
	| "ROUND_COMPLETE"
	| "PLAYER_DEFEATED"
	| "MATCH_COMPLETE"
	| "VICTORY"
	| "SPECTATING"
	| "CLEANUP"

export type Location = "Lobby" | "Arena" | "Tribune"

local GameStates = {
	Lobby = "LOBBY" :: GameState,
	ModeSelection = "MODE_SELECTION" :: GameState,
	PartyForming = "PARTY_FORMING" :: GameState,
	TeamSelection = "TEAM_SELECTION" :: GameState,
	ReadyCheck = "READY_CHECK" :: GameState,
	Countdown = "COUNTDOWN" :: GameState,
	MatchActive = "MATCH_ACTIVE" :: GameState,
	RoundComplete = "ROUND_COMPLETE" :: GameState,
	PlayerDefeated = "PLAYER_DEFEATED" :: GameState,
	MatchComplete = "MATCH_COMPLETE" :: GameState,
	Victory = "VICTORY" :: GameState,
	Spectating = "SPECTATING" :: GameState,
	Cleanup = "CLEANUP" :: GameState,

	StateAttribute = "GameState",
	LocationAttribute = "Location",
}

-- In an arena match and allowed to fight right now.
function GameStates.isFighter(state: unknown): boolean
	return state == GameStates.MatchActive or state == GameStates.RoundComplete
end

-- In the lobby area (any lobby sub-state): safe, may shop and train.
function GameStates.isInLobby(state: unknown): boolean
	return state == nil
		or state == GameStates.Lobby
		or state == GameStates.ModeSelection
		or state == GameStates.PartyForming
		or state == GameStates.TeamSelection
		or state == GameStates.ReadyCheck
end

-- May buy and equip items.
function GameStates.canChangeEquipment(state: unknown): boolean
	return GameStates.isInLobby(state)
end

return GameStates
