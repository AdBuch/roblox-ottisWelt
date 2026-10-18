--!strict
-- Stylized, non-graphic zombie limb and armor loss (zombies only; never players or Otti).
-- Only strong validated hits that the zombie survives can remove something. The chance depends
-- on the weapon (axe/morning star high, daggers/arrows low), specials, hit strength, remaining
-- health and the hit region. Rules:
--   * never the head, never both legs, at most MaxLimbs arms/legs per zombie
--   * the original parts are hidden (the rig keeps working) and a dark cap covers the joint
--   * the falling copy is anchored, non-colliding, can't hurt anyone and fades after ~5 s
--     (no physics, so nothing explodes or blocks navigation)
-- ZombieService applies the gameplay consequences (unarmed, no blocking, slow crawl, armor).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DamageEffectsConfig = require(ReplicatedStorage.Shared.DamageEffectsConfig)
local Arena = require(script.Parent.Arena)
local CombatEffects = require(script.Parent.CombatEffects)
local ZombieFactory = require(script.Parent.ZombieFactory)

type ZombieRig = ZombieFactory.ZombieRig

export type LossKey = "RightArm" | "LeftArm" | "RightLeg" | "LeftLeg" | "Helmet" | "ShoulderR" | "ShoulderL"

export type LimbState = {
	lost: { [string]: boolean },
	limbCount: number,
	armorLost: number,
}

export type HitParams = {
	damage: number,
	fractionAfter: number,
	weaponId: string?,
	isSpecial: boolean,
	spin: boolean, -- sweeping attacks favour the legs
	hitPosition: Vector3?, -- projectiles: exact impact point
	fromPosition: Vector3,
	rng: Random,
}

local CAP_COLOR = Color3.fromRGB(52, 40, 36) -- dark capped joint, no anatomy

local ZombieDismembermentService = {}

local function partsOf(model: Model, key: string): { BasePart }
	local list = {}
	local isLimb = key == "RightArm" or key == "LeftArm" or key == "RightLeg" or key == "LeftLeg"
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part:GetAttribute("Lost") then
			if (isLimb and part:GetAttribute("Limb") == key) or (not isLimb and part:GetAttribute("Detach") == key) then
				table.insert(list, part)
			end
		end
	end
	return list
end

local function hasVisible(model: Model, key: string): boolean
	for _, part in partsOf(model, key) do
		if part.Transparency < 1 then
			return true
		end
	end
	return false
end

local function jointFor(rig: ZombieRig, limb: BasePart): CFrame?
	for _, child in rig.torso:GetChildren() do
		if child:IsA("Motor6D") and child.Part1 == limb then
			return rig.torso.CFrame * child.C0
		end
	end
	return nil
end

-- A falling, fading, harmless copy of the removed parts.
local function spawnDebris(parts: { BasePart }, fromPosition: Vector3)
	local debris = Instance.new("Model")
	debris.Name = "DetachedZombiePart"
	local lowest = math.huge
	for _, original in parts do
		if original.Transparency < 1 then
			local copy = original:Clone()
			for _, child in copy:GetChildren() do
				if not child:IsA("SpecialMesh") then
					child:Destroy()
				end
			end
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanQuery = false
			copy.CanTouch = false
			copy.CFrame = original.CFrame
			copy.Parent = debris
			lowest = math.min(lowest, original.Position.Y - original.Size.Y / 2)
		end
	end
	if #debris:GetChildren() == 0 then
		debris:Destroy()
		return
	end
	debris.Parent = CombatEffects.container()
	local pivot = debris:GetPivot()
	local away = Vector3.new(pivot.Position.X - fromPosition.X, 0, pivot.Position.Z - fromPosition.Z)
	local push = if away.Magnitude > 0.1 then away.Unit * 1.5 else Vector3.zero
	local drop = math.max(0, lowest - (Arena.Layout.FloorTop + 0.15))
	local goal = CFrame.new(push - Vector3.new(0, drop * 0.85, 0)) * pivot * CFrame.Angles(math.rad(70), math.rad(math.random(-40, 40)), 0)
	local value = Instance.new("CFrameValue")
	value.Value = pivot
	value.Changed:Connect(function(cframe: CFrame)
		if debris.Parent then
			debris:PivotTo(cframe)
		end
	end)
	TweenService:Create(value, TweenInfo.new(0.45, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { Value = goal }):Play()
	local fadeSeconds = DamageEffectsConfig.LimbLoss.PartFadeSeconds
	task.delay(fadeSeconds - 1, function()
		for _, part in debris:GetChildren() do
			if part:IsA("BasePart") then
				TweenService:Create(part, TweenInfo.new(1), { Transparency = 1 }):Play()
			end
		end
	end)
	task.delay(fadeSeconds, function()
		debris:Destroy()
		value:Destroy()
	end)
end

-- Removes one limb or armor group from a living zombie (visual part of the loss).
function ZombieDismembermentService.detach(rig: ZombieRig, key: LossKey, fromPosition: Vector3)
	local parts = partsOf(rig.model, key)
	spawnDebris(parts, fromPosition)
	for _, part in parts do
		part.Transparency = 1
		part:SetAttribute("Lost", true)
		for _, child in part:GetChildren() do
			if child:IsA("PointLight") then
				child.Enabled = false
			elseif child:IsA("ParticleEmitter") then
				child.Enabled = false
			end
		end
	end
	local limb = if key == "RightArm" then rig.rightArm
		elseif key == "LeftArm" then rig.leftArm
		elseif key == "RightLeg" then rig.rightLeg
		elseif key == "LeftLeg" then rig.leftLeg
		else nil
	if limb then
		local joint = jointFor(rig, limb)
		if joint then
			local cap = Instance.new("Part")
			cap.Name = "JointCap"
			cap.Shape = Enum.PartType.Ball
			cap.Size = Vector3.one * math.max(0.6, math.min(limb.Size.X, limb.Size.Z) * 0.95)
			cap.CFrame = joint
			cap.Color = CAP_COLOR
			cap.Material = Enum.Material.SmoothPlastic
			cap.CanCollide = false
			cap.CanQuery = false
			cap.CanTouch = false
			cap.Massless = true
			local weld = Instance.new("Weld")
			weld.Part0 = rig.torso
			weld.Part1 = cap
			weld.C0 = rig.torso.CFrame:Inverse() * joint
			weld.Parent = cap
			cap.Parent = rig.model
			table.insert(rig.visibleParts, cap) -- fades with the corpse
		end
	end
end

-- Rolls for a loss after a strong hit and applies it. Returns what was lost (or nil).
function ZombieDismembermentService.tryDismember(rig: ZombieRig, state: LimbState, params: HitParams): LossKey?
	local rules = DamageEffectsConfig.LimbLoss
	if not DamageEffectsConfig.ZombieDismembermentEnabled or params.damage < rules.MinDamage or params.fractionAfter <= 0 then
		return nil
	end
	local base = rules.WeaponChance[params.weaponId or ""] or 0.12
	if params.isSpecial then
		base *= rules.SpecialMultiplier
	end
	local strength = math.clamp((params.damage - rules.MinDamage) / math.max(1, rules.StrongDamage - rules.MinDamage), 0, 1)
	local healthFactor = 0.5 + (1 - params.fractionAfter) * 0.8
	if params.fractionAfter < DamageEffectsConfig.CriticalBelow then
		healthFactor += rules.LowHealthBonus
	end
	local chance = base * (0.35 + 0.65 * strength) * healthFactor
	if params.rng:NextNumber() >= chance then
		return nil
	end

	-- Region: projectiles use the impact height; melee uses the attacker's side
	local model = rig.model
	local localFrom = rig.root.CFrame:PointToObjectSpace(params.hitPosition or params.fromPosition)
	local rightSide = localFrom.X >= 0
	local region = "Arms"
	if params.hitPosition then
		local height = params.hitPosition.Y - rig.root.Position.Y
		region = if height > rig.root.Size.Y * 1.2 then "Head" elseif height < -0.6 then "Legs" else "Arms"
	else
		local roll = params.rng:NextNumber()
		local legShare = if params.spin then 0.45 else 0.2
		region = if roll < legShare then "Legs" elseif roll < legShare + 0.3 then "Armor" else "Arms"
	end

	local candidates: { LossKey } = {}
	local function consider(key: any)
		if not state.lost[key] and hasVisible(model, key) then
			table.insert(candidates, key)
		end
	end
	local canLoseLimb = state.limbCount < rules.MaxLimbs
	local legLost = state.lost.RightLeg or state.lost.LeftLeg
	if region == "Head" then
		consider("Helmet") -- the head itself is never removed
	elseif region == "Legs" and canLoseLimb and not legLost then
		consider(if rightSide then "RightLeg" else "LeftLeg")
	elseif region == "Armor" then
		consider(if rightSide then "ShoulderR" else "ShoulderL")
		consider("Helmet")
	elseif canLoseLimb then
		consider(if rightSide then "RightArm" else "LeftArm")
	end
	if #candidates == 0 then
		-- Fall back to armor on that side (armor comes off a little more easily)
		if params.rng:NextNumber() < rules.ArmorChanceMultiplier - 1 + 0.5 then
			consider(if rightSide then "ShoulderR" else "ShoulderL")
		end
		if #candidates == 0 then
			return nil
		end
	end
	local key: LossKey = candidates[params.rng:NextInteger(1, #candidates)]
	state.lost[key] = true
	if key == "Helmet" or key == "ShoulderR" or key == "ShoulderL" then
		state.armorLost += 1
	else
		state.limbCount += 1
	end
	ZombieDismembermentService.detach(rig, key, params.fromPosition)
	return key
end

return ZombieDismembermentService
