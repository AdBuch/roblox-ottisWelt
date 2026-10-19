--!strict
-- The one authoritative per-player match record. Every spawn and every lobby return decides from
-- this state (never from timers or guesses):
--   CurrentMatchId     0 = in no match, otherwise the id of the match the player belongs to
--   CurrentGameMode    "" | Solo | Coop | TeamBattle
--   IsParticipant      fighting in that match (also while dead and waiting to respawn)
--   IsSpectator        watching from the tribunes
--   SelectedTeam       "" | Red | Blue
--   ExpectedSpawnZone  LOBBY | RED_TEAM | BLUE_TEAM | ZOMBIE_ARENA | SPECTATOR | ELIMINATED
-- The per-player GameState attribute (GameStates) stays the moment-to-moment state (LOBBY,
-- COUNTDOWN, MATCH_ACTIVE, PLAYER_DEFEATED, ...). Attributes replicate, so the HUD can read them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type SpawnZone = "LOBBY" | "RED_TEAM" | "BLUE_TEAM" | "ZOMBIE_ARENA" | "SPECTATOR" | "ELIMINATED"

local PREFIX = "[OttiArena][Match]"

local PlayerMatchStateService = {}

PlayerMatchStateService.Attributes = table.freeze({
	MatchId = "CurrentMatchId",
	Mode = "CurrentGameMode",
	Participant = "IsParticipant",
	Spectator = "IsSpectator",
	Team = "SelectedTeam",
	Zone = "ExpectedSpawnZone",
})

local A = PlayerMatchStateService.Attributes

function PlayerMatchStateService.init(player: Player)
	if player:GetAttribute(A.MatchId) == nil then
		player:SetAttribute(A.MatchId, 0)
		player:SetAttribute(A.Mode, "")
		player:SetAttribute(A.Participant, false)
		player:SetAttribute(A.Spectator, false)
		player:SetAttribute(A.Team, "")
		player:SetAttribute(A.Zone, "LOBBY")
	end
end

-- Makes the player a participant of a match (team = "" for zombie modes).
function PlayerMatchStateService.assign(player: Player, matchId: number, mode: string, team: string, zone: SpawnZone)
	player:SetAttribute(A.MatchId, matchId)
	player:SetAttribute(A.Mode, mode)
	player:SetAttribute(A.Participant, true)
	player:SetAttribute(A.Spectator, false)
	player:SetAttribute(A.Team, team)
	player:SetAttribute(A.Zone, zone)
	player:SetAttribute(Config.TeamAttribute, team)
	print(PREFIX, ("Match %d: %s assigned (%s%s, spawn %s)"):format(matchId, player.Name, mode, if team ~= "" then " " .. team else "", zone))
end

function PlayerMatchStateService.setZone(player: Player, zone: SpawnZone)
	player:SetAttribute(A.Zone, zone)
end

function PlayerMatchStateService.getZone(player: Player): SpawnZone
	return (player:GetAttribute(A.Zone) or "LOBBY") :: SpawnZone
end

function PlayerMatchStateService.getMatchId(player: Player): number
	return tonumber(player:GetAttribute(A.MatchId)) or 0
end

function PlayerMatchStateService.getTeam(player: Player): string
	return tostring(player:GetAttribute(A.Team) or "")
end

-- Spectating from the tribunes (no match membership).
function PlayerMatchStateService.setSpectator(player: Player, spectating: boolean)
	player:SetAttribute(A.Spectator, spectating)
	if PlayerMatchStateService.getMatchId(player) == 0 then
		player:SetAttribute(A.Zone, if spectating then "SPECTATOR" else "LOBBY")
	end
end

-- Releases the player from `matchId`. Returns false (and changes nothing) if the player already
-- belongs to a different (newer) match: an old cleanup can never touch a new match.
function PlayerMatchStateService.release(player: Player, matchId: number): boolean
	local current = PlayerMatchStateService.getMatchId(player)
	if current ~= 0 and current ~= matchId then
		print(PREFIX, ("Rejected lobby return for %s: cleanup of match %d, player is in match %d"):format(player.Name, matchId, current))
		return false
	end
	player:SetAttribute(A.MatchId, 0)
	player:SetAttribute(A.Mode, "")
	player:SetAttribute(A.Participant, false)
	player:SetAttribute(A.Spectator, false)
	player:SetAttribute(A.Team, "")
	player:SetAttribute(A.Zone, "LOBBY")
	player:SetAttribute(Config.TeamAttribute, "")
	return true
end

return PlayerMatchStateService
