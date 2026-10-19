--!strict
-- Validates gesture payloads from the Wild pad / Special Mode. The client sends normalized samples
-- (pad radii, relative to the touch-down point) and the duration; the server re-classifies them
-- with the same GestureDefinitions.classify, so the result is never what the client claims but what
-- its samples show. Malformed payloads, too many samples, impossible speed and floods are rejected.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GestureDefinitions = require(ReplicatedStorage.Shared.GestureDefinitions)

export type Validated = {
	kind: GestureDefinitions.Kind,
	tier: number,
	length: number,
	special: boolean,
}

local MIN_INTERVAL = 0.18 -- at most ~5 gestures per second

local GestureValidationService = {}

local last: { [Player]: number } = {}

function GestureValidationService.validate(player: Player, payload: unknown): (Validated?, string?)
	if typeof(payload) ~= "table" then
		return nil, "bad payload"
	end
	local now = os.clock()
	if now - (last[player] or 0) < MIN_INTERVAL then
		return nil, "too fast"
	end
	last[player] = now
	local data = payload :: { [any]: any }
	local seconds = data.seconds
	local samples = data.points
	if typeof(seconds) ~= "number" or seconds ~= seconds or seconds < 0 or seconds > GestureDefinitions.MaxSeconds + 0.5 then
		return nil, "bad duration"
	end
	if typeof(samples) ~= "table" or #samples > GestureDefinitions.MaxSamples then
		return nil, "bad samples"
	end
	local points: { Vector2 } = {}
	for _, sample in samples :: { any } do
		if typeof(sample) == "Vector2" then
			table.insert(points, sample)
		else
			return nil, "bad sample"
		end
	end
	local result = GestureDefinitions.classify(points, seconds)
	if result.kind == "None" then
		return nil, "unrecognized"
	end
	return { kind = result.kind, tier = result.tier, length = result.length, special = data.special == true }, nil
end

function GestureValidationService.forget(player: Player)
	last[player] = nil
end

return GestureValidationService
