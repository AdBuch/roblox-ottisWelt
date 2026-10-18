--!strict
-- Stylized damage feedback for players and zombies, plus zombie condition states and limb loss.
-- Purely visual switches never change combat logic: with BloodEnabled = false the same hits
-- still land, zombies still change state and lose limbs (if enabled), only the particles change.
--
--   BloodEnabled               brief dark-red stylized particles on validated hits
--   ReducedEffectsMode         replaces blood with orange-red sparks / dust everywhere
--   PlayerBloodEnabled         particles on players (off -> sparks)
--   ZombieDismembermentEnabled zombies may lose limbs/armor after strong hits (never players/Otti)
-- Otti never bleeds: boss hits always use sparks and sand dust.

local DamageEffectsConfig = {
	BloodEnabled = true,
	ReducedEffectsMode = false,
	PlayerBloodEnabled = true,
	ZombieDismembermentEnabled = true,

	-- Particles
	BloodColor = Color3.fromRGB(122, 18, 26),
	BloodHighlight = Color3.fromRGB(176, 36, 40),
	ZombieBloodColor = Color3.fromRGB(96, 26, 30), -- slightly darker, still stylized
	SparkColor = Color3.fromRGB(255, 140, 70), -- reduced mode / boss
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

-- The visual mode clients should use for a hit ("Blood" or "Sparks").
function DamageEffectsConfig.styleFor(kind: string): string
	if DamageEffectsConfig.ReducedEffectsMode or not DamageEffectsConfig.BloodEnabled or kind == "Boss" then
		return "Sparks"
	end
	if kind == "Player" and not DamageEffectsConfig.PlayerBloodEnabled then
		return "Sparks"
	end
	return "Blood"
end

function DamageEffectsConfig.modeName(): string
	if not DamageEffectsConfig.BloodEnabled then
		return "OFF"
	elseif DamageEffectsConfig.ReducedEffectsMode then
		return "REDUCED"
	end
	return "STYLIZED"
end

return table.freeze(DamageEffectsConfig)
