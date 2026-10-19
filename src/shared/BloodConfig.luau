--!strict
-- Stylized ZOMBIE blood (visual only, client-rendered from server-confirmed hit events).
-- Changing any of this never changes damage, rewards, AI, hit validation or results.
--   Mode "Stylized"  short dark particle bursts + sand stains that build up where fights happen
--   Mode "Reduced"   dark-red dust / sparks, very faint stains, no limb-loss blood
--   Mode "Off"       dust, sparks and armor fragments only
-- Only zombies bleed (never Otti, spectators, lobby characters, training dummies or players unless
-- PlayerBlood is enabled). No gore: no organs, bones, wounds, glossy pools or screen splashes.
-- Players can pick Auto / Stylized / Reduced / Off (saved preference "BloodFx"); Auto = Mode,
-- or MobileDefault on phones. ParentalMode forces Reduced for everyone.

export type Mode = "Off" | "Reduced" | "Stylized"
export type Quality = "Low" | "Medium" | "High"

local BloodConfig = {
	Mode = "Stylized" :: Mode,
	MobileDefault = "Stylized" :: Mode,
	ParentalMode = false, -- true: everyone sees Reduced at most
	ArenaOnly = true, -- no blood in the Hub (training) at all
	PlayerBlood = false,
	EnableParticles = true,
	EnableSandStains = true,
	EnableArenaAccumulation = true,
	MaxActiveStains = 100, -- High quality; see Quality below
	MaxParticlesPerHit = 12,
	StainLifetime = 180,
	FadeOldStains = true,

	-- Dark, desaturated zombie red with a brown undertone (distinct from the bright team red)
	Color = Color3.fromRGB(86, 22, 20),
	ColorDark = Color3.fromRGB(58, 18, 16),
	StainColor = Color3.fromRGB(96, 40, 30),
	ReducedColor = Color3.fromRGB(120, 60, 46),

	Quality = table.freeze({
		Low = table.freeze({ MaxStains = 32, ParticleScale = 0.5, FadeSeconds = 90 }),
		Medium = table.freeze({ MaxStains = 60, ParticleScale = 0.75, FadeSeconds = 140 }),
		High = table.freeze({ MaxStains = 100, ParticleScale = 1, FadeSeconds = 180 }),
	}) :: { [Quality]: { MaxStains: number, ParticleScale: number, FadeSeconds: number } },

	StainMergeRadius = 1.8, -- a new stain this close to an old one darkens / grows it instead
	StainMaxDarkness = 0.88, -- most opaque a merged patch gets (1 = fully opaque)
	MaxStainRadius = 2.6,
	FloorMaxDistance = 6, -- only hits this close above the sand leave a stain
}

-- The effective mode for a preference ("Auto" | Mode) on a device class.
function BloodConfig.resolve(preference: string?, device: string): Mode
	local mode: Mode = BloodConfig.Mode
	if preference == "Stylized" or preference == "Reduced" or preference == "Off" then
		mode = preference :: Mode
	elseif device == "Phone" then
		mode = BloodConfig.MobileDefault
	end
	if BloodConfig.ParentalMode and mode == "Stylized" then
		mode = "Reduced"
	end
	return mode
end

return table.freeze(BloodConfig)
