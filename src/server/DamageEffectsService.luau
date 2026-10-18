--!strict
-- Broadcasts stylized hit effects for validated server combat events only. Clients render the
-- particles (DamageEffectsController) according to DamageEffectsConfig, so turning blood off or
-- switching to reduced effects never touches combat logic. Otti always gets sparks/dust.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local DamageEffectsConfig = require(ReplicatedStorage.Shared.DamageEffectsConfig)
local Remotes = require(script.Parent.Remotes)

export type HitKind = "Zombie" | "Player" | "Boss"

local MAX_PER_SECOND = 40

local DamageEffectsService = {}

local budget = MAX_PER_SECOND
local budgetTime = os.clock()

local function allow(): boolean
	local now = os.clock()
	budget = math.min(MAX_PER_SECOND, budget + (now - budgetTime) * MAX_PER_SECOND)
	budgetTime = now
	if budget < 1 then
		return false
	end
	budget -= 1
	return true
end

function DamageEffectsService.init(arenaFolder: Instance)
	arenaFolder:SetAttribute(Config.DamageFxModeAttribute, DamageEffectsConfig.modeName())
end

-- position: the validated hit position; scale ~ hit strength (0.5 light .. 1.5 heavy).
function DamageEffectsService.hit(kind: HitKind, position: Vector3, scale: number, direction: Vector3?)
	if not allow() then
		return
	end
	local feedback = CombatConfig.Feedback.DamageFx
	for _, player in Players:GetPlayers() do
		Remotes.CombatFeedback:FireClient(player, feedback, position, kind, math.clamp(scale, 0.3, 2), direction)
	end
end

return DamageEffectsService
