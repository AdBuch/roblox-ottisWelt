--!strict
-- Every match type that runs on its own reserved Arena server. The Hub validates a requested
-- mode against this table; the Arena runs it with the existing systems:
--   Zombie modes -> MatchService zombie runs (Round 7 is always the Otti boss)
--   Team modes   -> TeamBattleService with the rules in TeamModeDefinitions
-- `Legacy` is the internal arena mode name used by MatchService / the HUD ("Solo" | "Coop" | "TeamBattle").

local ExperienceConfig = require(script.Parent.ExperienceConfig)

export type MatchMode = "SOLO_ZOMBIES" | "COOP_ZOMBIES" | "TIME_BATTLE" | "FIRST_TO" | "ELIMINATION"
export type MatchKind = "Zombies" | "Team"
export type Role = "FIGHTER" | "SPECTATOR" | "ELIMINATED_SPECTATOR"
export type SpectatorPolicy = "PUBLIC" | "FRIENDS_ONLY" | "PARTY_ONLY" | "PRIVATE"

export type MatchDefinition = {
	Id: MatchMode,
	DisplayName: string,
	Kind: MatchKind,
	Legacy: string,
	MinFighters: number,
	MaxFighters: number,
	MaxSpectators: number,
	Queued: boolean, -- uses cross-server matchmaking (Co-op optional, Team always)
	Filter: string, -- active-battle filter chip
}

local capacity = ExperienceConfig.Capacity

local function def(d: MatchDefinition): MatchDefinition
	return table.freeze(d) :: any
end

local list: { MatchDefinition } = {
	def({ Id = "SOLO_ZOMBIES", DisplayName = "SOLO ARENA", Kind = "Zombies", Legacy = "Solo", MinFighters = 1, MaxFighters = 1, MaxSpectators = capacity.MaxSpectators, Queued = false, Filter = "Zombies" }),
	def({ Id = "COOP_ZOMBIES", DisplayName = "CO-OP LEGIONS", Kind = "Zombies", Legacy = "Coop", MinFighters = 1, MaxFighters = 4, MaxSpectators = capacity.MaxSpectators, Queued = true, Filter = "Zombies" }),
	def({ Id = "TIME_BATTLE", DisplayName = "TIME BATTLE", Kind = "Team", Legacy = "TeamBattle", MinFighters = 2, MaxFighters = math.min(8, capacity.MaxFighters), MaxSpectators = capacity.MaxSpectators, Queued = true, Filter = "Time Battle" }),
	def({ Id = "FIRST_TO", DisplayName = "FIRST TO 20", Kind = "Team", Legacy = "TeamBattle", MinFighters = 2, MaxFighters = math.min(8, capacity.MaxFighters), MaxSpectators = capacity.MaxSpectators, Queued = true, Filter = "First to 20" }),
	def({ Id = "ELIMINATION", DisplayName = "ELIMINATION", Kind = "Team", Legacy = "TeamBattle", MinFighters = 2, MaxFighters = math.min(8, capacity.MaxFighters), MaxSpectators = capacity.MaxSpectators, Queued = true, Filter = "Elimination" }),
}

local byId: { [string]: MatchDefinition } = {}
for _, d in list do
	byId[d.Id] = d
end

local MatchDefinitions = {
	ById = table.freeze(byId),
	Ordered = table.freeze(list),
	Roles = table.freeze({ "FIGHTER", "SPECTATOR", "ELIMINATED_SPECTATOR" } :: { Role }),
	Policies = table.freeze({ "PUBLIC", "FRIENDS_ONLY", "PARTY_ONLY", "PRIVATE" } :: { SpectatorPolicy }),
	Filters = table.freeze({ "All", "Friends", "Zombies", "Otti", "Time Battle", "First to 20", "Elimination" }),
}

function MatchDefinitions.get(mode: unknown): MatchDefinition?
	if typeof(mode) ~= "string" then
		return nil
	end
	return byId[mode]
end

function MatchDefinitions.isRole(role: unknown): boolean
	return role == "FIGHTER" or role == "SPECTATOR" or role == "ELIMINATED_SPECTATOR"
end

return table.freeze(MatchDefinitions)
