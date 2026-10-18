--!strict
-- Executes Otti's attacks from OttiMoveDefinitions, server-authoritatively:
--   wind-up (pose + telegraph, warning for major attacks) -> active window (validated volumes,
--   checked every server step, one hit per target per hit phase) -> recovery -> cooldown.
-- Validation per kind:
--   Melee      range from Otti, facing arc, height, line of sight (primary target only)
--   TailSweep  the swept sector behind Otti between two steps (OttiTailService), radius, not
--              airborne (jump over it); several players can be hit once each
--   TailSlam   ground marker during the wind-up; direct radius + shockwave with falloff, blocked
--              by solid cover between impact and player
--   Bite       short lunge (never through walls), reach + arc at the end; a facing shield stops it
--   RiverDash  curved four-legged run inside the arena; contact volume around the body
-- The visible tail never deals damage by touching anything. A cancelled/interrupted attack or a
-- defeated Otti never deals delayed damage (ctx.stillValid / boss.interrupted are re-checked).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AudioConfig = require(ReplicatedStorage.Shared.AudioConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local OttiBossConfig = require(ReplicatedStorage.Shared.OttiBossConfig)
local OttiMoveDefinitions = require(ReplicatedStorage.Shared.OttiMoveDefinitions)
local Arena = require(script.Parent.Arena)
local BossGrappleService = require(script.Parent.BossGrappleService)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatUtil = require(script.Parent.CombatUtil)
local OttiAnimationService = require(script.Parent.OttiAnimationService)
local OttiTailService = require(script.Parent.OttiTailService)

type Boss = OttiAnimationService.Boss
type BossContext = OttiAnimationService.BossContext
type OttiMove = OttiMoveDefinitions.OttiMove

local BossAttackService = {}

local function valid(boss: Boss, ctx: BossContext): boolean
	return ctx.stillValid() and not boss.interrupted and not boss.defeated
end

-- Waits `seconds` while optionally turning toward the target. False if the attack was cancelled.
local function windUp(boss: Boss, ctx: BossContext, seconds: number, target: Player?, turn: boolean): boolean
	local elapsed = 0
	while elapsed < seconds do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt
		if not valid(boss, ctx) then
			return false
		end
		if turn and target then
			local _, _, root = CombatUtil.getLivingCharacter(target)
			if root then
				OttiAnimationService.faceTowards(boss, root.Position, dt)
			end
		end
	end
	return true
end

local function losIgnore(boss: Boss): { Instance }
	local list: { Instance } = { boss.model, CombatEffects.container() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	local arena = Workspace:FindFirstChild(Config.ArenaFolderName)
	local zombies = arena and arena:FindFirstChild(Config.ZombiesFolderName)
	if zombies then
		table.insert(list, zombies)
	end
	return list
end

-- Standing root height of a player (to tell whether they jumped over a low tail attack).
local function airborne(player: Player, root: BasePart): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local standing = Arena.Layout.FloorTop + (if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2
	return root.Position.Y > standing + OttiBossConfig.JumpClearance
end

local function hit(boss: Boss, ctx: BossContext, player: Player, move: OttiMove, damage: number, fromPosition: Vector3?): (number, boolean)
	boss.lastAttacked[player] = os.clock()
	local dealt, blocked = ctx.hitPlayer(player, {
		fromPosition = fromPosition or boss.root.Position,
		damage = damage,
		blockable = move.Blockable,
		blockStops = move.BlockStops,
		blockPierce = move.BlockPierce,
		knockback = move.Knockback,
		knockbackIfBlocked = move.KnockbackIfBlocked,
		knockdownSeconds = move.KnockdownSeconds,
		slowSeconds = move.PlayerSlowSeconds,
	})
	if dealt >= 14 then
		ctx.crowd("Gasp") -- a heavy hit on a player
	end
	return dealt, blocked
end

------------------------------------------------------------------------------------------
-- Melee (single strike or a validated multi-step combination)
------------------------------------------------------------------------------------------

local function meleeStep(boss: Boss, ctx: BossContext, move: OttiMove, target: Player, pose: string, wind: number, active: number, damage: number, range: number, arcDot: number): boolean
	OttiAnimationService.setPose(boss, pose .. "Wind", math.max(0.08, wind * 0.8))
	if wind >= 0.35 then
		CombatEffects.glow(boss.model, Color3.fromRGB(255, 200, 110), wind)
	end
	if not windUp(boss, ctx, wind, target, true) then
		return false
	end
	if damage <= 0 then
		return true -- a feint
	end
	OttiAnimationService.setPose(boss, pose .. "Strike", 0.06)
	boss.inActive = true
	local landed = false
	local elapsed = 0
	repeat
		local character, _, root = CombatUtil.getLivingCharacter(target)
		if character and root and table.find(ctx.fighters(), target) then
			local inRange = CombatUtil.flatDistance(boss.root.Position, root.Position) - 1 <= range
			local facing = CombatUtil.isFacing(boss.root.CFrame, root.Position, arcDot)
			local level = math.abs(boss.root.Position.Y - root.Position.Y) <= 6
			if inRange and facing and level and CombatUtil.hasLineOfSight(boss.root.Position + Vector3.new(0, 2, 0), root.Position, losIgnore(boss)) then
				local dealt, blocked = hit(boss, ctx, target, move, damage)
				landed = dealt > 0 or blocked
				break -- one hit per target per hit phase
			end
		end
		elapsed += RunService.Heartbeat:Wait()
	until elapsed >= active or not valid(boss, ctx)
	boss.inActive = false
	return landed
end

local function executeMelee(boss: Boss, ctx: BossContext, move: OttiMove, target: Player): boolean
	if move.Steps then
		local any = false
		for _, step in move.Steps do
			if not valid(boss, ctx) or not CombatUtil.getLivingCharacter(target) then
				return any
			end
			if meleeStep(boss, ctx, move, target, step.Pose, step.WindUp, step.Active, step.Damage, step.Range, step.ArcDot) and step.Damage > 0 then
				any = true
			end
		end
		return any
	end
	local pose = if move.Id == "ShieldBash" then "Bash" else "Slash"
	return meleeStep(boss, ctx, move, target, pose, move.WindUp, move.Active, move.Damage, move.Range, move.ArcDot)
end

------------------------------------------------------------------------------------------
-- Tail attacks
------------------------------------------------------------------------------------------

local function executeSweep(boss: Boss, ctx: BossContext, move: OttiMove, target: Player): boolean
	local low = move.Id == "TailTrip"
	-- Telegraph: crouch, look over the shoulder, tail pulled to one side, sand stirs
	OttiAnimationService.setPose(boss, if low then "TripWind" elseif move.Id == "ShieldTailCounter" then "CounterWind" else "SweepWind", math.max(0.1, move.WindUp * 0.6))
	local tailBase = boss.root.Position - CombatUtil.flat(boss.root.CFrame.LookVector) * 3
	CombatEffects.sandBurst(Vector3.new(tailBase.X, Arena.Layout.FloorTop, tailBase.Z), 3, 0.5)
	if move.WindUp >= 0.5 then
		CombatEffects.ring(Vector3.new(boss.root.Position.X, Arena.Layout.FloorTop + 0.1, boss.root.Position.Z), move.Radius or 10, Color3.fromRGB(255, 200, 120))
	end
	if not windUp(boss, ctx, move.WindUp, target, true) then
		return false
	end

	-- Active: the body turns; the tail volume is the sector swept behind it
	OttiAnimationService.setPose(boss, if low then "TripSweep" else "SweepExtend", 0.06)
	boss.inActive = true
	local direction = if boss.rng:NextNumber() < 0.5 then 1 else -1
	local total = math.rad(move.SweepDegrees or 360) * direction
	local startYaw = OttiAnimationService.getYaw(boss)
	local previousTail = OttiTailService.tailYaw(boss.root)
	local hitPlayers: { [Player]: boolean } = {}
	local landed = false
	local elapsed = 0
	local radius = move.Radius or OttiTailService.reach()
	while elapsed < move.Active and valid(boss, ctx) do
		local dt = RunService.Heartbeat:Wait()
		elapsed = math.min(move.Active, elapsed + dt)
		OttiAnimationService.setYaw(boss, startYaw + total * (elapsed / move.Active))
		local tailYaw = previousTail + total * (dt / move.Active)
		for _, player in ctx.fighters() do
			if not hitPlayers[player] then
				local _, _, root = CombatUtil.getLivingCharacter(player)
				if root and OttiTailService.inSweptSector(boss.root.Position, previousTail, tailYaw, 1.2, radius, root.Position) then
					if move.Jumpable and airborne(player, root) then
						continue -- jumped over the tail (it may still catch them later in the same sweep)
					end
					hitPlayers[player] = true
					local dealt, blocked = hit(boss, ctx, player, move, move.Damage)
					landed = landed or dealt > 0 or blocked
				end
			end
		end
		previousTail = tailYaw
	end
	boss.inActive = false
	CombatEffects.sandBurst(Vector3.new(boss.root.Position.X, Arena.Layout.FloorTop, boss.root.Position.Z), radius * 0.6, 0.6)
	return landed
end

local function executeSlam(boss: Boss, ctx: BossContext, move: OttiMove, target: Player): boolean
	local _, _, targetRoot = CombatUtil.getLivingCharacter(target)
	if not targetRoot then
		return false
	end
	OttiAnimationService.faceTowards(boss, targetRoot.Position, 0)
	local impact = OttiTailService.slamPoint(boss.root, targetRoot.Position)
	impact = Vector3.new(impact.X, Arena.Layout.FloorTop, impact.Z)
	-- Visible warning area during the whole wind-up
	OttiAnimationService.setPose(boss, "SlamRaise", move.WindUp * 0.7)
	CombatEffects.groundMarker(impact, move.Radius or 10, move.WindUp, Color3.fromRGB(255, 170, 80))
	CombatEffects.groundMarker(impact, move.DirectRadius or 3.5, move.WindUp, Color3.fromRGB(255, 70, 50))
	if not windUp(boss, ctx, move.WindUp, nil, false) then
		return false
	end
	OttiAnimationService.setPose(boss, "SlamStrike", 0.06)
	boss.inActive = true
	task.wait(move.Active)
	boss.inActive = false
	if not valid(boss, ctx) then
		return false
	end
	CombatEffects.sandBurst(impact, move.Radius or 10, 1.4)
	local direct = move.DirectRadius or 3.5
	local outer = move.Radius or 10
	local landed = false
	for _, player in ctx.fighters() do
		local _, _, root = CombatUtil.getLivingCharacter(player)
		if root then
			local distance = CombatUtil.flatDistance(root.Position, impact)
			if distance <= outer and CombatUtil.hasLineOfSight(impact + Vector3.new(0, 1, 0), root.Position, losIgnore(boss)) then
				local damage = if distance <= direct
					then move.DirectDamage or 20
					else move.Damage * (1 - 0.5 * (distance - direct) / math.max(1, outer - direct))
				local dealt, blocked = hit(boss, ctx, player, move, math.floor(damage + 0.5), impact)
				landed = landed or dealt > 0 or blocked
			end
		end
	end
	return landed
end

------------------------------------------------------------------------------------------
-- Bite, dash, battle cry
------------------------------------------------------------------------------------------

-- Moves Otti along `offset` this step unless something solid is in the way.
local function slide(boss: Boss, offset: Vector3, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local origin = boss.root.Position
	local goal = origin + offset
	if not Arena.isInside(goal, -4) then
		return false
	end
	if offset.Magnitude > 0.01 and Workspace:Raycast(origin, offset.Unit * (offset.Magnitude + 2), params) then
		return false
	end
	boss.root.CFrame = boss.root.CFrame + offset
	return true
end

local function executeBite(boss: Boss, ctx: BossContext, move: OttiMove, target: Player): (boolean, boolean)
	OttiAnimationService.setPose(boss, "BiteWind", move.WindUp * 0.7) -- drops low, head back
	if not windUp(boss, ctx, move.WindUp, target, true) then
		return false, false
	end
	OttiAnimationService.setPose(boss, "BiteLunge", 0.05)
	boss.inActive = true
	local ignore = losIgnore(boss)
	local look = CombatUtil.flat(boss.root.CFrame.LookVector).Unit
	local elapsed = 0
	local lunge = move.Lunge or 5
	while elapsed < move.Active and valid(boss, ctx) do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt
		if not slide(boss, look * (lunge * dt / move.Active), ignore) then
			break
		end
	end
	boss.inActive = false
	if not valid(boss, ctx) then
		return false, false
	end
	local character, _, root = CombatUtil.getLivingCharacter(target)
	if character and root and table.find(ctx.fighters(), target) then
		local inReach = CombatUtil.flatDistance(boss.root.Position, root.Position) <= move.Range + 2.5
		if inReach and CombatUtil.isFacing(boss.root.CFrame, root.Position, move.ArcDot) and CombatUtil.hasLineOfSight(boss.root.Position + Vector3.new(0, 1, 0), root.Position, ignore) then
			local dealt, blocked = hit(boss, ctx, target, move, move.Damage)
			return dealt > 0 or blocked, dealt > 0
		end
	end
	return false, false
end

local function bezier(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
	return a:Lerp(b, t):Lerp(b:Lerp(c, t), t)
end

local function executeDash(boss: Boss, ctx: BossContext, move: OttiMove, target: Player): boolean
	local _, _, targetRoot = CombatUtil.getLivingCharacter(target)
	if not targetRoot then
		return false
	end
	-- Curved path to a spot behind/beside the target, kept away from walls and gates
	local start = boss.root.Position
	local behind = -CombatUtil.flat(targetRoot.CFrame.LookVector)
	if behind.Magnitude < 0.1 then
		behind = CombatUtil.flat(targetRoot.Position - start).Unit
	end
	local side = Vector3.new(-behind.Z, 0, behind.X) * (if boss.rng:NextNumber() < 0.5 then 1 else -1)
	local finish = targetRoot.Position + behind.Unit * 6 + side * 3
	finish = Vector3.new(finish.X, start.Y, finish.Z)
	if not Arena.isInside(finish, -8) then
		finish = Vector3.new(0, start.Y, 0):Lerp(finish, 0.75)
	end
	local mid = (start + finish) / 2 + side * 8
	if not Arena.isInside(mid, -6) then
		mid = (start + finish) / 2
	end

	OttiAnimationService.setPose(boss, "DashWind", move.WindUp * 0.7)
	if not windUp(boss, ctx, move.WindUp, target, true) then
		return false
	end
	OttiAnimationService.setPose(boss, "DashRun", 0.05)
	OttiAnimationService.setLoco(boss, "QUADRUPED_RUN")
	boss.inActive = true
	local ignore = losIgnore(boss)
	local hitPlayers: { [Player]: boolean } = {}
	local landed = false
	local elapsed = 0
	local previous = start
	while elapsed < move.Active and valid(boss, ctx) do
		local dt = RunService.Heartbeat:Wait()
		elapsed = math.min(move.Active, elapsed + dt)
		local point = bezier(start, mid, finish, elapsed / move.Active)
		local offset = Vector3.new(point.X - previous.X, 0, point.Z - previous.Z)
		if offset.Magnitude > 0.01 then
			if not slide(boss, offset, ignore) then
				break -- never through walls or gates
			end
			boss.root.CFrame = CFrame.lookAt(boss.root.Position, boss.root.Position + offset)
			boss.root.AssemblyLinearVelocity = offset / math.max(dt, 1e-3) -- the client gait reads this
		end
		previous = point
		for _, player in ctx.fighters() do
			if not hitPlayers[player] then
				local _, _, root = CombatUtil.getLivingCharacter(player)
				if root and CombatUtil.flatDistance(root.Position, boss.root.Position) <= (move.Radius or OttiBossConfig.ContactRadius) then
					hitPlayers[player] = true
					local dealt, blocked = hit(boss, ctx, player, move, move.Damage)
					landed = landed or dealt > 0 or blocked
				end
			end
		end
	end
	boss.inActive = false
	boss.root.AssemblyLinearVelocity = Vector3.zero
	return landed
end

local function executeRoar(boss: Boss, ctx: BossContext, move: OttiMove): boolean
	OttiAnimationService.setPose(boss, "Roar", 0.15)
	if not windUp(boss, ctx, move.WindUp, nil, false) then
		return false
	end
	CombatEffects.ring(Vector3.new(boss.root.Position.X, Arena.Layout.FloorTop + 0.1, boss.root.Position.Z), 14, Color3.fromRGB(255, 120, 80))
	ctx.crowd("Cheer")
	if AudioConfig.OttiBattleCry ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = AudioConfig.OttiBattleCry
		sound.Volume = AudioConfig.Volume
		sound.PlayOnRemove = true
		sound.Parent = boss.root
		sound:Destroy()
	end
	task.wait(move.Active)
	return false
end

------------------------------------------------------------------------------------------
-- Entry point
------------------------------------------------------------------------------------------

export type Result = { landed: boolean, damaged: boolean }

-- Runs one attack (yields through wind-up, active window and recovery) and starts its cooldown.
function BossAttackService.execute(boss: Boss, ctx: BossContext, move: OttiMove, target: Player): Result
	local result: Result = { landed = false, damaged = false }
	if boss.busy or not valid(boss, ctx) then
		return result
	end
	boss.busy = true
	boss.attackId = move.Id
	boss.interrupted = false
	boss.humanoid:MoveTo(boss.root.Position)
	boss.humanoid.AutoRotate = false
	boss.model:SetAttribute("Attack", move.Id)

	if move.Stance ~= "Any" and boss.stance ~= move.Stance then
		OttiAnimationService.setStance(boss, move.Stance)
	end
	if move.Warning and move.Kind ~= "Grapple" then
		ctx.warn(move.Warning, move.WindUp + move.Active)
	end
	if boss.stance == "Biped" then
		OttiAnimationService.setLoco(boss, "BIPED_ATTACK")
	end

	local ok, err = pcall(function()
		if move.Kind == "Melee" then
			result.landed = executeMelee(boss, ctx, move, target)
		elseif move.Kind == "TailSweep" then
			result.landed = executeSweep(boss, ctx, move, target)
		elseif move.Kind == "TailSlam" then
			result.landed = executeSlam(boss, ctx, move, target)
		elseif move.Kind == "Bite" then
			result.landed, result.damaged = executeBite(boss, ctx, move, target)
		elseif move.Kind == "Grapple" then
			result.landed = BossGrappleService.execute(boss, ctx, target)
		elseif move.Kind == "RiverDash" then
			result.landed = executeDash(boss, ctx, move, target)
		elseif move.Kind == "Roar" then
			executeRoar(boss, ctx, move)
		end
	end)
	if not ok then
		warn("[OttiArena][Server] Otti attack failed:", move.Id, err)
		BossGrappleService.releaseAll()
	end

	boss.inActive = false
	boss.cooldowns[move.Id] = os.clock() + move.Cooldown
	if (move.Kind == "Grapple" and not result.landed) or move.Kind == "TailSlam" then
		-- Recovering from a missed grapple or a tail slam: a window to punish him
		boss.vulnerableUntil = os.clock() + move.Recovery + 0.6
	end
	if not boss.defeated then
		OttiAnimationService.setPose(boss, "Recover", 0.2)
		local recovery = move.Recovery + (if move.Kind == "Bite" and not result.landed then move.MissRecovery or 0 else 0)
		local elapsed = 0
		while elapsed < recovery and ctx.stillValid() do
			elapsed += RunService.Heartbeat:Wait()
		end
		OttiAnimationService.setPose(boss, "", 0.25)
	end
	boss.model:SetAttribute("Attack", "")
	boss.humanoid.AutoRotate = true
	boss.attackId = nil
	boss.busy = false
	return result
end

return BossAttackService
