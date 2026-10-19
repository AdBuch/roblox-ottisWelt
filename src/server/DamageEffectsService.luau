--!strict
-- Broadcasts hit effects for validated server combat events only. Clients render them
-- (CombatEffectsController, BloodEffectsController, SandStainController) according to their own
-- visual settings, so blood modes or camera settings never touch combat logic.
--   kind  Zombie (may bleed / stain the sand) · Player · Boss (sparks, never blood) · Block (shield)
--   extra { category, attackerId, victimId, heavy, perfect, projectile, killed, armored }
-- Also keeps the arena's BattleIntensity (0..1) that makes the animal crowd lean in during long,
-- hard fights, and bumps StainEpoch at match start so old stains fade (no stains between matches).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local DamageEffectsConfig = require(ReplicatedStorage.Shared.DamageEffectsConfig)
local Remotes = require(script.Parent.Remotes)

export type HitKind = "Zombie" | "Player" | "Boss" | "Block"

export type Extra = {
	category: string?,
	attackerId: number?,
	victimId: number?,
	heavy: boolean?,
	perfect: boolean?,
	projectile: boolean?,
	killed: boolean?,
	armored: boolean?,
}

local MAX_PER_SECOND = 40

local DamageEffectsService = {}

local budget = MAX_PER_SECOND
local budgetTime = os.clock()
local arena: Instance? = nil
local intensity = 0

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
	arena = arenaFolder
	arenaFolder:SetAttribute(Config.DamageFxModeAttribute, DamageEffectsConfig.modeName())
	arenaFolder:SetAttribute(Config.StainEpochAttribute, 0)
	arenaFolder:SetAttribute(Config.BattleIntensityAttribute, 0)
end

-- A new match: old sand stains fade away, the crowd calms down.
function DamageEffectsService.newMatch()
	local folder = arena
	if folder then
		folder:SetAttribute(Config.StainEpochAttribute, (tonumber(folder:GetAttribute(Config.StainEpochAttribute)) or 0) + 1)
		intensity = 0
		folder:SetAttribute(Config.BattleIntensityAttribute, 0)
	end
end

-- position: the validated hit position; scale ~ hit strength (0.5 light .. 1.5 heavy).
function DamageEffectsService.hit(kind: HitKind, position: Vector3, scale: number, direction: Vector3?, extra: Extra?)
	if kind == "Zombie" and arena then
		intensity = math.min(1, intensity + scale * 0.004)
		local folder = arena :: Instance
		if math.abs((tonumber(folder:GetAttribute(Config.BattleIntensityAttribute)) or 0) - intensity) >= 0.05 then
			folder:SetAttribute(Config.BattleIntensityAttribute, intensity)
		end
	end
	if not allow() then
		return
	end
	local feedback = CombatConfig.Feedback.DamageFx
	for _, player in Players:GetPlayers() do
		Remotes.CombatFeedback:FireClient(player, feedback, position, kind, math.clamp(scale, 0.3, 2), direction, extra)
	end
end

return DamageEffectsService
