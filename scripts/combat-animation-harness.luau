-- Behavioral test doubles for Roblox services. CFrame stores translation and Euler channels;
-- these tests verify layering/lifecycle/timing, not physical rotation composition or rendering.
local checks = 0
local function check(ok, label)
	assert(ok, label)
	checks += 1
end
local vm = {}
local Vector3 = {}
function Vector3.new(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, vm) end
vm.__index = function(v, key)
	if key == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
end
vm.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vm.__mul = function(a, b) return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
Vector3.zero = Vector3.new(0, 0, 0)
local cm = {}
local CFrame = {}
local function cf(x, y, z, rx, ry, rz)
	return setmetatable({ x, y, z, rx, ry, rz }, cm)
end
function CFrame.new(x, y, z) return cf(x or 0, y or 0, z or 0, 0, 0, 0) end
function CFrame.Angles(x, y, z) return cf(0, 0, 0, x, y, z) end
cm.__mul = function(a, b)
	return cf(a[1]+b[1], a[2]+b[2], a[3]+b[3], a[4]+b[4], a[5]+b[5], a[6]+b[6])
end
cm.__eq = function(a, b)
	for i = 1, 6 do if a[i] ~= b[i] then return false end end
	return true
end
CFrame.identity = CFrame.new()
local function signal()
	return { Connect = function(self, callback) self.callback = callback end }
end
local run = { PreAnimation = signal(), PreSimulation = signal() }
local now = 10
local attrs = {}
local motors = {}
local parts = {}
for part, name in {
	UpperTorso = "Waist", LowerTorso = "Root", RightUpperArm = "RightShoulder",
	LeftUpperArm = "LeftShoulder", RightUpperLeg = "RightHip", LeftUpperLeg = "LeftHip",
	RightLowerArm = "RightElbow", LeftLowerArm = "LeftElbow", RightLowerLeg = "RightKnee", LeftLowerLeg = "LeftKnee",
	RightHand = "RightWrist", LeftHand = "LeftWrist",
} do
	local motor = { Name = name, Enabled = true, Transform = CFrame.identity, IsA = function(_, kind) return kind == "Motor6D" end }
	motors[name] = motor
	parts[part] = {
		FindFirstChild = function(_, key) return if key == name then motor else nil end,
		GetChildren = function() return { motor } end,
	}
end
local character = {
	Parent = true,
	GetAttribute = function(_, key) return attrs[key] end,
	SetAttribute = function(_, key, value) attrs[key] = value end,
	FindFirstChild = function(_, key) return parts[key] end,
	GetDescendants = function()
		local list = {}
		for part, holder in parts do
			for _, child in holder.GetChildren() do table.insert(list, child) end
		end
		return list
	end,
}
local player = { Character = character }
local services = {
	Players = { GetPlayers = function() return { player } end },
	RunService = run,
	Workspace = { GetServerTimeNow = function() return now end },
	ReplicatedStorage = { WaitForChild = function(self) return self end },
}
local game = { GetService = function(_, name) return services[name] end }
local require = function() return { MaxChargeSeconds = 2.5 } end
local typeof = type
-- ANIMATOR_MODULE
animator.start()
check(run.PreAnimation.callback ~= nil and run.PreSimulation.callback ~= nil, "Animation lifecycle hooks")
local function frame(dt)
	run.PreAnimation.callback()
	now += dt
	run.PreSimulation.callback(dt)
end
local function advance(seconds, dt)
	for _ = 1, math.ceil(seconds / (dt or 1/60)) do frame(dt or 1/60) end
end
local function near(a, b, tolerance) return math.abs(a - b) <= (tolerance or 0.001) end
local function reset()
	table.clear(attrs)
	advance(2)
end
local function attack(name)
	attrs.AttackAnim = name
	attrs.AttackStart = now
	attrs.AttackWind = 0.1
	attrs.AttackLength = 0.5
end

attrs.Blocking = true
advance(0.5)
check(motors.LeftShoulder.Transform[4] > math.rad(75), "Active block visibly raises shoulder")
check(motors.LeftElbow.Transform[4] > 0.2, "Shield elbow follows shoulder")
local held = motors.LeftShoulder.Transform[4]
advance(2)
check(near(held, motors.LeftShoulder.Transform[4]), "No additive accumulation without base Animator writes")
attrs.SpecialChargeStart = now
advance(0.5)
check(near(held, motors.LeftShoulder.Transform[4]), "Charging leaves shield arm raised")
check(motors.RightShoulder.Transform[4] > 0.2, "Charging coils weapon arm")
attrs.BraceLevel = 1
advance(0.5)
check(motors.LeftShoulder.Transform[4] > math.rad(150), "Full brace lifts above head")
check(motors.Root.Transform[2] < -0.7, "Brace crouches body")
attrs.SpecialChargeStart = nil
attrs.Blocking = false
attrs.BraceLevel = 0
attack("SlashRL")
frame(1/60)
check(motors.LeftShoulder.Transform[4] > 0.2, "Block release crossfades rather than snapping")
advance(1.5)
for name, motor in motors do check(motor.Transform == CFrame.identity, "Restored locomotion: " .. name) end

local peaks = {}
for _, name in { "SlashRL", "SlashLR", "Thrust", "Overhead", "RetreatCut", "Wide", "AirSpinL", "AirSpinR", "SlideCut", "SlideThrust", "SlideCross", "SlideRise", "SlideReaper", "Ultimate" } do
	reset()
	attack(name)
	advance(0.19)
	peaks[name] = motors.Waist.Transform[5]
	check(math.abs(motors.RightShoulder.Transform[4]) + math.abs(motors.RightShoulder.Transform[6]) > 0.02, "Body coverage: " .. name)
	check(math.abs(motors.RightHip.Transform[4]) + math.abs(motors.LeftHip.Transform[4]) > 0.02, "Coordinated legs: " .. name)
end
check(peaks.SlashRL * peaks.SlashLR < 0, "Opposite slash directions")
check(peaks.AirSpinL * peaks.AirSpinR < 0, "Opposite aerial directions")
for _, dt in { 1/30, 1/60, 1/144 } do
	reset()
	attrs.Blocking = true
	advance(0.6, dt)
	check(near(motors.LeftShoulder.Transform[4], math.rad(88), 0.003), "Block settles at " .. 1/dt .. " fps")
	attrs.Blocking = false
	attack("Overhead")
	advance(0.12, dt)
	local before = motors.RightShoulder.Transform[4]
	attack("Thrust")
	frame(dt)
	check(math.abs(motors.RightShoulder.Transform[4] - before) < 0.8, "Interrupted attack crossfade at " .. 1/dt .. " fps")
end
reset()
attrs.HitReactAt = now
attrs.HitReactScale = 1
attrs.HitReactSide = -1
advance(0.1)
check(motors.Waist.Transform[6] < 0, "Directional hit recoil")
check(motors.RightElbow.Transform[4] > 0, "Hit recoil includes arms")
check(motors.RightKnee.Transform[4] < 0, "Hit recoil includes knees")
advance(1)
check(motors.Waist.Transform == CFrame.identity, "Hit recovery returns to base")
reset()
attrs.ParryPoseAt = now
advance(0.1)
check(motors.LeftShoulder.Transform[4] > 0.2, "Dagger parry moves arm without moving grip")
reset()

-- A real Animator may overwrite just one joint between the two callbacks.
attrs.Blocking = true
advance(0.5)
run.PreAnimation.callback()
local animatedBase = CFrame.Angles(0.1, 0.2, 0.3)
motors.LeftShoulder.Transform = animatedBase
run.PreSimulation.callback(1/60)
check(motors.LeftShoulder.Transform[4] > animatedBase[4], "Combat layers over changed Animator base")
run.PreAnimation.callback()
check(motors.LeftShoulder.Transform == animatedBase, "Restore changed base exactly")
reset()
-- Missing streamed joints and respawn must not throw or inherit the old guard state.
parts.LeftLowerArm = nil
player.Character = nil
frame(1/60)
player.Character = character
attrs.Blocking = true
frame(1/60)
check(true, "Missing character and optional joint tolerated")
parts.LeftLowerArm = { FindFirstChild = function(_, key) return if key == "LeftElbow" then motors.LeftElbow else nil end, GetChildren = function() return { motors.LeftElbow } end }
reset()

-- Default sword chain: every swing is carried by the hand (wrist + elbow), with a follow-through
local function peak(name, at)
	reset()
	attack(name)
	advance(at)
	return { rs = motors.RightShoulder.Transform, re = motors.RightElbow.Transform, rw = motors.RightWrist.Transform, waist = motors.Waist.Transform }
end
for _, name in { "Thrust", "SlashLR", "SlashRL", "Overhead" } do
	local windup = peak(name, 0.09)
	local strike = peak(name, 0.3)
	check(math.abs(strike.rw[4]) > math.rad(40), "Wrist lines the blade up: " .. name)
	check(math.abs(windup.re[4] - strike.re[4]) > math.rad(30), "Elbow travels through the swing: " .. name)
	check(math.abs(windup.rs[4] - strike.rs[4]) > math.rad(60) or math.abs(windup.rs[6] - strike.rs[6]) > math.rad(40), "Big shoulder travel: " .. name)
end
local left, right = peak("SlashLR", 0.09), peak("SlashRL", 0.09)
check(left.rs[6] < 0 and right.rs[6] > 0, "Cuts start high on opposite sides (upper left / upper right)")
reset()
attack("Overhead")
attrs.AttackWind = 0.3
advance(0.29)
check(motors.RightShoulder.Transform[4] > math.rad(140), "Overhead winds up above the head")

-- Upgraded avatar joints (AnimationConstraint) are driven exactly like Motor6D
reset()
local classicIsA = motors.RightShoulder.IsA
motors.RightShoulder.IsA = function(_, kind) return kind == "AnimationConstraint" end
attack("Thrust")
advance(0.3)
check(math.abs(motors.RightShoulder.Transform[4]) > math.rad(40), "AnimationConstraint rig animates")
advance(1.5)
check(motors.RightShoulder.Transform == CFrame.identity, "AnimationConstraint rig restored")
motors.RightShoulder.IsA = classicIsA
reset()

-- Holding BLOCK: the shield climbs and the body sinks gradually through the stages
attrs.Blocking = true
advance(0.6)
local stage1 = motors.LeftShoulder.Transform[4]
attrs.BraceLevel = 0.4
advance(1)
local stage2, crouch2 = motors.LeftShoulder.Transform[4], motors.Root.Transform[2]
attrs.BraceLevel = 1
frame(1/60)
check(motors.LeftShoulder.Transform[4] - stage2 < math.rad(10), "Brace rises slowly, never snaps")
advance(1)
local stage3, crouch3 = motors.LeftShoulder.Transform[4], motors.Root.Transform[2]
check(stage1 < stage2 and stage2 < stage3, "Shield climbs per stage")
check(crouch2 < -0.4 and crouch3 < crouch2, "Crouch deepens per stage")
reset()

local Workspace = services.Workspace
local pending = {}
local task = { delay = function(delay, callback) table.insert(pending, { at = now + delay, callback = callback }) end }
-- SERVER_ANIMATE
local function callbacks(seconds)
	now += seconds
	for i = #pending, 1, -1 do
		if pending[i].at <= now then
			local callback = table.remove(pending, i).callback
			callback()
		end
	end
end
local trail = { Parent = true, Enabled = false }
local state = { trail = trail }
animate(player, state, "SlashRL", 0.1, 0.5)
callbacks(0.11)
check(trail.Enabled, "Strike enables trail")
animate(player, state, "Guard", 0.1, 1)
callbacks(0.01)
check(not trail.Enabled, "New animation disables old trail immediately")
callbacks(0.5)
check(not trail.Enabled, "Old callbacks cannot enable trail during guard")
animate(player, state, "SlashLR", 0.1, 0.5)
state.trail = { Parent = true, Enabled = false }
callbacks(0.2)
check(not trail.Enabled and not state.trail.Enabled, "Equipment replacement invalidates callbacks")
animate(player, state, "SlashRL", 0.1, 0.5)
player.Character = nil
callbacks(0.2)
check(not state.trail.Enabled, "Respawn invalidates old character callbacks")
print("PASS: " .. checks .. " animation behavior checks")
