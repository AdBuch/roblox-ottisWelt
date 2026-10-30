--!strict
-- Runs the ONE match of this reserved Arena server:
--   admission (ArenaAdmissionService) -> wait for the expected fighters (or ArrivalTimeoutSeconds)
--   -> start the mode with the existing systems (MatchService zombie run with the Otti round, or
--   TeamBattleService with the submode rules) -> registry heartbeat -> result sequence ->
--   registry entry removed, slots closed -> on the tribune: RETRY (zombie modes: a new run on
--   this server with whoever chose it, once every fighter decided) or BACK TO LOBBY
--   (ArenaReturnService); whoever has not chosen after POST_MATCH_SECONDS goes back to the Hub.
-- Team matches only start with equal, non-empty teams (a player who never arrived cancels the
-- match safely: no rewards, everyone back with MATCH CANCELLED). Spectators are admitted while
-- the match is joinable and watch from the tribunes.
-- Mock mode (Studio): a local match (ExperienceConfig.Studio.ArenaMockMode) starts a few seconds
-- after the first player; RETRY works for every mode there (team modes alternate Red / Blue).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local GameProtocol = require(ReplicatedStorage.Shared.GameProtocol)
local MatchDefinitions = require(ReplicatedStorage.Shared.MatchDefinitions)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local Server = script.Parent.Parent
local Arena = require(Server.Arena)
local InventoryService = require(Server.InventoryService)
local MatchService = require(Server.MatchService)
local Remotes = require(Server.Remotes)
local ArenaAdmissionService = require(script.Parent.ArenaAdmissionService)
local ArenaRegistryHeartbeat = require(script.Parent.ArenaRegistryHeartbeat)
local ArenaReturnService = require(script.Parent.ArenaReturnService)
local ArenaSpectatorService = require(script.Parent.ArenaSpectatorService)

local PREFIX = "[OttiArena][Arena]"

local ArenaMatchService = {}

local started = false
local arrivalTimer = false
local mock = false
local mockRecord: MatchTypes.MatchRecord? = nil
local retryRecord: MatchTypes.MatchRecord? = nil -- the latest RETRY (outside mock mode)
local retries = 0

local POST_MATCH_SECONDS = 120
type PostMatch = { fighters: { Player }, retry: { Player }, decided: { [Player]: boolean }, canRetry: boolean }
local postMatch: PostMatch? = nil

local function message(player: Player, text: string, ok: boolean)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, text, ok)
end

local function currentRecord(): MatchTypes.MatchRecord?
	if retryRecord then
		return retryRecord
	end
	return if mock then mockRecord else ArenaAdmissionService.getRecord()
end

local function definition(): MatchDefinitions.MatchDefinition?
	local record = currentRecord()
	return if record then MatchDefinitions.get(record.mode) else nil
end

local function newMockRecord(): MatchTypes.MatchRecord
	local mode = MatchDefinitions.get(ExperienceConfig.Studio.ArenaMockMode) and ExperienceConfig.Studio.ArenaMockMode or "COOP_ZOMBIES"
	return {
		matchId = "mock_local_" .. tostring(os.time()),
		mode = mode :: any,
		protocol = GameProtocol.Version,
		privateServerId = "",
		fighters = {},
		policy = "PUBLIC",
		createdAt = os.time(),
		createdBy = "studio",
	}
end

local function start()
	if started then
		return
	end
	local record = currentRecord()
	local def = definition()
	if not record or not def then
		return
	end
	local arrived = ArenaAdmissionService.fighters()
	if #arrived == 0 then
		return
	end
	started = true
	local ok: boolean
	if def.Id == "BOSS_SOLO" then
		local players = {}
		for _, entry in arrived do
			table.insert(players, entry.player)
		end
		ok = MatchService.startBoss(players, record.boss or "Otti") -- the boss chosen in the Hub
	elseif def.Kind == "Zombies" then
		local players = {}
		for _, entry in arrived do
			table.insert(players, entry.player)
		end
		ok = MatchService.startZombies(def.Legacy :: any, players)
	else
		local red, blue = {}, {}
		for _, entry in arrived do
			table.insert(if entry.team == "Red" then red else blue, entry.player)
		end
		if #red == 0 or #blue == 0 or #red ~= #blue then
			print(PREFIX, ("Team match cancelled: %d v %d arrived"):format(#red, #blue))
			if mock then
				started = false
				for _, entry in arrived do
					message(entry.player, "STUDIO MOCK: team modes need an even number of players (Test > Local Server, 2+ players)", false)
				end
				return
			end
			MatchService.cancel("teams incomplete")
			ok = false
		else
			ok = MatchService.startTeams(red, blue, def.Id)
		end
	end
	if ok then
		ArenaRegistryHeartbeat.setStatus("ACTIVE")
		print(PREFIX, ("%s started with %d fighter(s)"):format(def.Id, #arrived))
	end
end

local function checkStart()
	if started then
		return
	end
	local record = currentRecord()
	if not record then
		return
	end
	-- Boss testing in Studio waits for a choice instead of starting a zombie wave.
	if mock and record.mode == "BOSS_SOLO" and not record.boss then
		return
	end
	local expected = #record.fighters
	if not mock and expected > 0 and ArenaAdmissionService.fighterCount() >= expected then
		start()
		return
	end
	if not arrivalTimer then
		arrivalTimer = true
		local wait = if mock then ExperienceConfig.Studio.ArenaMockStartSeconds else ExperienceConfig.Teleport.ArrivalTimeoutSeconds
		task.delay(wait, function()
			arrivalTimer = false
			if not started then
				start()
				if mock and not started then
					checkStart() -- e.g. waiting for a second team player
				end
			end
		end)
	end
end

-- RETRY: a new match of the same mode on this server with the players who chose it.
local function restart(current: PostMatch)
	if postMatch ~= current then
		return
	end
	postMatch = nil
	local previous = currentRecord()
	local voters = {}
	for _, player in current.retry do
		if player.Parent then
			table.insert(voters, player)
		end
	end
	if #voters == 0 or not previous then
		return
	end
	retries += 1
	local def = MatchDefinitions.get(previous.mode)
	local teams = def ~= nil and def.Kind == "Team"
	local record = table.clone(previous)
	record.matchId = ("%s_retry%d"):format((previous.matchId:gsub("_retry%d+$", "")), retries)
	record.fighters = {}
	for i, player in voters do
		table.insert(record.fighters, { userId = player.UserId, team = if not teams then "" elseif i % 2 == 1 then "Red" else "Blue", partyId = "" })
	end
	MatchService.reset()
	if mock then
		mockRecord = record
	else
		retryRecord = record
	end
	ArenaRegistryHeartbeat.reset(record)
	started = false
	ArenaAdmissionService.reassign(voters, teams)
	for _, player in Players:GetPlayers() do
		if table.find(voters, player) then
			ArenaSpectatorService.remove(player)
		else
			ArenaSpectatorService.add(player)
		end
		Remotes.MatchEvent:FireClient(player, "PostMatchClosed")
	end
	print(PREFIX, ("RETRY %s with %d fighter(s)"):format(record.mode, #voters))
	start()
end

-- Restarts as soon as every fighter still here has chosen and at least one chose RETRY.
local function checkDecided(current: PostMatch)
	if postMatch ~= current or #current.retry == 0 then
		return
	end
	for _, player in current.fighters do
		if player.Parent and not current.decided[player] then
			return
		end
	end
	restart(current)
end

local function backToLobby(player: Player)
	local current = postMatch
	if current then
		current.decided[player] = true
		task.defer(checkDecided, current)
	end
	ArenaReturnService.request(player)
end

local function retry(player: Player): (boolean, string)
	local current = postMatch
	if not current or not current.canRetry or not table.find(current.fighters, player) then
		return false, "Retry is only open to the fighters of the last match"
	end
	if not current.decided[player] then
		current.decided[player] = true
		table.insert(current.retry, player)
		checkDecided(current)
	end
	return true, if postMatch == current then "Waiting for the other fighters…" else "Again!"
end

local function onEnded(result: MatchService.Result)
	ArenaRegistryHeartbeat.complete()
	local fighters = MatchService.fighters()
	for _, player in Players:GetPlayers() do
		ArenaAdmissionService.demote(player)
	end
	if result.reason == "teams incomplete" then
		print(PREFIX, "Match cancelled: returning everybody to the Hub")
		task.delay(1, function()
			ArenaReturnService.returnAll("CANCELLED")
		end)
		return
	end
	-- On the tribune: RETRY (zombie modes; every mode in Studio) or BACK TO LOBBY
	local def = definition()
	local current: PostMatch = { fighters = fighters, retry = {}, decided = {}, canRetry = mock or (def ~= nil and def.Kind == "Zombies") }
	postMatch = current
	print(PREFIX, ("Match over (%s): waiting for RETRY / BACK TO LOBBY"):format(result.reason))
	for _, player in Players:GetPlayers() do
		Remotes.MatchEvent:FireClient(player, "PostMatch", { retry = current.canRetry and table.find(fighters, player) ~= nil, seconds = POST_MATCH_SECONDS })
	end
	task.delay(POST_MATCH_SECONDS, function()
		if postMatch ~= current then
			return
		end
		local idle = {}
		for _, player in Players:GetPlayers() do
			if not current.decided[player] then
				table.insert(idle, player)
			end
		end
		if #current.retry > 0 then
			restart(current)
		else
			postMatch = nil
		end
		ArenaReturnService.send(idle, nil)
	end)
end

function ArenaMatchService.init(folder: Instance)
	mock = EnvironmentConfig.isMockMode()
	if mock then
		mockRecord = newMockRecord()
		print(PREFIX, ("STUDIO MOCK MODE: local %s match, no tickets / teleports"):format((mockRecord :: MatchTypes.MatchRecord).mode))
	end

	MatchService.init(folder, {
		ended = onEnded,
		statusChanged = ArenaRegistryHeartbeat.poke,
	})

	ArenaAdmissionService.init({
		fighterAdmitted = function(player: Player, team: string)
			ArenaSpectatorService.remove(player)
			local record = currentRecord()
			if record then
				if mock then
					table.insert(record.fighters, { userId = player.UserId, team = team, partyId = "" })
				end
				ArenaRegistryHeartbeat.start(folder, record)
			end
			message(player, "Welcome to the Colosseum — waiting for the other fighters", true)
			checkStart()
		end,
		spectatorAdmitted = function(player: Player)
			ArenaSpectatorService.add(player)
			InventoryService.addStat(player, "matchesSpectated", 1) -- statistics only, never rewards
			local record = currentRecord()
			if record then
				ArenaRegistryHeartbeat.start(folder, record)
			end
			ArenaRegistryHeartbeat.poke()
		end,
		acceptsFighters = function()
			if started then
				return false
			end
			local def = definition()
			return not mock or (def ~= nil and ArenaAdmissionService.fighterCount() < def.MaxFighters)
		end,
		acceptsSpectators = function()
			return not MatchService.isFinished()
		end,
	})
	if mock then
		for i, choice in { { "Otti", "OTTI" }, { "Schili", "SCHILI" }, { "Kroko", "KROKERO" } } do
			local host = Instance.new("Part")
			host.Name = "StudioBossChoice_" .. choice[1]
			host.Anchored = true
			host.Size = Vector3.new(4, 3, 4)
			host.Position = Vector3.new((i - 2) * 9, Arena.Layout.FloorTop + 1.5, Arena.Layout.SemiAxisZ - 17)
			host.Color = Color3.fromRGB(176, 125, 60)
			host.Parent = folder
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Test boss fight"
			prompt.ObjectText = choice[2]
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.F
			prompt.Parent = host
			prompt.Triggered:Connect(function(player)
				local record = mockRecord
				if not record or record.mode ~= "BOSS_SOLO" or started or arrivalTimer then return end
				if player:GetAttribute("ArenaRole") ~= "FIGHTER" then return end
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if not root or not root:IsA("BasePart") or (root.Position - host.Position).Magnitude > 12 then return end
				record.boss = choice[1]
				message(player, "Boss test: " .. choice[2], true)
				checkStart()
			end)
		end
	end

	-- RETURN TO HUB (spectator bar / emergency button / the tribune door)
	Remotes.MatchRequest.OnServerInvoke = function(player: Player, action: unknown)
		if action == "ReturnToHub" then
			backToLobby(player)
			return { ok = true, message = "Returning to the Hub…" }
		elseif action == "Retry" then
			local ok, text = retry(player)
			return { ok = ok, message = text }
		end
		return { ok = false, message = "Not available in the arena" }
	end
	Remotes.CombatAction.OnServerEvent:Connect(function(player: Player, action: unknown)
		if action == "LeaveTribune" then
			backToLobby(player)
		end
	end)
	Players.PlayerRemoving:Connect(function()
		local current = postMatch
		if current then
			task.defer(checkDecided, current)
		end
	end)
	local door = Arena.Layout.ReturnDoor
	if door then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Return to Hub"
		prompt.ObjectText = "RETURN TO HUB"
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.Parent = door
		prompt.Triggered:Connect(function(player)
			if player:GetAttribute("ArenaRole") ~= "FIGHTER" or MatchService.isFinished() then
				backToLobby(player)
			end
		end)
	end

	-- A public (non-reserved) Arena server never runs matches: admission rejects every visitor
	-- (no valid ticket for this server) and sends them to the Hub.
	if not mock and game.PrivateServerId == "" then
		warn(PREFIX, "Public Arena server: matches only run on reserved servers")
	end
end

return ArenaMatchService
