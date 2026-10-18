--!strict
-- Who may fight whom right now. MatchService installs the real rules at startup; combat modules
-- only ask these questions, so they never need to know about modes, parties or teams.
--   Context "Zombies"  : participant of a Solo/Co-op match -> may hit arena zombies
--   Context "PvP"      : participant of a Team Battle -> may hit players of the other team
--   Context "Training" : lobby player inside the training area -> may hit training dummies
--   nil                : may not deal damage (lobby, spectators, defeated players, ...)

export type CombatContext = "Zombies" | "PvP" | "Training"

export type Rules = {
	getContext: (player: Player) -> CombatContext?,
	isEnemy: (attacker: Player, victim: Player) -> boolean,
	canZombiesTarget: (player: Player) -> boolean,
	onPlayerDamaged: (victim: Player, attacker: Player?, amount: number) -> (),
	zombieTargets: () -> { Player },
}

local CombatRules = {}

local rules: Rules = {
	getContext = function()
		return nil
	end,
	isEnemy = function()
		return false
	end,
	canZombiesTarget = function()
		return false
	end,
	onPlayerDamaged = function() end,
	zombieTargets = function()
		return {}
	end,
}

function CombatRules.install(newRules: Rules)
	rules = newRules
end

function CombatRules.getContext(player: Player): CombatContext?
	return rules.getContext(player)
end

function CombatRules.isEnemy(attacker: Player, victim: Player): boolean
	return attacker ~= victim and rules.isEnemy(attacker, victim)
end

function CombatRules.canZombiesTarget(player: Player): boolean
	return rules.canZombiesTarget(player)
end

function CombatRules.onPlayerDamaged(victim: Player, attacker: Player?, amount: number)
	rules.onPlayerDamaged(victim, attacker, amount)
end

function CombatRules.zombieTargets(): { Player }
	return rules.zombieTargets()
end

return CombatRules
