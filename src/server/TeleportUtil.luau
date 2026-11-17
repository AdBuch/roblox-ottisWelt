--!strict
-- Transfer ownership, profile preparation and Roblox retries live in one source-side flow.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local PlayerDataService = require(script.Parent.PlayerDataService)
local Remotes = require(script.Parent.Remotes)

export type FailureHandler = (player: Player, messageCode: string) -> ()

type Failure = { result: Enum.TeleportResult?, options: TeleportOptions? }
type Attempt = { id: string, placeId: number }
type Transfer = {
	placeId: number,
	payload: MatchTypes.TeleportPayload,
	deadline: number,
	retriesLeft: number,
	delay: number,
	onFailed: FailureHandler,
	preparing: boolean,
	attempt: Attempt?,
	failure: Failure?,
}

local TeleportUtil = {}
local pending: { [Player]: Transfer } = {}
local inFlight: { [Player]: Attempt } = {}
-- Roblox offers no cancellation. Keep ambiguous departures from starting a competing flight.
local uncertain: { [Player]: Attempt } = {}

local function codeFor(result: Enum.TeleportResult?): string
	if result == Enum.TeleportResult.GameFull then
		return "FULL"
	elseif result == Enum.TeleportResult.GameEnded or result == Enum.TeleportResult.GameNotFound then
		return "ENDED"
	elseif result == Enum.TeleportResult.Unauthorized then
		return "UNREACHABLE"
	end
	return "TELEPORT_FAILED"
end

local function finish(player: Player, entry: Transfer, code: string)
	if pending[player] ~= entry then
		return
	end
	pending[player] = nil
	if not player.Parent then
		return
	end
	if entry.preparing then
		PlayerDataService.cancelTransfer(player)
	end
	player:SetAttribute(Config.TeleportStateAttribute, "Failed")
	Remotes.MatchEvent:FireClient(player, "Teleport", "Failed", code)
	task.spawn(entry.onFailed, player, code)
end

local send: (players: { Player }, entries: { [Player]: Transfer }, routing: TeleportOptions) -> ()

local function handleFailure(player: Player, entry: Transfer, routing: TeleportOptions)
	local failure = entry.failure
	if pending[player] ~= entry or inFlight[player] or not failure then
		return
	end
	entry.failure = nil
	local result = failure.result
	if result == Enum.TeleportResult.IsTeleporting then
		return -- Roblox still has a departure in progress; wait for its outcome or the watchdog.
	end
	entry.attempt = nil
	local retryable = result == nil or result == Enum.TeleportResult.Failure or result == Enum.TeleportResult.Flooded
	if not retryable or entry.retriesLeft <= 0 then
		finish(player, entry, codeFor(result))
		return
	end
	entry.retriesLeft -= 1
	task.delay(entry.delay, function()
		send({ player }, { [player] = entry }, failure.options or routing)
	end)
end

send = function(players: { Player }, entries: { [Player]: Transfer }, routing: TeleportOptions)
	local valid: { Player } = {}
	local attempt: Attempt? = nil
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = routing.ReservedServerAccessCode
	options.ServerInstanceId = routing.ServerInstanceId
	for _, player in players do
		local entry = entries[player]
		if pending[player] ~= entry or not player.Parent or inFlight[player] or uncertain[player] then
			continue
		end
		if os.clock() >= entry.deadline then
			finish(player, entry, "TELEPORT_TIMEOUT")
		elseif not PlayerDataService.isTransferPrepared(player) then
			finish(player, entry, "DATA_SAVE_FAILED")
		else
			if not attempt then
				attempt = { id = HttpService:GenerateGUID(false), placeId = entry.placeId }
				local hint = entry.payload
				-- Whitelist wire fields. The attempt ID correlates Roblox callbacks on the source.
				options:SetTeleportData({
					attemptId = attempt.id,
					kind = hint.kind,
					matchId = hint.matchId,
					message = hint.message,
					fromSpectating = hint.fromSpectating,
				})
			end
			entry.attempt = attempt
			inFlight[player] = attempt
			table.insert(valid, player)
			if player:GetAttribute(Config.TeleportStateAttribute) ~= "Travelling" then
				player:SetAttribute(Config.TeleportStateAttribute, "Travelling")
				Remotes.MatchEvent:FireClient(player, "Teleport", if entry.payload.kind == "ToHub" then "Returning" else "Travelling", entry.payload.mode)
			end
		end
	end
	if not attempt then
		return
	end
	local ok = pcall(function()
		TeleportService:TeleportAsync(attempt.placeId, valid, options)
	end)
	for _, player in valid do
		if inFlight[player] == attempt then
			inFlight[player] = nil
		end
		if not ok and uncertain[player] == attempt then
			uncertain[player] = nil
		end
		local entry = entries[player]
		if pending[player] == entry and entry.attempt == attempt then
			if not ok and not entry.failure then
				entry.failure = {}
			end
			handleFailure(player, entry, routing)
		end
	end
end

local function start(
	players: { Player },
	placeId: number,
	payload: MatchTypes.TeleportPayload,
	resolveAccessCode: (() -> (string?, string?))?,
	retries: number,
	delay: number,
	onFailed: FailureHandler
): { Player }
	local entries: { [Player]: Transfer } = {}
	local accepted: { Player } = {}
	local deadline = os.clock() + ExperienceConfig.Teleport.TravelTimeoutSeconds
	for _, player in players do
		if not player.Parent or TeleportUtil.isPending(player) then
			continue
		end
		local entry: Transfer = {
			placeId = placeId,
			payload = payload,
			deadline = deadline,
			retriesLeft = retries,
			delay = delay,
			onFailed = onFailed,
			preparing = false,
		}
		pending[player] = entry
		entries[player] = entry
		table.insert(accepted, player)
		player:SetAttribute(Config.TeleportStateAttribute, "Preparing")
		Remotes.MatchEvent:FireClient(player, "Teleport", "Preparing")
		task.delay(ExperienceConfig.Teleport.TravelTimeoutSeconds, function()
			if pending[player] == entry then
				if entry.attempt and (not entry.failure or entry.failure.result == Enum.TeleportResult.IsTeleporting) then
					uncertain[player] = entry.attempt
				end
				finish(player, entry, "TELEPORT_TIMEOUT")
			end
		end)
	end
	if #accepted == 0 then
		return accepted
	end
	task.spawn(function()
		local routing = Instance.new("TeleportOptions")
		if not EnvironmentConfig.canTeleport() then
			for _, player in accepted do finish(player, entries[player], "UNREACHABLE") end
			return
		end
		if resolveAccessCode then
			local ok, accessCode, problem = pcall(resolveAccessCode)
			if not ok or not accessCode then
				local code = if ok and problem == "UPDATE" then "UPDATE" else "UNREACHABLE"
				for _, player in accepted do finish(player, entries[player], code) end
				return
			end
			routing.ReservedServerAccessCode = accessCode
		end
		local ready: { Player } = {}
		local remaining = #accepted
		for _, player in accepted do
			task.spawn(function()
				local entry = entries[player]
				while pending[player] == entry and player.Parent and os.clock() < deadline
					and PlayerDataService.getStatus(player) == "Loading" do
					task.wait(0.1)
				end
				if pending[player] == entry and player.Parent and os.clock() < deadline then
					entry.preparing = true
					local ok, prepared = pcall(PlayerDataService.beginTransfer, player)
					if ok and prepared then
						table.insert(ready, player)
					else
						finish(player, entry, "DATA_SAVE_FAILED")
					end
				end
				remaining -= 1
			end)
		end
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
		send(ready, entries, routing)
	end)
	return accepted
end

function TeleportUtil.toReserved(players: { Player }, resolveAccessCode: () -> (string?, string?), payload: MatchTypes.TeleportPayload, onFailed: FailureHandler): { Player }
	local config = ExperienceConfig.Teleport
	return start(players, EnvironmentConfig.get().ArenaPlaceId, payload, resolveAccessCode, config.Retries, config.RetryDelaySeconds, onFailed)
end

function TeleportUtil.toHub(players: { Player }, payload: MatchTypes.TeleportPayload, onFailed: FailureHandler): { Player }
	local config = ExperienceConfig.Teleport
	return start(players, EnvironmentConfig.get().HubPlaceId, payload, nil, config.ReturnRetries, config.ReturnRetryDelaySeconds, onFailed)
end

function TeleportUtil.isPending(player: Player): boolean
	return pending[player] ~= nil or inFlight[player] ~= nil or uncertain[player] ~= nil
end

function TeleportUtil.isForMatch(player: Player, matchId: string): boolean
	local entry = pending[player]
	return entry ~= nil and entry.payload.matchId == matchId
end

-- Data selects presentation or a record lookup. Arena admission verifies the server-side ticket.
function TeleportUtil.joinPayload(player: Player): MatchTypes.TeleportPayload?
	local ok, joinData = pcall(function() return player:GetJoinData() end)
	local data: any = if ok and typeof(joinData) == "table" then (joinData :: any).TeleportData else nil
	if typeof(data) ~= "table" then
		return nil
	end
	if data.kind == "ToArena" and typeof(data.matchId) == "string" and #data.matchId > 0 and #data.matchId <= 64 then
		return { kind = "ToArena", matchId = data.matchId }
	elseif data.kind == "ToHub" then
		return {
			kind = "ToHub",
			message = if typeof(data.message) == "string" and (MatchTypes.Messages :: any)[data.message] then data.message else nil,
			fromSpectating = data.fromSpectating == true,
		}
	end
	return nil
end

function TeleportUtil.markArrived(player: Player)
	player:SetAttribute(Config.TeleportStateAttribute, "Arrived")
end

function TeleportUtil.init()
	TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, _, placeId: number, retryOptions: TeleportOptions)
		local ok, data = pcall(function() return retryOptions:GetTeleportData() end)
		local id = if ok and typeof(data) == "table" then data.attemptId else nil
		local old = uncertain[player]
		if old and old.id == id and old.placeId == placeId then
			if result ~= Enum.TeleportResult.IsTeleporting then
				uncertain[player] = nil
			end
			return
		end
		local entry = pending[player]
		local attempt = if entry then entry.attempt else nil
		if not entry or not attempt or attempt.id ~= id or attempt.placeId ~= placeId or entry.failure then
			return
		end
		entry.failure = { result = result, options = retryOptions }
		handleFailure(player, entry, retryOptions)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local entry = pending[player]
		pending[player] = nil
		inFlight[player] = nil
		uncertain[player] = nil
		if entry and not entry.attempt then
			task.spawn(entry.onFailed, player, "LEFT")
		end
	end)
end

return TeleportUtil
