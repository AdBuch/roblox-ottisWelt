--!strict
-- Shield defense by HIT DIRECTION (server: PlayerCombatService.receiveHit). Balancing proposals;
-- every value lives here. The direction is always computed on the server from the attacker's
-- position relative to the defender (never reported by a client). The shield is carried on the
-- LEFT arm, so the left side is the shield side; there is no all-round defense.
--
--   zone          passive (shield equipped, no block)   active block (BLOCK on)
--   Front         0 %                                     70 %  (perfect block / guard break here)
--   ShieldSide    15 %                                    40 %
--   WeaponSide    0 %                                     0 %
--   Back          0 %                                     0 %
-- Each shield scales these by its quality (Reduction / ReferenceReduction, clamped), so a Champion
-- Shield still blocks more than the Wooden Buckler. Arrows use the shield's projectile ratio.

local ShieldDefenseConfig = {
	Passive = table.freeze({ Front = 0, ShieldSide = 0.15, WeaponSide = 0, Back = 0 }) :: { [string]: number },
	Active = table.freeze({ Front = 0.70, ShieldSide = 0.40, WeaponSide = 0, Back = 0 }) :: { [string]: number },

	ReferenceReduction = 0.70, -- a shield with this Reduction gets exactly the values above
	QualityMin = 0.75,
	QualityMax = 1.25,
	MaxReduction = 0.9, -- never full immunity from a normal block (perfect blocks still stop all)

	-- Zones (dot products with the flat direction to the attacker)
	SideDot = 0.3, -- dot(shield side, toAttacker) above this = the shield side
	BackDot = -0.35, -- dot(look, toAttacker) below this = from behind
	-- The front zone is the shield's own block angle (ShieldDefinitions.FacingDot).

	BlockWalkFactor = 0.65, -- walk speed share with the guard up (shields shift it slightly)
}

return table.freeze(ShieldDefenseConfig)
