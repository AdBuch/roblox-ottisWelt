--!strict
-- Gesture shapes for the Wild pad and Special Mode, measured RELATIVE TO THE PAD RADIUS (never in
-- pixels): a point (1, 0) is one pad radius to the right of where the finger went down, y is up.
-- classify() runs on the client (preview) AND on the server (authoritative, from the same
-- normalized samples), so a client can never claim a gesture its samples don't show.
--   Left / Right / Up / Down   net movement >= MinLength, dominant direction (±50° tolerance)
--   Circle                     total turning >= CircleTurnDegrees and path >= CirclePathLength
--   CircleDown                 a circle that ends in a clear downward stroke (Ultimate)
--   Tap                        tiny and short (a block tap on the pad centre)
-- Tier (specials) from the path length: < Tier2Length -> I, < Tier3Length -> II, else III.

export type Kind = "Left" | "Right" | "Up" | "Down" | "Circle" | "CircleDown" | "Tap" | "None"

export type Result = { kind: Kind, length: number, tier: number }

local GestureDefinitions = {
	MinLength = 0.32, -- net displacement (pad radii) that counts as a swipe; smaller = accidental
	TapMaxLength = 0.2,
	TapMaxSeconds = 0.25,
	DirectionToleranceDegrees = 50,
	CircleTurnDegrees = 290, -- a slightly imperfect child's circle still counts
	CirclePathLength = 2.0,
	CircleDownLength = 0.6, -- the final downward stroke of the Ultimate gesture
	Tier2Length = 0.95,
	Tier3Length = 1.6,
	MaxSamples = 40,
	MaxCoordinate = 3.5, -- samples farther than this from the start are invalid
	MinSeconds = 0.04, -- faster than this is impossible input
	MaxSeconds = 1.6,
	SampleSpacing = 0.06, -- client: minimum distance between recorded samples (pad radii)
	SpecialModeSeconds = 3.5, -- Special Mode expires if no gesture is drawn
	DesktopPadShare = 0.12, -- desktop mouse gestures: virtual pad radius = share of the viewport height
}

local function pathLength(points: { Vector2 }): number
	local length = 0
	for i = 2, #points do
		length += (points[i] - points[i - 1]).Magnitude
	end
	return length
end

-- Total signed turning of the path in degrees (segments shorter than 0.05 radii are ignored).
local function turning(points: { Vector2 }): number
	local total = 0
	local lastDir: Vector2? = nil
	local anchor = points[1]
	for i = 2, #points do
		local delta = points[i] - anchor
		if delta.Magnitude >= 0.05 then
			local dir = delta.Unit
			if lastDir then
				local cross = lastDir.X * dir.Y - lastDir.Y * dir.X
				local dot = lastDir.X * dir.X + lastDir.Y * dir.Y
				total += math.deg(math.atan2(cross, dot))
			end
			lastDir = dir
			anchor = points[i]
		end
	end
	return total
end

local function direction(delta: Vector2): Kind
	local angle = math.deg(math.atan2(delta.Y, delta.X)) -- 0 = right, 90 = up
	local tolerance = GestureDefinitions.DirectionToleranceDegrees
	local function near(target: number): boolean
		return math.abs(((angle - target + 180) % 360) - 180) <= tolerance
	end
	if near(0) then
		return "Right"
	elseif near(180) then
		return "Left"
	elseif near(90) then
		return "Up"
	elseif near(-90) then
		return "Down"
	end
	return "None"
end

function GestureDefinitions.tierFor(length: number): number
	if length < GestureDefinitions.Tier2Length then
		return 1
	elseif length < GestureDefinitions.Tier3Length then
		return 2
	end
	return 3
end

-- Validates and classifies normalized samples. `seconds` = gesture duration.
function GestureDefinitions.classify(points: { Vector2 }, seconds: number): Result
	local none: Result = { kind = "None", length = 0, tier = 1 }
	if #points < 2 or #points > GestureDefinitions.MaxSamples then
		return if #points == 1 and seconds <= GestureDefinitions.TapMaxSeconds then { kind = "Tap", length = 0, tier = 1 } else none
	end
	for _, p in points do
		if p.X ~= p.X or p.Y ~= p.Y or math.abs(p.X) > GestureDefinitions.MaxCoordinate or math.abs(p.Y) > GestureDefinitions.MaxCoordinate then
			return none
		end
	end
	local length = pathLength(points)
	if seconds < GestureDefinitions.MinSeconds and length > 0.5 then
		return none -- impossible input speed
	end
	local net = points[#points] - points[1]
	if length <= GestureDefinitions.TapMaxLength and seconds <= GestureDefinitions.TapMaxSeconds then
		return { kind = "Tap", length = length, tier = 1 }
	end
	local turn = math.abs(turning(points))
	if turn >= GestureDefinitions.CircleTurnDegrees and length >= GestureDefinitions.CirclePathLength then
		-- A circle that ends with a clear downward stroke = the Ultimate gesture
		local tail = points[#points]
		local back = math.max(1, #points - 8)
		local strokeStart = points[back]
		local stroke = tail - strokeStart
		if stroke.Y <= -GestureDefinitions.CircleDownLength and math.abs(stroke.X) < math.abs(stroke.Y) * 0.8 then
			return { kind = "CircleDown", length = length, tier = 4 }
		end
		return { kind = "Circle", length = length, tier = 2 }
	end
	if net.Magnitude < GestureDefinitions.MinLength then
		return none
	end
	return { kind = direction(net), length = length, tier = GestureDefinitions.tierFor(length) }
end

return table.freeze(GestureDefinitions)
