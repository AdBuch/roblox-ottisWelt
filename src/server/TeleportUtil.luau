--!strict
-- Server-side teleports (TeleportService:TeleportAsync, current API) with retries.
--   toReserved(players, accessCode, payload, onFailed)  Hub -> reserved Arena server
--   toHub(players, payload, onFailed)                    Arena -> a public Hub server
-- The access code only ever lives in TeleportOptions on the server. TeleportData (payload) is
-- visible to the client: it never contains secrets and the destination never trusts it.
-- Failures (TeleportAsync errors and TeleportInitFailed) are retried per player
-- ExperienceConfig.Teleport.Retries times; then `onFailed(player, messageCode)` runs so the caller
-- can release reservations, unlock parties and show a compact message.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)

local PREFIX = "[OttiArena][Teleport]"

export type FailureHandler = (player: Player, messageCode: string) -> ()

type Pending = {
	placeId: number,
	options: TeleportOptions,
	retriesLeft: number,
	delay: number,
	onFailed: FailureHandler?,
	token: number,
}

local TeleportUtil = {}

local pending: { [Player]: Pending } = {}
local tokenCounter = 0

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

local function retryable(result: Enum.TeleportResult?): boolean
	return result == nil or result == Enum.TeleportResult.Failure or result == Enum.TeleportResult.Flooded or result == Enum.TeleportResult.IsTeleporting
end

local send: (players: { Player }, placeId: number, options: TeleportOptions) -> boolean

local function fail(player: Player, entry: Pending, result: Enum.TeleportResult?)
	if pending[player] ~= entry then
		return
	end
	if entry.retriesLeft > 0 and retryable(result) and player.Parent then
		entry.retriesLeft -= 1
		task.delay(entry.delay, function()
			if pending[player] == entry and player.Parent then
				send({ player }, entry.placeId, entry.options)
			end
		end)
		return
	end
	pending[player] = nil
	if entry.onFailed and player.Parent then
		task.spawn(entry.onFailed, player, codeFor(result))
	end
end

send = function(players: { Player }, placeId: number, options: TeleportOptions): boolean
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, players, options)
	end)
	if not ok then
		warn(PREFIX, "TeleportAsync failed:", tostring(err))
		for _, player in players do
			local entry = pending[player]
			if entry then
				fail(player, entry, nil)
			end
		end
	end
	return ok
end

local function start(players: { Player }, placeId: number, options: TeleportOptions, retries: number, delay: number, onFailed: FailureHandler?): boolean
	local valid = {}
	for _, player in players do
		if player.Parent then
			tokenCounter += 1
			pending[player] = { placeId = placeId, options = options, retriesLeft = retries, delay = delay, onFailed = onFailed, token = tokenCounter }
			table.insert(valid, player)
		end
	end
	if #valid == 0 then
		return false
	end
	return send(valid, placeId, options)
end

-- Hub -> reserved Arena server. Returns false in mock mode (nothing is sent).
function TeleportUtil.toReserved(players: { Player }, accessCode: string, payload: MatchTypes.TeleportPayload, onFailed: FailureHandler?): boolean
	if not EnvironmentConfig.canTeleport() then
		return false
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData(payload)
	local config = ExperienceConfig.Teleport
	return start(players, EnvironmentConfig.get().ArenaPlaceId, options, config.Retries, config.RetryDelaySeconds, onFailed)
end

-- Arena -> any public Hub server.
function TeleportUtil.toHub(players: { Player }, payload: MatchTypes.TeleportPayload, onFailed: FailureHandler?): boolean
	if not EnvironmentConfig.canTeleport() then
		return false
	end
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(payload)
	local config = ExperienceConfig.Teleport
	return start(players, EnvironmentConfig.get().HubPlaceId, options, config.ReturnRetries, config.ReturnRetryDelaySeconds, onFailed)
end

function TeleportUtil.isPending(player: Player): boolean
	return pending[player] ~= nil
end

-- Reads the arriving player's TeleportData (untrusted: only ever used as a hint).
function TeleportUtil.joinPayload(player: Player): { [string]: any }?
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	local data = if ok and typeof(joinData) == "table" then (joinData :: any).TeleportData else nil
	return if typeof(data) == "table" then data else nil
end

function TeleportUtil.init()
	TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
		local entry = pending[player]
		warn(PREFIX, ("Teleport of %s failed: %s %s"):format(player.Name, tostring(result), message))
		if entry then
			fail(player, entry, result)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil -- left (usually: the teleport succeeded)
	end)
end

return TeleportUtil
