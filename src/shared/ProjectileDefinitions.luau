--!strict
-- Projectile tuning shared by the server (simulation, damage) and client (crosshair, display).
-- Player arrows: speed/range per move live in SpecialMoveDefinitions; damage falloff is here.
-- Enemy arrows: Undead Sagittarius shots (server-simulated, visible, slower so you can react).

export type FalloffStep = { From: number, Multiplier: number }

local ProjectileDefinitions = {
	PlayerArrow = table.freeze({
		MaxRange = 150,
		Speed = 145,
		-- 0-100: 100 %, 100-125: 90 %, 125-150: 75 %
		Falloff = table.freeze({
			{ From = 0, Multiplier = 1 },
			{ From = 100, Multiplier = 0.9 },
			{ From = 125, Multiplier = 0.75 },
		}) :: { FalloffStep },
		PierceDamageSteps = table.freeze({ 1, 0.75, 0.55 }), -- Piercing Arrow: 1st, 2nd, 3rd target
	}),

	EnemyArrow = table.freeze({
		Speed = 95, -- visibly slower than player arrows
		MaxRange = 165,
		Lifetime = 2.2,
		Gravity = 0, -- straight line: what you see is what hits
	}),

	ArrowPoolLimit = 60, -- at most this many arrows in flight; the oldest is removed first
}

-- Damage multiplier for a player arrow after travelling `distance` studs.
function ProjectileDefinitions.falloff(distance: number): number
	local multiplier = 1
	for _, step in ProjectileDefinitions.PlayerArrow.Falloff do
		if distance >= step.From then
			multiplier = step.Multiplier
		end
	end
	return multiplier
end

return table.freeze(ProjectileDefinitions)
