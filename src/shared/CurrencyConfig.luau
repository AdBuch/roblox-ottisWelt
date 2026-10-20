--!strict
-- The two currencies (server-owned; clients only display the player attributes):
--   AURA     progress. Earned by playing (zombie kills, assists, Otti, Team Battle results), never
--            spent. It UNLOCKS gear: an item can only be bought and equipped once your Aura has
--            reached its AuraRequired (WeaponDefinitions / ShieldDefinitions / ArmorDefinitions).
--   DENARII  money (the Roman silver denarius). Earned with every Aura reward, spent on gear: the
--            item's Price is in Denarii.
-- Saved in the profile (PlayerDataSchema v5). Profiles from v4 and older are converted once by
-- InventoryService.migrateProfile: the old spendable Aura balance becomes the Denarii balance, and
-- Aura becomes balance + the Aura that was spent on owned gear, so earlier unlocks stay unlocked.

local CurrencyConfig = {
	DenariiName = "DENARII",
	DenariiPerAura = 1, -- every reward pays this many Denarii per Aura point (rounded, at least 1)
	StarterDenarii = 0,
}

-- Denarii paid together with an Aura reward of `aura`.
function CurrencyConfig.denariiFor(aura: number): number
	if aura <= 0 then
		return 0
	end
	return math.max(1, math.floor(aura * CurrencyConfig.DenariiPerAura + 0.5))
end

return table.freeze(CurrencyConfig)
