--!strict
-- Local visual feedback: floating damage numbers ("15", "BLOCKED") and the movement parts of
-- server-approved moves (dash / lunge / knockback), which the client applies to its own
-- character because it owns that character's physics.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EffectsController = {}

local MAX_NUMBERS = 14

type Number = { gui: BillboardGui, label: TextLabel, token: number }
local free: { Number } = {}
local created = 0

-- A pooled floating number above a hit target (no GUI objects created per hit once warm).
function EffectsController.damageNumber(model: Instance, damage: number, blocked: boolean)
	local adornee = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if not adornee or not adornee:IsA("BasePart") then
		return
	end
	local entry = table.remove(free)
	if not entry then
		if created >= MAX_NUMBERS then
			return
		end
		created += 1
		local gui = Instance.new("BillboardGui")
		gui.Name = "DamageNumber"
		gui.Size = UDim2.fromOffset(90, 34)
		gui.AlwaysOnTop = true
		gui.ResetOnSpawn = false
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.Parent = gui
		entry = { gui = gui, label = label, token = 0 }
	end
	local number = entry :: Number
	number.token += 1
	local myToken = number.token
	local gui, label = number.gui, number.label
	gui.Adornee = adornee
	gui.StudsOffset = Vector3.new(math.random(-10, 10) / 10, 2.5, 0)
	gui.Enabled = true
	label.TextSize = if blocked then 18 else 24
	label.Text = if blocked then "BLOCKED" elseif damage <= 0 then "MISS" else tostring(math.round(damage))
	label.TextColor3 = if blocked then Color3.fromRGB(255, 220, 120) else Color3.new(1, 1, 1)
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.2
	TweenService:Create(gui, TweenInfo.new(0.7), { StudsOffset = gui.StudsOffset + Vector3.new(0, 2, 0) }):Play()
	local fade = TweenService:Create(label, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 })
	fade:Play()
	fade.Completed:Connect(function()
		if number.token == myToken then
			gui.Enabled = false
			(gui :: any).Adornee = nil
			table.insert(free, number)
		end
	end)
end

local function getRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Short dash/lunge in a direction, stopping before walls (the server validates the hit after).
function EffectsController.dash(direction: Vector3, distance: number)
	local root = getRoot()
	if not root or direction.Magnitude < 0.01 then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z).Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance }
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(root.Position, flat * distance, params)
	local allowed = if hit then math.max(0, (hit.Position - root.Position).Magnitude - 2) else distance
	if allowed > 0.3 then
		root.AssemblyLinearVelocity = flat * (allowed / 0.18) + Vector3.new(0, 2, 0)
		task.delay(0.18, function()
			if root.Parent then
				root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
			end
		end)
	end
end

-- A short, controlled knockdown (Otti's tail trip / throw landing): the character lies back for at
-- most 1.2 s and then stands up again; the server grants protection meanwhile. No ragdoll.
local knockdownToken = 0
function EffectsController.knockdown(seconds: number)
	local root = getRoot()
	local character = root and root.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	knockdownToken += 1
	local myToken = knockdownToken
	local duration = math.clamp(seconds, 0.2, 1.2)
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	local upright = root.CFrame
	root.CFrame = upright * CFrame.new(0, -1.2, 0) * CFrame.Angles(math.rad(70), 0, 0)
	task.delay(duration, function()
		if knockdownToken ~= myToken or not root.Parent then
			return
		end
		humanoid.PlatformStand = false
		root.AssemblyAngularVelocity = Vector3.zero
		local position = root.Position
		root.CFrame = CFrame.new(position.X, upright.Position.Y, position.Z) * upright.Rotation
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)
end

-- One controlled hop for a combo aerial started on the ground (a single velocity change: no
-- repeated acceleration, so no flying).
function EffectsController.leap(upVelocity: number, direction: Vector3, distance: number)
	local root = getRoot()
	if not root then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local forward = if flat.Magnitude > 0.01 then flat.Unit * (distance / 0.6) else Vector3.zero
	root.AssemblyLinearVelocity = Vector3.new(forward.X, math.min(upVelocity, 40), forward.Z)
end

-- The aerial descent: forward travel (stopping before walls) plus a fixed downward speed.
function EffectsController.dive(direction: Vector3, distance: number, downVelocity: number)
	local root = getRoot()
	if not root then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local forward = Vector3.zero
	if flat.Magnitude > 0.01 and distance > 0 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { root.Parent :: Instance }
		params.RespectCanCollide = true
		local hit = Workspace:Raycast(root.Position, flat.Unit * distance, params)
		local allowed = if hit then math.max(0, (hit.Position - root.Position).Magnitude - 2) else distance
		forward = flat.Unit * (allowed / 0.35)
	end
	root.AssemblyLinearVelocity = Vector3.new(forward.X, -math.abs(downVelocity), forward.Z)
end

function EffectsController.knockback(velocity: Vector3)
	local root = getRoot()
	if root then
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, math.max(velocity.Y, 8), velocity.Z)
	end
end

return EffectsController
