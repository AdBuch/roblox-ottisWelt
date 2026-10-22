--!strict
-- Data shapes shared by Hub and Arena servers (MemoryStore records, tickets, teleport payload).
-- Public vs. private:
--   RegistryRecord   PUBLIC (Hub servers read it to list battles; clients only get sanitized cards)
--   MatchRecord      server-only definition of the match (fighters, teams, policy, protocol)
--   ConnectionRecord server-only reserved-server access code. Never sent to clients, GUIs,
--                    attributes, RemoteEvents or TeleportData.
--   AdmissionTicket  server-only, one-time, keyed "<matchId>:<userId>"
--   TeleportPayload  what a client CAN see (TeleportData): no secrets, never trusted.

local MatchDefinitions = require(script.Parent.MatchDefinitions)

export type MatchMode = MatchDefinitions.MatchMode
export type Role = MatchDefinitions.Role

export type MatchStatus = "STARTING" | "ACTIVE" | "COMPLETED" | "CLEANUP"

export type RegistryRecord = {
	matchId: string,
	mode: MatchMode,
	subMode: string?,
	status: MatchStatus,
	protocol: number,
	policy: string,
	round: number,
	maxRounds: number,
	phase: string, -- "Round 4", "Otti Phase 2", "Sudden Death", ...
	bossPhase: number, -- 0 = no boss
	redScore: number,
	blueScore: number,
	target: number, -- FIRST_TO target / ELIMINATION rounds to win
	timeLeft: number, -- -1 = no clock
	redAlive: number,
	blueAlive: number,
	suddenDeath: boolean,
	fighterCount: number,
	maxFighters: number,
	spectatorCount: number,
	maxSpectators: number,
	joinableAsSpectator: boolean,
	startedAt: number,
	heartbeatAt: number,
	publicParticipantIds: { number },
	partyIds: { string },
}

export type Fighter = { userId: number, team: string, partyId: string }

export type MatchRecord = {
	matchId: string,
	mode: MatchMode,
	protocol: number,
	privateServerId: string, -- game.PrivateServerId of the reserved Arena server ("" in mock mode)
	fighters: { Fighter },
	policy: string,
	createdAt: number,
	createdBy: string, -- Hub JobId
	boss: string?, -- BOSS_SOLO: the companion boss chosen in the Hub (Otti | Kroko | Schili)
}

export type ConnectionRecord = {
	matchId: string,
	accessCode: string,
	placeId: number,
}

export type AdmissionTicket = {
	ticketId: string,
	matchId: string,
	userId: number,
	role: Role,
	team: string,
	mode: MatchMode,
	issuedAt: number,
	expiresAt: number,
	consumed: boolean,
	protocol: number,
}

export type SlotRecord = {
	matchId: string,
	joinable: boolean,
	maxSpectators: number,
	connectedSpectators: number,
	reservations: { [string]: number }, -- tostring(userId) -> expiresAt
}

export type TeleportPayload = {
	kind: "ToArena" | "ToHub",
	matchId: string?,
	role: Role?,
	mode: string?, -- loading-screen text only
	message: string?, -- ToHub: a known message code (shown compactly in the Hub)
	fromSpectating: boolean?,
}

local MatchTypes = {
	-- Known message codes the Hub shows after a return / failure (anything else is ignored)
	Messages = table.freeze({
		UNREACHABLE = "ARENA COULD NOT BE REACHED",
		FULL = "MATCH IS ALREADY FULL",
		ENDED = "BATTLE HAS ENDED",
		TELEPORT_FAILED = "TELEPORT FAILED — TRY AGAIN",
		UPDATE = "GAME UPDATE IN PROGRESS",
		INVALID = "ADMISSION REJECTED",
		CANCELLED = "MATCH CANCELLED — A PLAYER COULD NOT JOIN",
		NO_BATTLES = "NO LIVE BATTLES RIGHT NOW",
	}),
}

function MatchTypes.ticketKey(matchId: string, userId: number): string
	return matchId .. ":" .. tostring(userId)
end

return table.freeze(MatchTypes)
