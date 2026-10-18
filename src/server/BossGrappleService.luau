--!strict
-- Otti's GRAPPLE AND ARENA THROW, fully server-controlled and safe:
--   wind-up (paws open, growl, warning) -> validated grab (range, facing, line of sight)
--   -> movement locked, held in front of Otti -> Otti turns toward a safe landing spot
--   -> deterministic, clamped arc (no physics launch) -> safe landing with a short knockdown,
--   damage exactly once, brief landing immunity, crowd cheer once.
-- Safety: landing points stay LandingMargin inside the wall, on the sand, away from other players;
-- control is restored on every exit path (success, interruption, Otti defeated, player died or
-- left, match cleanup) and by a hard timeout.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local OttiBossConfig = require(ReplicatedStorage.Shared.OttiBossConfig)
local OttiMoveDefinitions = require(ReplicatedStorage.Shared.OttiMoveDefinitions)
local Arena = require(script.Parent.Arena)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatUtil = require(script.Parent.CombatUtil)
local OttiAnimationService = require(script.Parent.OttiAnimationService)

type Boss = OttiAnimationService.Boss
type BossContext = OttiAnimationService.BossContext

type Hold = {
	player: Player,
	root: BasePart,
	ctx: BossContext,
	released: boolean,
}

local BossGrappleService = {}

local holds: { [Player]: Hold } = {}

local function standingOffset(player: Player): number
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and root:IsA("BasePart") then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 3
end

-- Restores everything for a held player. Idempotent and safe to call from any path.
local function release(hold: Hold, landing: Vector3?)
	if hold.released then
		return
	end
	hold.released = true
	holds[hold.player] = nil
	local root = hold.root
	if root.Parent then
		local position = landing or Vector3.new(root.Position.X, Arena.Layout.FloorTop, root.Position.Z)
		if not Arena.isInside(position, -OttiBossConfig.LandingMargin) then
			position = Arena.getSafePoint(position)
		end
		root.Anchored = false
		root.CFrame = CFrame.new(position + Vector3.new(0, standingOffset(hold.player) + 0.2, 0)) * root.CFrame.Rotation
		root.AssemblyLinearVelocity = Vector3.zero
		pcall(function()
			root:SetNetworkOwner(hold.player) -- the client simulates its own character again
		end)
	end
	if hold.player.Parent then
		hold.ctx.setControlLocked(hold.player, false)
	end
end

-- A safe landing spot: inside the arena, on the sand, away from other fighters and walls.
local function findLanding(boss: Boss, ctx: BossContext, victim: Player): Vector3?
	local origin = boss.root.Position
	local floor = Arena.Layout.FloorTop
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { boss.model }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true

	local best, bestScore = nil, -math.huge
	for step = 0, 11 do
		local angle = step / 12 * 2 * math.pi
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		for distance = OttiBossConfig.ThrowDistanceMax, OttiBossConfig.ThrowDistanceMin, -2 do
			local point = Vector3.new(origin.X, floor, origin.Z) + direction * distance
			if Arena.isInside(point, -OttiBossConfig.LandingMargin) then
				-- Nothing solid on the way (gates, walls) and sand underneath
				local clear = Workspace:Raycast(origin + Vector3.new(0, 3, 0), (point + Vector3.new(0, 3, 0)) - (origin + Vector3.new(0, 3, 0)), params) == nil
				local ground = Workspace:Raycast(point + Vector3.new(0, 15, 0), Vector3.new(0, -25, 0), params)
				local onFloor = ground ~= nil and math.abs(ground.Position.Y - floor) < 2
				local crowded = false
				for _, other in ctx.fighters() do
					if other ~= victim then
						local _, _, otherRoot = CombatUtil.getLivingCharacter(other)
						if otherRoot and CombatUtil.flatDistance(otherRoot.Position, point) < OttiBossConfig.LandingPlayerClearance then
							crowded = true
						end
					end
				end
				if clear and onFloor and not crowded then
					local score = distance * 0.3 - point.Magnitude * 0.05 -- far enough, toward the middle
					if score > bestScore then
						best, bestScore = point, score
					end
					break
				end
			end
		end
	end
	return best
end

-- Runs the whole grapple. Returns true if a throw landed.
function BossGrappleService.execute(boss: Boss, ctx: BossContext, target: Player): boolean
	local move = OttiMoveDefinitions.GrappleThrow
	local _, _, targetRoot = CombatUtil.getLivingCharacter(target)
	if not targetRoot then
		return false
	end

	-- Telegraph: weapon arm aside, both paws open, growl, warning indicator
	ctx.warn(move.Warning or "GRAPPLE!", move.WindUp + move.Active)
	OttiAnimationService.setPose(boss, "GrabOpen", move.WindUp * 0.6)
	CombatEffects.glow(boss.model, Color3.fromRGB(255, 140, 80), move.WindUp)
	local elapsed = 0
	while elapsed < move.WindUp do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt
		local _, _, root = CombatUtil.getLivingCharacter(target)
		if root then
			OttiAnimationService.faceTowards(boss, root.Position, dt)
		end
		if not ctx.stillValid() or boss.interrupted then
			return false
		end
	end

	-- Grab: validated once at the active moment
	OttiAnimationService.setPose(boss, "GrabLunge", 0.08)
	boss.inActive = true
	task.wait(move.Active)
	boss.inActive = false
	local character, _, root = CombatUtil.getLivingCharacter(target)
	if not ctx.stillValid() or not character or not root or not table.find(ctx.fighters(), target) then
		return false
	end
	local inRange = CombatUtil.flatDistance(boss.root.Position, root.Position) <= move.Range + 1
	local facing = CombatUtil.isFacing(boss.root.CFrame, root.Position, move.ArcDot)
	local losIgnore: { Instance } = { boss.model, character }
	if not (inRange and facing and CombatUtil.hasLineOfSight(boss.root.Position + Vector3.new(0, 2, 0), root.Position, losIgnore)) then
		return false -- dodged
	end
	local landing = findLanding(boss, ctx, target)
	if not landing then
		return false -- no safe throw possible right now: Otti lets go instead of risking it
	end

	-- Held: movement locked, anchored in front of Otti (server-controlled, no physics)
	local hold: Hold = { player = target, root = root, ctx = ctx, released = false }
	holds[target] = hold
	boss.grabbed = target
	boss.lastGrappled = target
	ctx.setControlLocked(target, true)
	root.Anchored = true
	task.delay(OttiBossConfig.GrappleSafetyTimeout, function()
		release(hold, nil) -- hard safety net: control always comes back
	end)

	local ok = pcall(function()
		local function holdPoint(): CFrame
			return boss.root.CFrame * CFrame.new(0, 2.2, -3.2)
		end
		-- Lift and turn toward the landing spot
		OttiAnimationService.setPose(boss, "GrabHold", 0.15)
		local startYaw = OttiAnimationService.getYaw(boss)
		local toLanding = CombatUtil.flat(landing - boss.root.Position)
		-- Turn to face the landing spot, then hurl the target forward
		local goalYaw = math.atan2(-toLanding.X, -toLanding.Z)
		local turn = (goalYaw - startYaw + math.pi) % (2 * math.pi) - math.pi
		local t = 0
		while t < 0.5 do
			local dt = RunService.Heartbeat:Wait()
			t += dt
			if hold.released or not ctx.stillValid() or not CombatUtil.getLivingCharacter(target) then
				return
			end
			OttiAnimationService.setYaw(boss, startYaw + turn * math.min(1, t / 0.5))
			root.CFrame = holdPoint() * CFrame.Angles(0, math.pi, 0)
		end

		-- The throw: deterministic clamped arc
		OttiAnimationService.setPose(boss, "Throw", 0.1)
		local from = root.Position
		local to = landing + Vector3.new(0, standingOffset(target), 0)
		local height = math.min(OttiBossConfig.ThrowHeight, 3 + (to - from).Magnitude * 0.25)
		local duration = OttiBossConfig.ThrowSeconds
		t = 0
		while t < duration do
			local dt = RunService.Heartbeat:Wait()
			t += dt
			if hold.released or not CombatUtil.getLivingCharacter(target) then
				return
			end
			local alpha = math.min(1, t / duration)
			local position = from:Lerp(to, alpha) + Vector3.new(0, 4 * height * alpha * (1 - alpha), 0)
			root.CFrame = CFrame.lookAt(position, position + CombatUtil.flat(to - from))
		end
	end)
	local landed = ok and not hold.released and ctx.stillValid() and CombatUtil.getLivingCharacter(target) ~= nil
	release(hold, landing)
	boss.grabbed = nil
	if not landed then
		return false
	end

	-- Landing: one hit, a short knockdown, then protection against unavoidable follow-ups
	CombatEffects.sandBurst(landing, 6, 1)
	ctx.hitPlayer(target, {
		fromPosition = boss.root.Position,
		damage = move.Damage,
		blockable = false,
		knockback = 0,
		knockdownSeconds = 0.8,
	})
	ctx.grantImmunity(target, OttiBossConfig.LandingImmunitySeconds)
	ctx.crowd("Throw") -- once per throw
	return true
end

-- Releases every held player immediately (Otti defeated, encounter stopped, cleanup).
function BossGrappleService.releaseAll()
	local all = {}
	for _, hold in holds do
		table.insert(all, hold)
	end
	for _, hold in all do
		release(hold, nil)
	end
end

-- A player left or died: make sure nothing stays locked.
function BossGrappleService.releasePlayer(player: Player)
	local hold = holds[player]
	if hold then
		release(hold, nil)
	end
end

return BossGrappleService
