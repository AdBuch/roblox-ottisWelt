--!strict
-- CONTROLLED, ONE-TIME RESET OF TEST PROFILES (server only). OFF by default.
-- The game is in development with a few test players; when the data structure changes
-- incompatibly, test profiles can be reset ONCE instead of writing a migration:
--   1. set Enabled = true and a NEW Token (any new text, e.g. "2026-10-21-v6")
--   2. optionally list the test players' UserIds (empty = every profile that loads in DEV)
--   3. publish to DEV only; every listed profile is replaced by a fresh one on its next join and
--      remembers the token, so it is reset exactly once per token (never on every server start)
--   4. set Enabled = false again afterwards
-- Safety: only in AllowedEnvironments (DEV), only after a SUCCESSFUL load (a failed DataStore load
-- never resets or saves anything), never without a token, and every reset is logged.
-- Do not enable for PROD without explicit approval: it deletes the players' progress.

local PlayerDataResetConfig = {
	Enabled = false,
	Token = "",
	AllowedEnvironments = table.freeze({ DEV = true }) :: { [string]: boolean },
	UserIds = table.freeze({}) :: { number }, -- empty = all profiles in the allowed environment
}

-- The reset token to apply to this profile now, or nil.
function PlayerDataResetConfig.tokenFor(userId: number, environment: string, savedToken: unknown): string?
	if not PlayerDataResetConfig.Enabled or PlayerDataResetConfig.Token == "" then
		return nil
	end
	if not PlayerDataResetConfig.AllowedEnvironments[environment] then
		return nil
	end
	if #PlayerDataResetConfig.UserIds > 0 and not table.find(PlayerDataResetConfig.UserIds, userId) then
		return nil
	end
	if savedToken == PlayerDataResetConfig.Token then
		return nil -- this profile was already reset with this token
	end
	return PlayerDataResetConfig.Token
end

return table.freeze(PlayerDataResetConfig)
