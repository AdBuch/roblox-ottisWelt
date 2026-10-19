--!strict
-- The ONE place for Roblox Experience settings: Place IDs per environment, DataStore and
-- MemoryStore names, teleport, registry, matchmaking, capacity and Studio test settings.
--
-- >>> Enter the real Place IDs here after publishing (Creator Dashboard -> your Experience ->
-- >>> Places -> the number in the place URL). 0 = not configured yet: teleports are disabled
-- >>> and the game runs in local mock mode (see README "Studio local mode").
--
-- Environment selection happens on the server only (EnvironmentConfig): a server is PROD only if
-- its game.PlaceId equals a configured PROD Place ID and it is not running in Studio. Everything
-- else (Studio, unknown or DEV places) is DEV, so a DEV server can never write to the PROD data.

export type EnvironmentName = "DEV" | "PROD"

export type EnvironmentSettings = {
	HubPlaceId: number,
	ArenaPlaceId: number,
	DataStoreName: string, -- stable per environment: NEVER change it for a normal update
	MemoryStoreNamespace: string, -- prefix of every MemoryStore map of this environment
	StudioMockData: boolean, -- Studio uses in-memory player data (no DataStore reads/writes)
}

local ExperienceConfig = {
	Environments = table.freeze({
		DEV = table.freeze({
			HubPlaceId = 127694690386807, -- DEV Hub (start place), Experience 10771565873
			ArenaPlaceId = 70661230851944, -- DEV Colosseum Arena, Experience 10771565873
			DataStoreName = "OttiPlayerData_DEV_v1",
			MemoryStoreNamespace = "OttiMatches_DEV",
			StudioMockData = true,
		} :: EnvironmentSettings),
		PROD = table.freeze({
			HubPlaceId = 0, -- TODO: PROD Hub (start place) ID
			ArenaPlaceId = 0, -- TODO: PROD Arena place ID
			DataStoreName = "OttiPlayerData_PROD_v1",
			MemoryStoreNamespace = "OttiMatches_PROD",
			StudioMockData = false,
		} :: EnvironmentSettings),
	}),

	Teleport = table.freeze({
		Retries = 3, -- Hub -> Arena attempts per player group
		RetryDelaySeconds = 2,
		ReturnRetries = 5, -- Arena -> Hub attempts (then the emergency button stays visible)
		ReturnRetryDelaySeconds = 3,
		ArrivalTimeoutSeconds = 25, -- Arena waits this long for the expected fighters
		TransitionHoldSeconds = 30, -- a profile marked "transferring" goes back to normal after this
	}),

	Registry = table.freeze({
		HeartbeatSeconds = 12,
		ExpirationSeconds = 50, -- a match without heartbeat disappears after this
		MatchRecordSeconds = 3 * 60 * 60, -- server-only match definition / connection lifetime
		CompletedVisibleSeconds = 0, -- completed matches are removed at once (never joinable)
		ListRefreshSeconds = 12, -- Hub overlay background refresh while open
		ListCacheSeconds = 4, -- Hub servers cache the registry read for this long
	}),

	Tickets = table.freeze({
		LifetimeSeconds = 120,
		SpectatorReservationSeconds = 60,
	}),

	Matchmaking = table.freeze({
		TickSeconds = 3, -- each Hub server runs the matchmaker this often
		QueueEntrySeconds = 90, -- queue entries expire unless their home server refreshes them
		RefreshSeconds = 20,
		LeaseSeconds = 8, -- one server matches a given queue at a time
		AssignmentSeconds = 60,
		CoopOfferStartAfterSeconds = 20, -- then START WITH CURRENT PARTY is highlighted
		CoopFillSeconds = 45, -- after this the matchmaker starts co-op groups below 4 players
		-- Team Battles: the smallest equal team size allowed after waiting this long
		TeamSizeWaitSeconds = table.freeze({ [4] = 0, [3] = 15, [2] = 30, [1] = 45 }),
		MaxEntriesScanned = 40,
	}),

	Capacity = table.freeze({
		MaxFighters = 8,
		MaxSpectators = 20,
		RecommendedServerSize = 28, -- set "Max Players" of the Arena place to this
	}),

	Spectating = table.freeze({
		FriendWeight = 5,
		FeaturedWeight = 3,
		NormalWeight = 1,
		WeightRule = "Max", -- "Max" | "Sum" | "Product": how friend + featured combine
		FriendCacheSeconds = 300,
		FeaturedSpectatorThreshold = 10,
		DefaultPolicy = "PUBLIC", -- PUBLIC | FRIENDS_ONLY | PARTY_ONLY | PRIVATE
	}),

	Studio = table.freeze({
		UseMockMemoryStore = true, -- Studio: in-memory registry / queues / tickets
		MockMatches = 4, -- fake live battles in the Hub overlay (0 = none)
		MockFriendIds = table.freeze({} :: { number }), -- e.g. { 12345 } to see FRIENDS IN BATTLE
		MockFriendSelf = true, -- also treat the local test player as a "friend" in one mock battle
		-- Arena place opened directly in Studio: run this match with the local players
		ArenaMockMode = "COOP_ZOMBIES", -- SOLO_ZOMBIES | COOP_ZOMBIES | TIME_BATTLE | FIRST_TO | ELIMINATION
		ArenaMockStartSeconds = 4,
	}),
}

return table.freeze(ExperienceConfig)
