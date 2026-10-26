--!strict
-- Runs the ONE match of this reserved Arena server:
--   admission (ArenaAdmissionService) -> wait for the expected fighters (or ArrivalTimeoutSeconds)
--   -> start the mode with the existing systems (MatchService zombie run with the Otti round, or
--   TeamBattleService with the submode rules) -> registry heartbeat -> result sequence ->
--   registry entry removed, slots closed -> everybody back to the Hub (ArenaReturnService).
-- Team matches only start with equal, non-empty teams (a player who never arrived cancels the
-- match safely: no rewards, everyone back with MATCH CANCELLED). Spectators are admitted while
-- the match is joinable and watch from the tribunes.
-- Mock mode (Studio): a local match (ExperienceConfig.Studio.ArenaMockMode) starts a few seconds
-- after the first player; after its end a fresh one starts on the same server (no stale state).

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

local function message(player: Player, text: string, ok: boolean)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, text, ok)
end

local function currentRecord(): MatchTypes.MatchRecord?
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

local function onEnded(result: MatchService.Result)
	ArenaRegistryHeartbeat.complete()
	for _, player in Players:GetPlayers() do
		ArenaAdmissionService.demote(player)
	end
	print(PREFIX, ("Match over (%s): returning everybody to the Hub"):format(result.reason))
	local code = if result.reason == "teams incomplete" then "CANCELLED" else nil
	task.delay(1, function()
		ArenaReturnService.returnAll(code)
	end)
	if mock then
		task.delay(10, function()
			-- Studio: a fresh local match with whoever is still here (stale-state test)
			MatchService.resetForMock()
			local record = newMockRecord()
			mockRecord = record
			ArenaRegistryHeartbeat.reset(record)
			started = false
			local def = definition()
			for _, entry in ArenaAdmissionService.reassignMock(if def then def.MaxFighters else 1) do
				if entry.role == "FIGHTER" then
					ArenaSpectatorService.remove(entry.player)
					table.insert(record.fighters, { userId = entry.player.UserId, team = entry.team, partyId = "" })
				else
					ArenaSpectatorService.add(entry.player)
				end
			end
			checkStart()
		end)
	end
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
			ArenaReturnService.request(player)
			return { ok = true, message = "Returning to the Hub…" }
		end
		return { ok = false, message = "Not available in the arena" }
	end
	Remotes.CombatAction.OnServerEvent:Connect(function(player: Player, action: unknown)
		if action == "LeaveTribune" then
			ArenaReturnService.request(player)
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
				ArenaReturnService.request(player)
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
