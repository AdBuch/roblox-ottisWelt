--!strict
-- Team Battle balance for aerial attacks and combination moves (on top of each move's own
-- PvPMultiplier and PvPMaxTargets). Nothing may eliminate a full-health player in one move.

local PvPBalanceConfig = {
	MaxHitFraction = 0.45, -- one hit: at most this share of max health (CombatConfig.PvPMaxDamageFraction)
	MaxMoveFraction = 0.5, -- one whole combo / aerial move against one player: at most this share
	MaxKnockdownSeconds = 0.8,
	PostKnockdownProtection = 1.0,
	StaggerLockWindow = 2.5, -- a player can't be staggered again by combos within this window
	GuardBreakShieldLock = 1.2, -- a broken guard can't be raised again for this long
	CounterReduction = 0.6, -- damage reduction inside a combo's counter window
}

return table.freeze(PvPBalanceConfig)
