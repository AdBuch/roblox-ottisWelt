--!strict
-- Client-side procedural animation for Otti (Motor6D.Transform only, like ZombieAnimator).
-- The server publishes WHAT happens (OttiAnimationService attributes: Loco, Stance, Pose,
-- PoseStart, PoseBlend, Guard); this module decides HOW it looks:
--   four legs  low body, alternating paws close to the ground, side-to-side body sway, stretch
--              when running, the tail trails and swings against turns
--   two legs   shield-forward gladiator stance, the tail rests on the sand for balance, never
--              rigid (breathing, bobbing, an occasional front paw put down for balance)
--   poses      sword/shield/bite/grapple/tail telegraphs and strikes, blended from PoseStart with
--              the same timings the server validates (OttiMoveDefinitions)
-- Authored animations can replace any state later: put Animation IDs into
-- OttiBossConfig.AnimationIds (key = Loco state or Pose); those states then play the track.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local OttiAnimator = {}

type PoseTable = { [string]: CFrame }

local rad = math.rad
local function A(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

local MOTORS = { "RootJoint", "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightHip", "LeftHip", "Tail1", "Tail2", "Tail3", "Tail4", "Tail5", "Tail6" }

local BIPED: PoseTable = {
	RootJoint = A(-10, 0, 0),
	Waist = A(-6, 0, 0),
	Neck = A(14, 0, 0),
	RightShoulder = A(45, 0, 8), -- sword ready
	LeftShoulder = A(50, 0, 15), -- shield forward
	RightHip = A(10, 0, 0),
	LeftHip = A(10, 0, 0),
	Tail1 = A(-12, 0, 0), -- rests on the sand: balance
	Tail2 = A(2, 0, 0),
	Tail3 = A(4, 0, 0),
	Tail4 = A(4, 0, 0),
	Tail5 = A(6, 0, 0),
	Tail6 = A(8, 0, 0),
}

local QUAD: PoseTable = {
	RootJoint = CFrame.new(0, -0.7, 0) * A(-72, 0, 0),
	Waist = A(-6, 0, 0),
	Neck = A(60, 0, 0),
	RightShoulder = A(78, 0, 0),
	LeftShoulder = A(78, 0, 0),
	RightHip = A(66, 0, 0),
	LeftHip = A(66, 0, 0),
	Tail1 = A(-45, 0, 0), -- trails behind
	Tail2 = A(0, 0, 0),
	Tail3 = A(0, 0, 0),
	Tail4 = A(0, 0, 0),
	Tail5 = A(0, 0, 0),
	Tail6 = A(0, 0, 0),
}

-- Attack and intro poses: only the listed joints are overridden.
local POSES: { [string]: PoseTable } = {
	SlashWind = { RightShoulder = A(150, 0, 35), Waist = A(-4, 25, 0), Tail1 = A(-12, -20, 0) },
	SlashStrike = { RightShoulder = A(30, 0, -40), Waist = A(-8, -30, 0), Tail1 = A(-12, 25, 0) },
	SlashHWind = { RightShoulder = A(90, 0, 70), Waist = A(0, 35, 0), Tail1 = A(-12, -25, 0) },
	SlashHStrike = { RightShoulder = A(90, 0, -50), Waist = A(0, -35, 0), Tail1 = A(-12, 25, 0) },
	SlashH2Wind = { RightShoulder = A(90, 0, -50), Waist = A(0, -30, 0), Tail1 = A(-12, 20, 0) },
	SlashH2Strike = { RightShoulder = A(90, 0, 60), Waist = A(0, 30, 0), Tail1 = A(-12, -25, 0) },
	FeintWind = { LeftShoulder = A(85, 0, 20), Waist = A(-10, -10, 0) },
	ThrustWind = { RightShoulder = A(60, 0, 10), RootJoint = A(2, 0, 0) },
	ThrustStrike = { RightShoulder = A(95, 0, 0), RootJoint = A(-24, 0, 0), Tail1 = A(5, 0, 0) },
	BashWind = { LeftShoulder = A(40, 0, 10), Waist = A(0, -20, 0) },
	BashStrike = { LeftShoulder = A(95, 0, 15), Waist = A(-10, 20, 0), RootJoint = A(-20, 0, 0) },
	SweepWind = {
		RootJoint = CFrame.new(0, -0.8, 0) * A(-30, 0, 0), Neck = A(10, 70, 0),
		Tail1 = A(-5, 60, 0), Tail2 = A(0, 14, 0), Tail3 = A(0, 14, 0), Tail4 = A(0, 12, 0), Tail5 = A(0, 10, 0), Tail6 = A(0, 8, 0),
	},
	SweepExtend = {
		RootJoint = CFrame.new(0, -0.6, 0) * A(-25, 0, 0), RightShoulder = A(60, 0, 50), LeftShoulder = A(60, 0, -30),
		Tail1 = A(30, 0, 0), Tail2 = A(0, 0, 0), Tail3 = A(0, 0, 0), Tail4 = A(-2, 0, 0), Tail5 = A(-4, 0, 0), Tail6 = A(-6, 0, 0),
	},
	CounterWind = { LeftShoulder = A(70, 0, 25), Tail1 = A(-5, 45, 0), Neck = A(10, 40, 0) },
	TripWind = { Tail1 = A(-55, 50, 0), Tail2 = A(-5, 10, 0), Tail3 = A(-5, 10, 0), Neck = A(70, 50, 0) },
	TripSweep = { Tail1 = A(-58, -10, 0), Tail2 = A(-4, 0, 0), Tail3 = A(-4, 0, 0), Tail4 = A(-4, 0, 0) },
	SlamRaise = {
		RootJoint = A(8, 0, 0), Neck = A(20, 0, 0),
		Tail1 = A(120, 0, 0), Tail2 = A(14, 0, 0), Tail3 = A(14, 0, 0), Tail4 = A(14, 0, 0), Tail5 = A(12, 0, 0), Tail6 = A(10, 0, 0),
	},
	SlamStrike = {
		RootJoint = A(-15, 0, 0),
		Tail1 = A(165, 0, 0), Tail2 = A(14, 0, 0), Tail3 = A(14, 0, 0), Tail4 = A(12, 0, 0), Tail5 = A(10, 0, 0), Tail6 = A(8, 0, 0),
	},
	BiteWind = { Neck = A(85, 0, 0), RootJoint = CFrame.new(0, -0.5, 0.6) * A(-62, 0, 0) },
	BiteLunge = { Neck = A(40, 0, 0), RootJoint = CFrame.new(0, -0.8, -0.8) * A(-80, 0, 0) },
	GrabOpen = { RightShoulder = A(70, 0, 70), LeftShoulder = A(80, 0, -40), Neck = A(5, 0, 0), RootJoint = A(-18, 0, 0) },
	GrabLunge = { RightShoulder = A(95, 0, 12), LeftShoulder = A(95, 0, -12), RootJoint = A(-28, 0, 0) },
	GrabHold = { RightShoulder = A(150, 0, 12), LeftShoulder = A(150, 0, -12), RootJoint = A(6, 0, 0), Neck = A(20, 0, 0) },
	Throw = { RightShoulder = A(60, 0, 20), LeftShoulder = A(60, 0, -20), Waist = A(-25, 0, 0), RootJoint = A(-20, 0, 0) },
	DashWind = { RootJoint = CFrame.new(0, -0.9, 0.4) * A(-78, 0, 0), Tail1 = A(-55, 0, 0) },
	DashRun = { RootJoint = CFrame.new(0, -0.8, 0) * A(-80, 0, 0), Tail1 = A(-60, 0, 0), Neck = A(68, 0, 0) },
	Roar = { RootJoint = A(10, 0, 0), Neck = A(35, 0, 0), RightShoulder = A(40, 0, 35), LeftShoulder = A(40, 0, -35), Tail1 = A(20, 0, 0) },
	ShieldStrike = { RightShoulder = A(110, 0, -35), LeftShoulder = A(70, 0, 28), Neck = A(10, 0, 0) },
	DrawSword = { RightShoulder = A(30, 0, -45), Waist = A(0, -15, 0) },
	RaiseShield = { LeftShoulder = A(70, 0, 22), RightShoulder = A(60, 0, 15) },
	IntroSweep = { RootJoint = CFrame.new(0, -0.6, 0) * A(-25, 0, 0), Tail1 = A(25, 0, 0) },
	Recover = {},
	Surrender = {
		RootJoint = CFrame.new(0, -1.5, 0.4) * A(12, 0, 0), RightHip = A(80, 0, 12), LeftHip = A(80, 0, -12),
		LeftShoulder = A(165, 0, -10), RightShoulder = A(8, 0, 12), Neck = A(-10, 0, 0),
		Tail1 = A(-20, 35, 0), Tail2 = A(0, 15, 0), Tail3 = A(0, 15, 0), Tail4 = A(0, 15, 0),
	},
}

-- Spectating in the imperial box: sits like an otter, tail beside the throne, paws on the knees
local SITTING: PoseTable = {
	RootJoint = CFrame.new(0, -1.5, 0.4) * A(8, 0, 0),
	Waist = A(-4, 0, 0),
	Neck = A(6, 0, 0),
	RightShoulder = A(35, 0, 6),
	LeftShoulder = A(35, 0, -6),
	RightHip = A(82, 0, 10),
	LeftHip = A(82, 0, -10),
	Tail1 = A(-20, 55, 0),
	Tail2 = A(0, 18, 0),
	Tail3 = A(0, 16, 0),
	Tail4 = A(0, 14, 0),
	Tail5 = A(4, 10, 0),
	Tail6 = A(6, 8, 0),
}

-- Reactions in the box and the entrance
local SPECTATOR_POSES: { [string]: PoseTable } = {
	SitLean = { RootJoint = CFrame.new(0, -1.5, 0.1) * A(-18, 0, 0), RightShoulder = A(55, 0, 6), LeftShoulder = A(55, 0, -6), Neck = A(20, 0, 0) },
	RailStrike = { RootJoint = CFrame.new(0, -1.5, 0.1) * A(-18, 0, 0), RightShoulder = A(100, 0, 10), LeftShoulder = A(55, 0, -6), Neck = A(20, 0, 0) },
	PawRaise = { LeftShoulder = A(165, 0, -10), Neck = A(10, 0, 0) },
	StandBrief = { RootJoint = A(-6, 0, 0), RightHip = A(10, 0, 0), LeftHip = A(10, 0, 0), RightShoulder = A(130, 0, 25), LeftShoulder = A(130, 0, -25), Tail1 = A(-15, 0, 0), Tail2 = A(0, 0, 0), Tail3 = A(0, 0, 0), Tail4 = A(0, 0, 0) },
	Surprised = { RootJoint = CFrame.new(0, -1.5, 0.5) * A(14, 0, 0), RightShoulder = A(70, 0, 40), LeftShoulder = A(70, 0, -40), Neck = A(-12, 0, 0) },
	Clap = { RightShoulder = A(70, 0, 15), LeftShoulder = A(70, 0, -15), Neck = A(12, 0, 0) },
	SitBack = { RootJoint = CFrame.new(0, -1.6, 0.6) * A(20, 0, 0), Neck = A(-16, 0, 0), RightShoulder = A(10, 0, 8), LeftShoulder = A(10, 0, -8) },
	SitImpatient = { RightShoulder = A(45, 0, 4), Tail1 = A(-15, 55, 0) },
	StandUp = { RootJoint = A(-6, 0, 0), RightHip = A(10, 0, 0), LeftHip = A(10, 0, 0) },
	ClimbRail = { RootJoint = A(-30, 0, 0), RightShoulder = A(100, 0, 10), LeftShoulder = A(100, 0, -10), RightHip = A(70, 0, 0), LeftHip = A(10, 0, 0) },
	Leap = { RootJoint = A(-20, 0, 0), RightShoulder = A(110, 0, 60), LeftShoulder = A(110, 0, -60), RightHip = A(35, 0, 0), LeftHip = A(-15, 0, 0), Tail1 = A(30, 0, 0), Tail2 = A(5, 0, 0) },
	Land = { RootJoint = CFrame.new(0, -1.4, 0) * A(-30, 0, 0), RightShoulder = A(40, 0, 40), LeftShoulder = A(40, 0, -40), RightHip = A(50, 0, 0), LeftHip = A(50, 0, 0), Tail1 = A(-40, 0, 0) },
}
for name, pose in SPECTATOR_POSES do
	POSES[name] = pose
end

local LOCO_POSES: { [string]: PoseTable } = {
	STAGGER = { RootJoint = A(14, 0, 0), RightShoulder = A(30, 0, 40), LeftShoulder = A(30, 0, -40), Neck = A(-10, 0, 0) },
	KNOCKDOWN = { RootJoint = CFrame.new(0, -1.9, 0.6) * A(70, 0, 10), RightHip = A(40, 0, 0), LeftHip = A(40, 0, 0), RightShoulder = A(100, 0, 50), LeftShoulder = A(100, 0, -50) },
	DEFEATED = POSES.Surrender,
}

type State = {
	model: Model,
	root: BasePart,
	motors: { [string]: Motor6D },
	current: { [string]: CFrame },
	phase: number,
	stanceBlend: number, -- 0 = two legs, 1 = four legs
	lastYaw: number,
	yawRate: number,
	pawDownUntil: number,
	nextPawDown: number,
	tracks: { [string]: AnimationTrack },
	playing: string?,
}

local function findMotors(model: Model): { [string]: Motor6D }
	local motors: { [string]: Motor6D } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") and table.find(MOTORS, descendant.Name) then
			motors[descendant.Name] = descendant
		end
	end
	return motors
end

local function animationIds(): { [string]: string }
	local ok, config = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("OttiBossConfig")) :: any
	end)
	if ok and type(config) == "table" and type(config.AnimationIds) == "table" then
		return config.AnimationIds
	end
	return {}
end

-- Authored animation hook: plays the track for `key` if an ID is configured. True if it plays.
local function playAuthored(state: State, key: string, ids: { [string]: string }): boolean
	local id = ids[key]
	if not id or id == "" then
		if state.playing then
			local track = state.tracks[state.playing]
			if track then
				track:Stop(0.2)
			end
			state.playing = nil
		end
		return false
	end
	if state.playing ~= key then
		local humanoid = state.model:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			return false
		end
		local track = state.tracks[key]
		if not track then
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			track = (animator :: Animator):LoadAnimation(animation)
			state.tracks[key] = track
		end
		if state.playing and state.tracks[state.playing] then
			state.tracks[state.playing]:Stop(0.2)
		end
		(track :: AnimationTrack):Play(0.2)
		state.playing = key
	end
	return true
end

local function update(state: State, dt: number, ids: { [string]: string })
	local model = state.model
	local root = state.root
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	local loco = tostring(model:GetAttribute("Loco") or "BIPED_IDLE")
	local pose = tostring(model:GetAttribute("Pose") or "")
	local stance = model:GetAttribute("Stance")

	if playAuthored(state, if pose ~= "" and ids[pose] then pose else loco, ids) then
		for _, motor in state.motors do
			motor.Transform = CFrame.identity
		end
		return
	end

	-- Stance blend (rise to two legs / drop to all fours)
	local quadTarget = if stance == "Quad" then 1 else 0
	local blendSpeed = if loco == "RISE_TO_BIPED" then 2.2 elseif loco == "DROP_TO_QUADRUPED" then 2.6 else 4
	state.stanceBlend += math.clamp(quadTarget - state.stanceBlend, -dt * blendSpeed, dt * blendSpeed)
	local q = state.stanceBlend

	-- Movement
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local deltaYaw = (yaw - state.lastYaw + math.pi) % (2 * math.pi) - math.pi
	state.lastYaw = yaw
	state.yawRate += ((if dt > 0 then deltaYaw / dt else 0) - state.yawRate) * math.min(1, dt * 8)
	local moving = math.clamp(speed / 10, 0, 1)
	local running = math.clamp((speed - 14) / 16, 0, 1)
	state.phase += dt * (2 + speed * (if q > 0.5 then 0.45 else 0.6))
	local p = state.phase
	local s = math.sin(p)

	local target: { [string]: CFrame } = {}
	local sitting = loco == "SITTING"
	for _, name in MOTORS do
		target[name] = if sitting then SITTING[name] else BIPED[name]:Lerp(QUAD[name], q)
	end
	if sitting then
		moving = 0
		-- The head follows the fighting below
		local lookAt = model:GetAttribute("LookAt")
		if typeof(lookAt) == "Vector3" then
			local localTarget = root.CFrame:PointToObjectSpace(lookAt)
			local yaw = math.clamp(math.atan2(-localTarget.X, -localTarget.Z), rad(-70), rad(70))
			target.Neck *= CFrame.Angles(0, yaw, 0)
		end
	end

	-- Gait
	if sitting then
		target.Waist *= CFrame.Angles(math.sin(now * 1.6) * rad(2), 0, 0) -- breathing
	elseif q > 0.5 then
		local amp = rad(18 + 18 * running) * moving
		target.RightShoulder *= CFrame.Angles(s * amp, 0, 0)
		target.LeftShoulder *= CFrame.Angles(-s * amp, 0, 0)
		target.RightHip *= CFrame.Angles(-s * amp, 0, 0)
		target.LeftHip *= CFrame.Angles(s * amp, 0, 0)
		-- Side-to-side body sway, stretch while running, slight bank in turns
		local bank = math.clamp(-state.yawRate * 0.06, -0.3, 0.3)
		target.RootJoint *= CFrame.Angles(math.sin(2 * p) * rad(4) * moving - rad(6) * running, s * rad(7) * moving, bank)
	else
		local amp = rad(18) * moving
		target.RightHip *= CFrame.Angles(s * amp, 0, 0)
		target.LeftHip *= CFrame.Angles(-s * amp, 0, 0)
		target.RootJoint = CFrame.new(0, math.abs(math.sin(p)) * 0.12 * moving, 0) * target.RootJoint * CFrame.Angles(0, s * rad(4) * moving, 0)
		-- Breathing
		target.Waist *= CFrame.Angles(math.sin(now * 2) * rad(2), 0, 0)
		-- Now and then a front paw goes down for balance while moving on two legs
		if loco == "BIPED_STRAFE" and pose == "" and now >= state.nextPawDown then
			state.pawDownUntil = now + 0.6
			state.nextPawDown = now + 4 + math.random() * 4
		end
		if now < state.pawDownUntil then
			target.RootJoint *= CFrame.Angles(rad(-22), 0, 0)
			target.LeftShoulder = A(78, 0, 10)
		end
	end

	-- Tail: wave along the segments, swing against turns (stabilizes), trail when running
	local counter = math.clamp(-state.yawRate * 0.12, -0.45, 0.45)
	for i = 1, 6 do
		local name = "Tail" .. i
		local wave = math.sin(p * 0.5 - i * 0.7) * rad(3 + i * (2 + 3 * moving))
		local idleSway = math.sin(now * 1.3 - i * 0.5) * rad(2 + i)
		target[name] *= CFrame.Angles(0, wave + idleSway * (1 - moving) + counter * (0.6 + i * 0.1), 0)
	end

	-- Guard (shield raised) when no attack pose owns the arm
	if model:GetAttribute("Guard") and pose == "" then
		target.LeftShoulder = A(72, 0, 24)
	end

	-- Locomotion reactions and attack poses (blended from the server's start time)
	local overlay = LOCO_POSES[loco]
	if overlay then
		for name, cframe in overlay do
			target[name] = cframe
		end
	end
	local poseTable = POSES[pose]
	if poseTable then
		local blend = math.clamp((serverNow - (tonumber(model:GetAttribute("PoseStart")) or 0)) / math.max(0.03, tonumber(model:GetAttribute("PoseBlend")) or 0.15), 0, 1)
		for name, cframe in poseTable do
			if pose == "IntroSweep" and name == "Tail1" then
				cframe *= CFrame.Angles(0, math.sin(now * 6) * rad(60), 0)
			elseif pose == "Clap" and (name == "RightShoulder" or name == "LeftShoulder") then
				cframe *= CFrame.Angles(0, 0, math.sin(now * 14) * rad(14) * (if name == "RightShoulder" then -1 else 1))
			elseif pose == "RailStrike" and name == "RightShoulder" then
				cframe *= CFrame.Angles(math.abs(math.sin(now * 9)) * rad(-40), 0, 0)
			elseif pose == "SitImpatient" and name == "Tail1" then
				cframe *= CFrame.Angles(math.abs(math.sin(now * 7)) * rad(18), 0, 0) -- tail tapping
			end
			target[name] = target[name]:Lerp(cframe, blend)
		end
	end

	local alpha = 1 - math.exp(-dt * 14)
	for name, motor in state.motors do
		local goal = target[name]
		if goal then
			local current = state.current[name] or CFrame.identity
			current = current:Lerp(goal, alpha)
			state.current[name] = current
			motor.Transform = current
		end
	end
end

function OttiAnimator.start(tag: string)
	local states: { [Instance]: State } = setmetatable({}, { __mode = "k" }) :: any
	local ids = animationIds()

	RunService.Stepped:Connect(function(_time: number, dt: number)
		for _, model in CollectionService:GetTagged(tag) do
			if model:IsA("Model") then
				local state = states[model]
				if not state or not state.root.Parent then
					local root = model:FindFirstChild("HumanoidRootPart")
					if root and root:IsA("BasePart") then
						local created: State = {
							model = model,
							root = root,
							motors = findMotors(model),
							current = {},
							phase = 0,
							stanceBlend = if model:GetAttribute("Stance") == "Quad" then 1 else 0,
							lastYaw = 0,
							yawRate = 0,
							pawDownUntil = 0,
							nextPawDown = os.clock() + 3,
							tracks = {},
							playing = nil,
						}
						state = created
						states[model] = created
					end
				end
				if state then
					update(state :: any, dt, ids)
				end
			end
		end
	end)
end

return OttiAnimator
