--!strict
-- Townspeople for Rome: a standard R15 figure (Players:CreateHumanoidModelFromDescriptionAsync with
-- the default body) in a toga or a smith's apron, or a blocky R6 figure when the description can't
-- be loaded. They walk short fixed routes with Humanoid:MoveTo and the standard walk animation,
-- pause at every waypoint, and stop to face a player who talks to them. Server-owned physics.
local Players = game:GetService("Players")

local RomeNpc = {}

export type Npc = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	busyUntil: number,
	route: { Vector3 }?,
	alive: boolean,
}

export type Look = { skin: Color3, cloth: Color3, accent: Color3, apron: boolean? }

local WALK_R15, IDLE_R15 = "rbxassetid://507777826", "rbxassetid://507766388"
local WALK_R6 = "rbxassetid://180426354"

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = a, b
	w.Parent = a
end

local function cloth(parent: Model, host: BasePart, name: string, cf: CFrame, size: Vector3, color: Color3, wedge: boolean?): BasePart
	local p: BasePart = if wedge then Instance.new("WedgePart") else Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = host.CFrame * cf
	p.Color = color
	p.Material = Enum.Material.Fabric
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.CastShadow = false
	p.Parent = parent
	weld(host, p)
	return p
end

-- A blocky R6 figure (fallback): torso, head, limbs and the joints the Humanoid walks with.
local function blocky(look: Look): Model
	local model = Instance.new("Model")
	local function limb(name: string, size: Vector3, color: Color3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local root = limb("HumanoidRootPart", Vector3.new(2, 2, 1), look.skin)
	root.Transparency = 1
	local torso = limb("Torso", Vector3.new(2, 2, 1), look.cloth)
	local head = limb("Head", Vector3.new(2, 1, 1), look.skin)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local parts = {
		{ name = "Left Arm", offset = Vector3.new(-1.5, 0, 0), joint = "Left Shoulder" },
		{ name = "Right Arm", offset = Vector3.new(1.5, 0, 0), joint = "Right Shoulder" },
		{ name = "Left Leg", offset = Vector3.new(-0.5, -2, 0), joint = "Left Hip" },
		{ name = "Right Leg", offset = Vector3.new(0.5, -2, 0), joint = "Right Hip" },
	}
	local function joint(name: string, a: BasePart, b: BasePart, c0: CFrame, c1: CFrame)
		local m = Instance.new("Motor6D")
		m.Name, m.Part0, m.Part1, m.C0, m.C1 = name, a, b, c0, c1
		m.Parent = a
	end
	joint("RootJoint", root, torso, CFrame.identity, CFrame.identity)
	joint("Neck", torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.5, 0))
	for _, spec in parts do
		local p = limb(spec.name, Vector3.new(1, 2, 1), if spec.name:find("Leg") then look.cloth else look.skin)
		local offset = spec.offset
		joint(spec.joint, torso, p, CFrame.new(offset.X, if offset.Y < 0 then -1 else 0.5, 0), CFrame.new(0, if offset.Y < 0 then 1 else 0.5, 0))
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.Parent = model
	Instance.new("Animator").Parent = humanoid
	model.PrimaryPart = root
	return model
end

local function r15(look: Look): Model?
	local description = Instance.new("HumanoidDescription")
	description.HeadColor, description.LeftArmColor, description.RightArmColor = look.skin, look.skin, look.skin
	description.LeftLegColor, description.RightLegColor, description.TorsoColor = look.cloth, look.cloth, look.cloth
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		return model
	end
	return nil
end

-- Builds a figure standing at `cf` (feet on cf.Position), dressed in `look`.
function RomeNpc.spawn(parent: Instance, name: string, cf: CFrame, look: Look): Npc
	local model = r15(look) or blocky(look)
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = 6
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth, humanoid.Health = math.huge, math.huge
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	-- dress: a toga sash over the torso and a long skirt, or a leather apron for the smith
	local torso = (model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")) :: BasePart
	local lower = (model:FindFirstChild("LowerTorso") or torso) :: BasePart
	if look.apron then
		cloth(model, torso, "Apron", CFrame.new(0, -0.4, -0.55), Vector3.new(1.8, 2.4, 0.15), look.accent)
	else
		cloth(model, lower, "TogaSkirt", CFrame.new(0, -1.5, 0), Vector3.new(2.3, 2.6, 1.3), look.cloth)
		cloth(model, torso, "TogaSash", CFrame.new(0.2, 0.1, -0.56) * CFrame.Angles(0, 0, 0.6), Vector3.new(0.7, 2.6, 0.12), look.accent)
		cloth(model, torso, "TogaDrape", CFrame.new(-0.7, 0.4, 0) , Vector3.new(0.9, 1.4, 1.25), look.cloth)
	end
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CollisionGroup = "Default"
		end
	end
	model:SetAttribute("TownNpc", true)
	model.Parent = parent
	local height = humanoid.HipHeight + root.Size.Y / 2 + (if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else 0)
	model:PivotTo(cf + Vector3.new(0, height, 0))
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local npc: Npc = { model = model, humanoid = humanoid, root = root, busyUntil = 0, route = nil, alive = true }
	-- the walk cycle while moving, idle otherwise
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local walk = Instance.new("Animation")
	walk.AnimationId = if humanoid.RigType == Enum.HumanoidRigType.R15 then WALK_R15 else WALK_R6
	local idle = Instance.new("Animation")
	idle.AnimationId = IDLE_R15
	local okWalk, walkTrack = pcall(function()
		return animator:LoadAnimation(walk)
	end)
	local okIdle, idleTrack = pcall(function()
		return animator:LoadAnimation(idle)
	end)
	if okIdle and idleTrack and humanoid.RigType == Enum.HumanoidRigType.R15 then
		idleTrack.Looped = true
		idleTrack:Play()
	end
	if okWalk and walkTrack then
		walkTrack.Looped = true
		humanoid.Running:Connect(function(speed: number)
			if speed > 0.5 and not walkTrack.IsPlaying then
				walkTrack:Play(0.2)
			elseif speed <= 0.5 and walkTrack.IsPlaying then
				walkTrack:Stop(0.3)
			end
		end)
	end
	return npc
end

-- Walks the route round and round (pausing `pause` seconds at every point). A talk pauses it.
function RomeNpc.patrol(npc: Npc, route: { Vector3 }, pause: number)
	npc.route = route
	task.spawn(function()
		local index = 1
		while npc.alive and npc.model.Parent do
			if os.clock() < npc.busyUntil then
				task.wait(0.3)
			else
				local target = route[index]
				npc.humanoid:MoveTo(target)
				local reached = false
				local connection = npc.humanoid.MoveToFinished:Connect(function(ok: boolean)
					reached = ok
				end)
				local started = os.clock()
				while not reached and os.clock() - started < 8 and os.clock() >= npc.busyUntil do
					task.wait(0.15)
					local flat = Vector3.new(target.X - npc.root.Position.X, 0, target.Z - npc.root.Position.Z)
					if flat.Magnitude < 1.4 then
						reached = true
					end
				end
				connection:Disconnect()
				if os.clock() < npc.busyUntil then
					npc.humanoid:MoveTo(npc.root.Position)
				else
					index = index % #route + 1
					task.wait(pause)
				end
			end
		end
	end)
end

-- Stops for `seconds` and turns toward `position`.
function RomeNpc.attend(npc: Npc, position: Vector3, seconds: number)
	npc.busyUntil = os.clock() + seconds
	npc.humanoid:MoveTo(npc.root.Position)
	local flat = Vector3.new(position.X, npc.root.Position.Y, position.Z)
	if (flat - npc.root.Position).Magnitude > 0.5 then
		npc.root.CFrame = CFrame.lookAt(npc.root.Position, flat)
	end
end

return RomeNpc
