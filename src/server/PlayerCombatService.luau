--!strict
-- Player equipment, defense and authoritative attack handling.
--   * Hands: the equipped weapon (right) and shield (left) are welded and visible together.
--     Twin daggers are two-handed: a second dagger replaces the shield and blocking becomes a
--     short parry. Models are always rebuilt from InventoryService (no client claims).
--   * CombatAction(action, aimPoint): action = "Basic" (instant attack; airborne -> the weapon's
--     aerial attack, once per jump), "Jump" (J combo input) or "Execute" (resolves the combo
--     buffer). The server rate-limits, checks the combat context (CombatRules), alive, spawn
--     protection, knockdown, busy time and per-move cooldowns, records A/B/J inputs
--     (ComboValidationService) and runs the move (SpecialMoveService). Nothing is charged.
--   * ShieldBlock(boolean): request only; the server owns block/parry state, raise time and the
--     maximum block duration.
--   * Incoming damage (zombies and PvP) goes through here: spawn protection, immunity, shield
--     angle/reduction, parry, PvP caps, knockback and slows.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local DamageConfig = require(ReplicatedStorage.Shared.DamageConfig)
local InputDefinitions = require(ReplicatedStorage.Shared.InputDefinitions)
local PvPBalanceConfig = require(ReplicatedStorage.Shared.PvPBalanceConfig)
local SpecialMoveDefinitions = require(ReplicatedStorage.Shared.SpecialMoveDefinitions)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatRules = require(script.Parent.CombatRules)
local CombatTargets = require(script.Parent.CombatTargets)
local CombatUtil = require(script.Parent.CombatUtil)
local DamageEffectsService = require(script.Parent.DamageEffectsService)
local ComboValidationService = require(script.Parent.ComboValidationService)
local EquipmentModels = require(script.Parent.EquipmentModels)
local InventoryService = require(script.Parent.InventoryService)
local JumpAttackService = require(script.Parent.JumpAttackService)
local OttiBossService = require(script.Parent.OttiBossService)
local OttiSpectatorService = require(script.Parent.OttiSpectatorService)
local Remotes = require(script.Parent.Remotes)
local SpecialMoveService = require(script.Parent.SpecialMoveService)

type Anim = SpecialMoveDefinitions.Anim

local PREFIX = "[OttiArena][Server]"
local MAX_AIM_DISTANCE = 400

-- Poses relative to the hand's grip attachment (+Y forward when the arm hangs, +Z up the arm).
local SHIELD_IDLE = CFrame.new(-0.45, 0.1, 0.7) * CFrame.Angles(0, 0, math.rad(90)) -- on the outer forearm
local SHIELD_BLOCK = CFrame.new(0.9, 1.4, 1.6) -- raised in front of the chest
local SHIELD_BASH = CFrame.new(0.9, 2.6, 1.6) -- pushed forward
local OFFHAND_REST = CFrame.Angles(math.rad(30), 0, 0)
local TEAM_RED = Color3.fromRGB(170, 30, 34)
local TEAM_BLUE = Color3.fromRGB(36, 70, 170)

type PlayerState = {
	weaponId: string?,
	shieldId: string?, -- nil when two-handed
	weaponWeld: Weld?,
	offhandWeld: Weld?,
	weaponModel: Model?,
	offhandModel: Model?,
	weaponGrip: CFrame,
	offhandGrip: CFrame,
	busyUntil: number,
	cooldowns: { [string]: number },
	blocking: boolean,
	blockStart: number,
	blockToken: number,
	parryUntil: number,
	parryReadyAt: number,
	lastHitTaken: number,
	spawnProtectedUntil: number,
	immuneUntil: number, -- landing / knockdown recovery protection (no visual force field)
	controlLocked: boolean, -- grappled by Otti: no walking or jumping
	counterUntil: number, -- combo counter window (damage reduced, never the whole combo)
	blockLockedUntil: number, -- guard broken: can't raise the shield again yet
	lastComboStagger: number, -- PvP: no repeated stun-lock from combos
	knockedUntil: number, -- knocked down: no actions
	trail: Trail?, -- weapon trail during strikes
	slowFactor: number,
	slowToken: number,
	actionToken: number, -- changes on death/state reset: running moves stop
	actionBucket: number,
	blockBucket: number,
	bucketTime: number,
	rejectLog: { [string]: number },
}

local PlayerCombatService = {}

local states: { [Player]: PlayerState } = {}

local function getState(player: Player): PlayerState
	local state = states[player]
	if not state then
		state = {
			weaponId = nil,
			shieldId = nil,
			weaponWeld = nil,
			offhandWeld = nil,
			weaponModel = nil,
			offhandModel = nil,
			weaponGrip = CFrame.identity,
			offhandGrip = CFrame.identity,
			busyUntil = 0,
			cooldowns = {},
			blocking = false,
			blockStart = 0,
			blockToken = 0,
			parryUntil = 0,
			parryReadyAt = 0,
			lastHitTaken = 0,
			spawnProtectedUntil = 0,
			immuneUntil = 0,
			controlLocked = false,
			counterUntil = 0,
			blockLockedUntil = 0,
			lastComboStagger = -100,
			knockedUntil = 0,
			trail = nil,
			slowFactor = 1,
			slowToken = 0,
			actionToken = 0,
			actionBucket = CombatConfig.ActionRateLimit,
			blockBucket = CombatConfig.BlockRateLimit,
			bucketTime = os.clock(),
			rejectLog = {},
		}
		states[player] = state
	end
	return state
end

-- Token buckets: at most N requests per second per player for each remote.
local function allowRequest(state: PlayerState, kind: "action" | "block"): boolean
	local now = os.clock()
	local elapsed = now - state.bucketTime
	state.bucketTime = now
	state.actionBucket = math.min(CombatConfig.ActionRateLimit, state.actionBucket + elapsed * CombatConfig.ActionRateLimit)
	state.blockBucket = math.min(CombatConfig.BlockRateLimit, state.blockBucket + elapsed * CombatConfig.BlockRateLimit)
	if kind == "action" then
		if state.actionBucket < 1 then
			return false
		end
		state.actionBucket -= 1
	else
		if state.blockBucket < 1 then
			return false
		end
		state.blockBucket -= 1
	end
	return true
end

-- Temporary diagnostics: one warning per player and reason every RejectLogInterval seconds.
local function reject(player: Player, reason: string)
	if not CombatConfig.DebugRejectedAttacks then
		return
	end
	local state = getState(player)
	local now = os.clock()
	local last = state.rejectLog[reason]
	if last and now - last < CombatConfig.RejectLogInterval then
		return
	end
	state.rejectLog[reason] = now
	warn(PREFIX, ("Attack from %s rejected: %s"):format(player.Name, reason))
end

local function updateWalkSpeed(player: Player)
	local _, humanoid = CombatUtil.getLivingCharacter(player)
	if not humanoid then
		return
	end
	local state = getState(player)
	local speed = CombatConfig.PlayerWalkSpeed
	local shield = InventoryService.getActiveShield(player)
	if state.blocking and shield then
		speed = CombatConfig.BlockingWalkSpeed * shield.BlockSpeedMultiplier
	end
	speed *= 1 - math.clamp(InventoryService.getEquippedArmor(player).MovePenalty, 0, 0.5) -- heavier armor, slower steps
	humanoid.WalkSpeed = if state.controlLocked then 0 else speed * state.slowFactor
	humanoid.JumpPower = if state.controlLocked then 0 else 50
	humanoid.UseJumpPower = true
end

------------------------------------------------------------------------------------------
-- Equipment in the hands
------------------------------------------------------------------------------------------

local function getGrip(character: Model, r15Name: string, r6Name: string, attachmentName: string): (BasePart?, CFrame)
	local limb = character:FindFirstChild(r15Name) or character:FindFirstChild(r6Name)
	if not limb or not limb:IsA("BasePart") then
		return nil, CFrame.identity
	end
	local attachment = limb:FindFirstChild(attachmentName)
	if attachment and attachment:IsA("Attachment") then
		return limb, attachment.CFrame
	end
	return limb, CFrame.new(0, -limb.Size.Y / 2, 0) * CFrame.Angles(math.rad(-90), 0, 0)
end

local function attach(model: Model, core: BasePart, limb: BasePart, c0: CFrame, character: Model): Weld
	local weld = Instance.new("Weld")
	weld.Name = "EquipmentWeld"
	weld.Part0 = limb
	weld.Part1 = core
	weld.C0 = c0
	weld.Parent = core
	model:SetAttribute("OttiEquipment", true)
	model.Parent = character
	return weld
end

-- Rebuilds the weapon and shield (or offhand dagger) in the current character's hands.
function PlayerCombatService.refreshEquipment(player: Player)
	local character = player.Character
	if not character then
		return
	end
	for _, child in character:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("OttiEquipment") then
			child:Destroy()
		end
	end
	local state = getState(player)
	state.weaponWeld, state.offhandWeld, state.weaponModel, state.offhandModel = nil, nil, nil, nil
	state.weaponId, state.shieldId = nil, nil

	local rightHand, rightGrip = getGrip(character, "RightHand", "Right Arm", "RightGripAttachment")
	local leftHand, leftGrip = getGrip(character, "LeftHand", "Left Arm", "LeftGripAttachment")
	if not rightHand or not leftHand then
		warn(PREFIX, "Could not find hands for", player.Name, "- equipment not attached")
		return
	end

	local weapon = InventoryService.getEquippedWeapon(player)
	local shield = InventoryService.getActiveShield(player)
	local weaponModel, weaponCore = EquipmentModels.buildWeapon(weapon.Id)
	state.weaponGrip = rightGrip
	state.offhandGrip = leftGrip
	state.weaponWeld = attach(weaponModel, weaponCore, rightHand, rightGrip * EquipmentModels.weaponRestPose(weapon.Id), character)
	state.weaponModel = weaponModel
	state.weaponId = weapon.Id
	state.trail = EquipmentModels.addTrail(weaponModel, weaponCore)
	ComboValidationService.clear(player) -- weapon changes clear the combo buffer

	if shield then
		local shieldModel, shieldCore = EquipmentModels.buildShield(shield.Id)
		local sound = Instance.new("Sound")
		sound.Name = "BlockSound"
		sound.SoundId = CombatConfig.ShieldSoundId
		sound.Volume = 0.6
		sound.Parent = shieldCore
		state.offhandWeld = attach(shieldModel, shieldCore, leftHand, leftGrip * (if state.blocking then SHIELD_BLOCK else SHIELD_IDLE), character)
		state.offhandModel = shieldModel
		state.shieldId = shield.Id
	else
		local daggerModel, daggerCore = EquipmentModels.buildOffhandDagger()
		state.offhandWeld = attach(daggerModel, daggerCore, leftHand, leftGrip * OFFHAND_REST, character)
		state.offhandModel = daggerModel
	end

	-- Armor on the body (no helmet: the player stays recognisable); cloth takes the team color
	local armorModel = EquipmentModels.buildArmor(InventoryService.getEquippedArmor(player).Id, character)
	armorModel:SetAttribute("OttiEquipment", true)
	armorModel.Parent = character
	PlayerCombatService.applyTeamColor(player)
	updateWalkSpeed(player) -- armor weight
end

-- Team Battle: the armor's cloth pieces show the team color (default armor colors otherwise).
function PlayerCombatService.applyTeamColor(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local team = player:GetAttribute(Config.TeamAttribute)
	local color: Color3? = if team == "Red" then TEAM_RED elseif team == "Blue" then TEAM_BLUE else nil
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("TeamCloth") then
			local default = part:GetAttribute("DefaultColor")
			part.Color = color or (if typeof(default) == "Color3" then default else part.Color)
		end
	end
end

------------------------------------------------------------------------------------------
-- Procedural attack motions (weld C0 tweens replicate to everyone)
------------------------------------------------------------------------------------------

local function tweenWeld(weld: Weld?, goal: CFrame, seconds: number)
	if weld and weld.Parent then
		TweenService:Create(weld, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { C0 = goal }):Play()
	end
end

-- Animation abstraction: the server publishes WHAT to play (character attributes AttackAnim,
-- AttackStart, AttackWind, AttackLength; PlayerAnimator on every client adds torso twist,
-- shoulders, steps and recovery on top of the walk animation) and moves the weapon/shield welds
-- (replicated). Authored Roblox animations can later replace both behind this one function.
local function animate(player: Player, state: PlayerState, anim: Anim, windUp: number, duration: number)
	local character = player.Character
	if character then
		character:SetAttribute("AttackAnim", anim)
		character:SetAttribute("AttackStart", Workspace:GetServerTimeNow())
		character:SetAttribute("AttackWind", windUp)
		character:SetAttribute("AttackLength", duration)
	end
	local weld = state.weaponWeld
	if not weld or not weld.Parent or not state.weaponId then
		return
	end
	local grip = state.weaponGrip
	local rest = grip * EquipmentModels.weaponRestPose(state.weaponId)
	local windPose, strikePose = rest, rest
	if anim == "Slash" or anim == "Flurry" then
		windPose, strikePose = grip * CFrame.Angles(math.rad(105), 0, math.rad(25)), grip * CFrame.Angles(math.rad(-25), 0, math.rad(-35))
	elseif anim == "Backhand" then
		windPose, strikePose = grip * CFrame.Angles(math.rad(90), 0, math.rad(-80)), grip * CFrame.Angles(math.rad(60), 0, math.rad(90))
	elseif anim == "Low" then
		windPose, strikePose = grip * CFrame.Angles(math.rad(20), 0, math.rad(70)), grip * CFrame.Angles(math.rad(-10), 0, math.rad(-80))
	elseif anim == "Overhead" or anim == "Dive" then
		windPose, strikePose = grip * CFrame.Angles(math.rad(165), 0, 0), grip * CFrame.Angles(math.rad(-50), 0, 0)
	elseif anim == "Rise" then
		windPose, strikePose = grip * CFrame.Angles(math.rad(-30), 0, 0), grip * CFrame.Angles(math.rad(170), 0, 0)
	elseif anim == "Thrust" then
		windPose, strikePose = rest * CFrame.new(0, -1.1, 0), rest * CFrame.new(0, 2.4, 0)
	elseif anim == "Spin" then
		windPose, strikePose = grip * CFrame.Angles(math.rad(80), 0, math.rad(70)), grip * CFrame.Angles(math.rad(80), 0, math.rad(-150))
	elseif anim == "Draw" then
		windPose, strikePose = rest * CFrame.new(0, -0.6, 0), rest * CFrame.new(0, 0.25, 0)
	elseif anim == "Guard" or anim == "Bash" then
		tweenWeld(state.offhandWeld, state.offhandGrip * (if anim == "Bash" then SHIELD_BASH else SHIELD_BLOCK), math.max(0.05, windUp))
		task.delay(math.max(0.2, duration * (if anim == "Guard" then 0.3 else 0.8)), function()
			tweenWeld(state.offhandWeld, state.offhandGrip * (if state.blocking then SHIELD_BLOCK else SHIELD_IDLE), 0.15)
		end)
	end
	local trail = state.trail
	tweenWeld(weld, windPose, math.max(0.04, windUp * 0.9))
	task.delay(windUp, function()
		if trail and anim ~= "Draw" and anim ~= "Guard" then
			trail.Enabled = true -- weapon trail only while the blade travels
		end
		tweenWeld(weld, strikePose, 0.1)
		if anim == "Flurry" and not state.shieldId then
			tweenWeld(state.offhandWeld, state.offhandGrip * CFrame.Angles(math.rad(-20), 0, 0), 0.08)
		end
	end)
	task.delay(math.max(windUp + 0.15, duration * 0.85), function()
		if trail then
			trail.Enabled = false
		end
		tweenWeld(weld, rest, 0.18) -- follow-through back to the guard
		if not state.shieldId then
			tweenWeld(state.offhandWeld, state.offhandGrip * OFFHAND_REST, 0.15)
		end
	end)
end

------------------------------------------------------------------------------------------
-- Blocking and parrying
------------------------------------------------------------------------------------------

local function setBlocking(player: Player, active: boolean)
	local state = getState(player)
	if state.blocking == active then
		return
	end
	state.blocking = active
	state.blockToken += 1
	state.blockStart = os.clock()
	updateWalkSpeed(player)
	local shield = InventoryService.getActiveShield(player)
	if shield then
		tweenWeld(state.offhandWeld, state.offhandGrip * (if active then SHIELD_BLOCK else SHIELD_IDLE), math.max(0.04, shield.RaiseSeconds))
	end
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Block, active)
	if active then
		local myToken = state.blockToken
		task.delay(CombatConfig.ShieldMaxBlockSeconds, function()
			if state.blockToken == myToken and state.blocking then
				setBlocking(player, false)
			end
		end)
	end
end

local function onBlockRequest(player: Player, wantsBlock: unknown)
	if typeof(wantsBlock) ~= "boolean" then
		return
	end
	local state = getState(player)
	if not allowRequest(state, "block") then
		return
	end
	if not wantsBlock then
		setBlocking(player, false)
		return
	end
	local _, humanoid = CombatUtil.getLivingCharacter(player)
	if not humanoid or not state.offhandWeld or not state.offhandWeld.Parent then
		return
	end
	local now = os.clock()
	-- Every block PRESS is also a "B" combo input (holding keeps defending normally)
	if CombatRules.getContext(player) then
		ComboValidationService.record(player, "B")
	end
	if state.shieldId == nil then
		-- Twin daggers: a short parry window on a cooldown instead of a held block
		if now >= state.parryReadyAt then
			state.parryUntil = now + CombatConfig.ParryWindowSeconds
			state.parryReadyAt = now + CombatConfig.ParryCooldownSeconds
			tweenWeld(state.offhandWeld, state.offhandGrip * CFrame.Angles(math.rad(70), 0, math.rad(40)), 0.05)
			task.delay(CombatConfig.ParryWindowSeconds, function()
				tweenWeld(state.offhandWeld, state.offhandGrip * OFFHAND_REST, 0.15)
			end)
			Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Parry)
		end
		return
	end
	local activeShield = InventoryService.getActiveShield(player)
	if activeShield == nil or state.shieldId ~= activeShield.Id then
		return -- the shield in the hand must be the owned, equipped one
	end
	if now < state.blockLockedUntil then
		return -- guard broken a moment ago
	end
	setBlocking(player, true)
end

local function shieldFeedback(state: PlayerState)
	local shield = state.offhandModel
	if not shield or not shield.Parent then
		return
	end
	CombatEffects.glow(shield, Color3.new(1, 1, 1), 0.15)
	local core = shield.PrimaryPart
	local sound = core and core:FindFirstChild("BlockSound")
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

function PlayerCombatService.isBlockingToward(player: Player, position: Vector3): boolean
	local state = states[player]
	local shield = InventoryService.getActiveShield(player)
	local _, _, root = CombatUtil.getLivingCharacter(player)
	return state ~= nil and state.blocking and shield ~= nil and root ~= nil and CombatUtil.isFacing(root.CFrame, position, shield.FacingDot)
end

-- True while the player blocks with a big shield (fast zombies avoid attacking them head-on).
function PlayerCombatService.isHeavyBlocking(player: Player): boolean
	local state = states[player]
	local shield = InventoryService.getActiveShield(player)
	return state ~= nil and state.blocking and shield ~= nil and shield.Reduction >= 0.75
end

------------------------------------------------------------------------------------------
-- Incoming damage
------------------------------------------------------------------------------------------

type Incoming = {
	damage: number,
	fromPosition: Vector3,
	isProjectile: boolean,
	blockPierce: number,
	knockback: number,
	fromZombie: boolean, -- zombies and Otti (PvE): brief hit immunity, no PvP cap
	attacker: Player?,
	blockStops: boolean?, -- a facing shield stops all damage (Otti's bite)
	knockbackIfBlocked: boolean?, -- tail sweeps push back even through a shield
	knockdownSeconds: number?,
	slowSeconds: number?, -- strong stagger
	unblockable: boolean?,
	guardBreak: boolean?, -- combo GUARD BREAK: a raised shield only stops half and drops
	fromCombo: boolean?, -- PvP combo / aerial: stagger lock applies
	pvpCap: number?, -- PvP: whole-move damage cap left for this victim
}

-- Armor share removed from this hit (step 5): full in PvE, reduced in PvP (DamageConfig).
local function armorReduction(victim: Player, incoming: Incoming): number
	if incoming.unblockable and not DamageConfig.ArmorAppliesToUnblockable then
		return 0
	end
	local armor = InventoryService.getEquippedArmor(victim)
	local effectiveness = if incoming.fromZombie then DamageConfig.PvEArmorEffectiveness else DamageConfig.PvPArmorEffectiveness
	return math.clamp(armor.Reduction * effectiveness, 0, DamageConfig.MaxArmorReduction)
end

-- THE player damage pipeline: every zombie blow, enemy arrow, Otti attack and PvP hit (melee,
-- arrows, combos, aerials) arrives here, so no weapon can skip the shield or the armor.
--   1 validate target / protection   2 base damage (incoming.damage; the attack already applied
--   3 its mode multiplier)   4 shield block / parry   5 armor   6 temporary effects (counter)
--   7 PvP caps + minimum damage   8 Humanoid damage   9 feedback
-- Returns damage dealt, whether it was blocked/parried, and the stagger multiplier for the attacker.
local function receiveHit(victim: Player, incoming: Incoming): (number, boolean, number)
	-- 1. Validate
	local _, humanoid, root = CombatUtil.getLivingCharacter(victim)
	if not humanoid or not root then
		return 0, false, 1
	end
	if incoming.attacker and not CombatRules.isEnemy(incoming.attacker, victim) then
		return 0, false, 1 -- no friendly fire, no PvP outside Team Battle (lobby / armory are safe)
	end
	local state = getState(victim)
	local now = os.clock()
	if now < state.spawnProtectedUntil or (incoming.fromZombie and now < state.immuneUntil) then
		return 0, true, 1
	end
	if incoming.fromZombie and now - state.lastHitTaken < CombatConfig.HitImmunitySeconds then
		return 0, false, 1 -- brief immunity: no burst damage from several zombies at once
	end

	-- 2./3. Base damage (mode multipliers were applied by the attack itself)
	local baseDamage = math.max(0, incoming.damage)
	local shieldMultiplier = 1
	local stopped = false -- a facing shield stops everything (Otti's bite)
	local blocked = false
	local stagger = 1
	local shield = InventoryService.getActiveShield(victim)
	-- 4. Shield block / parry
	if incoming.unblockable then
		-- grapples can't be blocked
	elseif state.blocking and shield and state.shieldId == shield.Id and now - state.blockStart >= shield.RaiseSeconds then
		local inRange = incoming.isProjectile or CombatUtil.flatDistance(root.Position, incoming.fromPosition) <= CombatConfig.ShieldBlockDistance
		if inRange and CombatUtil.isFacing(root.CFrame, incoming.fromPosition, shield.FacingDot) then
			local reduction = (if incoming.isProjectile then shield.ProjectileReduction else shield.Reduction) * (1 - incoming.blockPierce)
			if incoming.guardBreak then
				-- The guard breaks: half protection, the shield drops and stays down briefly
				reduction *= 0.5
				setBlocking(victim, false)
				state.blockLockedUntil = now + PvPBalanceConfig.GuardBreakShieldLock
				CombatEffects.burst(root.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 150, 80), 1)
			end
			shieldMultiplier = 1 - reduction
			stopped = incoming.blockStops == true
			blocked = not incoming.guardBreak
			stagger = shield.StaggerMultiplier
			shieldFeedback(state)
		end
	elseif state.shieldId == nil and now < state.parryUntil and CombatUtil.isFacing(root.CFrame, incoming.fromPosition, 0) then
		shieldMultiplier = 1 - CombatConfig.ParryReduction
		stopped = incoming.blockStops == true
		blocked = true
		stagger = 1.5
		CombatEffects.burst(root.Position + Vector3.new(0, 1, 0), Color3.fromRGB(200, 230, 255), 0.8)
		Remotes.CombatFeedback:FireClient(victim, CombatConfig.Feedback.Parry)
	end
	local afterBlock = if stopped then 0 else baseDamage * shieldMultiplier

	-- 5. Armor
	local afterArmor = afterBlock * (1 - armorReduction(victim, incoming))

	-- 6. Temporary effects: inside a combo's short counter window the first blow is deflected
	-- (never the whole combo)
	if not blocked and afterArmor > 0 and now < state.counterUntil and CombatUtil.isFacing(root.CFrame, incoming.fromPosition, 0) then
		afterArmor *= 1 - PvPBalanceConfig.CounterReduction
		blocked = true
		stagger = 1.3
		CombatEffects.burst(root.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 230, 160), 0.8)
	end

	-- 7. Minimum valid damage (only when something got through) and PvP caps
	local damage = if afterArmor > 0 then math.max(DamageConfig.MinimumDamage, math.round(afterArmor)) else 0
	if not incoming.fromZombie and damage > 0 then
		-- PvP: no single hit may remove more than a share of max health (no one-shots), and one
		-- combo / aerial move never takes more than its whole-move share
		damage = math.min(damage, math.floor(humanoid.MaxHealth * PvPBalanceConfig.MaxHitFraction))
		if incoming.pvpCap then
			damage = math.min(damage, incoming.pvpCap)
		end
		if incoming.fromCombo then
			if now - state.lastComboStagger < PvPBalanceConfig.StaggerLockWindow then
				incoming.knockback = 0 -- no repeated stun-lock
			else
				state.lastComboStagger = now
			end
		end
	end
	damage = math.floor(damage + 0.5)
	-- 9a. Knockback (also for fully blocked hits)
	local pushed = incoming.knockback > 0 and (not blocked or incoming.knockbackIfBlocked == true)
	if pushed then
		local away = CombatUtil.flat(root.Position - incoming.fromPosition)
		if away.Magnitude > 0.05 then
			-- Horizontal only and limited: the arena barrier keeps everyone on the floor
			local strength = if blocked then incoming.knockback * 0.6 else incoming.knockback
			Remotes.CombatFeedback:FireClient(victim, CombatConfig.Feedback.Knockback, away.Unit * math.min(strength, 45))
		end
	end
	if damage <= 0 then
		return 0, blocked, stagger
	end
	-- 8. Apply
	state.lastHitTaken = now
	CombatRules.onPlayerDamaged(victim, incoming.attacker, damage)
	humanoid:TakeDamage(damage)
	-- 9. Feedback
	Remotes.CombatFeedback:FireClient(victim, CombatConfig.Feedback.PlayerHit, damage, blocked, incoming.fromPosition)
	if not blocked then
		DamageEffectsService.hit("Player", root.Position + Vector3.new(0, 0.8, 0), math.clamp(damage / 15, 0.4, 1.4), CombatUtil.flat(root.Position - incoming.fromPosition))
	end
	if incoming.knockdownSeconds and incoming.knockdownSeconds > 0 and not blocked then
		PlayerCombatService.knockdown(victim, incoming.knockdownSeconds)
	end
	if incoming.slowSeconds and incoming.slowSeconds > 0 then
		PlayerCombatService.applySlow(victim, if blocked then 0.75 else 0.5, incoming.slowSeconds)
	end
	return damage, blocked, stagger
end

-- A zombie blow lands. Returns landed, blocked, staggerMultiplier.
function PlayerCombatService.applyZombieHit(player: Player, attackerPosition: Vector3, damage: number, blockPierce: number, knockback: number): (boolean, boolean, number)
	if not CombatRules.canZombiesTarget(player) then
		return false, false, 1 -- lobby players and spectators can't be hurt
	end
	if damage >= 15 or knockback > 0 then
		OttiSpectatorService.react("PlayerHurt") -- a heavy zombie hit: Otti is surprised (cooldown)
	end
	local dealt, blocked, stagger = receiveHit(player, {
		damage = damage,
		fromPosition = attackerPosition,
		isProjectile = false,
		blockPierce = blockPierce,
		knockback = knockback,
		fromZombie = true,
	})
	return dealt > 0 or blocked, blocked, stagger
end

-- An Undead Sagittarius arrow reaches a player (projectile: shields use their arrow protection).
function PlayerCombatService.applyEnemyArrowHit(player: Player, fromPosition: Vector3, damage: number): boolean
	if not CombatRules.canZombiesTarget(player) then
		return false
	end
	local dealt, blocked = receiveHit(player, {
		damage = damage,
		fromPosition = fromPosition,
		isProjectile = true,
		blockPierce = 0,
		knockback = 6,
		fromZombie = true,
	})
	return dealt > 0 or blocked
end

export type BossHit = {
	fromPosition: Vector3,
	damage: number,
	blockable: boolean,
	blockStops: boolean?,
	blockPierce: number?,
	knockback: number,
	knockbackIfBlocked: boolean?,
	knockdownSeconds: number?,
	slowSeconds: number?,
}

-- One validated Otti hit. Returns damage dealt and whether a shield (or parry) caught it.
function PlayerCombatService.applyBossHit(player: Player, hit: BossHit): (number, boolean)
	if not CombatRules.canZombiesTarget(player) then
		return 0, false -- the same rules as zombies: lobby players and spectators are never hit
	end
	local dealt, blocked = receiveHit(player, {
		damage = hit.damage,
		fromPosition = hit.fromPosition,
		isProjectile = false,
		blockPierce = hit.blockPierce or 0,
		knockback = hit.knockback,
		fromZombie = true,
		blockStops = hit.blockStops,
		knockbackIfBlocked = hit.knockbackIfBlocked,
		knockdownSeconds = hit.knockdownSeconds,
		slowSeconds = hit.slowSeconds,
		unblockable = not hit.blockable,
	})
	return dealt, blocked
end

-- Brief protection without a visible force field (after knockdowns and throws).
function PlayerCombatService.grantImmunity(player: Player, seconds: number)
	local state = getState(player)
	state.immuneUntil = math.max(state.immuneUntil, os.clock() + seconds)
end

-- A short, controlled knockdown (the client owns its physics and lies down at most
-- OttiBossConfig.MaxKnockdownSeconds), followed by brief recovery protection.
function PlayerCombatService.knockdown(player: Player, seconds: number)
	local duration = math.min(seconds, 1.2)
	setBlocking(player, false)
	local state = getState(player)
	state.knockedUntil = os.clock() + duration
	ComboValidationService.clear(player) -- a knockdown cancels any combo in progress
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Knockdown, duration)
	PlayerCombatService.grantImmunity(player, duration + 1)
end

-- Otti's grapple: no walking or jumping while held. Always paired with an unlock.
function PlayerCombatService.setControlLocked(player: Player, locked: boolean)
	local state = getState(player)
	state.controlLocked = locked
	if locked then
		setBlocking(player, false)
		state.actionToken += 1 -- a running move stops
	end
	updateWalkSpeed(player)
end

-- Slow (nets): sets, never stacks, always expires.
function PlayerCombatService.applySlow(player: Player, factor: number, seconds: number)
	local state = getState(player)
	state.slowFactor = math.clamp(factor, 0.3, 1)
	state.slowToken += 1
	local myToken = state.slowToken
	updateWalkSpeed(player)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Slowed, seconds)
	task.delay(seconds, function()
		if state.slowToken == myToken then
			state.slowFactor = 1
			updateWalkSpeed(player)
		end
	end)
end

function PlayerCombatService.setSpawnProtection(player: Player, seconds: number)
	getState(player).spawnProtectedUntil = os.clock() + seconds
	local character = player.Character
	if character then
		local field = Instance.new("ForceField")
		field.Visible = true
		field.Parent = character
		task.delay(seconds, function()
			field:Destroy()
		end)
	end
end

-- Clears blocking, slows, combos, busy time and cooldowns (entering/leaving matches, death).
function PlayerCombatService.resetCombatState(player: Player)
	local state = getState(player)
	setBlocking(player, false)
	state.controlLocked = false
	state.slowFactor = 1
	state.slowToken += 1
	state.actionToken += 1
	state.busyUntil = 0
	state.parryUntil = 0
	table.clear(state.cooldowns)
	ComboValidationService.clear(player)
	updateWalkSpeed(player)
end

------------------------------------------------------------------------------------------
-- Attack requests
------------------------------------------------------------------------------------------

-- Runs a validated move: cooldown/busy bookkeeping (server time only), feedback, execution.
local function runMove(player: Player, state: PlayerState, context: CombatRules.CombatContext, weapon: any, move: any, aim: unknown, comboName: string?, advanced: boolean)
	local character, _, root = CombatUtil.getLivingCharacter(player)
	if not character or not root then
		return
	end
	local now = os.clock()
	state.cooldowns[move.Id] = now + move.Cooldown -- the cooldown starts when the move executes
	state.busyUntil = now + move.Duration
	if state.blocking then
		setBlocking(player, false) -- a move lowers the shield
	end
	if move.CounterWindow then
		state.counterUntil = now + move.CounterWindow -- only the opening counter window, never the whole move
	end
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Action, if comboName then "Combo" else "Basic", move.Name, move.Cooldown, comboName)

	local aimPoint = root.Position + root.CFrame.LookVector * 50
	if typeof(aim) == "Vector3" and aim.X == aim.X and aim.Y == aim.Y and aim.Z == aim.Z and (aim - root.Position).Magnitude <= MAX_AIM_DISTANCE then
		aimPoint = aim
	end

	local sound = Instance.new("Sound")
	sound.SoundId = CombatConfig.SwingSoundId
	sound.Volume = 0.5
	sound.PlayOnRemove = true
	sound.Parent = root
	sound:Destroy()

	local basic = SpecialMoveDefinitions[weapon.Basic]
	local myToken = state.actionToken
	local shield = InventoryService.getActiveShield(player)
	local landed = SpecialMoveService.execute(move, {
		player = player,
		context = context,
		weaponId = weapon.Id,
		character = character,
		root = root,
		aimPoint = aimPoint,
		comboMultiplier = 1,
		bonusStagger = 0,
		bashMultiplier = if shield then shield.BashMultiplier else 1,
		basicDamage = if basic then basic.Damage else 20,
		basicRange = if basic then basic.Range else 7,
		fromCombo = comboName ~= nil or move.Kind == "Aerial",
		weaponModel = state.weaponModel,
		animate = function(anim: Anim, windUp: number, duration: number)
			animate(player, state, anim, windUp, duration)
		end,
		extendBusy = function(seconds: number)
			state.busyUntil = math.max(state.busyUntil, os.clock() + seconds) -- landing recovery
		end,
		stillValid = function()
			-- Cancelled by death, a state change, a knockdown or leaving the fight
			return state.actionToken == myToken and CombatRules.getContext(player) == context
		end,
		reject = function(reason: string)
			reject(player, reason)
		end,
	})
	if comboName and landed then
		-- Meaningful moments only: Otti reacts from the imperial box, and as a boss he learns patterns
		OttiSpectatorService.react(if advanced then "AdvancedCombo" else "Combo")
		OttiBossService.onPlayerCombo(player, comboName)
	elseif move.Kind == "Aerial" and landed and (move.Shockwave or 0) >= 7 then
		OttiSpectatorService.react("BigAerial")
	end
end

local function onActionRequest(player: Player, action: unknown, aim: unknown)
	if action ~= "Basic" and action ~= "Jump" and action ~= "Execute" then
		return
	end
	local state = getState(player)
	if not allowRequest(state, "action") then
		return
	end
	local context: CombatRules.CombatContext? = CombatRules.getContext(player)
	if not context then
		return -- lobby (outside training), spectators, defeated players: silently ignored
	end
	local character, _, root = CombatUtil.getLivingCharacter(player)
	if not character or not root then
		return
	end
	local now = os.clock()
	if state.controlLocked or now < state.knockedUntil then
		ComboValidationService.clear(player) -- held by Otti or knocked down: no inputs count
		return
	end
	if action == "Jump" then
		ComboValidationService.record(player, "J") -- only counts later if the server saw a real jump
		return
	end
	local weapon = InventoryService.getEquippedWeapon(player)
	if state.weaponId ~= weapon.Id or not state.weaponWeld or not state.weaponWeld.Parent then
		reject(player, "weapon not equipped")
		return
	end
	if now < state.spawnProtectedUntil then
		return -- spawn protection: no attacks either
	end

	if action == "Basic" then
		ComboValidationService.record(player, "A") -- every attack press is an A input
		if now < state.busyUntil or state.blocking then
			return -- still performing a move (no macro can skip attack timing) / shield raised
		end
		-- In the air (a real jump, once per jump): the weapon's aerial attack
		local moveId = if JumpAttackService.tryAerial(player) then weapon.Aerial else weapon.Basic
		local move = SpecialMoveDefinitions[moveId]
		if not move or now < (state.cooldowns[move.Id] or 0) then
			return
		end
		runMove(player, state, context :: CombatRules.CombatContext, weapon, move, aim, nil, false)
		return
	end

	-- Execute: resolve the buffered A / B / J sequence (waits briefly for a finishing move)
	local wait = state.busyUntil - now
	if wait > InputDefinitions.ExecuteGrace then
		ComboValidationService.clear(player)
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.ComboFail, "BUSY")
		return
	end
	local combo, reason = ComboValidationService.resolve(player, weapon.Id)
	if not combo then
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.ComboFail, if reason == "expired" then "TOO SLOW" else "NO COMBO")
		return
	end
	local move = SpecialMoveDefinitions[combo.Move]
	if not move then
		return
	end
	if now < (state.cooldowns[move.Id] or 0) then
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.ComboFail, "NOT READY")
		return
	end
	local myToken = state.actionToken
	task.delay(math.max(0, wait), function()
		if state.actionToken == myToken and CombatRules.getContext(player) == context and os.clock() >= state.busyUntil - 0.02 then
			runMove(player, state, context :: CombatRules.CombatContext, weapon, move, aim, combo.Name, combo.Advanced)
		end
	end)
end

------------------------------------------------------------------------------------------
-- Characters
------------------------------------------------------------------------------------------

local function removeRegeneration(character: Model)
	-- Roblox's default "Health" script regenerates players; the project override with the same
	-- name is empty. Either way, nothing named Health may run in the character.
	local function check(child: Instance)
		if child.Name == "Health" and child:IsA("Script") then
			child:Destroy()
		end
	end
	for _, child in character:GetChildren() do
		check(child)
	end
	local connection = character.ChildAdded:Connect(check)
	task.delay(5, function()
		connection:Disconnect()
	end)
end

local function onCharacterAdded(player: Player, character: Model)
	local state = getState(player)
	state.blocking = false
	state.blockToken += 1
	state.slowFactor = 1
	state.slowToken += 1
	state.actionToken += 1
	state.busyUntil = 0
	state.lastHitTaken = 0
	state.parryUntil = 0
	state.controlLocked = false
	ComboValidationService.clear(player)
	removeRegeneration(character)

	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		warn(PREFIX, "No Humanoid for", player.Name, "- equipment not attached")
		return
	end
	humanoid.MaxHealth = CombatConfig.PlayerMaxHealth
	humanoid.Health = CombatConfig.PlayerMaxHealth
	humanoid.WalkSpeed = CombatConfig.PlayerWalkSpeed
	humanoid.Died:Connect(function()
		state.actionToken += 1
		setBlocking(player, false)
		ComboValidationService.clear(player)
	end)

	character:WaitForChild("RightHand", 1)
	character:WaitForChild("LeftHand", 1)
	PlayerCombatService.refreshEquipment(player)
end

function PlayerCombatService.init()
	-- Jump tracking for aerial attacks and J combo inputs (only players who may fight)
	JumpAttackService.init(function(player: Player): boolean
		return CombatRules.getContext(player) ~= nil
	end)
	Remotes.CombatAction.OnServerEvent:Connect(onActionRequest)
	Remotes.ShieldBlock.OnServerEvent:Connect(onBlockRequest)

	-- PvP damage and slows from player attacks come through CombatTargets
	CombatTargets.setPlayerHandlers(function(victim: Player, attacker: Player, damage: number, info: CombatTargets.HitInfo)
		local dealt, blocked = receiveHit(victim, {
			damage = damage,
			fromPosition = info.fromPosition,
			isProjectile = info.isProjectile,
			blockPierce = 0,
			knockback = info.knockback,
			fromZombie = false,
			attacker = attacker,
			guardBreak = info.guardBreak,
			fromCombo = info.fromCombo,
			pvpCap = info.pvpCap,
		})
		return dealt, blocked
	end, PlayerCombatService.applySlow)

	local function setup(player: Player)
		InventoryService.publish(player)
		player:GetAttributeChangedSignal(Config.TeamAttribute):Connect(function()
			PlayerCombatService.applyTeamColor(player)
		end)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		ComboValidationService.clear(player)
	end)
end

return PlayerCombatService
