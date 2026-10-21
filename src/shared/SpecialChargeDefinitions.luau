--!strict
-- The SPECIAL attack: hold to charge, release to fire (PlayerCombatService measures the held time
-- on the server between "SpecialStart" and "SpecialRelease"; the client only shows the charge).
--   Tier I    released before 0.5 s   quick special
--   Tier II   0.5 - 1.5 s             strengthened special
--   Tier III  from 1.5 s              maximum special (full strength at 2.5 s; holding longer adds nothing)
-- The charge stays until release unless it is interrupted (death, knockdown, a grab, or a heavy hit
-- that was not blocked). Blocking is allowed while charging; firing lowers the shield.
-- A full charge with a full Momentum bar fires the weapon's ULTIMATE instead (spends the Momentum).
--
-- Personal specials later: specialFor(characterId, weapon, tier) is the one place that picks the
-- move. Today every character uses the weapon's special families (WeaponSpecialDefinitions);
-- Otti, Schili, Krokero, ... can get their own entries in Characters without touching the combat code.

local WeaponAttackDefinitions = require(script.Parent.WeaponAttackDefinitions)
local WeaponSpecialDefinitions = require(script.Parent.WeaponSpecialDefinitions)

export type TierDefinition = {
	Tier: number,
	From: number, -- seconds held
	Name: string,
	Family: string, -- WeaponSpecialDefinitions family used for this tier
	DamageMultiplier: number, -- PvE
	PvPMultiplier: number, -- PvP (flatter)
	Recovery: number, -- extra seconds of commitment after the move
	Cooldown: number, -- seconds until the next special
}

local function tier(def: TierDefinition): TierDefinition
	return table.freeze(def) :: any
end

local SpecialChargeDefinitions = {
	MaxChargeSeconds = 2.5,
	MaxHoldSeconds = 8, -- safety: a charge held this long without release is cancelled
	ChargeMoveFactor = 0.75, -- walk speed share while charging (with a block the stronger slow applies)
	StartLatency = 0.12, -- seconds: a release this soon after the start still counts as tier I
	UltimateMomentum = 100,
	UltimateCooldown = 8,
	Tiers = table.freeze({
		tier({ Tier = 1, From = 0, Name = "I", Family = "Right", DamageMultiplier = 1, PvPMultiplier = 1, Recovery = 0, Cooldown = 2.5 }),
		tier({ Tier = 2, From = 0.5, Name = "II", Family = "Left", DamageMultiplier = 1.3, PvPMultiplier = 1.1, Recovery = 0.1, Cooldown = 4 }),
		tier({ Tier = 3, From = 1.5, Name = "III", Family = "Down", DamageMultiplier = 1.7, PvPMultiplier = 1.25, Recovery = 0.2, Cooldown = 6 }),
	}) :: { TierDefinition },
	-- Per-character overrides (family -> move id), e.g. Otti = { Down = "Otti_TailSlam" }. Empty for now.
	Characters = table.freeze({}) :: { [string]: { [string]: string } },
}

-- The tier reached after holding `seconds`.
function SpecialChargeDefinitions.tierFor(seconds: number): TierDefinition
	local tiers = SpecialChargeDefinitions.Tiers
	local reached = tiers[1]
	local held = math.clamp(seconds, 0, SpecialChargeDefinitions.MaxChargeSeconds)
	for _, def in tiers do
		if held >= def.From then
			reached = def
		end
	end
	return reached
end

-- The move for a released special. `family` is the tier's family or "Ultimate".
-- Returns the move id (or nil when the weapon has no special for it).
function SpecialChargeDefinitions.specialFor(characterId: string?, weaponBasic: string, family: string): string?
	local overrides = characterId and SpecialChargeDefinitions.Characters[characterId]
	if overrides and overrides[family] then
		return overrides[family]
	end
	local specials = WeaponSpecialDefinitions.forPrefix(WeaponAttackDefinitions.prefixOf(weaponBasic))
	return if specials then (specials :: any)[family] else nil
end

return table.freeze(SpecialChargeDefinitions)
