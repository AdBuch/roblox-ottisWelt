-- Actual MatchService callbacks with isolated world/service mocks.
do
	local callbacks, emitted, bosses = {}, {}, {}
	local removing = {}
	local teamHooks
	local wave
	local states = setmetatable({
		isFighter = function() return true end,
	}, { __index = function(_, key) return key end })
	local names = setmetatable({}, { __index = function(_, key) return key end })
	local function nothing() end
	local function stub()
		return setmetatable({}, { __index = function() return nothing end })
	end
	local function player(id)
		local p = { UserId = id, Parent = true, attrs = {} }
		function p:GetAttribute(key) return self.attrs[key] end
		function p:SetAttribute(key, value) self.attrs[key] = value end
		return p
	end
	local a, b = player(201), player(202)
	local mods = setmetatable({}, { __index = function(t, key)
		local value = stub()
		rawset(t, key, value)
		return value
	end })
	mods.Config = names
	mods.GameStates = states
	mods.GameModeDefinitions = {
		Solo = { MaxPlayers = 1, ShellCount = 1 },
		Coop = { MaxPlayers = 4, MaxShellCount = 3, BaseShellCount = 1, ShellsPerPlayer = 1 },
	}
	mods.CombatConfig = { Feedback = { Shop = "Shop" }, CoopRespawnHealthFraction = 0.6 }
	mods.CurrencyConfig = { denariiFor = function(amount) return amount end }
	mods.OttiBossConfig = { SoloReward = 50, CoopSurvivorReward = 30, CoopContributorReward = 10 }
	mods.MomentumConfig = { Start = { Solo = 0, Coop = 0, TeamBattle = 0 } }
	mods.TeamModeDefinitions = { Common = {
		RespawnSeconds = 1, WinAura = 80, LoseAura = 20, DrawAura = 10, ResultSeconds = 5,
		ArenaCountdownSeconds = 0, SpawnProtectionSeconds = 0,
	} }
	mods.ArenaCampaignProgress = {
		Bosses = { "Otti", "Kroko", "Schili" },
		key = function() return "roster" end,
		loadStage = function() return 1 end,
		beginBoss = function() return true end,
	}
	mods.RoundDefinitions = { TotalRounds = 6 }
	mods.PlayerDataService = { isReady = function() return true end, getStatus = function() return "Loaded" end }
	mods.CombatUtil = { getLivingCharacter = function() return nil end }
	mods.OttiBossService = {
		startEncounter = function(options) table.insert(bosses, options) end,
		stop = nothing,
	}
	mods.WaveService = {
		startRun = function(options) wave = options end,
		setBossPhase = nothing, abort = nothing,
	}
	mods.AuraService = {
		resetRunStats = nothing,
		grant = function(...) table.insert(emitted, { ... }) end,
		awardBossVictory = function(rewards, id, stage, mode)
			table.insert(emitted, { rewards = rewards, id = id, stage = stage, mode = mode })
			return true
		end,
	}
	mods.TeamBattleService = {
		init = function(_, hooks) teamHooks = hooks end,
		beginMatch = nothing, activate = nothing, stop = nothing,
		getScore = function() return 1, 0 end,
		teamOf = function(p) return if p == a then "Red" else "Blue" end,
	}
	mods.Remotes = { CombatFeedback = { FireClient = nothing } }
	local guid = 0
	local services = {
		Players = {
			GetPlayers = function() return {} end,
			PlayerAdded = { Connect = nothing },
			PlayerRemoving = { Connect = function(_, fn) table.insert(removing, fn) end },
		},
		ReplicatedStorage = { Shared = names },
		HttpService = { GenerateGUID = function() guid += 1 return "match-" .. guid end },
	}
	local scheduler = {
		spawn = function(fn, ...) fn(...) end,
		delay = function(seconds, fn) table.insert(callbacks, { seconds, fn }) end,
		wait = nothing,
	}
	local scene = { SetAttribute = nothing, FindFirstChild = function() return nil end }
	local match = matchSource({ Parent = names }, { GetService = function(_, key) return services[key] end },
		function(key) return mods[key] end, scheduler)
	match.init(scene, { ended = nothing, statusChanged = nothing })
	assert(match.startZombies("Coop", { a, b }))
	for i, callback in callbacks do
		if callback[1] == 0.5 then table.remove(callbacks, i) callback[2]() break end
	end
	assert(wave, "normal campaign entry starts a wave")
	wave.onBossRound()
	assert(#bosses == 1)
	-- Disconnect a contributor after the encounter began. Retained roster identifies the entitlement.
	b.Parent = nil
	for _, handler in removing do handler(b) end
	bosses[1].onDefeated({ [a] = 10, [b] = 4 })
	bosses[1].onDefeated({ [a] = 10, [b] = 4 })
	assert(#emitted == 1 and emitted[1].id == "match-1" and emitted[1].stage == 1 and emitted[1].mode == "Coop",
		"double boss end uses one stable match/chapter claim set")
	assert(#emitted[1].rewards == 2 and emitted[1].rewards[2].player == b and emitted[1].rewards[2].amount == 10,
		"disconnected boss contributor remains eligible")
	for i, callback in callbacks do
		if callback[1] == 3 then table.remove(callbacks, i) callback[2]() break end
	end
	bosses[1].onDefeated({ [a] = 10 })
	assert(#emitted == 1, "late end event for the old boss cannot clear the next chapter")
	match.reset()
	table.clear(callbacks)
	table.clear(emitted)
	b.Parent = true
	assert(match.startTeams({ a }, { b }, "TIME_BATTLE"))
	teamHooks.finished("Blue", "participant disconnected", 2)
	assert(#emitted == 0, "technical abort cannot award a PvP win or participation payout")
	match.reset()
	assert(match.startTeams({ a }, { b }, "TIME_BATTLE"))
	teamHooks.finished("Red", "time", 2)
	assert(#emitted == 0, "stale PvP result cannot pay the next match")
	teamHooks.finished("Red", "time", 3)
	teamHooks.finished("Red", "time", 3)
	assert(#emitted == 2 and emitted[1][2] == "match-3" and emitted[1][3] == "result",
		"a valid repeated result produces one stable per-player result")
	print("PASS: MatchService boss replay, disconnected contributor and technical PvP abort")
end
