--!strict
-- Per-player game states (server-owned, replicated as the player attribute "GameState").
--   LOBBY / EQUIPMENT_SELECTION  safe underground lobby; equipment may change
--   ENTERING_ARENA               being moved into the arena (short)
--   ROUND_ACTIVE / ROUND_COMPLETE the one active fighter; may attack and be attacked
--   PLAYER_DEFEATED              died during a run; respawns in the lobby
--   VICTORY                      all six rounds won; returns to the lobby shortly
--   SPECTATING                   on the tribune; can't attack or be attacked

export type GameState =
	"LOBBY"
	| "EQUIPMENT_SELECTION"
	| "ENTERING_ARENA"
	| "ROUND_ACTIVE"
	| "ROUND_COMPLETE"
	| "PLAYER_DEFEATED"
	| "VICTORY"
	| "SPECTATING"

export type Location = "Lobby" | "Arena" | "Tribune"

local GameStates = {
	Lobby = "LOBBY" :: GameState,
	EquipmentSelection = "EQUIPMENT_SELECTION" :: GameState,
	EnteringArena = "ENTERING_ARENA" :: GameState,
	RoundActive = "ROUND_ACTIVE" :: GameState,
	RoundComplete = "ROUND_COMPLETE" :: GameState,
	PlayerDefeated = "PLAYER_DEFEATED" :: GameState,
	Victory = "VICTORY" :: GameState,
	Spectating = "SPECTATING" :: GameState,

	StateAttribute = "GameState",
	LocationAttribute = "Location",
}

-- May attack zombies and be attacked by them.
function GameStates.isFighter(state: unknown): boolean
	return state == GameStates.RoundActive or state == GameStates.RoundComplete
end

-- May buy and equip items.
function GameStates.canChangeEquipment(state: unknown): boolean
	return state == nil or state == GameStates.Lobby or state == GameStates.EquipmentSelection
end

return GameStates
