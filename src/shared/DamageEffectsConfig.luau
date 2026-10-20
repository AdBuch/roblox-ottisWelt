--!strict
-- Hit feedback for players and zombies (always child-friendly: NO blood anywhere), plus zombie
-- condition states and limb loss. Purely visual switches never change combat logic.
--   Validated hits show short orange sparks and sand dust; Otti, players and zombies alike.
--   ZombieDismembermentEnabled  zombies may lose limbs/armor after strong hits (never players/Otti);
--                               stylized: the parts fall, a dark cap closes the joint, no gore

local DamageEffectsConfig = {
	ZombieDismembermentEnabled = true,

	-- Particles
	SparkColor = Color3.fromRGB(255, 140, 70),
	DustColor = Color3.fromRGB(214, 190, 140),
	ParticleLifetime = 0.35, -- very short; nothing persists
	MaxBurstsPerSecond = 30, -- client-side safety cap

	-- Zombie condition states (share of max health)
	WoundedBelow = 0.65,
	CriticalBelow = 0.30,
	ArmorLostDamageBonus = 0.15, -- per lost armor piece (helmet / shoulder)
	MaxArmorDamageBonus = 0.3,

	-- Limb loss. chance = WeaponChance * strength * health factor (* region bias), only for hits
	-- of at least MinDamage that the zombie survives.
	LimbLoss = table.freeze({
		MinDamage = 18,
		StrongDamage = 34, -- strength factor reaches 1 here
		MaxLimbs = 2, -- arms/legs per zombie (never both legs, never the head)
		LowHealthBonus = 0.6, -- extra chance factor below CriticalBelow
		PartFadeSeconds = 5,
		WeaponChance = table.freeze({
			BattleAxe = 0.5,
			MorningStar = 0.45,
			LegionSword = 0.28,
			Gladius = 0.22,
			Trident = 0.2,
			HopliteSpear = 0.2,
			TwinDaggers = 0.06,
			HunterBow = 0.05,
		}) :: { [string]: number },
		SpecialMultiplier = 1.5, -- specials (not basic attacks)
		ArmorChanceMultiplier = 1.4, -- helmets/shoulder plates come off a little more easily
	}),
}

return table.freeze(DamageEffectsConfig)
