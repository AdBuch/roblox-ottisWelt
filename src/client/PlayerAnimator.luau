--!strict
-- Procedural body motion for every R15 player character (display only). The server publishes WHAT
-- is played (character attributes): attacks (AttackAnim, AttackStart, AttackWind, AttackLength),
-- blocks (Blocking, BlockPose, BraceLevel, BlockStage, BlockImpactAt, BlockImpactHeavy, BlockPerfect),
-- slides (SlideStart, SlideLength) and hit reactions (HitReactAt, HitReactScale, HitReactSide). This
-- layers all of them ON TOP of the normal walk animation (joint Transform in PreSimulation, after the
-- Animator ran). All layers are summed per frame and written once per joint, so they never overwrite
-- each other.
-- Joints: classic Motor6D rigs and the upgraded avatar joints (StarterPlayer.AvatarJointUpgrade,
-- AnimationConstraint) both expose Transform; either is driven.
-- The weapon stays welded to the hand: every swing is carried by waist, shoulder, elbow and WRIST,
-- so the blade always moves with the hand that holds it.
-- Authored animations can replace this module later without any server change (same attributes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SpecialChargeDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SpecialChargeDefinitions"))
local SpecialAnimations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SpecialAnimationDefinitions"))

local PlayerAnimator = {}

local rad = math.rad

type Pose = {
	waist: Vector3,
	rightShoulder: Vector3,
	leftShoulder: Vector3,
	rightHip: Vector3,
	leftHip: Vector3,
	crouch: number,
	rightElbow: number, -- degrees of bend (forearm forward)
	leftElbow: number,
	rightWrist: Vector3,
	leftWrist: Vector3,
}

-- Explicit elbow bends and wrist angles. A pose without an elbow bend gets a natural one derived
-- from its shoulder angle, so older poses keep bending through the limb chain.
type Arms = { re: number?, le: number?, rw: Vector3?, lw: Vector3? }

local ZERO: Pose = {
	waist = Vector3.zero, rightShoulder = Vector3.zero, leftShoulder = Vector3.zero, rightHip = Vector3.zero,
	leftHip = Vector3.zero, crouch = 0, rightElbow = 0, leftElbow = 0, rightWrist = Vector3.zero, leftWrist = Vector3.zero,
}

local function derivedElbow(shoulder: Vector3, cap: number, share: number): number
	return math.min(cap, shoulder.Magnitude * share, math.max(0, 180 - shoulder.X) * 0.8)
end

local function pose(waist: Vector3, rs: Vector3?, ls: Vector3?, rh: Vector3?, lh: Vector3?, crouch: number?, arms: Arms?): Pose
	local right = rs or Vector3.zero
	local left = ls or Vector3.zero
	return {
		waist = waist, rightShoulder = right, leftShoulder = left, rightHip = rh or Vector3.zero, leftHip = lh or Vector3.zero,
		crouch = crouch or 0,
		rightElbow = if arms and arms.re then arms.re else derivedElbow(right, 65, 0.35),
		leftElbow = if arms and arms.le then arms.le else derivedElbow(left, 85, 0.5),
		rightWrist = if arms and arms.rw then arms.rw else Vector3.zero,
		leftWrist = if arms and arms.lw then arms.lw else Vector3.zero,
	}
end

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- Degrees (x = pitch, y = twist, z = roll): { windup, strike[, follow-through] }.
-- Blade direction of a one-handed weapon: it leaves the fist at a right angle to the forearm, so
-- shoulder pitch + elbow + wrist pitch decide where it points (wrist -70..-95 lines it up for cuts
-- and the thrust; elbow bent far over the shoulder lays it down the back for the big wind-ups).
local POSES: { [string]: { Pose } } = {
	-- DEFAULT SWORD CHAIN ------------------------------------------------------------------------
	-- Thrust: the sword hand draws back to the hip (blade level), then the whole body drives it
	-- straight forward, the front foot lunges, the shield arm pulls back for balance.
	Thrust = {
		pose(v(6, -28, 0), v(-25, 0, 12), v(45, 0, -15), v(-10, 0, 0), v(20, 0, 0), 0.2, { re = 100, le = 55, rw = v(-80, 0, 0) }),
		pose(v(-14, 22, 0), v(78, 0, 4), v(30, 0, -25), v(-28, 0, 0), v(38, 0, 0), 0.35, { re = 0, le = 50, rw = v(-90, 0, 0) }),
		pose(v(-16, 24, 0), v(82, 0, 2), v(28, 0, -25), v(-30, 0, 0), v(40, 0, 0), 0.38, { re = 0, le = 50, rw = v(-92, 0, 0) }),
	},
	-- From the upper LEFT: the sword hand rises past the left ear (torso turned left), then cuts
	-- diagonally down to the lower right while the hips turn through.
	SlashLR = {
		pose(v(6, 34, 6), v(150, 0, -40), v(30, 0, -30), v(16, 0, 0), v(-10, 0, 0), 0.1, { re = 85, le = 70, rw = v(-10, 0, 0) }),
		pose(v(-12, -34, -8), v(50, 0, 50), v(35, 0, -15), v(-14, 0, 0), v(24, 0, 0), 0.28, { re = 10, le = 45, rw = v(-65, 0, 0) }),
		pose(v(-14, -42, -10), v(30, 0, 65), v(35, 0, -15), v(-16, 0, 0), v(26, 0, 0), 0.3, { re = 15, le = 45, rw = v(-70, 0, 0) }),
	},
	-- From the upper RIGHT: the sword hand rises above the right shoulder (torso turned right), then
	-- cuts diagonally down to the lower left.
	SlashRL = {
		pose(v(6, -32, -6), v(165, 0, 35), v(35, 0, -20), v(-12, 0, 0), v(18, 0, 0), 0.1, { re = 70, le = 50, rw = v(-10, 0, 0) }),
		pose(v(-14, 34, 8), v(55, 0, -45), v(25, 0, -10), v(20, 0, 0), v(-15, 0, 0), 0.28, { re = 10, le = 40, rw = v(-70, 0, 0) }),
		pose(v(-16, 42, 10), v(35, 0, -60), v(25, 0, -10), v(24, 0, 0), v(-16, 0, 0), 0.3, { re = 15, le = 40, rw = v(-75, 0, 0) }),
	},
	-- Middle, top to bottom: both feet set, the sword goes up over the head (blade down the back),
	-- then comes down through the centre line while the body folds forward.
	Overhead = {
		pose(v(10, 0, 0), v(165, 0, 8), v(40, 0, -15), v(-14, 0, 0), v(20, 0, 0), 0.1, { re = 75, le = 60, rw = v(-10, 0, 0) }),
		pose(v(-26, 0, 0), v(45, 0, -4), v(25, 0, -20), v(-24, 0, 0), v(34, 0, 0), 0.4, { re = 5, le = 40, rw = v(-70, 0, 0) }),
		pose(v(-30, 0, 0), v(30, 0, -4), v(25, 0, -20), v(-26, 0, 0), v(36, 0, 0), 0.45, { re = 8, le = 40, rw = v(-72, 0, 0) }),
	},
	-- OTHER MOVES ---------------------------------------------------------------------------------
	Slash = { pose(v(8, 46, -8), v(78, -18, 48), v(24, 0, -18), v(-16, 12, -5), v(24, -10, 5), 0.12), pose(v(-16, -52, 10), v(-42, 22, -58), v(34, 0, -24), v(26, -16, 4), v(-32, 14, -4), 0.18) },
	Backhand = { pose(v(5, -48, 9), v(48, 18, -64), v(28, 0, -18), v(22, -14, 4), v(-20, 12, -4), 0.12), pose(v(-12, 50, -10), v(28, -24, 72), v(18, 0, -28), v(-26, 16, -4), v(28, -14, 4), 0.18) },
	Low = { pose(v(-18, 38, -8), v(32, 0, 68), v(32, 0, -20), v(28, 12, 0), v(24, -12, 0), 0.45), pose(v(-24, -48, 8), v(12, 0, -74), v(42, 0, -24), v(34, -14, 0), v(-22, 14, 0), 0.5) },
	Dive = { pose(v(22, 15, -8), v(138, 0, 20), v(48, 0, -28), v(42, 0, 12), v(38, 0, -12)), pose(v(-38, -20, 8), v(-46, 0, -18), v(32, 0, -24), v(32, 0, 8), v(-24, 0, -8), 0.2) },
	Rise = { pose(v(-26, 24, -6), v(-32, 0, 28), v(24, 0, -18), v(36, 0, 0), v(32, 0, 0), 0.5), pose(v(20, -28, 8), v(142, 0, -24), v(48, 0, -28), v(-26, 0, 0), v(34, 0, 0)) },
	Spin = { pose(v(0, 58, -8), v(54, 0, 70), v(30, 0, -48), v(-24, 20, 0), v(26, -20, 0), 0.18), pose(v(-12, -125, 10), v(48, 0, -80), v(36, 0, -52), v(28, -26, 0), v(-28, 24, 0), 0.22) },
	Flurry = { pose(v(4, 32, -6), v(68, 0, 34), v(24, 0, -36), v(-16, 0, 0), v(22, 0, 0), 0.12), pose(v(-12, -38, 8), v(-22, 0, -42), v(82, 0, 36), v(24, 0, 0), v(-24, 0, 0), 0.16) },
	Draw = { pose(v(0, 40, 0), v(60, 0, 0), v(85, 0, 0)), pose(v(0, 38, 0), v(70, 0, 0), v(85, 0, 0)) },
	Guard = { pose(v(-8, 10, 0), nil, v(88, -15, -18), nil, v(-10, 0, 0), 0.3), pose(v(-8, 10, 0), nil, v(88, -15, -18), nil, v(-10, 0, 0), 0.3) },
	Bash = { pose(v(4, -20, 0), nil, v(40, 0, 0)), pose(v(-14, 24, 0), nil, v(80, 0, 0), nil, v(-25, 0, 0), 0.2) },
	RetreatCut = { pose(v(-8, 30, -8), v(62, 0, 42), v(25, 0, -20), v(24, 0, 0), v(-12, 0, 0), 0.2), pose(v(12, -42, 8), v(-24, 0, -56), v(42, 0, -18), v(-32, 0, 0), v(28, 0, 0), 0.28) },
	Wide = { pose(v(4, -58, 8), v(76, 0, -76), v(28, 0, -28), v(16, -20, 0), v(-18, 18, 0), 0.2), pose(v(-12, 62, -10), v(68, 0, 84), v(35, 0, -32), v(-22, 22, 0), v(28, -20, 0), 0.24) },
	Cross = { pose(v(8, 32, -8), v(72, 0, 42), v(24, 0, -42), v(-20, 0, 0), v(24, 0, 0), 0.15), pose(v(-18, -34, 8), v(-28, 0, -58), v(76, 0, 48), v(26, 0, 0), v(-26, 0, 0), 0.2) },
	Ultimate = { pose(v(24, 30, -8), v(152, 0, 24), v(68, 0, -32), v(30, 0, 0), v(30, 0, 0), 0.45), pose(v(-40, -38, 10), v(-55, 0, -24), v(32, 0, -42), v(38, 0, 0), v(-32, 0, 0), 0.5) },
	AirSpinL = { pose(v(12, 48, -18), v(94, 0, 62), v(38, 0, -45), v(42, 0, 18), v(-30, 0, -16)), pose(v(-18, -72, 22), v(44, 0, -76), v(58, 0, -52), v(-28, 0, -12), v(46, 0, 16)) },
	AirSpinR = { pose(v(12, -48, 18), v(94, 0, -62), v(38, 0, -45), v(-30, 0, 16), v(42, 0, -18)), pose(v(-18, 72, -22), v(44, 0, 76), v(58, 0, -52), v(46, 0, -16), v(-28, 0, 12)) },
}

local ALIAS: { [string]: string } = {
	ParryCounter = "Thrust",
	SlideCut = "Low", SlideThrust = "Thrust", SlideCross = "Cross",
	SlideRise = "Rise", SlideReaper = "Low",
}

-- The shield rides on the outer left forearm (its face points out of the back of the hand), so
-- these arm angles turn the face: they were solved against the R15 arm chain for the shield
-- centre and facing given in each comment (torso space, -Z forward).
-- Carried, drawn and not blocking: forearm across the body, shield upright beside the chest.
local CARRY: Pose = pose(Vector3.zero, nil, v(20, -60, 30), nil, nil, 0, { le = 105, lw = v(0, 0, 30) })
local CARRY_RISE = 5 -- 1 / seconds
-- Block poses: the shield comes up in front of the chest, to either side, up high or down low
local BLOCK: { [string]: Pose } = {
	Front = pose(v(-8, 10, 0), nil, v(90, 0, 60), nil, v(-10, 0, 0), 0.3, { le = 30, lw = v(-30, 0, 30) }), -- chest high, facing forward
	Left = pose(v(-6, -22, 0), nil, v(90, 0, 45), nil, v(-6, 0, 0), 0.2, { le = 120, lw = v(-30, 0, 0) }), -- facing front-left
	Right = pose(v(-6, 22, 0), nil, v(90, -45, 60), nil, v(-6, 0, 0), 0.25, { le = 60, lw = v(-30, 0, 60) }), -- across, facing front-right
	High = pose(v(-4, 0, 0), nil, v(130, 30, 60), nil, v(-6, 0, 0), 0, { le = 0, lw = v(0, 0, 30) }), -- before the forehead, tilted up
	Low = pose(v(12, 0, 0), nil, v(70, -45, 60), nil, v(12, 0, 0), 0.4, { le = 0, lw = v(0, 0, 30) }), -- before the knees, tilted down
}
-- Holding BLOCK (BraceLevel 0 -> 1, server-driven): the player sinks slowly into a deep crouch while
-- the shield climbs from the chest (stage I) to the forehead (II) until it lies flat over the head
-- (III), about where the standing player's shoulders were. The sword arm stays back, ready.
local BRACE_MID_AT = 0.4 -- BraceLevel of the middle pose (= stage II, BlockDefinitions)
local BRACE_MID: Pose = pose(v(-10, 4, 0), v(10, 0, 10), v(130, 30, 60), v(10, 0, 0), v(10, 0, 0), 0.7, { re = 30, le = 0, lw = v(0, 0, 30) })
local BRACE: Pose = pose(v(-12, 0, 0), v(15, 0, 14), v(140, 45, 60), v(10, 0, 0), v(10, 0, 0), 1.25, { re = 35, le = 0, lw = v(30, 0, 60) }) -- flat, face up
-- Twin daggers have no shield: BLOCK crosses both blades before and above the face like a grille.
local DAGGER_GUARD: Pose = pose(v(-6, 0, 0), v(100, -15, -30), v(100, 15, 30), nil, nil, 0.25, { re = 0, le = 0, rw = v(-60, 0, 60), lw = v(-60, 0, -60) })
-- Drawing and putting away (SheatheAt, SheatheReach, SheatheOffReach): each hand reaches its
-- mount (over the shoulder to the back, or down to the hip), the gear changes place on the
-- server at the peak, then the arm returns.
local SHEATHE_REACH = 0.3 -- = PlayerCombatService
local SHEATHE_RETURN = 0.4
local REACH_RIGHT: { [string]: Pose } = {
	Back = pose(v(0, -8, 0), v(160, 45, 15), nil, nil, nil, 0, { re = 120 }),
	Belt = pose(v(0, -10, 0), v(-30, 0, 0), nil, nil, nil, 0.05, { re = 50 }),
}
local REACH_LEFT: { [string]: Pose } = {
	Back = pose(v(0, 8, 0), nil, v(160, -45, -15), nil, nil, 0, { le = 120 }),
	Belt = pose(v(0, 10, 0), nil, v(-30, 0, 0), nil, nil, 0.05, { le = 50 }),
}
-- Deep crouch: beyond CROUCH_FREE the legs fold (thigh forward, shin back) so the feet stay on
-- the ground instead of sinking while the root drops (two leg segments of about LEG studs).
local CROUCH_FREE = 0.45
local LEG = 1.05
local BRACE_FOLLOW = 6 -- 1 / seconds: the shown brace eases toward the server's BraceLevel
local BLOCK_RISE = 8 -- 1 / seconds to fully raise the block
local IMPACT_SECONDS = 0.3
local IMPACT: Pose = pose(v(-9, 0, 0), v(0, 0, -8))
local SLIDE_BLEND = 0.1
local SLIDE_POSE: Pose = pose(v(-22, 0, 8), v(10, 0, -18), v(10, 0, 18), v(-30, 0, 0), v(55, 0, 0), 0.75)
local HIT_SECONDS = 0.35
local HIT_POSE: Pose = pose(v(18, 0, 0), v(18, 0, -14), v(22, 0, 14), v(-18, 0, 0), v(22, 0, 0), 0.16)
-- Special charge: the weapon arm (right) draws back and up, the body coils. It never touches the
-- shield arm, so it combines cleanly with the block layer (block + charge together).
local CHARGE_POSE: Pose = pose(v(4, 26, 0), v(55, 0, 35), nil, v(-8, 0, 0), v(14, 0, 0), 0.25, { rw = v(-30, 0, 0) })

local CROSSFADE = 26 -- 1 / seconds: how fast the shown pose follows the summed layers
local STRIKE_SECONDS = 0.12 -- wind-up end -> strike pose
local FOLLOW_SECONDS = 0.1 -- strike pose -> follow-through pose (three-key moves)

local function angles(a: Vector3): CFrame
	return CFrame.Angles(rad(a.X), rad(a.Y), rad(a.Z))
end

local function scaled(p: Pose, k: number): Pose
	return {
		waist = p.waist * k, rightShoulder = p.rightShoulder * k, leftShoulder = p.leftShoulder * k,
		rightHip = p.rightHip * k, leftHip = p.leftHip * k, crouch = p.crouch * k,
		rightElbow = p.rightElbow * k, leftElbow = p.leftElbow * k, rightWrist = p.rightWrist * k, leftWrist = p.leftWrist * k,
	}
end

local function add(a: Pose, b: Pose): Pose
	return {
		waist = a.waist + b.waist, rightShoulder = a.rightShoulder + b.rightShoulder, leftShoulder = a.leftShoulder + b.leftShoulder,
		rightHip = a.rightHip + b.rightHip, leftHip = a.leftHip + b.leftHip, crouch = a.crouch + b.crouch,
		rightElbow = a.rightElbow + b.rightElbow, leftElbow = a.leftElbow + b.leftElbow,
		rightWrist = a.rightWrist + b.rightWrist, leftWrist = a.leftWrist + b.leftWrist,
	}
end

local function blend(a: Pose, b: Pose, t: number): Pose
	return add(scaled(a, 1 - t), scaled(b, t))
end

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- The pose at time `elapsed` of an attack: anticipation -> fast strike [-> follow-through] -> recovery.
-- The anticipation starts from `from`: the pose an interrupted previous attack had reached, so a
-- quick combo flows from one swing into the next instead of snapping back to rest first.
local function sample(anim: string, elapsed: number, wind: number, length: number, from: Pose): Pose?
	local set = POSES[ALIAS[anim] or anim]
	if not set or elapsed < 0 or elapsed > length + 0.25 then
		return nil
	end
	if elapsed < wind then
		return blend(from, set[1], ease(elapsed / math.max(0.001, wind)))
	elseif elapsed < wind + STRIKE_SECONDS then
		return blend(set[1], set[2], ease((elapsed - wind) / STRIKE_SECONDS))
	end
	local last = set[2]
	local settled = wind + STRIKE_SECONDS
	local follow = set[3]
	if follow then
		if elapsed < settled + FOLLOW_SECONDS then
			return blend(set[2], follow, ease((elapsed - settled) / FOLLOW_SECONDS))
		end
		last = follow
		settled += FOLLOW_SECONDS
	end
	local recover = math.max(0.2, length + 0.25 - settled)
	return blend(last, ZERO, ease((elapsed - settled) / recover))
end

-- SPECIAL MOVES: keyframe tracks from SpecialAnimationDefinitions ("<Prefix>:<MoveId>" in the
-- SpecialAnimation attribute). Poses are eased between keys; the whole-body spin is sampled straight
-- from the track (never crossfaded) and wraps at 360°, so a turn never unwinds backwards.
local SPECIAL_RECOVER = 0.3 -- seconds from the last key back to the walk
local SPECIAL_MAX_AIR = 3 -- an aerial without a reported landing lets go after this long

local converted: { [SpecialAnimations.KeyPose]: Pose } = setmetatable({}, { __mode = "k" }) :: any
local function keyPose(p: SpecialAnimations.KeyPose): Pose
	local cached = converted[p]
	if not cached then
		cached = pose(p.w or Vector3.zero, p.rs, p.ls, p.rh, p.lh, p.c, { re = p.re, le = p.le, rw = p.rw, lw = p.lw })
		converted[p] = cached
	end
	return cached
end

-- The pose and spin of a key list at `t` (nil once the keys and their recovery are over). `hold`
-- keeps the last key instead of recovering (an aerial waiting for its landing).
local function sampleKeys(keys: { SpecialAnimations.Key }, t: number, hold: boolean): (Pose?, number)
	if #keys == 0 or t < 0 then
		return nil, 0
	end
	local spin = 0
	local previous: SpecialAnimations.Key? = nil
	for _, key in keys do
		if t < key.t then
			local fromPose = if previous then keyPose(previous.p) else ZERO
			local fromTime = if previous then previous.t else 0
			local share = ease((t - fromTime) / math.max(0.001, key.t - fromTime))
			local toSpin = key.s or spin
			return blend(fromPose, keyPose(key.p), share), spin + (toSpin - spin) * share
		end
		spin = key.s or spin
		previous = key
	end
	local last = keys[#keys]
	if hold then
		return keyPose(last.p), spin
	end
	local after = t - last.t
	if after > SPECIAL_RECOVER then
		return nil, 0
	end
	return blend(keyPose(last.p), ZERO, ease(after / SPECIAL_RECOVER)), spin
end

local function specialPose(character: Model, now: number): (Pose?, number)
	local name = character:GetAttribute("SpecialAnimation")
	local track = if typeof(name) == "string" then SpecialAnimations[name] else nil
	if not track then
		return nil, 0
	end
	local start = tonumber(character:GetAttribute("SpecialAnimationStart")) or 0
	local landing = tonumber(character:GetAttribute("SpecialLandingStart"))
	local p: Pose?, spin: number
	if track.Aerial and track.Land and landing and landing >= start then
		p, spin = sampleKeys(track.Land, now - landing, false)
	else
		local elapsed = now - start
		p, spin = sampleKeys(track.Keys, elapsed, track.Aerial and elapsed < SPECIAL_MAX_AIR)
	end
	return p, spin % 360
end

-- The shield pose for a raised guard of `brace` (0 = just raised, 1 = full brace over the head)
local function guardPose(direction: Pose, brace: number): Pose
	if brace <= BRACE_MID_AT then
		return blend(direction, BRACE_MID, ease(brace / BRACE_MID_AT))
	end
	return blend(BRACE_MID, BRACE, ease((brace - BRACE_MID_AT) / (1 - BRACE_MID_AT)))
end

-- A joint we can drive: classic Motor6D or an upgraded avatar joint (AnimationConstraint)
type Joint = Motor6D | AnimationConstraint
type Motors = {
	waist: Joint?, root: Joint?, rightShoulder: Joint?, leftShoulder: Joint?, rightHip: Joint?, leftHip: Joint?,
	rightElbow: Joint?, leftElbow: Joint?, rightKnee: Joint?, leftKnee: Joint?, rightWrist: Joint?, leftWrist: Joint?,
}
type BlockState = { alpha: number, pose: string, brace: number, carry: number }
type AttackState = { start: number, from: Pose, last: Pose }

-- How well a joint of the wanted name can drive the limb: an enabled upgraded joint beats an
-- enabled Motor6D (a rig may keep its old Motor6D disabled next to the AnimationConstraint).
local function rank(instance: Instance): number
	if instance:IsA("AnimationConstraint") then
		return if instance.Enabled then 4 else 1
	elseif instance:IsA("Motor6D") then
		return if instance.Enabled then 3 else 2
	end
	return 0
end

local function find(character: Model, partName: string, motorName: string): Joint?
	local best: Instance? = nil
	local bestRank = 0
	local function consider(instance: Instance)
		if instance.Name == motorName then
			local r = rank(instance)
			if r > bestRank then
				best, bestRank = instance, r
			end
		end
	end
	local part = character:FindFirstChild(partName)
	if part then
		for _, child in part:GetChildren() do
			consider(child)
		end
	end
	if bestRank < 4 then
		-- upgraded joints may live elsewhere in the rig
		for _, descendant in character:GetDescendants() do
			consider(descendant)
		end
	end
	local found = best
	if found and found:IsA("Motor6D") then
		return found
	elseif found and found:IsA("AnimationConstraint") then
		return found
	end
	return nil
end

-- Additive write that never accumulates: if the Animator didn't touch the joint since our last
-- write, we build on the same base again instead of on our own previous result.
type Written = { written: CFrame, base: CFrame }
local written: { [Joint]: Written } = setmetatable({}, { __mode = "k" }) :: any

local function setTransform(joint: Joint, value: CFrame)
	if joint:IsA("Motor6D") then
		joint.Transform = value
	elseif joint:IsA("AnimationConstraint") then
		joint.Transform = value
	end
end

local function applyAdditive(motor: Joint?, offset: CFrame?)
	if not motor then
		return
	end
	local entry = written[motor]
	local current = motor.Transform
	local base = if entry and current == entry.written then entry.base else current
	if offset then
		local result = base * offset
		setTransform(motor, result)
		written[motor] = { written = result, base = base }
	elseif entry then
		if current == entry.written then
			setTransform(motor, entry.base) -- layers ended: back to the untouched pose
		end
		written[motor] = nil
	end
end

local function residualOf(p: Pose): number
	return p.waist.Magnitude + p.rightShoulder.Magnitude + p.leftShoulder.Magnitude + p.rightHip.Magnitude
		+ p.leftHip.Magnitude + math.abs(p.crouch) + math.abs(p.rightElbow) + math.abs(p.leftElbow)
		+ p.rightWrist.Magnitude + p.leftWrist.Magnitude
end

function PlayerAnimator.start()
	local cache: { [Model]: Motors } = setmetatable({}, { __mode = "k" }) :: any
	local blocks: { [Model]: BlockState } = setmetatable({}, { __mode = "k" }) :: any
	local attacks: { [Model]: AttackState } = setmetatable({}, { __mode = "k" }) :: any
	-- Remove our previous offsets BEFORE Animator evaluation, including joints it skips.
	RunService.PreAnimation:Connect(function()
		for motor in written do
			applyAdditive(motor, nil)
		end
	end)
	local displayed: { [Model]: Pose } = setmetatable({}, { __mode = "k" }) :: any
	RunService.PreSimulation:Connect(function(dt)
		local now = Workspace:GetServerTimeNow()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if not character then
				continue
			end

			local total: Pose = ZERO
			local active = false
			local spin = 0

			-- Attack: a special move's own choreography, otherwise the basic attack pose
			local anim = character:GetAttribute("AttackAnim")
			local attackState = attacks[character]
			local special, specialSpin = specialPose(character, now)
			if special then
				total = add(total, special)
				spin = specialSpin
				active = true
				if attackState then
					attackState.last = special -- the next attack winds up from here
				end
			elseif typeof(anim) == "string" then
				local start = tonumber(character:GetAttribute("AttackStart")) or 0
				if not attackState then
					attackState = { start = start, from = ZERO, last = ZERO }
					attacks[character] = attackState
				elseif attackState.start ~= start then
					-- a new attack: wind up from wherever the previous one is right now
					attackState.start = start
					attackState.from = attackState.last
				end
				local p = sample(anim, now - start, tonumber(character:GetAttribute("AttackWind")) or 0.1, tonumber(character:GetAttribute("AttackLength")) or 0.5, attackState.from)
				attackState.last = p or ZERO
				if p then
					total = add(total, p)
					active = true
				end
			elseif attackState then
				attackState.last = ZERO
			end

			-- Block layer (eased in and out), the slow brace while BLOCK is held, and the impact
			-- recoil on every blocked hit
			local state = blocks[character]
			if not state then
				state = { alpha = 0, pose = "Front", brace = 0, carry = 0 }
				blocks[character] = state
			end
			local daggers = character:GetAttribute("GuardStyle") == "Daggers"
			local blocking = character:GetAttribute("Blocking") == true or (daggers and character:GetAttribute("SpecialBlockHeld") == true)
			if blocking then
				local chosen = character:GetAttribute("BlockPose")
				if typeof(chosen) == "string" and BLOCK[chosen] then
					state.pose = chosen
				end
			end
			local target = if blocking then 1 else 0
			state.alpha += math.clamp(target - state.alpha, -dt * BLOCK_RISE, dt * BLOCK_RISE)
			-- The server publishes BraceLevel ten times a second; easing toward it keeps the crouch smooth
			local braceTarget = if blocking then math.clamp(tonumber(character:GetAttribute("BraceLevel")) or 0, 0, 1) else 0
			state.brace += (braceTarget - state.brace) * (1 - math.exp(-BRACE_FOLLOW * math.min(dt, 0.1)))
			if state.alpha > 0.001 then
				local guard = if daggers then DAGGER_GUARD else guardPose(BLOCK[state.pose] or BLOCK.Front, state.brace)
				total = add(total, scaled(guard, ease(state.alpha)))
				active = true
			end
			-- Shield carried beside the chest while drawn; it gives way to strikes and the block
			local carryTarget = if not active and character:GetAttribute("ShieldInHand") == true and character:GetAttribute("GuardStyle") == "Shield" then 1 else 0
			state.carry += math.clamp(carryTarget - state.carry, -dt * CARRY_RISE * 2, dt * CARRY_RISE)
			local carryWeight = ease(state.carry) * (1 - ease(state.alpha))
			if carryWeight > 0.001 then
				total = add(total, scaled(CARRY, carryWeight))
				active = true
			end

			-- Drawing / putting away: reach to the mount, then back
			local sheatheAt = tonumber(character:GetAttribute("SheatheAt"))
			local sinceSheathe = if sheatheAt then now - sheatheAt else -1
			if sinceSheathe >= 0 and sinceSheathe < SHEATHE_REACH + SHEATHE_RETURN then
				local w = if sinceSheathe < SHEATHE_REACH then ease(sinceSheathe / SHEATHE_REACH) else 1 - ease((sinceSheathe - SHEATHE_REACH) / SHEATHE_RETURN)
				local right = REACH_RIGHT[tostring(character:GetAttribute("SheatheReach"))]
				local left = REACH_LEFT[tostring(character:GetAttribute("SheatheOffReach"))]
				if right then
					total = add(total, scaled(right, w))
				end
				if left then
					total = add(total, scaled(left, w))
				end
				active = true
			end
			local impactAt = tonumber(character:GetAttribute("BlockImpactAt")) or 0
			local sinceImpact = now - impactAt
			if sinceImpact >= 0 and sinceImpact < IMPACT_SECONDS then
				local k = if character:GetAttribute("BlockImpactHeavy") == true then 1.7 elseif character:GetAttribute("BlockPerfect") == true then 1.3 else 0.9
				total = add(total, scaled(IMPACT, k * (1 - sinceImpact / IMPACT_SECONDS)))
				active = true
			end

			local sinceParry = now - (tonumber(character:GetAttribute("ParryPoseAt")) or 0)
			if sinceParry >= 0 and sinceParry < 0.3 and not daggers then -- the crossed guard is the daggers' parry
				total = add(total, scaled(POSES.Cross[2], math.sin(math.pi * sinceParry / 0.3)))
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
				total = add(total, scaled(CHARGE_POSE, ease(math.min(1, held / 0.12)) * ease(0.35 + 0.65 * held / SpecialChargeDefinitions.MaxChargeSeconds)))
				active = true
			end

			-- Hit reaction: a short lean away from the hit, strength by damage share
			local hitAt = tonumber(character:GetAttribute("HitReactAt")) or 0
			local sinceHit = now - hitAt
			if sinceHit >= 0 and sinceHit < HIT_SECONDS then
				local scale = tonumber(character:GetAttribute("HitReactScale")) or 0.5
				local side = tonumber(character:GetAttribute("HitReactSide")) or 0
				local w = math.clamp(scale, 0, 1.5) * ease(math.min(1, sinceHit / 0.045)) * (1 - ease(sinceHit / HIT_SECONDS))
				local lean = scaled(HIT_POSE, w)
				lean.waist += Vector3.new(0, side * 8 * w, side * 18 * w)
				total = add(total, lean)
				active = true
			end

			local fallAt = tonumber(character:GetAttribute("SpecialFallStart")) or -100
			local fallLength = tonumber(character:GetAttribute("SpecialFallLength")) or 1.1
			if now >= fallAt and now < fallAt + fallLength then
				local phase = (now - fallAt) / fallLength
				local weight = if phase < 0.2 then ease(phase / 0.2) elseif phase > 0.7 then 1 - ease((phase - 0.7) / 0.3) else 1
				total = scaled(pose(v(15, 0, 8), v(65, 0, 40), v(65, 0, -40), v(25, 0, 8), v(12, 0, -8), 0.1, { re = 35, le = 35 }), weight)
				active = true
			end

			-- A short frame-rate-independent crossfade also covers interrupted combo stages,
			-- block direction changes, charge release, and the final return to locomotion.
			local previous = displayed[character] or ZERO
			total = blend(previous, total, 1 - math.exp(-CROSSFADE * math.min(dt, 0.1)))
			displayed[character] = total
			local motors = cache[character]
			if not active and residualOf(total) < 0.02 then
				displayed[character] = nil
				-- Nothing to add: release the joints this character had written
				if motors then
					local m = motors :: Motors
					for _, joint in { m.waist, m.root, m.rightShoulder, m.leftShoulder, m.rightHip, m.leftHip, m.rightElbow, m.leftElbow, m.rightKnee, m.leftKnee, m.rightWrist, m.leftWrist } do
						applyAdditive(joint, nil)
					end
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
					rightElbow = find(character, "RightLowerArm", "RightElbow"),
					leftElbow = find(character, "LeftLowerArm", "LeftElbow"),
					rightKnee = find(character, "RightLowerLeg", "RightKnee"),
					leftKnee = find(character, "LeftLowerLeg", "LeftKnee"),
					rightWrist = find(character, "RightHand", "RightWrist"),
					leftWrist = find(character, "LeftHand", "LeftWrist"),
				}
				cache[character] = motors
			end
			local m = motors :: Motors
			applyAdditive(m.waist, angles(total.waist))
			-- Root: the crouch, and the whole-body spin of a special (one turn = 360°)
			local rootOffset: CFrame? = if total.crouch > 0 then CFrame.new(0, -total.crouch, 0) else nil
			if spin ~= 0 then
				rootOffset = (rootOffset or CFrame.identity) * CFrame.Angles(0, rad(spin), 0)
			end
			applyAdditive(m.root, rootOffset)
			applyAdditive(m.rightShoulder, angles(total.rightShoulder))
			applyAdditive(m.leftShoulder, angles(total.leftShoulder))
			-- Deep crouch: fold both legs by `fold` (thigh) and twice that (knee) so the feet stay down
			local fold = 0
			if total.crouch > CROUCH_FREE then
				fold = math.deg(math.acos(math.clamp(1 - (total.crouch - CROUCH_FREE) / (2 * LEG), -1, 1)))
			end
			applyAdditive(m.rightHip, angles(total.rightHip + Vector3.new(fold, 0, 0)))
			applyAdditive(m.leftHip, angles(total.leftHip + Vector3.new(fold, 0, 0)))
			-- Bend through the limb chain; grips inherit hand movement without any weld animation.
			applyAdditive(m.rightElbow, angles(Vector3.new(math.clamp(total.rightElbow, 0, 120), 0, 0)))
			applyAdditive(m.leftElbow, angles(Vector3.new(math.clamp(total.leftElbow, 0, 120), 0, 0)))
			applyAdditive(m.rightWrist, angles(total.rightWrist))
			applyAdditive(m.leftWrist, angles(total.leftWrist))
			applyAdditive(m.rightKnee, angles(Vector3.new(-math.min(140, math.min(55, math.abs(total.rightHip.X) * 0.5 + total.crouch * 25) + 2 * fold), 0, 0)))
			applyAdditive(m.leftKnee, angles(Vector3.new(-math.min(140, math.min(55, math.abs(total.leftHip.X) * 0.5 + total.crouch * 25) + 2 * fold), 0, 0)))
		end
	end)
end

return PlayerAnimator
