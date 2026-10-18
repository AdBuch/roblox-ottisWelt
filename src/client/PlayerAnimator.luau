--!strict
-- Procedural attack body motion for every R15 player character (display only). The server
-- publishes WHAT is played (character attributes AttackAnim, AttackStart, AttackWind,
-- AttackLength); this layers torso twist, shoulder swing, a lunge step and recovery ON TOP of the
-- normal walk animation (Motor6D.Transform after the Animator ran), so attacks use the whole body
-- instead of only the weapon. Authored animations can replace this module later without any
-- server change (same attributes).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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

local function angles(v: Vector3, k: number): CFrame
	return CFrame.Angles(rad(v.X) * k, rad(v.Y) * k, rad(v.Z) * k)
end

local function blend(a: Pose, b: Pose, t: number): Pose
	return {
		waist = a.waist:Lerp(b.waist, t),
		rightShoulder = a.rightShoulder:Lerp(b.rightShoulder, t),
		leftShoulder = a.leftShoulder:Lerp(b.leftShoulder, t),
		rightHip = a.rightHip:Lerp(b.rightHip, t),
		leftHip = a.leftHip:Lerp(b.leftHip, t),
		crouch = a.crouch + (b.crouch - a.crouch) * t,
	}
end

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- The pose at time `elapsed` of an attack: anticipation -> fast strike -> recovery.
local function sample(anim: string, elapsed: number, wind: number, length: number): Pose?
	local set = POSES[anim]
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

local function find(character: Model, partName: string, motorName: string): Motor6D?
	local part = character:FindFirstChild(partName)
	local motor = part and part:FindFirstChild(motorName)
	return if motor and motor:IsA("Motor6D") then motor else nil
end

-- Additive write that never accumulates: if the Animator didn't touch the joint since our last
-- write, we build on the same base again instead of on our own previous result.
type Written = { written: CFrame, base: CFrame }
local written: { [Motor6D]: Written } = setmetatable({}, { __mode = "k" }) :: any

local function applyAdditive(motor: Motor6D?, add: CFrame?)
	if not motor then
		return
	end
	local entry = written[motor]
	local current = motor.Transform
	local base = if entry and current == entry.written then entry.base else current
	if add then
		local result = base * add
		motor.Transform = result
		written[motor] = { written = result, base = base }
	elseif entry then
		if current == entry.written then
			motor.Transform = entry.base -- attack over: back to the untouched pose
		end
		written[motor] = nil
	end
end

function PlayerAnimator.start()
	local cache: { [Model]: Motors } = setmetatable({}, { __mode = "k" }) :: any
	RunService.Stepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local anim = character and character:GetAttribute("AttackAnim")
			if character and typeof(anim) == "string" then
				local elapsed = now - (tonumber(character:GetAttribute("AttackStart")) or 0)
				local p = sample(anim, elapsed, tonumber(character:GetAttribute("AttackWind")) or 0.1, tonumber(character:GetAttribute("AttackLength")) or 0.5)
				local motors = cache[character]
				if p or motors then
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
					-- Additive on top of whatever the Animator set this frame (nil = release)
					applyAdditive(m.waist, if p then angles(p.waist, 1) else nil)
					applyAdditive(m.root, if p and p.crouch > 0 then CFrame.new(0, -p.crouch, 0) else nil)
					applyAdditive(m.rightShoulder, if p then angles(p.rightShoulder, 1) else nil)
					applyAdditive(m.leftShoulder, if p then angles(p.leftShoulder, 1) else nil)
					applyAdditive(m.rightHip, if p then angles(p.rightHip, 1) else nil)
					applyAdditive(m.leftHip, if p then angles(p.leftHip, 1) else nil)
					if not p then
						cache[character] = nil
					end
				end
			end
		end
	end)
end

return PlayerAnimator
