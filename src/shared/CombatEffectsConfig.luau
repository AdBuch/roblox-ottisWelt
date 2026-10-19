--!strict
-- Client combat presentation by weapon category (CombatEffectsController / CombatCameraController).
-- Purely visual: hits are already validated before any effect plays.
--   Blade   brief spark on armor, stylized blood on zombies, short target flash, tiny camera impulse
--   Blunt   dust burst, stronger impulse and knockback presentation
--   Heavy   (axe) blade + dust, strong impulse
--   Pierce  narrow focused burst, small backward target reaction
--   Bow     focused small burst, arrows deflect / stick briefly into shields (pooled)
-- Camera shake: Full / Reduced / Off (saved preference "CameraShake"), never affects aim or hits.

export type Category = "Blade" | "Blunt" | "Heavy" | "Pierce" | "Bow"

local CombatEffectsConfig = {
	Categories = table.freeze({
		Blade = table.freeze({ Spark = 6, Dust = 0, Impulse = 0.18, Flash = 0.12 }),
		Blunt = table.freeze({ Spark = 2, Dust = 10, Impulse = 0.45, Flash = 0.1 }),
		Heavy = table.freeze({ Spark = 5, Dust = 8, Impulse = 0.5, Flash = 0.12 }),
		Pierce = table.freeze({ Spark = 4, Dust = 0, Impulse = 0.22, Flash = 0.08 }),
		Bow = table.freeze({ Spark = 3, Dust = 0, Impulse = 0.08, Flash = 0.06 }),
	}) :: { [string]: { Spark: number, Dust: number, Impulse: number, Flash: number } },

	-- Camera (studs of offset / degrees, decaying quickly)
	Camera = table.freeze({
		HitImpulse = 0.25,
		HeavyImpulse = 0.6,
		PerfectBlock = 0.5,
		LandingImpulse = 0.4,
		UltimateImpulse = 1.1,
		SpectatorScale = 0.4,
		Decay = 10, -- per second
		MaxOffset = 1.2,
		ReducedScale = 0.4,
	}),
	ParryTimeScale = 0.18, -- seconds of local slow-motion look (presentation only, no server time change)
	TrailSeconds = 0.25,
	MaxEmbeddedArrows = 12,
}

return table.freeze(CombatEffectsConfig)
