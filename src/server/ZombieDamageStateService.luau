--!strict
-- Progressive zombie condition states (zombies only; never players or Otti):
--   Healthy  > 65 %   normal look and behaviour
--   Wounded  65-30 %  darker skin, scratches, torn cloth, lost armor bits, slight hunch
--   Critical < 30 %   heavy cracks, more armor gone, pronounced limp (client animator), hunched
-- Nothing is rebuilt: prepared "DamageDetail" parts are shown and a few named pieces are hidden.
-- Behaviour changes come from the profile's Wounded/Critical modifiers (ZombieAIProfiles).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DamageEffectsConfig = require(ReplicatedStorage.Shared.DamageEffectsConfig)
local ZombieAIProfiles = require(ReplicatedStorage.Shared.ZombieAIProfiles)

type ConditionMods = ZombieAIProfiles.ConditionMods
type ZombieAIProfile = ZombieAIProfiles.ZombieAIProfile

export type Condition = "Healthy" | "Wounded" | "Critical"

local WOUNDED_SKIN = Color3.fromRGB(92, 118, 74)
local CRITICAL_SKIN = Color3.fromRGB(78, 92, 66)

-- Pieces that break off (hidden) when a state is reached; the first `count` matches per name.
local BREAKS: { [string]: { { name: string, count: number } } } = {
	Healthy = {},
	Wounded = {
		{ name = "ScarfTail", count = 1 },
		{ name = "Strip", count = 2 },
		{ name = "Phalera", count = 1 },
		{ name = "ChestDisc", count = 1 },
		{ name = "Plank", count = 1 },
	},
	Critical = {
		{ name = "Crest", count = 1 },
		{ name = "CrestStub", count = 1 },
		{ name = "CheekGuard", count = 1 },
		{ name = "Buckle", count = 1 },
		{ name = "Strip", count = 2 },
		{ name = "Rosette", count = 1 },
		{ name = "Medallion", count = 1 },
		{ name = "Greave", count = 1 },
	},
}

local ZombieDamageStateService = {}

ZombieDamageStateService.NeutralMods = table.freeze({
	AggressionAdd = 0,
	BlockMultiplier = 1,
	CooldownMultiplier = 1,
	SpeedMultiplier = 1,
	RetreatAdd = 0,
	BashChanceAdd = 0,
	NetCooldownMultiplier = 1,
	PreferredDistanceAdd = 0,
	AimErrorMultiplier = 1,
	FireCooldownMultiplier = 1,
	BurstSeconds = 0,
	RestSeconds = 0,
	HeavySwingChance = 0,
	ComboChance = 0,
	AvoidMelee = false,
}) :: ConditionMods

function ZombieDamageStateService.conditionFor(healthFraction: number): Condition
	if healthFraction < DamageEffectsConfig.CriticalBelow then
		return "Critical" :: Condition
	elseif healthFraction < DamageEffectsConfig.WoundedBelow then
		return "Wounded" :: Condition
	end
	return "Healthy" :: Condition
end

-- RootJoint offset for the posture of a condition (crawling zombies use their own pose).
function ZombieDamageStateService.postureOffset(condition: Condition): CFrame
	if condition == "Critical" then
		return CFrame.Angles(math.rad(-16), 0, math.rad(7))
	elseif condition == "Wounded" then
		return CFrame.Angles(math.rad(-8), 0, 0)
	end
	return CFrame.identity
end

function ZombieDamageStateService.modsFor(profile: ZombieAIProfile, condition: Condition): ConditionMods
	if condition == "Critical" then
		return profile.Critical
	elseif condition == "Wounded" then
		return profile.Wounded
	end
	return ZombieDamageStateService.NeutralMods
end

-- Hides a part and everything welded onto it (e.g. a skirt strip with its stud).
local function breakOff(model: Instance, part: BasePart)
	part.Transparency = 1
	part:SetAttribute("Broken", true)
	for _, other in model:GetDescendants() do
		if other:IsA("Weld") and other.Part0 == part and other.Part1 then
			other.Part1.Transparency = 1
			other.Part1:SetAttribute("Broken", true)
		end
	end
end

-- Shows the visuals of `condition` (and of every lighter state). Cheap: runs once per transition.
-- rootJoint/rest: the zombie's RootJoint for the posture change.
function ZombieDamageStateService.apply(model: Model, condition: Condition, rootJoint: Motor6D?, rootRest: CFrame?)
	if condition == "Healthy" then
		return
	end
	local previous = model:GetAttribute("Condition")
	model:SetAttribute("Condition", condition)
	local skin = if condition == "Critical" then CRITICAL_SKIN else WOUNDED_SKIN
	local showWounded = true
	local showCritical = condition == "Critical"
	local remaining: { [string]: number } = {}
	local lists = { BREAKS[condition] }
	if condition == "Critical" and previous ~= "Wounded" then
		table.insert(lists, BREAKS.Wounded) -- skipped straight past Wounded
	end
	for _, list in lists do
		for _, entry in list do
			remaining[entry.name] = (remaining[entry.name] or 0) + entry.count
		end
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part:GetAttribute("Lost") then
			if part:GetAttribute("Skin") then
				part.Color = skin
			end
			local detailState = part:GetAttribute("DamageDetail")
			if (detailState == "Wounded" and showWounded) or (detailState == "Critical" and showCritical) then
				if not part:GetAttribute("Broken") then
					part.Transparency = 0
				end
			end
			local left = remaining[part.Name]
			if left and left > 0 and part.Transparency < 1 and detailState == nil then
				remaining[part.Name] = left - 1
				breakOff(model, part)
			end
		end
	end
	-- Posture: hunched when wounded, hunched and leaning to one side when critical
	if rootJoint and rootRest and not model:GetAttribute("Crawl") then
		local goal = rootRest * ZombieDamageStateService.postureOffset(condition)
		TweenService:Create(rootJoint, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { C0 = goal }):Play()
	end
end

return ZombieDamageStateService
