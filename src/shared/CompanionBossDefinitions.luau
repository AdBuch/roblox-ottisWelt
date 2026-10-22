--!strict
-- The two legacy companions of Otti, as boss personalities (data only; the fighter AI lives in
-- CompanionBossAI on the server). Kroko acts first, Schili thinks first, Otti brings them together.
--
-- Personality traits are 0..1 and drive the decisions, not the look:
--   Boldness   how eagerly the boss closes in and starts attacks
--   Patience   how long it waits for a good moment before committing
--   Caution    how much it guards and retreats when hurt
--   Stubborn   how much it keeps pushing a plan / target after taking damage
--   Cunning    how often it feints or waits for an opening after a block
--
-- Moves are ROLES (Strike, Charge, Sweep, Guard, Feint, Roar, Retreat). The integration maps each role
-- onto a real move (BossAttackService), so the personalities don't depend on any move existing yet.

export type Role = "Strike" | "Charge" | "Sweep" | "Guard" | "Feint" | "Roar" | "Retreat"

export type RoleDefinition = {
	Weight: number, -- base weight before personality and situation
	MinRange: number, -- studs to the target
	MaxRange: number,
	Cooldown: number, -- seconds before the same role may be used again
	Telegraph: number, -- readable wind-up for the players, seconds
	Recovery: number, -- seconds the boss stays committed afterwards
	Damage: number, -- relative damage (1 = the boss's basic hit)
}

export type Personality = {
	Id: string,
	DisplayName: string,
	Title: string,
	Boldness: number,
	Patience: number,
	Caution: number,
	Stubborn: number,
	Cunning: number,
	Roles: { [Role]: RoleDefinition },
	RepeatPenalty: number, -- weight multiplier for repeating the last role (lower = avoids repeats)
	RecklessBelow: number, -- boss health share below which the personality turns reckless (Kroko) or cautious (Schili)
	PacingSeconds: { number }, -- {min, max} pause between sequences at full health
}

local function role(def: RoleDefinition): RoleDefinition
	return table.freeze(def) :: any
end

local function personality(def: Personality): Personality
	return table.freeze(def) :: any
end

local CompanionBossDefinitions = {
	Kroko = personality({
		Id = "Kroko",
		DisplayName = "KROKERO · KROKO",
		Title = "The Fearless Protector",
		-- bold, impulsive, competitive; stubborn overconfidence is the weakness
		Boldness = 0.9,
		Patience = 0.25,
		Caution = 0.15,
		Stubborn = 0.85,
		Cunning = 0.3,
		RepeatPenalty = 1.1, -- repeats his favourite moves happily
		RecklessBelow = 0.35, -- below a third of his health he stops holding back
		PacingSeconds = { 1.0, 2.0 },
		Roles = {
			Strike = role({ Weight = 1.4, MinRange = 0, MaxRange = 6.5, Cooldown = 1.6, Telegraph = 0.45, Recovery = 0.7, Damage = 1.0 }),
			Charge = role({ Weight = 1.2, MinRange = 6, MaxRange = 18, Cooldown = 4.0, Telegraph = 0.9, Recovery = 1.0, Damage = 1.2 }),
			Sweep = role({ Weight = 0.8, MinRange = 0, MaxRange = 5, Cooldown = 3.0, Telegraph = 0.6, Recovery = 0.8, Damage = 1.1 }),
			Guard = role({ Weight = 0.2, MinRange = 0, MaxRange = 12, Cooldown = 6.0, Telegraph = 0.3, Recovery = 0.6, Damage = 0 }),
			Feint = role({ Weight = 0.3, MinRange = 2, MaxRange = 7, Cooldown = 5.0, Telegraph = 0.2, Recovery = 0.4, Damage = 0 }),
			Roar = role({ Weight = 0.6, MinRange = 0, MaxRange = 30, Cooldown = 9.0, Telegraph = 0.8, Recovery = 0.9, Damage = 0 }),
			Retreat = role({ Weight = 0.05, MinRange = 0, MaxRange = 8, Cooldown = 12.0, Telegraph = 0.2, Recovery = 0.5, Damage = 0 }),
		},
	}),

	Schili = personality({
		Id = "Schili",
		DisplayName = "SCHILIBITZLI · SCHILI",
		Title = "The Calm Strategist",
		-- observant, patient, cautious but never cowardly, persistent once decided
		Boldness = 0.35,
		Patience = 0.85,
		Caution = 0.7,
		Stubborn = 0.75,
		Cunning = 0.9,
		RepeatPenalty = 0.4, -- avoids repeating a move, keeps changing its approach
		RecklessBelow = 0.35, -- below a third of its health it turns cautious and retreats more
		PacingSeconds = { 2.0, 3.5 },
		Roles = {
			Strike = role({ Weight = 0.9, MinRange = 0, MaxRange = 6.5, Cooldown = 2.0, Telegraph = 0.5, Recovery = 0.6, Damage = 0.9 }),
			Charge = role({ Weight = 0.2, MinRange = 7, MaxRange = 14, Cooldown = 6.0, Telegraph = 0.9, Recovery = 1.0, Damage = 0.9 }),
			Sweep = role({ Weight = 0.7, MinRange = 0, MaxRange = 5, Cooldown = 3.5, Telegraph = 0.7, Recovery = 0.7, Damage = 0.9 }),
			Guard = role({ Weight = 1.3, MinRange = 0, MaxRange = 12, Cooldown = 3.0, Telegraph = 0.2, Recovery = 0.5, Damage = 0 }),
			Feint = role({ Weight = 1.1, MinRange = 2, MaxRange = 8, Cooldown = 3.5, Telegraph = 0.25, Recovery = 0.4, Damage = 0 }),
			Roar = role({ Weight = 0.1, MinRange = 0, MaxRange = 30, Cooldown = 14.0, Telegraph = 0.8, Recovery = 0.8, Damage = 0 }),
			Retreat = role({ Weight = 0.6, MinRange = 0, MaxRange = 8, Cooldown = 5.0, Telegraph = 0.2, Recovery = 0.5, Damage = 0 }),
		},
	}),
}

-- Lookup by personality id ("Kroko" / "Schili"), nil for anything unknown.
function CompanionBossDefinitions.get(id: string): Personality?
	local value = (CompanionBossDefinitions :: any)[id]
	return if typeof(value) == "table" and value.Roles then value :: Personality else nil
end

return table.freeze(CompanionBossDefinitions)
