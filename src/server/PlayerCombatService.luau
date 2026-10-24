--!strict
-- Player equipment, defense and authoritative attack handling.
--   * Hands: the equipped weapon (right) and shield (left) are welded and visible together.
--     Twin daggers are two-handed: a second dagger replaces the shield and blocking becomes a
--     short parry. Models are always rebuilt from InventoryService (no client claims).
--   * CombatAction(action, payload): "Basic" (attack: the contextual chain, AttackSequenceService),
--     "SpecialStart" / "SpecialRelease" (hold-to-charge special, SpecialChargeDefinitions: the held
--     time is measured HERE), "Slide" (SlideService, no client sends it in Classic V2). The server
--     rate-limits, checks the combat context (CombatRules), alive, spawn protection, knockdown, busy
--     time, cooldowns and the Momentum cost of every tier and runs the move (SpecialMoveService).
--   * ShieldBlock(boolean): the toggled block state the client wants; the server owns block/parry
--     state, raise time and every reduction.
--   * Combat state is split, not one state machine: DEFENSE (blocking) and SPECIAL CHARGE
--     (chargeStart) may be active together; ATTACK (busyUntil / cooldowns) is separate.
--       ATTACK          drops the block, then attacks; never while charging
--       SPECIAL START   allowed while blocking; not during an attack or its cooldown
--       BLOCK toggle    allowed while charging (the defense stays fully effective)
--       SPECIAL RELEASE drops the block, then fires the reached tier
--       interruptions   death, respawn, knockdown, grab, match reset, a heavy UNBLOCKED hit
--   * Incoming damage (zombies and PvP) goes through here: spawn protection, immunity, shield
--     angle/reduction, parry, PvP caps, knockback and slows.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local DamageConfig = require(ReplicatedStorage.Shared.DamageConfig)
local BlockDefinitions = require(ReplicatedStorage.Shared.BlockDefinitions)
local PvPBalanceConfig = require(ReplicatedStorage.Shared.PvPBalanceConfig)
local ShieldDefenseConfig = require(ReplicatedStorage.Shared.ShieldDefenseConfig)
local SlideDefinitions = require(ReplicatedStorage.Shared.SlideDefinitions)
local SpecialChargeDefinitions = require(ReplicatedStorage.Shared.SpecialChargeDefinitions)
local SpecialMoveDefinitions = require(ReplicatedStorage.Shared.SpecialMoveDefinitions)
local AttackSequenceService = require(script.Parent.AttackSequenceService)
local CombatEffects = require(script.Parent.CombatEffects)
local CrowdReactionService = require(script.Parent.CrowdReactionService)
local CombatRules = require(script.Parent.CombatRules)
local CombatTargets = require(script.Parent.CombatTargets)
local CombatUtil = require(script.Parent.CombatUtil)
local DamageEffectsService = require(script.Parent.DamageEffectsService)
local EquipmentModels = require(script.Parent.EquipmentModels)
local InventoryService = require(script.Parent.InventoryService)
local JumpAttackService = require(script.Parent.JumpAttackService)
local MomentumService = require(script.Parent.MomentumService)
local OttiBossService = require(script.Parent.OttiBossService)
local OttiSpectatorService = require(script.Parent.OttiSpectatorService)
local Remotes = require(script.Parent.Remotes)
local SpecialMoveService = require(script.Parent.SpecialMoveService)
local SlideService = require(script.Parent.SlideService)
local TrainingService = require(script.Parent.TrainingService)

type Anim = SpecialMoveDefinitions.Anim

local PREFIX = "[OttiArena][Server]"
local MAX_AIM_DISTANCE = 400
-- Hit reactions: a heavy unblocked hit of at least this share of max health makes the player lose
-- balance briefly (walk speed x FACTOR for SECONDS), at most once per COOLDOWN (no stun-lock).
local BALANCE_LOSS_SHARE = 0.08
local BALANCE_LOSS_FACTOR = 0.55
local BALANCE_LOSS_SECONDS = 0.4
local BALANCE_LOSS_COOLDOWN = 1.5

-- Poses relative to the hand's grip attachment (+Y forward when the arm hangs, +Z up the arm).
-- Fixed hand-local grip: the body joints raise and turn the shield, never its weld.
local SHIELD_GRIP = CFrame.new(0, -0.22, 0)
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
	counterReadyUntil: number, -- after a perfect block: the next attack is a PARRY COUNTER
	committedUntil: number, -- a committed special: no slide out of it
	heavyReactUntil: number, -- pushed back by a heavy blow on the shield
	lastHitReact: number,
	chargeStart: number, -- SPECIAL CHARGE: os.clock() of the start, 0 = not charging
	chargeToken: number,
	balanceFactor: number, -- brief loss of balance after a heavy unblocked hit (1 = none)
	balanceToken: number,
	lastBalanceLoss: number,
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
			counterReadyUntil = 0,
			committedUntil = 0,
			heavyReactUntil = 0,
			lastHitReact = 0,
			chargeStart = 0,
			chargeToken = 0,
			balanceFactor = 1,
			balanceToken = 0,
			lastBalanceLoss = -100,
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

-- 0 when the guard just came up, 1 once BLOCK has been held for BlockDefinitions.BraceSeconds
local function braceLevel(state: PlayerState, now: number): number
	if not state.blocking then
		return 0
	end
	return math.clamp((now - state.blockStart) / BlockDefinitions.BraceSeconds, 0, 1)
end

local function updateWalkSpeed(player: Player)
	local _, humanoid = CombatUtil.getLivingCharacter(player)
	if not humanoid then
		return
	end
	local state = getState(player)
	local factor = 1
	local shield = InventoryService.getActiveShield(player)
	if state.blocking and shield then
		-- about 65 % with the guard up; light shields a little faster, heavy ones a little slower
		factor = ShieldDefenseConfig.BlockWalkFactor * (0.5 + 0.5 * shield.BlockSpeedMultiplier)
		-- the longer the brace, the slower the steps
		factor *= 1 - braceLevel(state, os.clock()) * (1 - BlockDefinitions.BraceWalkFactor)
	end
	if state.chargeStart > 0 then
		-- charging a special: the stronger of the two slow-downs applies (never multiplied)
		factor = math.min(factor, SpecialChargeDefinitions.ChargeMoveFactor)
	end
	local speed = CombatConfig.PlayerWalkSpeed * factor
	speed *= 1 - math.clamp(InventoryService.getEquippedArmor(player).MovePenalty, 0, 0.5) -- heavier armor, slower steps
	humanoid.WalkSpeed = if state.controlLocked then 0 else speed * state.slowFactor * state.balanceFactor
	humanoid.JumpPower = if state.controlLocked then 0 else 50
	humanoid.UseJumpPower = true
end

-- Ends a special charge without firing (interruption, death, reset). `reason` is shown briefly.
local function cancelCharge(player: Player, reason: string?)
	local state = getState(player)
	if state.chargeStart <= 0 then
		return
	end
	state.chargeStart = 0
	state.chargeToken += 1
	local character = player.Character
	if character then
		character:SetAttribute("SpecialChargeStart", nil)
	end
	updateWalkSpeed(player)
	if player.Parent then
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.SpecialCharge, "cancel", reason)
	end
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
	AttackSequenceService.reset(player) -- weapon changes reset the attack chain

	if shield then
		local shieldModel, shieldCore = EquipmentModels.buildShield(shield.Id)
		local sound = Instance.new("Sound")
		sound.Name = "BlockSound"
		sound.SoundId = CombatConfig.ShieldSoundId
		sound.Volume = 0.6
		sound.Parent = shieldCore
		state.offhandWeld = attach(shieldModel, shieldCore, leftHand, leftGrip * SHIELD_GRIP, character)
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
-- Replicated presentation cues. Equipment welds stay fixed at their hand attachments.
------------------------------------------------------------------------------------------

-- PlayerAnimator owns the complete body motion on every client. Never translate equipment
-- away from its grip to fake a strike. Capture this attack's timestamp to retire old trail work.
local function animate(player: Player, state: PlayerState, anim: Anim, windUp: number, duration: number, tier: number?)
	local character = player.Character
	local started = Workspace:GetServerTimeNow()
	if character then
		character:SetAttribute("AttackAnim", anim)
		character:SetAttribute("AttackStart", started)
		character:SetAttribute("AttackWind", windUp)
		character:SetAttribute("AttackLength", duration)
		character:SetAttribute("AttackTier", tier or 0)
	end
	local trail = state.trail
	if trail then
		trail.Enabled = false
	end
	local function current(): boolean
		return player.Character == character and character ~= nil and character.Parent ~= nil
			and character:GetAttribute("AttackStart") == started and state.trail == trail
	end
	task.delay(windUp, function()
		if current() and trail and trail.Parent and anim ~= "Draw" and anim ~= "Guard" then
			trail.Enabled = true
		end
	end)
	task.delay(math.max(windUp + 0.15, duration * 0.85), function()
		if current() and trail and trail.Parent then
			trail.Enabled = false
		end
	end)
end

------------------------------------------------------------------------------------------
-- Blocking and parrying
------------------------------------------------------------------------------------------

-- Moves the shield up, slows the walk and publishes BraceLevel while the guard is held
local function applyBrace(player: Player, state: PlayerState)
	local brace = braceLevel(state, os.clock())
	local character = player.Character
	if character then
		character:SetAttribute("BraceLevel", brace)
	end
	updateWalkSpeed(player)
end

-- Keeps the brace growing for as long as this guard is up (ends with the guard or a new block)
local function startBraceLoop(player: Player, token: number)
	task.spawn(function()
		while true do
			local state = states[player]
			if not state or not state.blocking or state.blockToken ~= token or not player.Parent then
				break
			end
			applyBrace(player, state)
			task.wait(BlockDefinitions.BraceTick)
		end
	end)
end

local function setBlocking(player: Player, active: boolean)
	local state = getState(player)
	if state.blocking == active then
		return
	end
	state.blocking = active
	state.blockToken += 1
	state.blockStart = os.clock()
	updateWalkSpeed(player)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Block, active)
	local character = player.Character
	if character then
		-- Every client shows the block pose (BlockAnimation layer in PlayerAnimator)
		character:SetAttribute("Blocking", active)
		if active then
			character:SetAttribute("BlockPose", "Front")
		else
			character:SetAttribute("BraceLevel", 0)
		end
	end
	if active and state.shieldId then
		startBraceLoop(player, state.blockToken)
	end
	-- Toggle block: it stays up until BLOCK is pressed again, ATTACK, a fired special, a slide,
	-- a guard break, a knockdown, a grab, death or a reset lowers it (no timeout)
end

-- The guard can't come up right now: tell the client so its toggle shows "off" again.
local function refuseBlock(player: Player)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Block, false)
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
		refuseBlock(player)
		return
	end
	local now = os.clock()
	if now < state.heavyReactUntil then
		refuseBlock(player)
		return -- pushed back by a heavy blow: the guard comes up again a moment later
	end
	if state.shieldId == nil then
		-- Twin daggers: a short parry window on a cooldown instead of a held block
		if now >= state.parryReadyAt then
			state.parryUntil = now + CombatConfig.ParryWindowSeconds
			state.parryReadyAt = now + CombatConfig.ParryCooldownSeconds
			local character = player.Character
			if character then
				character:SetAttribute("ParryPoseAt", Workspace:GetServerTimeNow())
			end
			Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Parry)
		end
		refuseBlock(player) -- daggers parry; there is no held guard to show
		return
	end
	local activeShield = InventoryService.getActiveShield(player)
	if activeShield == nil or state.shieldId ~= activeShield.Id then
		refuseBlock(player)
		return -- the shield in the hand must be the owned, equipped one
	end
	if now < state.blockLockedUntil then
		refuseBlock(player)
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
	height: string?, -- Low | Mid | High: block pose (and what a slide can duck under)
	heavy: boolean?, -- heavy blow: heavy block reaction, pushes through the guard a little
	training: boolean?, -- training dummy swing: evaluate block / parry / dodge, never damage
	undodgeable: boolean?,
}

-- Where a hit comes from, seen from the defender (server-side, ShieldDefenseConfig):
-- "Front" (inside the shield's block angle), "ShieldSide" (left), "WeaponSide" (right) or "Back".
local function defenseZone(root: BasePart, fromPosition: Vector3, shield: any): string
	local toAttacker = CombatUtil.flat(fromPosition - root.Position)
	if toAttacker.Magnitude < 0.1 then
		return "Front"
	end
	local direction = toAttacker.Unit
	local look = CombatUtil.flat(root.CFrame.LookVector)
	local lookDot = if look.Magnitude > 0.01 then direction:Dot(look.Unit) else 1
	if lookDot >= shield.FacingDot then
		return "Front"
	elseif lookDot <= ShieldDefenseConfig.BackDot then
		return "Back"
	end
	local shieldSide = -CombatUtil.flat(root.CFrame.RightVector) -- the shield is on the left arm
	if shieldSide.Magnitude > 0.01 and direction:Dot(shieldSide.Unit) >= ShieldDefenseConfig.SideDot then
		return "ShieldSide"
	end
	return "WeaponSide"
end

-- Which block pose meets this attack (BlockDefinitions).
local function blockPose(root: BasePart, incoming: Incoming): string
	if incoming.height == "High" then
		return "High"
	elseif incoming.height == "Low" then
		return "Low"
	end
	local toAttacker = CombatUtil.flat(incoming.fromPosition - root.Position)
	if toAttacker.Magnitude > 0.1 then
		local side = toAttacker.Unit:Dot(CombatUtil.flat(root.CFrame.RightVector))
		if side > BlockDefinitions.SideThresholdDot then
			return "Right"
		elseif side < -BlockDefinitions.SideThresholdDot then
			return "Left"
		end
	end
	return "Front"
end

-- Replicated block presentation for every client (pose + impact).
local function publishBlockImpact(character: Model, pose: string, heavy: boolean, perfect: boolean)
	character:SetAttribute("BlockPose", pose)
	character:SetAttribute("BlockImpactAt", Workspace:GetServerTimeNow())
	character:SetAttribute("BlockImpactHeavy", heavy)
	character:SetAttribute("BlockPerfect", perfect)
end

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
	local character = root.Parent :: Model

	-- Slide dodge: only the short window at the start of a slide (never the whole slide)
	if not incoming.undodgeable then
		local dodged = SlideService.tryDodge(victim)
		if dodged then
			Remotes.CombatFeedback:FireClient(victim, CombatConfig.Feedback.Dodge)
			return 0, false, 1
		end
	end

	-- 2./3. Base damage (mode multipliers were applied by the attack itself)
	local baseDamage = math.max(0, incoming.damage)
	local shieldMultiplier = 1
	local stopped = false -- a facing shield stops everything (Otti's bite, a perfect block)
	local blocked = false
	local perfect = false
	local stagger = 1
	local shield = InventoryService.getActiveShield(victim)
	-- 4. Shield defense by hit direction (ShieldDefenseConfig): front / shield side / weapon side /
	-- back, passive while the shield is only carried, stronger with the guard up
	if incoming.unblockable then
		-- grapples can't be blocked
	elseif shield and state.shieldId == shield.Id then
		local zone = defenseZone(root, incoming.fromPosition, shield)
		local raised = state.blocking and now - state.blockStart >= shield.RaiseSeconds
		local inRange = incoming.isProjectile or CombatUtil.flatDistance(root.Position, incoming.fromPosition) <= CombatConfig.ShieldBlockDistance
		local active = raised and inRange
		local base = if active then ShieldDefenseConfig.Active[zone] else ShieldDefenseConfig.Passive[zone]
		if active and zone == "Front" then
			-- a longer brace stops more of the blows that hit the shield head-on
			base = (base or 0) + BlockDefinitions.BraceReductionBonus * braceLevel(state, now)
		end
		local quality = math.clamp(shield.Reduction / ShieldDefenseConfig.ReferenceReduction, ShieldDefenseConfig.QualityMin, ShieldDefenseConfig.QualityMax)
		local projectileRatio = if incoming.isProjectile then shield.ProjectileReduction / math.max(0.01, shield.Reduction) else 1
		local reduction = math.clamp((base or 0) * quality * projectileRatio, 0, ShieldDefenseConfig.MaxReduction) * (1 - incoming.blockPierce)
		if active and zone == "Front" then
			if incoming.guardBreak then
				-- The guard breaks: half protection, the shield drops and stays down briefly
				reduction *= 0.5
				setBlocking(victim, false)
				state.blockLockedUntil = now + PvPBalanceConfig.GuardBreakShieldLock
				CombatEffects.burst(root.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 150, 80), 1)
			elseif now - state.blockStart <= BlockDefinitions.PerfectWindow + shield.RaiseSeconds then
				-- PERFECT BLOCK: raised just before the blow (server time only)
				perfect = true
			end
			shieldMultiplier = 1 - reduction
			stopped = incoming.blockStops == true or perfect
			blocked = not incoming.guardBreak
			stagger = if perfect then 2.5 else shield.StaggerMultiplier
			shieldFeedback(state)
		elseif reduction > 0 then
			-- a side hit on the shield: partial protection only (active guard = still a block)
			shieldMultiplier = 1 - reduction
			blocked = active
			if active then
				stagger = shield.StaggerMultiplier * 0.6
				shieldFeedback(state)
			end
		end
	elseif state.shieldId == nil and now < state.parryUntil and CombatUtil.isFacing(root.CFrame, incoming.fromPosition, 0) then
		-- Twin daggers: the parry is timing-based, so it counts as a perfect deflection
		shieldMultiplier = 1 - CombatConfig.ParryReduction
		stopped = incoming.blockStops == true
		blocked = true
		perfect = true
		stagger = 1.8
		CombatEffects.burst(root.Position + Vector3.new(0, 1, 0), Color3.fromRGB(200, 230, 255), 0.8)
		Remotes.CombatFeedback:FireClient(victim, CombatConfig.Feedback.Parry)
	end
	if blocked then
		local heavy = incoming.heavy == true and not perfect
		publishBlockImpact(character, blockPose(root, incoming), heavy, perfect)
		local shieldPoint = root.Position + CombatUtil.flat(incoming.fromPosition - root.Position).Unit * 1.4 + Vector3.new(0, 0.6, 0)
		DamageEffectsService.hit("Block", shieldPoint, if heavy then 1.3 elseif perfect then 1.1 else 0.7, CombatUtil.flat(root.Position - incoming.fromPosition), {
			perfect = perfect,
			heavy = heavy,
			projectile = incoming.isProjectile,
			victimId = victim.UserId,
		})
		if perfect then
			state.counterReadyUntil = now + BlockDefinitions.CounterWindow
			Remotes.CombatFeedback:FireClient(victim, CombatConfig.Feedback.PerfectBlock)
			-- The attacker recoils (players: a short forced pause; zombies: the returned stagger)
			local attacker = incoming.attacker
			local attackerState = attacker and states[attacker]
			if attacker and attackerState then
				attackerState.busyUntil = math.max(attackerState.busyUntil, now + BlockDefinitions.PerfectRecoil)
				Remotes.CombatFeedback:FireClient(attacker, CombatConfig.Feedback.ComboFail, "PARRIED")
			end
		else
			if heavy then
				-- Heavy blow on the shield: pushed back a step, no slide / attack / re-raise for a moment
				state.heavyReactUntil = now + BlockDefinitions.HeavyReactionSeconds
				incoming.knockback = math.max(incoming.knockback, BlockDefinitions.HeavyKnockback)
				incoming.knockbackIfBlocked = true
			end
		end
	end
	if incoming.training then
		-- Training dummy swing: show the result, never deal damage
		local text = if perfect then "PERFECT BLOCK!" elseif blocked then "BLOCKED" else "HIT — raise the shield just before the swing"
		Remotes.CombatFeedback:FireClient(victim, CombatConfig.Feedback.Shop, text, blocked)
		return 0, blocked, stagger
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
		DamageEffectsService.hit("Player", root.Position + Vector3.new(0, 0.8, 0), math.clamp(damage / 15, 0.4, 1.4), CombatUtil.flat(root.Position - incoming.fromPosition), { victimId = victim.UserId })
		-- Hit reaction for every client: strength by damage share, weaker when hits come in quickly
		-- (frequent small zombie hits never lock the player's controls)
		local share = damage / math.max(1, humanoid.MaxHealth)
		if share >= 0.02 then
			local scale = math.clamp(share * 9, 0.2, 1)
			if now - state.lastHitReact < 0.6 then
				scale *= 0.5
			end
			state.lastHitReact = now
			local toAttacker = CombatUtil.flat(incoming.fromPosition - root.Position)
			local side = if toAttacker.Magnitude > 0.1 then toAttacker.Unit:Dot(CombatUtil.flat(root.CFrame.RightVector)) else 0
			character:SetAttribute("HitReactAt", Workspace:GetServerTimeNow())
			character:SetAttribute("HitReactScale", scale)
			character:SetAttribute("HitReactSide", side)
		end
	end
	if incoming.heavy and not blocked and state.chargeStart > 0 then
		cancelCharge(victim, "INTERRUPTED") -- a heavy hit that got through breaks the charge, even with the guard up
	end
	if incoming.heavy and not blocked and damage >= humanoid.MaxHealth * BALANCE_LOSS_SHARE and now - state.lastBalanceLoss >= BALANCE_LOSS_COOLDOWN then
		-- A short loss of balance (quiet slow-down), never chained into a stun-lock
		state.lastBalanceLoss = now
		state.balanceToken += 1
		local myToken = state.balanceToken
		state.balanceFactor = BALANCE_LOSS_FACTOR
		updateWalkSpeed(victim)
		task.delay(BALANCE_LOSS_SECONDS, function()
			if state.balanceToken == myToken then
				state.balanceFactor = 1
				updateWalkSpeed(victim)
			end
		end)
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
function PlayerCombatService.applyZombieHit(player: Player, attackerPosition: Vector3, damage: number, blockPierce: number, knockback: number, info: { height: string?, heavy: boolean? }?): (boolean, boolean, number)
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
		height = info and info.height,
		heavy = info and info.heavy,
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
	cancelCharge(player, "INTERRUPTED")
	local state = getState(player)
	state.knockedUntil = os.clock() + duration
	AttackSequenceService.reset(player) -- a knockdown resets the attack chain
	SlideService.cancel(player)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Knockdown, duration)
	PlayerCombatService.grantImmunity(player, duration + 1)
end

-- Otti's grapple: no walking or jumping while held. Always paired with an unlock.
function PlayerCombatService.setControlLocked(player: Player, locked: boolean)
	local state = getState(player)
	state.controlLocked = locked
	if locked then
		setBlocking(player, false)
		cancelCharge(player, "INTERRUPTED")
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
	cancelCharge(player, nil)
	state.controlLocked = false
	state.slowFactor = 1
	state.balanceFactor = 1
	state.balanceToken += 1
	state.slowToken += 1
	state.actionToken += 1
	state.busyUntil = 0
	state.parryUntil = 0
	table.clear(state.cooldowns)
	AttackSequenceService.reset(player)
	SlideService.cancel(player)
	state.counterReadyUntil = 0
	state.committedUntil = 0
	state.heavyReactUntil = 0
	updateWalkSpeed(player)
end

------------------------------------------------------------------------------------------
-- Attack requests
------------------------------------------------------------------------------------------

type RunKind = "Basic" | "Aerial" | "Slide" | "Counter" | "Special"

type RunOptions = {
	kind: RunKind,
	slot: string, -- contextual attack slot
	tier: number?, -- Specials: 1-3, 4 = Ultimate
	damageMultiplier: number?, -- Specials: the charge tier's PvE multiplier
	pvpScale: number?,
	cooldownKey: string?,
	cooldown: number?,
	extraRecovery: number?,
	label: string?, -- Specials: "GLADIATOR CLEAVE II"
}

-- Runs a validated move: cooldown/busy bookkeeping (server time only), feedback, execution.
local function runMove(player: Player, state: PlayerState, context: CombatRules.CombatContext, weapon: any, move: any, aim: unknown, options: RunOptions)
	local character, _, root = CombatUtil.getLivingCharacter(player)
	if not character or not root then
		return
	end
	local now = os.clock()
	local tier = options.tier or 0
	state.cooldowns[options.cooldownKey or move.Id] = now + (options.cooldown or move.Cooldown) -- starts when the move executes
	state.busyUntil = now + move.Duration + (options.extraRecovery or 0)
	if options.kind == "Special" then
		state.committedUntil = state.busyUntil -- no slide out of a committed special
	end
	if state.blocking then
		setBlocking(player, false) -- a move lowers the shield
	end
	if move.CounterWindow then
		state.counterUntil = now + move.CounterWindow -- only the opening counter window, never the whole move
	end
	local isSpecial = options.kind == "Special"
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Action, if isSpecial then "Special" else options.kind, move.Name, move.Cooldown, options.label)
	if move.Ultimate then
		-- Strong, readable telegraph: everyone sees where the Ultimate will land
		local feet = root.Position - Vector3.new(0, 2.6, 0)
		CombatEffects.groundMarker(feet + CombatUtil.flat(root.CFrame.LookVector) * 4, 10, move.WindUp + 0.6, Color3.fromRGB(255, 170, 60))
	end

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
		comboMultiplier = options.damageMultiplier or 1,
		pvpScale = options.pvpScale,
		bonusStagger = 0,
		bashMultiplier = if shield then shield.BashMultiplier else 1,
		basicDamage = if basic then basic.Damage else 20,
		basicRange = if basic then basic.Range else 7,
		fromCombo = isSpecial or move.Kind == "Aerial" or options.kind == "Slide",
		weaponModel = state.weaponModel,
		animate = function(anim: Anim, windUp: number, duration: number)
			animate(player, state, anim, windUp, duration, tier)
		end,
		extendBusy = function(seconds: number)
			state.busyUntil = math.max(state.busyUntil, os.clock() + seconds) -- landing recovery / missed heavy move
		end,
		stillValid = function()
			-- Cancelled by death, a state change, a knockdown or leaving the fight
			return state.actionToken == myToken and CombatRules.getContext(player) == context
		end,
		reject = function(reason: string)
			reject(player, reason)
		end,

	})
	if isSpecial and landed then
		-- Meaningful moments only: Otti reacts from the imperial box, as a boss he learns patterns,
		-- and the crowd cheers for the big ones (with cooldowns)
		OttiSpectatorService.react(if tier >= 3 then "AdvancedCombo" else "Combo")
		OttiBossService.onPlayerCombo(player, move.Name)
		if tier >= 3 then
			CrowdReactionService.majorMove(if tier == 4 then "Ultimate" else "Special")
		end
	elseif options.kind == "Counter" and landed then
		CrowdReactionService.majorMove("Counter")
	elseif move.Kind == "Aerial" and landed and (move.Shockwave or 0) >= 7 then
		OttiSpectatorService.react("BigAerial")
	end
end

-- The next normal attack from the context (AttackSequenceService). nil = nothing allowed now.
local function chooseNormal(player: Player, state: PlayerState, weapon: any, root: BasePart, gesture: string?): (any?, RunOptions?)
	local now = os.clock()
	local counter = now < state.counterReadyUntil
	local sliding = SlideService.isSliding(player)
	local slide = sliding and not counter and SlideService.consumeAttack(player)
	if sliding and counter then
		SlideService.consumeAttack(player) -- Perfect Block -> Slide -> Counter uses the slide's attack
	end
	local airborne = not counter and not slide and JumpAttackService.tryAerial(player)
	local choice = AttackSequenceService.choose(player, {
		weaponBasic = weapon.Basic,
		weaponAerial = weapon.Aerial,
		root = root,
		counter = counter,
		slide = slide,
		airborne = airborne,
		gesture = gesture,
	})
	if not choice then
		return nil, nil
	end
	local move = SpecialMoveDefinitions[choice.moveId]
	if not move then
		return nil, nil
	end
	if move.RequiresAir and not airborne then
		return nil, nil
	end
	if choice.kind == "Counter" then
		state.counterReadyUntil = 0 -- one counter per perfect block
	end
	return move, { kind = choice.kind, slot = choice.slot }
end

local SPECIAL_COOLDOWN_KEY = "Special"

-- SPECIAL START: begins a charge (allowed while blocking). Not during an attack or the cooldown.
local function startSpecial(player: Player, state: PlayerState)
	local now = os.clock()
	if state.chargeStart > 0 then
		return -- already charging (repeated presses can't restart or stack a charge)
	end
	if now < state.busyUntil - 0.1 or now < (state.cooldowns[SPECIAL_COOLDOWN_KEY] or 0) then
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.SpecialCharge, "cancel", "NOT READY")
		return
	end
	if MomentumService.get(player) < SpecialChargeDefinitions.Tiers[1].MomentumCost then
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.SpecialCharge, "cancel", "SPECIAL RECHARGING")
		return
	end
	state.chargeStart = now
	state.chargeToken += 1
	local myToken = state.chargeToken
	local character = player.Character
	if character then
		character:SetAttribute("SpecialChargeStart", Workspace:GetServerTimeNow()) -- every client shows the charge pose
	end
	updateWalkSpeed(player)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.SpecialCharge, "start")
	-- Safety: a charge that is never released ends by itself (no permanent slow-down)
	task.delay(SpecialChargeDefinitions.MaxHoldSeconds, function()
		if state.chargeToken == myToken and state.chargeStart > 0 then
			cancelCharge(player, nil)
		end
	end)
end

-- SPECIAL RELEASE: fires the tier reached by the SERVER-measured hold time; lowers the shield.
local function releaseSpecial(player: Player, state: PlayerState, context: CombatRules.CombatContext, weapon: any, aim: unknown)
	local now = os.clock()
	if state.chargeStart <= 0 then
		return -- nothing charging (a release without a start, or the charge was interrupted)
	end
	local held = now - state.chargeStart
	state.chargeStart = 0
	state.chargeToken += 1
	local character = player.Character
	if character then
		character:SetAttribute("SpecialChargeStart", nil)
	end
	updateWalkSpeed(player)
	local seconds = if held <= SpecialChargeDefinitions.StartLatency then 0 else held
	local tierDef, ultimate, cost = SpecialChargeDefinitions.forRelease(seconds, MomentumService.get(player))
	if not tierDef then
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.SpecialCharge, "cancel", "SPECIAL RECHARGING")
		return
	end
	local tier = tierDef.Tier
	local family = if ultimate then "Ultimate" else tierDef.Family
	local move = SpecialMoveDefinitions[SpecialChargeDefinitions.specialFor(nil, weapon.Basic, family) or ""]
	if not move then
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.SpecialCharge, "cancel", "NO SPECIAL")
		return
	end
	-- Charge only for a valid move; no yield between deduction and execution.
	if not MomentumService.trySpend(player, cost) then
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.SpecialCharge, "cancel", "SPECIAL RECHARGING")
		return
	end
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.SpecialCharge, "fire", tier)
	runMove(player, state, context, weapon, move, aim, {
		kind = "Special",
		slot = "Special" .. tierDef.Name,
		tier = if ultimate then 4 else tier,
		damageMultiplier = if ultimate then 1 else tierDef.DamageMultiplier,
		pvpScale = if ultimate then 1 else tierDef.PvPMultiplier,
		cooldownKey = SPECIAL_COOLDOWN_KEY,
		cooldown = if ultimate then SpecialChargeDefinitions.UltimateCooldown else tierDef.Cooldown,
		extraRecovery = if ultimate then 0 else tierDef.Recovery,
		label = if ultimate then move.Name else ("%s %s"):format(move.Name, tierDef.Name),
	})
end

-- CombatAction(action, payload):
--   "Basic"          (aim point)  attack: the contextual chain; drops an active block first
--   "SpecialStart"                start charging the special (block may stay up)
--   "SpecialRelease" (aim point)  fire the reached tier
--   "Slide"                       start a slide (not sent by the Classic V2 controls)
--   "Jump"                        legacy jump report (ignored: jumps are measured server-side)
local function onActionRequest(player: Player, action: unknown, payload: unknown)
	if action ~= "Basic" and action ~= "SpecialStart" and action ~= "SpecialRelease" and action ~= "Slide" and action ~= "Jump" then
		return
	end
	local state = getState(player)
	if action ~= "SpecialRelease" and not allowRequest(state, "action") then -- a release must never get lost (it only ends a running charge)
		return
	end
	local context: CombatRules.CombatContext? = CombatRules.getContext(player)
	if not context then
		if action == "SpecialRelease" then
			cancelCharge(player, nil) -- left the fight while charging
		end
		return -- lobby (outside training), spectators, defeated players: silently ignored
	end
	local character, _, root = CombatUtil.getLivingCharacter(player)
	if not character or not root then
		return
	end
	local now = os.clock()
	if state.controlLocked or now < state.knockedUntil then
		AttackSequenceService.reset(player) -- held by Otti or knocked down: the chain resets
		return
	end
	if action == "Jump" then
		return
	end

	if action == "Slide" then
		if now < state.busyUntil - 0.05 or now < state.committedUntil or now < state.heavyReactUntil then
			reject(player, "slide not possible right now")
			return
		end
		local direction, reason = SlideService.tryStart(player, JumpAttackService.isAirborne(player))
		if not direction then
			reject(player, "slide: " .. tostring(reason))
			return
		end
		setBlocking(player, false) -- Block -> Slide -> Attack: the guard drops for the slide
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Slide, direction, SlideDefinitions.Distance, SlideDefinitions.Duration)
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

	local aim: unknown = payload
	if action == "SpecialStart" then
		startSpecial(player, state)
		return
	elseif action == "SpecialRelease" then
		releaseSpecial(player, state, context :: CombatRules.CombatContext, weapon, aim)
		return
	end

	if now < state.busyUntil or state.chargeStart > 0 then
		return -- still performing a move (no macro can skip attack timing) / charging a special
	end
	local move, options = chooseNormal(player, state, weapon, root, nil)
	if not move or not options or now < (state.cooldowns[move.Id] or 0) then
		return
	end
	if state.blocking then
		setBlocking(player, false) -- ATTACK drops the guard right before the swing (no re-raise afterwards)
	end
	runMove(player, state, context :: CombatRules.CombatContext, weapon, move, aim, options)
end

-- Training dummy swing at a player (TrainingService): evaluates block / perfect block / dodge
-- exactly like a real attack, but never deals damage, Momentum or statistics.
function PlayerCombatService.trainingSwing(player: Player, fromPosition: Vector3, height: string?)
	receiveHit(player, {
		damage = 10,
		fromPosition = fromPosition,
		isProjectile = false,
		blockPierce = 0,
		knockback = 0,
		fromZombie = true,
		height = height,
		training = true,
	})
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
	state.chargeStart = 0
	state.chargeToken += 1
	state.slowFactor = 1
	state.balanceFactor = 1
	state.balanceToken += 1
	state.slowToken += 1
	state.actionToken += 1
	state.busyUntil = 0
	state.lastHitTaken = 0
	state.parryUntil = 0
	state.controlLocked = false
	AttackSequenceService.reset(player)
	SlideService.cancel(player)
	state.counterReadyUntil = 0
	state.committedUntil = 0
	state.heavyReactUntil = 0
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
		cancelCharge(player, nil)
		AttackSequenceService.reset(player)
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
		AttackSequenceService.forget(player)
		SlideService.forget(player)
	end)
	MomentumService.init()
	TrainingService.setSparringHandler(PlayerCombatService.trainingSwing)
end

return PlayerCombatService
