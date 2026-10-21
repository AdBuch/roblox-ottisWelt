--!strict
-- Economy and experience (server-owned; clients only display the player attributes):
--   AURA     experience points. Earned in fights, rounds and wins; never spent. Total Aura gives the
--            GLADIATOR LEVEL (GladiatorLevelDefinitions), which unlocks gear (LevelRequired) and is a
--            matchmaking factor.
--   DENARII  the money (the Roman silver denarius). Earned in PvE fights, completed rounds and
--            defined rewards; spent on weapons, shields and armor (their Price). Never negative.
-- Every reward is decided and paid once by the server (AuraService); purchases are validated by
-- InventoryService. Both are saved in the profile (PlayerDataSchema).

local CurrencyConfig = {
	DenariiName = "DENARII",
	DenariiPerAura = 1, -- every combat reward pays this many Denarii per Aura point (rounded, at least 1)
	StarterDenarii = 0,
	-- A completed zombie round, paid once per round to every fighter still in it
	RoundCompleteAura = 10,
	RoundCompleteDenarii = 15,
}

-- Denarii paid together with an Aura reward of `aura`.
function CurrencyConfig.denariiFor(aura: number): number
	if aura <= 0 then
		return 0
	end
	return math.max(1, math.floor(aura * CurrencyConfig.DenariiPerAura + 0.5))
end

return table.freeze(CurrencyConfig)
