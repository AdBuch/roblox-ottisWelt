--!strict
-- Procedural body motion for every R15 player character (display only). The server publishes WHAT
-- is played (character attributes): attacks (AttackAnim, AttackStart, AttackWind, AttackLength),
-- blocks (Blocking, BlockPose, BraceLevel, BlockImpactAt, BlockImpactHeavy, BlockPerfect), slides (SlideStart,
-- SlideLength) and hit reactions (HitReactAt, HitReactScale, HitReactSide). This layers all of them
-- ON TOP of the normal walk animation (Motor6D.Transform after the Animator ran). All layers are
-- summed per frame and written once per joint, so they never overwrite each other.
-- Authored animations can replace this module later without any server change (same attributes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SpecialChargeDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SpecialChargeDefinitions"))

local PlayerAnimator = {}

local rad = math.rad

type Pose = { waist: Vector3, rightShoulder: Vector3, leftShoulder: Vector3, rightHip: Vector3, leftHip: Vector3, crouch: number }

local ZERO: Pose = { waist = Vector3.zero, rightShoulder = Vector3.zero, leftShoulder = Vector3.zero, rightHip = Vector3.zero, leftHip = Vector3.zero, crouch = 0 }

local function pose(waist: Vector3, rs: Vector3?, ls: Vector3?, rh: Vector3?, lh: Vector3?, crouch: number?): Pose
	return { waist = waist, rightShoulder = rs or Vector3.zero, leftShoulder = ls or Vector3.zero, rightHip = rh or Vector3.zero, leftHip = lh or Vector3.zero, crouch = crouch or 0 }
end

-- Degrees (x = pitch, y = twist, z = roll): { windup pose, strike pose }
local POSES: { [string]: { Pose } } = {
	Slash = { pose(Vector3.new(4, 32, 0), Vector3.new(40, 0, 20)), pose(Vector3.new(-10, -38, 0), Vector3.new(-25, 0, -10), nil, Vector3.new(10, 0, 0), Vector3.new(-22, 0, 0)) },
	Backhand = { pose(Vector3.new(0, -38, 0), Vector3.new(20, 0, -30)), pose(Vector3.new(-6, 42, 0), Vector3.new(10, 0, 40), nil, Vector3.new(-18, 0, 0), Vector3.new(10, 0, 0)) },
	Low = { pose(Vector3.new(-16, 20, 0), Vector3.new(10, 0, 30), nil, Vector3.new(20, 0, 0), Vector3.new(20, 0, 0), 0.45), pose(Vector3.new(-18, -35, 0), Vector3.new(-10, 0, -30), nil, Vector3.new(25, 0, 0), Vector3.new(-10, 0, 0), 0.45) },
	Overhead = { pose(Vector3.new(18, 10, 0), Vector3.new(70, 0, 0), Vector3.new(30, 0, 0)), pose(Vector3.new(-28, -8, 0), Vector3.new(-30, 0, 0), nil, Vector3.new(15, 0, 0), Vector3.new(-25, 0, 0), 0.25) },
	Dive = { pose(Vector3.new(15, 0, 0), Vector3.new(70, 0, 0)), pose(Vector3.new(-30, 0, 0), Vector3.new(-30, 0, 0), nil, Vector3.new(30, 0, 0), Vector3.new(30, 0, 0)) },
	Rise = { pose(Vector3.new(-18, 10, 0), Vector3.new(-20, 0, 0), nil, Vector3.new(25, 0, 0), Vector3.new(25, 0, 0), 0.5), pose(Vector3.new(14, -15, 0), Vector3.new(80, 0, 0)) },
	Thrust = { pose(Vector3.new(4, 24, 0), Vector3.new(10, 0, 0)), pose(Vector3.new(-16, -12, 0), Vector3.new(30, 0, 0), nil, Vector3.new(12, 0, 0), Vector3.new(-30, 0, 0), 0.2) },
	Spin = { pose(Vector3.new(0, 40, 0), Vector3.new(20, 0, 50)), pose(Vector3.new(-5, -120, 0), Vector3.new(20, 0, 60), Vector3.new(0, 0, -40)) },
	Flurry = { pose(Vector3.new(0, 18, 0), Vector3.new(30, 0, 10), Vector3.new(30, 0, -10)), pose(Vector3.new(-6, -18, 0), Vector3.new(-10, 0, -10), Vector3.new(40, 0, 10), nil, Vector3.new(-12, 0, 0)) },
	Draw = { pose(Vector3.new(0, 40, 0), Vector3.new(60, 0, 0), Vector3.new(85, 0, 0)), pose(Vector3.new(0, 38, 0), Vector3.new(70, 0, 0), Vector3.new(85, 0, 0)) },
	Guard = { pose(Vector3.new(-8, 10, 0), nil, Vector3.new(60, 0, 10), nil, Vector3.new(-10, 0, 0), 0.3), pose(Vector3.new(-8, 10, 0), nil, Vector3.new(60, 0, 10), nil, Vector3.new(-10, 0, 0), 0.3) },
	Bash = { pose(Vector3.new(4, -20, 0), nil, Vector3.new(40, 0, 0)), pose(Vector3.new(-14, 24, 0), nil, Vector3.new(80, 0, 0), nil, Vector3.new(-25, 0, 0), 0.2) },
}

-- New server anim names reuse the closest authored pose until each gets its own
local ALIAS: { [string]: string } = {
	SlashRL = "Slash",
	SlashLR = "Backhand",
	RetreatCut = "Low",
	ParryCounter = "Thrust",
	Wide = "Spin",
	Cross = "Flurry",
	AirSpinL = "Spin",
	AirSpinR = "Spin",
}

-- Block poses: the shield arm (left) comes up in front, across, over the head or down low
local BLOCK: { [string]: Pose } = {
	Front = pose(Vector3.new(-8, 10, 0), nil, Vector3.new(60, 0, 10), nil, Vector3.new(-10, 0, 0), 0.3),
	Left = pose(Vector3.new(-6, -22, 0), nil, Vector3.new(70, 0, 28), nil, Vector3.new(-6, 0, 0), 0.2),
	Right = pose(Vector3.new(-6, 22, 0), nil, Vector3.new(68, -14, -12), nil, Vector3.new(-6, 0, 0), 0.25),
	High = pose(Vector3.new(-4, 0, 0), nil, Vector3.new(120, 0, 0), nil, Vector3.new(-6, 0, 0), 0),
	Low = pose(Vector3.new(12, 0, 0), nil, Vector3.new(28, 0, 0), nil, Vector3.new(12, 0, 0), 0.4),
}
-- Full brace (BraceLevel 1, server-driven while BLOCK is held): the shield arm lifts the shield flat
-- over the head and the knees bend into a crouch. It replaces the block pose as it grows.
local BRACE: Pose = pose(Vector3.new(-10, 0, 0), nil, Vector3.new(165, 0, 6), Vector3.new(30, 0, 0), Vector3.new(30, 0, 0), 0.9)
local BLOCK_RISE = 8 -- 1 / seconds to fully raise the block
local IMPACT_SECONDS = 0.3
local IMPACT: Pose = pose(Vector3.new(-9, 0, 0), Vector3.new(0, 0, -8))
local SLIDE_BLEND = 0.1
local SLIDE_POSE: Pose = pose(Vector3.new(-22, 0, 8), Vector3.new(10, 0, -18), Vector3.new(10, 0, 18), Vector3.new(-30, 0, 0), Vector3.new(55, 0, 0), 0.75)
local HIT_SECONDS = 0.35
local HIT_POSE: Pose = pose(Vector3.new(-8, 0, 14), Vector3.new(0, 0, -6), Vector3.new(0, 0, 6))
-- Special charge: the weapon arm (right) draws back and up, the body coils. It never touches the
-- shield arm, so it combines cleanly with the block layer (block + charge together).
local CHARGE_POSE: Pose = pose(Vector3.new(4, 26, 0), Vector3.new(55, 0, 35), nil, Vector3.new(-8, 0, 0), Vector3.new(14, 0, 0), 0.25)

local function angles(v: Vector3): CFrame
	return CFrame.Angles(rad(v.X), rad(v.Y), rad(v.Z))
end

local function scaled(p: Pose, k: number): Pose
	return { waist = p.waist * k, rightShoulder = p.rightShoulder * k, leftShoulder = p.leftShoulder * k, rightHip = p.rightHip * k, leftHip = p.leftHip * k, crouch = p.crouch * k }
end

local function add(a: Pose, b: Pose): Pose
	return { waist = a.waist + b.waist, rightShoulder = a.rightShoulder + b.rightShoulder, leftShoulder = a.leftShoulder + b.leftShoulder, rightHip = a.rightHip + b.rightHip, leftHip = a.leftHip + b.leftHip, crouch = a.crouch + b.crouch }
end

local function blend(a: Pose, b: Pose, t: number): Pose
	return add(scaled(a, 1 - t), scaled(b, t))
end

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- The pose at time `elapsed` of an attack: anticipation -> fast strike -> recovery.
local function sample(anim: string, elapsed: number, wind: number, length: number): Pose?
	local set = POSES[ALIAS[anim] or anim]
	if not set or elapsed < 0 or elapsed > length + 0.25 then
		return nil
	end
	local strikeTime = 0.12
	if elapsed < wind then
		return blend(ZERO, set[1], ease(elapsed / math.max(0.05, wind)))
	elseif elapsed < wind + strikeTime then
		return blend(set[1], set[2], ease((elapsed - wind) / strikeTime))
	end
	local recover = math.max(0.2, length + 0.25 - wind - strikeTime)
	return blend(set[2], ZERO, ease((elapsed - wind - strikeTime) / recover))
end

type Motors = { waist: Motor6D?, root: Motor6D?, rightShoulder: Motor6D?, leftShoulder: Motor6D?, rightHip: Motor6D?, leftHip: Motor6D? }
type BlockState = { alpha: number, pose: string }

local function find(character: Model, partName: string, motorName: string): Motor6D?
	local part = character:FindFirstChild(partName)
	local motor = part and part:FindFirstChild(motorName)
	return if motor and motor:IsA("Motor6D") then motor else nil
end

-- Additive write that never accumulates: if the Animator didn't touch the joint since our last
-- write, we build on the same base again instead of on our own previous result.
type Written = { written: CFrame, base: CFrame }
local written: { [Motor6D]: Written } = setmetatable({}, { __mode = "k" }) :: any

local function applyAdditive(motor: Motor6D?, offset: CFrame?)
	if not motor then
		return
	end
	local entry = written[motor]
	local current = motor.Transform
	local base = if entry and current == entry.written then entry.base else current
	if offset then
		local result = base * offset
		motor.Transform = result
		written[motor] = { written = result, base = base }
	elseif entry then
		if current == entry.written then
			motor.Transform = entry.base -- layers ended: back to the untouched pose
		end
		written[motor] = nil
	end
end

function PlayerAnimator.start()
	local cache: { [Model]: Motors } = setmetatable({}, { __mode = "k" }) :: any
	local blocks: { [Model]: BlockState } = setmetatable({}, { __mode = "k" }) :: any
	RunService.Stepped:Connect(function(_, dt)
		local now = Workspace:GetServerTimeNow()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if not character then
				continue
			end

			local total: Pose = ZERO
			local active = false

			-- Attack
			local anim = character:GetAttribute("AttackAnim")
			if typeof(anim) == "string" then
				local p = sample(anim, now - (tonumber(character:GetAttribute("AttackStart")) or 0), tonumber(character:GetAttribute("AttackWind")) or 0.1, tonumber(character:GetAttribute("AttackLength")) or 0.5)
				if p then
					total = add(total, p)
					active = true
				end
			end

			-- Block layer (eased in and out) plus the impact recoil on every blocked hit
			local state = blocks[character]
			if not state then
				state = { alpha = 0, pose = "Front" }
				blocks[character] = state
			end
			local blocking = character:GetAttribute("Blocking") == true
			if blocking then
				local chosen = character:GetAttribute("BlockPose")
				if typeof(chosen) == "string" and BLOCK[chosen] then
					state.pose = chosen
				end
			end
			local target = if blocking then 1 else 0
			state.alpha += math.clamp(target - state.alpha, -dt * BLOCK_RISE, dt * BLOCK_RISE)
			local brace = ease(math.clamp(tonumber(character:GetAttribute("BraceLevel")) or 0, 0, 1))
			if state.alpha > 0.001 and brace < 1 then
				total = add(total, scaled(BLOCK[state.pose] or BLOCK.Front, ease(state.alpha) * (1 - brace)))
				active = true
			end
			if brace > 0.001 then
				total = add(total, scaled(BRACE, brace))
				active = true
			end
			local impactAt = tonumber(character:GetAttribute("BlockImpactAt")) or 0
			local sinceImpact = now - impactAt
			if sinceImpact >= 0 and sinceImpact < IMPACT_SECONDS then
				local k = if character:GetAttribute("BlockImpactHeavy") == true then 1.7 elseif character:GetAttribute("BlockPerfect") == true then 1.3 else 0.9
				total = add(total, scaled(IMPACT, k * (1 - sinceImpact / IMPACT_SECONDS)))
				active = true
			end

			-- Slide posture: low lean with the legs spread, faded in and out
			local slideStart = tonumber(character:GetAttribute("SlideStart")) or 0
			local slideLength = tonumber(character:GetAttribute("SlideLength")) or 0
			local slideElapsed = now - slideStart
			if slideLength > 0 and slideElapsed >= 0 and slideElapsed <= slideLength then
				local w = math.min(1, slideElapsed / SLIDE_BLEND, (slideLength - slideElapsed) / SLIDE_BLEND)
				total = add(total, scaled(SLIDE_POSE, ease(w)))
				active = true
			end

			-- Special charge: the coil grows with the charge (full at MaxChargeSeconds)
			local chargeStart = tonumber(character:GetAttribute("SpecialChargeStart"))
			if chargeStart then
				local held = math.clamp(now - chargeStart, 0, SpecialChargeDefinitions.MaxChargeSeconds)
				total = add(total, scaled(CHARGE_POSE, ease(0.35 + 0.65 * held / SpecialChargeDefinitions.MaxChargeSeconds)))
				active = true
			end

			-- Hit reaction: a short lean away from the hit, strength by damage share
			local hitAt = tonumber(character:GetAttribute("HitReactAt")) or 0
			local sinceHit = now - hitAt
			if sinceHit >= 0 and sinceHit < HIT_SECONDS then
				local scale = tonumber(character:GetAttribute("HitReactScale")) or 0.5
				local side = tonumber(character:GetAttribute("HitReactSide")) or 0
				local w = scale * (1 - sinceHit / HIT_SECONDS)
				local lean = scaled(HIT_POSE, w)
				total = add(total, pose(lean.waist + Vector3.new(0, 0, side * 10 * w), nil, nil, nil, nil, 0))
				active = true
			end

			local motors = cache[character]
			if not active then
				-- Nothing to add: release the joints this character had written
				if motors then
					local m = motors :: Motors
					applyAdditive(m.waist, nil)
					applyAdditive(m.root, nil)
					applyAdditive(m.rightShoulder, nil)
					applyAdditive(m.leftShoulder, nil)
					applyAdditive(m.rightHip, nil)
					applyAdditive(m.leftHip, nil)
					cache[character] = nil
				end
				continue
			end
			if not motors then
				motors = {
					waist = find(character, "UpperTorso", "Waist"),
					root = find(character, "LowerTorso", "Root"),
					rightShoulder = find(character, "RightUpperArm", "RightShoulder"),
					leftShoulder = find(character, "LeftUpperArm", "LeftShoulder"),
					rightHip = find(character, "RightUpperLeg", "RightHip"),
					leftHip = find(character, "LeftUpperLeg", "LeftHip"),
				}
				cache[character] = motors
			end
			local m = motors :: Motors
			applyAdditive(m.waist, angles(total.waist))
			applyAdditive(m.root, if total.crouch > 0 then CFrame.new(0, -total.crouch, 0) else nil)
			applyAdditive(m.rightShoulder, angles(total.rightShoulder))
			applyAdditive(m.leftShoulder, angles(total.leftShoulder))
			applyAdditive(m.rightHip, angles(total.rightHip))
			applyAdditive(m.leftHip, angles(total.leftHip))
		end
	end)
end

return PlayerAnimator
