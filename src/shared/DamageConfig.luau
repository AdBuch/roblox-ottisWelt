--!strict
-- Tuning for the one authoritative player damage pipeline (PlayerCombatService.receiveHit):
--   1 validate attacker/target  2 base damage  3 mode multiplier (move PvPMultiplier, done by the
--   attack)  4 shield block / parry  5 armor  6 temporary effects (counter window)
--   7 PvP caps + minimum damage  8 Humanoid damage  9 feedback.
--   afterBlock = base * shieldMultiplier
--   afterArmor = afterBlock * (1 - effectiveArmorReduction)
--   final      = max(MinimumDamage, round(afterArmor))   (only when something got through)

local DamageConfig = {
	MinimumDamage = 1, -- a landed, non-blocked-to-zero hit always removes at least this much
	PvEArmorEffectiveness = 1, -- zombies, archers, Otti: the full listed armor reduction
	PvPArmorEffectiveness = 0.75, -- Team Battle: 75 % of the listed reduction (Champion 35 % -> ~26 %)
	MaxArmorReduction = 0.6, -- safety cap for any future armor / stacking
	ArmorAppliesToUnblockable = true, -- grapples and slams are still softened by armor
}

return table.freeze(DamageConfig)
