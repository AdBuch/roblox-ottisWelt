--!strict
-- Saved attempts are keyed by weapon AND move: shared moves train independently per weapon.
local Practice = {
	StartFailure = 0.5,
	Improvement = 0.01,
	MaxAttempts = 50,
	FallSeconds = 1.1,
	UpLevel = 5,
	CircleLevel = 9,
}

function Practice.key(weaponId: string, moveId: string): string
	return weaponId .. ":" .. moveId
end

-- Player attribute holding a key's attempts (attribute names allow only letters, digits and _).
function Practice.attribute(key: string): string
	return "SpecialAttempts_" .. (key:gsub(":", "_"))
end

function Practice.failure(attempts: number): number
	return math.max(0, Practice.StartFailure - math.clamp(attempts, 0, Practice.MaxAttempts) * Practice.Improvement)
end

function Practice.label(player: Player, weaponId: string, moveId: string): string
	local attempts = tonumber(player:GetAttribute(Practice.attribute(Practice.key(weaponId, moveId)))) or 0
	return ("fail %.0f%%"):format(Practice.failure(attempts) * 100)
end

-- Ultimate takes priority. Locked context variants fall back to the ordinary charge tier.
function Practice.family(base: string, ultimate: boolean, airborne: boolean, blocking: boolean, level: number): string
	if ultimate then return "Ultimate" end
	if airborne and level >= Practice.UpLevel then return "Up" end
	if blocking and level >= Practice.CircleLevel then return "Circle" end
	return base
end

return table.freeze(Practice)
