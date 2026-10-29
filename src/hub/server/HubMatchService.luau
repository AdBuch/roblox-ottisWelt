--!strict
-- Hub entry for every match request. Clients may only ASK (MatchRequest RemoteFunction, rate
-- limited per action); every decision is made here:
--   Party / PartyCreate / PartyInvite / PartyAccept / PartyLeave / PartyReady / ServerPlayers
--   PlaySolo           Solo zombie run on its own reserved Arena server (no waiting)
--   StartCoop          Co-op with the current party (or alone), no waiting for 4 players
--   Queue / LeaveQueue matchmaking for COOP_ZOMBIES, TIME_BATTLE, FIRST_TO, ELIMINATION
--   ListBattles        the LIVE IN THE COLOSSEUM sections (filter)
--   Watch / WatchRandom spectate one battle (slot reserved atomically)
-- The lobby's walk-on pads (LobbyPadService), the arena portcullis (opens the PLAY menu), the
-- tribune doors (WATCH LIVE) and the Gate to Rome call the same functions. Clients never send
-- match ids for fighting, teams, roles, rewards, ids of places or servers, Aura or inventory:
-- those come from the server-side records.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local Server = script.Parent.Parent
local InventoryService = require(Server.InventoryService)
local LobbyService = require(Server.LobbyService)
local MatchRegistryService = require(Server.MatchRegistryService)
local PlayerDataService = require(Server.PlayerDataService)
local RateLimiter = require(Server.RateLimiter)
local Remotes = require(Server.Remotes)
local TeleportUtil = require(Server.TeleportUtil)
local ArenaReservationService = require(script.Parent.ArenaReservationService)
local FriendBattleService = require(script.Parent.FriendBattleService)
local HubTeleportService = require(script.Parent.HubTeleportService)
local LiveBattlesService = require(script.Parent.LiveBattlesService)
local LobbyPadService = require(script.Parent.LobbyPadService)
local MatchmakingService = require(script.Parent.MatchmakingService)
local PartyService = require(script.Parent.PartyService)
local SpectatorJoinService = require(script.Parent.SpectatorJoinService)

local PREFIX = "[OttiArena][Hub]"

type Response = { ok: boolean, message: string?, data: any? }

local HubMatchService = {}

local starting: { [Player]: boolean } = {}
local layout: LobbyService.LobbyLayout? = nil

local limiter = RateLimiter.new({
	ListBattles = 2,
	Watch = 2,
	WatchRandom = 2,
	PlaySolo = 2,
	StartBoss = 2,
	StartCoop = 2,
	Queue = 1.5,
	LeaveQueue = 1,
	PartyInvite = 1,
	ServerPlayers = 2,
}, 0.4)

local function respond(ok: boolean, message: string?, data: any?): Response
	return { ok = ok, message = message, data = data }
end

local function inLobby(player: Player): boolean
	return GameStates.isInLobby(player:GetAttribute(GameStates.StateAttribute)) and PlayerDataService.isReady(player)
end

-- Creates a zombie match for `players` and sends them. `party` (optional) is locked meanwhile.
local function startZombies(mode: MatchTypes.MatchMode, players: { Player }, party: PartyService.Party?, boss: string?): (boolean, string)
	local fighters: { MatchTypes.Fighter } = {}
	local valid = {}
	for _, player in players do
		local ok, reason = InventoryService.hasValidLoadout(player)
		if not player.Parent or not inLobby(player) or starting[player] or MatchmakingService.isQueued(player) then
			continue
		end
		if not ok then
			HubTeleportService.message(player, reason, false)
			continue
		end
		table.insert(valid, player)
		table.insert(fighters, { userId = player.UserId, team = "", partyId = if party then party.id else "" })
	end
	if #valid == 0 then
		return false, "Nobody can start right now (equipment, queue or loading)"
	end
	for _, player in valid do
		starting[player] = true
	end
	if party then
		PartyService.setLocked(party, true)
	end
	local created = ArenaReservationService.create(mode, fighters, nil, boss)
	if not created then
		for _, player in valid do
			starting[player] = nil
		end
		if party then
			PartyService.setLocked(party, false)
		end
		return false, MatchTypes.Messages.UNREACHABLE
	end
	HubTeleportService.send(valid, {
		matchId = created.record.matchId,
		role = "FIGHTER",
		mode = mode,
		mock = created.mock,
		onFailed = function(player: Player, _code: string)
			starting[player] = nil
			if party and party.locked then
				PartyService.setLocked(party, false)
			end
		end,
	})
	if not created.mock then
		task.delay(20, function()
			-- players who are still here after a successful start get their flags back
			for _, player in valid do
				starting[player] = nil
			end
			if party and party.locked and not MatchmakingService.isQueued(party.members[1]) then
				PartyService.setLocked(party, false)
			end
		end)
	else
		for _, player in valid do
			starting[player] = nil
		end
	end
	return true, if created.mock then "STUDIO MOCK: match created (no teleport)" else "Preparing the arena…"
end

function HubMatchService.playSolo(player: Player): (boolean, string)
	if not inLobby(player) then
		return false, "Finish what you are doing first"
	end
	if PartyService.get(player) then
		if not PartyService.leave(player, true) then
			return false, "Leave the queue first"
		end
	end
	return startZombies("SOLO_ZOMBIES", { player }, nil)
end

-- START WITH CURRENT PARTY (or alone): the ready members, or everybody if nobody marked ready.
function HubMatchService.startCoop(player: Player): (boolean, string)
	local party = PartyService.get(player)
	if party and party.members[1] ~= player then
		return false, "Only the party leader can start"
	end
	if MatchmakingService.isQueued(player) then
		local left = MatchmakingService.leave(player)
		if not left then
			return false, "A match was just found"
		end
	end
	if party and party.locked then
		PartyService.setLocked(party, false)
	end
	local members = if party then PartyService.readyMembers(party) else { player }
	if party and #members == 0 then
		members = table.clone(party.members)
	end
	return startZombies("COOP_ZOMBIES", members, party)
end

-- The companion or Otti boss fight (BOSS FIGHT menu): a solo run that goes straight to the boss.
-- `bossId` is one of BOSS_CHOICES; anything else is refused.
local BOSS_CHOICES = { "Otti", "Kroko", "Schili" }

function HubMatchService.startBoss(player: Player, bossId: unknown): (boolean, string)
	if typeof(bossId) ~= "string" or not table.find(BOSS_CHOICES, bossId) then
		return false, "Choose Otti, Kroko or Schili"
	end
	if not inLobby(player) then
		return false, "Finish what you are doing first"
	end
	if PartyService.get(player) then
		if not PartyService.leave(player, true) then
			return false, "Leave the queue first"
		end
	end
	return startZombies("BOSS_SOLO", { player }, nil, bossId)
end

local function serverPlayers(viewer: Player): { { userId: number, name: string, inParty: boolean } }
	local list = {}
	for _, other in Players:GetPlayers() do
		if other ~= viewer then
			table.insert(list, { userId = other.UserId, name = other.DisplayName, inParty = PartyService.get(other) ~= nil })
		end
	end
	return list
end

local handlers: { [string]: (player: Player, arg: unknown) -> Response } = {
	Party = function(player)
		return respond(true, nil, PartyService.snapshotFor(player))
	end,
	PartyCreate = function(player)
		local ok, text = PartyService.create(player)
		return respond(ok, text, PartyService.snapshotFor(player))
	end,
	PartyInvite = function(player, arg)
		local target = if typeof(arg) == "number" then Players:GetPlayerByUserId(arg) else nil
		if not target then
			return respond(false, "That player is not in this server")
		end
		local ok, text = PartyService.invite(player, target)
		return respond(ok, text, PartyService.snapshotFor(player))
	end,
	PartyAccept = function(player, arg)
		if typeof(arg) ~= "string" then
			return respond(false, "Invalid invite")
		end
		local ok, text = PartyService.accept(player, arg)
		return respond(ok, text, PartyService.snapshotFor(player))
	end,
	PartyLeave = function(player)
		local ok = PartyService.leave(player)
		return respond(ok, if ok then "You left the party" else "Leave the queue first", PartyService.snapshotFor(player))
	end,
	PartyReady = function(player)
		local ok, text = PartyService.setReady(player, nil)
		return respond(ok, text, PartyService.snapshotFor(player))
	end,
	ServerPlayers = function(player)
		return respond(true, nil, serverPlayers(player))
	end,
	PlaySolo = function(player)
		local ok, text = HubMatchService.playSolo(player)
		return respond(ok, text)
	end,
	StartBoss = function(player, arg)
		local ok, text = HubMatchService.startBoss(player, arg)
		return respond(ok, text)
	end,
	StartCoop = function(player)
		local ok, text = HubMatchService.startCoop(player)
		return respond(ok, text)
	end,
	Queue = function(player, arg)
		if not inLobby(player) then
			return respond(false, "Finish what you are doing first")
		end
		local ok, text = MatchmakingService.join(player, arg)
		return respond(ok, text)
	end,
	LeaveQueue = function(player)
		local ok, text = MatchmakingService.leave(player)
		return respond(ok, text)
	end,
	ListBattles = function(player, arg)
		return respond(true, nil, LiveBattlesService.list(player, arg))
	end,
	Watch = function(player, arg)
		local ok, text = SpectatorJoinService.watch(player, arg)
		return respond(ok, text)
	end,
	WatchRandom = function(player)
		local ok, text = SpectatorJoinService.watch(player, "RANDOM")
		return respond(ok, text)
	end,
}

local function onRequest(player: Player, action: unknown, arg: unknown): Response
	if typeof(action) ~= "string" then
		return respond(false, "Invalid request")
	end
	local handler = handlers[action]
	if not handler then
		return respond(false, "Invalid request")
	end
	if not limiter.allow(player, action) then
		return respond(false, "Slow down a little")
	end
	local ok, result = pcall(handler, player, arg)
	if not ok then
		warn(PREFIX, ("%s from %s failed: %s"):format(action, player.Name, tostring(result)))
		return respond(false, "Something went wrong — try again")
	end
	return result :: Response
end

------------------------------------------------------------------------------------------
-- Basement prompts and the live board
------------------------------------------------------------------------------------------

local function addPrompt(host: BasePart, actionText: string, objectText: string, callback: (Player) -> (boolean, string))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.DPadUp
	prompt.Parent = host
	prompt.Triggered:Connect(function(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or (root.Position-host.Position).Magnitude > 13 or not inLobby(player) then return end
		if not limiter.allow(player, "Prompt") then
			return
		end
		local ok, text = callback(player)
		if text ~= "" then
			HubTeleportService.message(player, text, ok)
		end
	end)
end

-- Search / stop: a second press leaves the queue again.
local function toggleQueue(player: Player, mode: string): (boolean, string)
	if MatchmakingService.isQueued(player) then
		return MatchmakingService.leave(player)
	end
	if not inLobby(player) then
		return false, "Finish what you are doing first"
	end
	return MatchmakingService.join(player, mode)
end

local function updateLiveBoard()
	local current = layout
	if not current then
		return
	end
	local records = MatchRegistryService.list(false)
	local count = #records
	current.liveBoard.Text = if count == 0 then "No live battles" elseif count == 1 then "1 live battle" else ("%d live battles"):format(count)
	current.folder:SetAttribute(Config.LiveBattleCountAttribute, count)
end

-- Direct joins see the games ahead. Respawns and Arena returns use a separate safe position.
-- Track the first character per join, rather than treating every CharacterAdded as a new arrival.
local function onArrival(player: Player)
	local current = layout
	if not current then
		return
	end
	local payload = TeleportUtil.joinPayload(player)
	local returning = payload ~= nil and payload.kind == "ToHub"
	local firstCharacter = true
	local initialSpawn = if returning then current.respawnSpawn else current.arrivalSpawn
	player.RespawnLocation = initialSpawn
	local function place(character: Model)
		local first = firstCharacter
		firstCharacter = false
		local target = if first then initialSpawn.CFrame else current.spawnCFrame
		if first and returning and payload and payload.fromSpectating == true then
			target = current.liveCFrame
		end
		local root = character:WaitForChild("HumanoidRootPart", 10)
		-- Let Roblox finish its own spawn placement before applying the exact arrival position.
		task.wait(0.2)
		if root and root:IsA("BasePart") and player.Character == character and character.Parent then
			player.RespawnLocation = current.respawnSpawn
			root.AssemblyLinearVelocity = Vector3.zero
			character:PivotTo(target + Vector3.new(0, 3.5, 0))
			if first and not returning then
				player:SetAttribute("HubArrivalCFrame", target + Vector3.new(0, 3.5, 0))
			end
		end
	end
	player.CharacterAdded:Connect(place)
	if player.Character then
		task.spawn(place, player.Character)
	end
	if returning and payload then
		local code = if typeof(payload.message) == "string" then payload.message else nil
		local text = if code then (MatchTypes.Messages :: any)[code] else nil
		if typeof(text) == "string" then
			task.delay(3, function()
				if player.Parent then
					HubTeleportService.message(player, text, false)
				end
			end)
		end
	end
end

function HubMatchService.init(lobby: LobbyService.LobbyLayout)
	layout = lobby
	FriendBattleService.init()
	PartyService.init(lobby.folder, nil)
	MatchmakingService.init()
	LiveBattlesService.init()
	Remotes.MatchRequest.OnServerInvoke = onRequest

	-- Walk-on pads (singleplayer + multiplayer wings)
	LobbyPadService.init(lobby.pads, {
		playSolo = HubMatchService.playSolo,
		startCoop = HubMatchService.startCoop,
		toggleQueue = toggleQueue,
		message = HubTeleportService.message,
	})
	-- Walking to the gate starts Solo Zombies via the entrance pad; no choice menu here.
	for _,host in lobby.soloHosts do
		addPrompt(host, "Start solo fight", "ZOMBIE SOLO", HubMatchService.playSolo)
	end
	for _,host in lobby.bossBoards do
		addPrompt(host, "Choose boss", "BOSS FIGHT · TEST", function(player)
			Remotes.MatchEvent:FireClient(player, "OpenMenu", "BOSS")
			return true, ""
		end)
	end
	for _, host in lobby.modeBoards do
		addPrompt(host, "Choose game / form party", "ALL GAME MODES", function(player)
			Remotes.MatchEvent:FireClient(player, "OpenMenu", host:GetAttribute("MenuTab") or "ZOMBIES")
			return true, ""
		end)
	end
	for _, door in lobby.tribuneDoors do
		addPrompt(door, "Watch live", "TRIBUNES", function(player)
			Remotes.MatchEvent:FireClient(player, "OpenLive")
			return true, ""
		end)
	end
	for _,entry in lobby.matchActions do
		addPrompt(entry.part, "Join / leave queue", entry.mode, function(player)
			return toggleQueue(player, entry.mode)
		end)
	end
	addPrompt(lobby.romeGate, "Open", "GATE TO ROME", function()
		return false, "The gate to Rome is still barred · the road opens soon"
	end)

	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute(Config.QueueStatusAttribute, "")
		player:SetAttribute(GameStates.StateAttribute, GameStates.Lobby)
		player:SetAttribute(GameStates.LocationAttribute, "Lobby")
		onArrival(player)
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute(Config.QueueStatusAttribute, "")
		player:SetAttribute(GameStates.StateAttribute, GameStates.Lobby)
		player:SetAttribute(GameStates.LocationAttribute, "Lobby")
		onArrival(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		starting[player] = nil
	end)

	task.spawn(function()
		while true do
			pcall(updateLiveBoard)
			task.wait(15)
		end
	end)
	print(PREFIX, ("Hub matchmaking ready (%s)%s"):format(EnvironmentConfig.describe(), if EnvironmentConfig.isMockMode() then " — LOCAL MOCK MODE: matches are simulated, not teleported" else ""))
end

return HubMatchService
