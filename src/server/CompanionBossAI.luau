--!strict
-- Fighter AI for the companion bosses (Kroko, Schili). A pure decision module: it reads a snapshot of
-- the fight and returns the next ROLE (see CompanionBossDefinitions); it never moves anything, deals
-- damage or changes state itself. The integration (later step) runs the chosen role through
-- BossAttackService, so every validation, hit and cooldown stays on the server.
--
-- Decision per call:
--   1. candidates: roles in range (distance) and off cooldown
--   2. weight = base weight x personality x situation x repetition
--        Kroko   bold: strikes and charges, favours the same moves, reckless when hurt
--        Schili  patient and cunning: waits, guards when the target attacks, feints after a block,
--                retreats more when hurt
--   3. weighted random choice with the caller's Random (deterministic in tests)
-- Otti is NOT handled here; he keeps OttiBossAI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CompanionBossDefinitions = require(ReplicatedStorage.Shared.CompanionBossDefinitions)

type Role = CompanionBossDefinitions.Role
type Personality = CompanionBossDefinitions.Personality

export type Snapshot = {
	now: number,
	distance: number, -- studs to the current target
	bossHealth: number, -- 0..1
	lastRole: Role?, -- the role used last
	readyAt: { [Role]: number }, -- when each role is off cooldown (os.clock time)
	targetAttacking: boolean, -- the target is winding up an attack (Schili waits for it)
	recentlyBlocked: boolean, -- the boss's last attack was blocked
	surrounded: boolean, -- several fighters are close to the boss
}

export type Choice = {
	role: Role?, -- nil: wait this turn
	reason: string, -- short label for logs and tests
}

local CompanionBossAI = {}

local STRIKING: { [Role]: boolean } = { Strike = true, Charge = true, Sweep = true }
local DEFENSIVE: { [Role]: boolean } = { Guard = true, Retreat = true }

local function isReckless(p: Personality, health: number): boolean
	return health < p.RecklessBelow
end

-- Weight of one role in this situation (0 = not a candidate).
local function weigh(p: Personality, s: Snapshot, role: Role, def: CompanionBossDefinitions.RoleDefinition): (number, string)
	local weight = def.Weight
	local reason = "base"
	-- personality
	if STRIKING[role] then
		weight *= 0.5 + p.Boldness
	elseif DEFENSIVE[role] then
		weight *= 0.5 + p.Caution
	elseif role == "Feint" then
		weight *= 0.5 + p.Cunning
	else -- Roar
		weight *= 0.5 + p.Boldness * 0.5
	end
	-- patience: committing attacks wait for a moment when the target isn't attacking
	if STRIKING[role] and not s.targetAttacking then
		weight *= 1 - 0.4 * p.Patience
	end
	-- situation
	if s.targetAttacking and role == "Guard" then
		weight *= 1 + p.Cunning
		reason = "guard-the-attack"
	end
	if s.recentlyBlocked and role == "Feint" then
		weight *= 1 + 1.5 * p.Cunning
		reason = "feint-after-block"
	end
	if s.recentlyBlocked and role == "Strike" then
		weight *= 1 + 0.5 * p.Stubborn
		reason = "press-after-block"
	end
	if s.surrounded and role == "Sweep" then
		weight *= 1.5
		reason = "sweep-surrounded"
	end
	-- reckless (Kroko) or cautious (Schili) below the health threshold
	if isReckless(p, s.bossHealth) then
		if p.Boldness > p.Caution then
			if STRIKING[role] then
				weight *= 1.5
				reason = "reckless"
			elseif role == "Guard" then
				weight *= 0.5
			end
		else
			if role == "Retreat" then
				weight *= 2
				reason = "cautious-retreat"
			elseif role == "Guard" then
				weight *= 1.5
			end
		end
	end
	-- repetition: each personality repeats (or avoids repeating) its last move
	if role == s.lastRole then
		weight *= p.RepeatPenalty
	end
	return weight, reason
end

-- The next role for this snapshot, or nil to wait this turn.
function CompanionBossAI.choose(p: Personality, s: Snapshot, rng: Random): Choice
	local total = 0
	local candidates: { { role: Role, weight: number, reason: string } } = {}
	-- (the roles are read as names and cast to Role: Luau widens map keys to string otherwise)
	for name, def in p.Roles do
		local role: Role = name :: any -- the keys of Roles are exactly the Role names
		if s.distance < def.MinRange or s.distance > def.MaxRange then
			continue
		end
		if s.now < (s.readyAt[role] or 0) then
			continue
		end
		local weight, reason = weigh(p, s, role, def)
		if weight > 0 then
			total += weight
			table.insert(candidates, { role = role, weight = weight, reason = reason })
		end
	end
	if #candidates == 0 or total <= 0 then
		return { role = nil, reason = "wait" }
	end
	-- stable order, so the same random number always picks the same role
	table.sort(candidates, function(a, b)
		return a.role < b.role
	end)
	local pick = rng:NextNumber() * total
	for _, candidate in candidates do
		pick -= candidate.weight
		if pick <= 0 then
			return { role = candidate.role, reason = candidate.reason }
		end
	end
	local last = candidates[#candidates]
	return { role = last.role, reason = last.reason }
end

-- Seconds to pause before the next sequence (shorter when reckless).
function CompanionBossAI.pause(p: Personality, bossHealth: number, rng: Random): number
	local range = p.PacingSeconds
	local seconds = range[1] + (range[2] - range[1]) * rng:NextNumber()
	if isReckless(p, bossHealth) and p.Boldness > p.Caution then
		seconds *= 0.6
	end
	return seconds
end

-- When the role is ready again after it was used at `now`.
function CompanionBossAI.cooldownEnds(p: Personality, role: Role, now: number): number
	local def = p.Roles[role]
	return if def then now + def.Cooldown else now
end

return CompanionBossAI
