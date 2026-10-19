--!strict
-- Resolves the running environment (DEV / PROD) and what this server may do. Server-side
-- decisions only use game.PlaceId and RunService (nothing a client can influence):
--   * Studio is always DEV (even when editing the published PROD place).
--   * PROD only when game.PlaceId equals a configured PROD Hub/Arena Place ID (non-zero).
--   * Everything else is DEV.
-- Teleports need both Place IDs of the environment, a live server and the right place role.

local RunService = game:GetService("RunService")

local ExperienceConfig = require(script.Parent.ExperienceConfig)

export type Role = "Hub" | "Arena"

local EnvironmentConfig = {}

local function prodMatches(placeId: number): boolean
	local prod = ExperienceConfig.Environments.PROD
	return placeId ~= 0 and (placeId == prod.HubPlaceId or placeId == prod.ArenaPlaceId)
end

function EnvironmentConfig.name(): ExperienceConfig.EnvironmentName
	if RunService:IsStudio() then
		return "DEV"
	end
	return if prodMatches(game.PlaceId) then "PROD" else "DEV"
end

function EnvironmentConfig.get(): ExperienceConfig.EnvironmentSettings
	return ExperienceConfig.Environments[EnvironmentConfig.name()]
end

function EnvironmentConfig.isStudio(): boolean
	return RunService:IsStudio()
end

-- The build-time role of this place (ReplicatedStorage.Shared.PlaceRole, set by the Rojo project).
function EnvironmentConfig.role(): Role
	local module = script.Parent:FindFirstChild("PlaceRole")
	if module and module:IsA("ModuleScript") then
		local role = require(module) :: any
		if role == "Arena" then
			return "Arena"
		end
	end
	return "Hub"
end

-- Real cross-place teleports are possible (published, not Studio, both IDs configured).
function EnvironmentConfig.canTeleport(): boolean
	local env = EnvironmentConfig.get()
	return not RunService:IsStudio() and game.PlaceId ~= 0 and env.HubPlaceId ~= 0 and env.ArenaPlaceId ~= 0
end

-- Local mock mode: Studio or an unconfigured place. Matches are simulated, never teleported.
function EnvironmentConfig.isMockMode(): boolean
	return not EnvironmentConfig.canTeleport()
end

function EnvironmentConfig.useMockData(): boolean
	return RunService:IsStudio() and EnvironmentConfig.get().StudioMockData
end

function EnvironmentConfig.useMockMemoryStore(): boolean
	return RunService:IsStudio() and ExperienceConfig.Studio.UseMockMemoryStore
end

function EnvironmentConfig.describe(): string
	local env = EnvironmentConfig.get()
	return ("%s %s (place %d, data %s%s, memory %s%s)"):format(
		EnvironmentConfig.role(),
		EnvironmentConfig.name(),
		game.PlaceId,
		env.DataStoreName,
		if EnvironmentConfig.useMockData() then " MOCK" else "",
		env.MemoryStoreNamespace,
		if EnvironmentConfig.useMockMemoryStore() then " MOCK" else ""
	)
end

return EnvironmentConfig
