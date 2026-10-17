--!strict
-- Player equipment and authoritative player combat.
--   * Every character carries its equipped weapon (right hand) and shield (left hand), both
--     welded and visible at once (no Tools). The models come from EquipmentModels and the
--     loadout from InventoryService, so a client can't claim items it doesn't own.
--   * WeaponAttack(aimPoint): only fighters (GameStates.isFighter) can deal damage. The server
--     validates alive, equipment, not blocking and the weapon cooldown, then
--       melee: picks the closest living zombie inside the weapon's range and arc with line of sight
--       bow:   fires an arrow from the character's own position toward the aim point and
--              simulates it on the server (walls stop it; it only damages zombies)
--     Every attack can damage at most one zombie.
--   * ShieldBlock(boolean): a request; the server owns the block state, enforces a maximum
--     block duration and decides whether zombie hits are blocked (applyZombieHit).
--   * Zombie hits: 0.35 s immunity after a landed hit, shield reduction per shield, no regen.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local WeaponDefinitions = require(ReplicatedStorage.Shared.WeaponDefinitions)
local CombatUtil = require(script.Parent.CombatUtil)
local EquipmentModels = require(script.Parent.EquipmentModels)
local InventoryService = require(script.Parent.InventoryService)
local Remotes = require(script.Parent.Remotes)
local ZombieService = require(script.Parent.ZombieService)

type WeaponDefinition = WeaponDefinitions.WeaponDefinition
type Zombie = ZombieService.Zombie

local PREFIX = "[OttiArena][Server]"
local FACING_RETRY_SECONDS = 0.12 -- the client turns the character just before attacking
local MAX_AIM_DISTANCE = 400

-- Shield poses relative to the left hand's grip attachment (+Y forward when the arm hangs,
-- +Z up the arm, +X to the character's right).
local SHIELD_IDLE = CFrame.new(-0.45, 0.1, 0.7) * CFrame.Angles(0, 0, math.rad(90)) -- on the outer forearm
local SHIELD_BLOCK = CFrame.new(0.9, 1.4, 1.6) -- raised in front of the chest

type PlayerState = {
	weaponId: string?,
	shieldId: string?,
	weaponWeld: Weld?,
	shieldWeld: Weld?,
	weaponGrip: CFrame,
	shieldGrip: CFrame,
	shieldModel: Model?,
	lastAttack: number,
	blocking: boolean,
	blockToken: number,
	lastHitTaken: number,
	slowFactor: number,
	slowToken: number,
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
			shieldWeld = nil,
			weaponGrip = CFrame.identity,
			shieldGrip = CFrame.identity,
			shieldModel = nil,
			lastAttack = 0,
			blocking = false,
			blockToken = 0,
			lastHitTaken = 0,
			slowFactor = 1,
			slowToken = 0,
			rejectLog = {},
		}
		states[player] = state
	end
	return state
end

local function isFighter(player: Player): boolean
	return GameStates.isFighter(player:GetAttribute(GameStates.StateAttribute))
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
	if state.blocking then
		speed = CombatConfig.BlockingWalkSpeed * InventoryService.getEquippedShield(player).BlockSpeedMultiplier
	end
	humanoid.WalkSpeed = speed * state.slowFactor
end

------------------------------------------------------------------------------------------
-- Equipment in the hands
------------------------------------------------------------------------------------------

-- R15 hands or R6 arms with their grip attachments (fallback: a sensible grip offset).
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
	model.Parent = character
	return weld
end

-- Rebuilds the weapon and shield models in the current character's hands from the inventory.
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
	state.weaponWeld = nil
	state.shieldWeld = nil
	state.shieldModel = nil
	state.weaponId = nil
	state.shieldId = nil

	local rightHand, rightGrip = getGrip(character, "RightHand", "Right Arm", "RightGripAttachment")
	local leftHand, leftGrip = getGrip(character, "LeftHand", "Left Arm", "LeftGripAttachment")
	if not rightHand or not leftHand then
		warn(PREFIX, "Could not find hands for", player.Name, "- equipment not attached")
		return
	end

	local weapon = InventoryService.getEquippedWeapon(player)
	local shield = InventoryService.getEquippedShield(player)
	local weaponModel, weaponCore = EquipmentModels.buildWeapon(weapon.Id)
	local shieldModel, shieldCore = EquipmentModels.buildShield(shield.Id)
	weaponModel:SetAttribute("OttiEquipment", true)
	shieldModel:SetAttribute("OttiEquipment", true)

	local shieldSound = Instance.new("Sound")
	shieldSound.Name = "BlockSound"
	shieldSound.SoundId = CombatConfig.ShieldSoundId
	shieldSound.Volume = 0.6
	shieldSound.Parent = shieldCore

	state.weaponGrip = rightGrip
	state.shieldGrip = leftGrip
	state.weaponWeld = attach(weaponModel, weaponCore, rightHand, rightGrip * EquipmentModels.weaponRestPose(weapon.Id), character)
	state.shieldWeld = attach(shieldModel, shieldCore, leftHand, leftGrip * (if state.blocking then SHIELD_BLOCK else SHIELD_IDLE), character)
	state.shieldModel = shieldModel
	state.weaponId = weapon.Id
	state.shieldId = shield.Id
end

------------------------------------------------------------------------------------------
-- Blocking
------------------------------------------------------------------------------------------

local function setBlocking(player: Player, active: boolean)
	local state = getState(player)
	if state.blocking == active then
		return
	end
	state.blocking = active
	state.blockToken += 1
	updateWalkSpeed(player)

	local weld = state.shieldWeld
	if weld and weld.Parent then
		local goal = { C0 = state.shieldGrip * (if active then SHIELD_BLOCK else SHIELD_IDLE) }
		TweenService:Create(weld, TweenInfo.new(0.1), goal):Play()
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
	if wantsBlock then
		local _, humanoid = CombatUtil.getLivingCharacter(player)
		local state = getState(player)
		if not humanoid or not state.shieldWeld or not state.shieldWeld.Parent then
			return
		end
		if state.shieldId ~= InventoryService.getEquippedShield(player).Id then
			return -- the shield in the hand must be the owned, equipped one
		end
	end
	setBlocking(player, wantsBlock)
end

local function shieldFeedback(state: PlayerState)
	local shield = state.shieldModel
	if not shield or not shield.Parent then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.2
	highlight.OutlineTransparency = 1
	highlight.Parent = shield
	task.delay(0.15, function()
		highlight:Destroy()
	end)
	local core = shield.PrimaryPart
	local sound = core and core:FindFirstChild("BlockSound")
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

-- True if the player is blocking and the position is in front of them (used by the zombie AI).
function PlayerCombatService.isBlockingToward(player: Player, position: Vector3): boolean
	local state = states[player]
	local _, _, root = CombatUtil.getLivingCharacter(player)
	return state ~= nil and state.blocking and root ~= nil and CombatUtil.isFacing(root.CFrame, position, CombatConfig.ShieldFacingDot)
end

-- A zombie blow lands: applies immunity, shield reduction and damage.
-- Returns landed, blocked, staggerMultiplier (for pushing the zombie back).
function PlayerCombatService.applyZombieHit(player: Player, attackerPosition: Vector3, damage: number): (boolean, boolean, number)
	if not isFighter(player) then
		return false, false, 1 -- lobby players and spectators can't be hurt
	end
	local _, humanoid, root = CombatUtil.getLivingCharacter(player)
	if not humanoid or not root then
		return false, false, 1
	end
	local state = getState(player)
	local now = os.clock()
	if now - state.lastHitTaken < CombatConfig.HitImmunitySeconds then
		return false, false, 1 -- brief immunity: no burst damage from several zombies at once
	end

	local shield = InventoryService.getEquippedShield(player)
	local blocked = state.blocking
		and state.shieldId == shield.Id
		and CombatUtil.flatDistance(root.Position, attackerPosition) <= CombatConfig.ShieldBlockDistance
		and CombatUtil.isFacing(root.CFrame, attackerPosition, CombatConfig.ShieldFacingDot)
	local finalDamage = damage
	if blocked then
		finalDamage = math.max(1, math.floor(damage * (1 - shield.Reduction) + 0.5))
		shieldFeedback(state)
	end

	state.lastHitTaken = now
	humanoid:TakeDamage(finalDamage)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.PlayerHit, finalDamage, blocked)
	return true, blocked, if blocked then shield.StaggerMultiplier else 1
end

-- Net slow: sets (never stacks) a speed multiplier for a few seconds.
function PlayerCombatService.applySlow(player: Player, factor: number, seconds: number)
	if not isFighter(player) then
		return
	end
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

-- Clears blocking and slows (used when entering/leaving the arena).
function PlayerCombatService.resetCombatState(player: Player)
	local state = getState(player)
	setBlocking(player, false)
	state.slowFactor = 1
	state.slowToken += 1
	state.lastAttack = 0
	updateWalkSpeed(player)
end

------------------------------------------------------------------------------------------
-- Attacks
------------------------------------------------------------------------------------------

local function playSwingSound(character: Model)
	local sound = Instance.new("Sound")
	sound.SoundId = CombatConfig.SwingSoundId
	sound.Volume = 0.5
	sound.PlayOnRemove = true
	sound.Parent = character.PrimaryPart or character
	sound:Destroy()
end

local function playAttackMotion(state: PlayerState, weapon: WeaponDefinition)
	local weld = state.weaponWeld
	if not weld or not weld.Parent then
		return
	end
	local grip = state.weaponGrip
	local rest = grip * EquipmentModels.weaponRestPose(weapon.Id)
	local windup: CFrame, strike: CFrame, strikeTime: number, returnDelay: number
	if weapon.Kind == "Bow" then
		windup = rest * CFrame.new(0, -0.5, 0) -- draw
		strike = rest * CFrame.new(0, 0.2, 0) -- release
		strikeTime, returnDelay = 0.06, 0.2
	elseif weapon.Id == "MorningStar" then
		windup = grip * CFrame.Angles(math.rad(135), math.rad(35), 0)
		strike = grip * CFrame.Angles(math.rad(-50), math.rad(-40), 0)
		strikeTime, returnDelay = 0.18, 0.45
	else
		windup = grip * CFrame.Angles(math.rad(105), 0, 0)
		strike = grip * CFrame.Angles(math.rad(-25), 0, 0)
		strikeTime, returnDelay = 0.12, 0.3
	end
	weld.C0 = windup
	task.delay(0.08, function()
		TweenService:Create(weld, TweenInfo.new(strikeTime, Enum.EasingStyle.Quad), { C0 = strike }):Play()
	end)
	task.delay(returnDelay, function()
		TweenService:Create(weld, TweenInfo.new(0.2), { C0 = rest }):Play()
	end)
end

local function hitZombie(player: Player, zombie: Zombie, weapon: WeaponDefinition, fromPosition: Vector3)
	if ZombieService.tryGuardBlock(zombie, fromPosition) then
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Hit, zombie.model, 0, true)
		return
	end
	if ZombieService.applyDamage(zombie, player, weapon.Damage, fromPosition, weapon.Stagger, weapon.Knockback) then
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Hit, zombie.model, weapon.Damage, false)
	else
		reject(player, "target dead")
	end
end

-- Closest valid living zombie in the weapon's range and arc, or the reason the closest one failed.
local function findMeleeTarget(character: Model, root: BasePart, weapon: WeaponDefinition): (Zombie?, string?)
	local best: Zombie? = nil
	local bestDistance = math.huge
	local closestReason, closestDistance = "invalid target (no living zombie)", math.huge

	for _, model in CollectionService:GetTagged(CombatConfig.ZombieTag) do
		local zombie = ZombieService.getByModel(model)
		local reason: string? = nil
		local distance = math.huge
		if not zombie then
			reason = "target dead"
		else
			local target = zombie.root.Position
			-- Measure to the zombie's body surface, so big zombies are as easy to reach as small ones
			distance = math.max(0, CombatUtil.flatDistance(root.Position, target) - zombie.root.Size.X / 2)
			if distance > weapon.Range or math.abs(root.Position.Y - target.Y) > 7 then
				reason = ("out of range (%.1f studs)"):format(distance)
			elseif not CombatUtil.isFacing(root.CFrame, target, weapon.FacingDot) then
				reason = "invalid facing direction"
			elseif not CombatUtil.hasLineOfSight(root.Position, target, { character, zombie.model.Parent or zombie.model }) then
				reason = "blocked line of sight"
			end
		end
		if reason == nil then
			if distance < bestDistance then
				best, bestDistance = zombie, distance
			end
		elseif distance < closestDistance then
			closestReason, closestDistance = reason, distance
		end
	end

	if best then
		return best, nil
	end
	return nil, closestReason
end

local function meleeAttack(player: Player, character: Model, root: BasePart, weapon: WeaponDefinition)
	local zombie, reason = findMeleeTarget(character, root, weapon)
	if not zombie and reason == "invalid facing direction" then
		-- The client turned the character toward the cursor right before sending; give
		-- that rotation a moment to replicate, then validate everything again once.
		task.wait(FACING_RETRY_SECONDS)
		local newCharacter, _, newRoot = CombatUtil.getLivingCharacter(player)
		if not newCharacter or not newRoot or not isFighter(player) then
			return
		end
		character, root = newCharacter, newRoot
		zombie, reason = findMeleeTarget(character, root, weapon)
	end
	if not zombie then
		reject(player, reason or "invalid target")
		return
	end
	hitZombie(player, zombie, weapon, root.Position)
end

-- Server-simulated arrow: moves along a straight line, raycasting each step. Stops at the first
-- solid hit (walls, barrier, zombie body); only living zombies take damage; one hit maximum.
local function fireArrow(player: Player, character: Model, root: BasePart, weapon: WeaponDefinition, aim: Vector3)
	local head = character:FindFirstChild("Head")
	local origin = if head and head:IsA("BasePart") then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	local offset = aim - origin
	local direction = if offset.Magnitude > 2 then offset.Unit else root.CFrame.LookVector
	local flatDirection = CombatUtil.flat(direction)
	if flatDirection.Magnitude > 0.05 then
		origin += flatDirection.Unit * 1.2 -- start just in front of the player
	end

	local arrow, shaft = EquipmentModels.buildArrow()
	shaft.CFrame = CFrame.lookAt(origin, origin + direction)
	arrow.Parent = Workspace

	local ignore: { Instance } = { arrow }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character) -- arrows never interact with players
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local speed = weapon.ProjectileSpeed or 110
	local traveled = 0
	local position = origin
	local connection: RBXScriptConnection? = nil
	local finished = false

	local function finish()
		if finished then
			return
		end
		finished = true
		if connection then
			connection:Disconnect()
		end
		task.delay(0.15, function()
			arrow:Destroy()
		end)
	end

	connection = RunService.Heartbeat:Connect(function(dt: number)
		local step = math.min(speed * dt, weapon.Range - traveled)
		if step <= 0 then
			finish()
			return
		end
		local result = Workspace:Raycast(position, direction * step, params)
		if result then
			shaft.CFrame = CFrame.lookAt(result.Position, result.Position + direction)
			local model = result.Instance:FindFirstAncestorOfClass("Model")
			local zombie = if model and CollectionService:HasTag(model, CombatConfig.ZombieTag) then ZombieService.getByModel(model) else nil
			if zombie and isFighter(player) then
				hitZombie(player, zombie, weapon, origin)
			end
			finish()
			return
		end
		position += direction * step
		traveled += step
		shaft.CFrame = CFrame.lookAt(position, position + direction)
	end)
	task.delay(weapon.Range / speed + 0.5, finish) -- lifetime safeguard
end

local function onAttackRequest(player: Player, aim: unknown)
	if not isFighter(player) then
		return -- lobby players and spectators can't deal damage (silently ignored)
	end
	local state = getState(player)
	local character, _, root = CombatUtil.getLivingCharacter(player)
	if not character or not root then
		return
	end
	local weapon = InventoryService.getEquippedWeapon(player)
	if state.weaponId ~= weapon.Id or not state.weaponWeld or not state.weaponWeld.Parent then
		reject(player, "weapon not equipped")
		return
	end
	if state.blocking then
		return -- attacking while blocking is ignored by design
	end
	local now = os.clock()
	if now - state.lastAttack < weapon.Cooldown then
		reject(player, "cooldown")
		return
	end
	state.lastAttack = now -- the cooldown belongs to the player, not to any zombie

	playAttackMotion(state, weapon)
	playSwingSound(character)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Swing)

	if weapon.Kind == "Bow" then
		-- Validate the client's aim point: a finite position within a sane distance
		local aimPoint = root.Position + root.CFrame.LookVector * 50
		if typeof(aim) == "Vector3" and aim.X == aim.X and aim.Y == aim.Y and aim.Z == aim.Z and (aim - root.Position).Magnitude <= MAX_AIM_DISTANCE then
			aimPoint = aim
		end
		fireArrow(player, character, root, weapon, aimPoint)
	else
		meleeAttack(player, character, root, weapon)
	end
end

------------------------------------------------------------------------------------------
-- Characters
------------------------------------------------------------------------------------------

local function removeRegeneration(character: Model)
	-- Roblox's default "Health" script regenerates players; the project override with the
	-- same name is empty. Either way, nothing named Health may run in the character.
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
	state.lastAttack = 0
	state.lastHitTaken = 0
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
		setBlocking(player, false)
	end)

	-- Hands may load a moment after the character
	character:WaitForChild("RightHand", 1)
	character:WaitForChild("LeftHand", 1)
	PlayerCombatService.refreshEquipment(player)
	local weapon = InventoryService.getEquippedWeapon(player)
	local shield = InventoryService.getEquippedShield(player)
	print(PREFIX, ("Equipment granted to %s: %s + %s"):format(player.Name, weapon.DisplayName, shield.DisplayName))
end

function PlayerCombatService.init()
	Remotes.WeaponAttack.OnServerEvent:Connect(onAttackRequest)
	Remotes.ShieldBlock.OnServerEvent:Connect(onBlockRequest)

	local function setup(player: Player)
		InventoryService.publish(player)
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
	end)
end

return PlayerCombatService
