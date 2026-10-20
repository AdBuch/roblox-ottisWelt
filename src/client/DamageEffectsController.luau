--!strict
-- Stylized hit effects, triggered only by validated server combat events (Feedback.DamageFx and
-- PlayerHit). Brief and small, child-friendly: orange sparks and sand dust only (no blood, no wounds),
-- nothing that covers the screen. Your own hits also show a small directional indicator toward
-- the attacker.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DamageEffectsConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DamageEffectsConfig"))

local DamageEffectsController = {}

local folder: Folder? = nil
local budget = 0
local budgetTime = os.clock()

local function container(): Folder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "LocalHitEffects"
	created.Parent = Workspace
	folder = created
	return created
end

local function allow(): boolean
	local now = os.clock()
	local rate = DamageEffectsConfig.MaxBurstsPerSecond
	budget = math.min(rate, budget + (now - budgetTime) * rate)
	budgetTime = now
	if budget < 1 then
		return false
	end
	budget -= 1
	return true
end

local function emitter(parent: Instance, color: ColorSequence, size: NumberSequence, speed: NumberRange, lifetime: number, light: number, gravity: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = color
	e.Size = size
	e.Speed = speed
	e.Lifetime = NumberRange.new(lifetime * 0.7, lifetime)
	e.LightEmission = light
	e.Acceleration = Vector3.new(0, -gravity, 0)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Transparency = NumberSequence.new(0, 1)
	e.Rate = 0
	e.EmissionDirection = Enum.NormalId.Front
	e.Parent = parent
	return e
end

-- A burst at a validated hit position. kind: "Zombie" | "Player" | "Boss" | "Block" (same look).
function DamageEffectsController.burst(position: Vector3, _kind: string, scale: number, direction: Vector3?)
	if not allow() then
		return
	end
	local facing = if direction and direction.Magnitude > 0.01 then direction.Unit else Vector3.yAxis
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.lookAt(position, position + facing + Vector3.new(0, 0.6, 0))
	holder.Parent = container()
	local life = DamageEffectsConfig.ParticleLifetime
	local count = math.clamp(math.floor(6 * scale + 0.5), 3, 12)
	local sparks = emitter(holder, ColorSequence.new(DamageEffectsConfig.SparkColor, Color3.fromRGB(255, 220, 140)), NumberSequence.new(0.22 * scale, 0), NumberRange.new(10, 18), life, 1, 10)
	sparks:Emit(count)
	local dust = emitter(holder, ColorSequence.new(DamageEffectsConfig.DustColor), NumberSequence.new(0.6 * scale, 1.4 * scale), NumberRange.new(2, 5), life * 1.6, 0, 0)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust:Emit(math.max(2, math.floor(count / 2)))
	task.delay(life * 2 + 0.2, function()
		holder:Destroy()
	end)
end

-- A small wedge on a ring around the screen centre pointing toward the attacker (fades quickly).
function DamageEffectsController.hitIndicator(gui: ScreenGui, fromPosition: Vector3?, blocked: boolean)
	local camera = Workspace.CurrentCamera
	if not fromPosition or not camera then
		return
	end
	local cameraCFrame = camera.CFrame
	local toAttacker = fromPosition - cameraCFrame.Position
	local localDirection = cameraCFrame:VectorToObjectSpace(Vector3.new(toAttacker.X, 0, toAttacker.Z))
	local angle = math.atan2(localDirection.X, -localDirection.Z) -- 0 = straight ahead
	local wedge = Instance.new("Frame")
	wedge.AnchorPoint = Vector2.new(0.5, 0.5)
	wedge.Size = UDim2.fromOffset(70, 12)
	wedge.BackgroundColor3 = if blocked then Color3.fromRGB(150, 200, 255) else Color3.fromRGB(255, 60, 50)
	wedge.BackgroundTransparency = 0.2
	wedge.BorderSizePixel = 0
	wedge.Rotation = math.deg(angle)
	wedge.Position = UDim2.new(0.5, math.sin(angle) * 150, 0.5, -math.cos(angle) * 150)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = wedge
	wedge.Parent = gui
	local fade = TweenService:Create(wedge, TweenInfo.new(0.7), { BackgroundTransparency = 1 })
	fade:Play()
	fade.Completed:Connect(function()
		wedge:Destroy()
	end)
end

return DamageEffectsController
