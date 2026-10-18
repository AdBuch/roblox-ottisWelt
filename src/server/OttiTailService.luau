--!strict
-- Otti's functional tail: six articulated, progressively narrower and slightly flattened
-- segments chained with Motor6D joints from the pelvis (no loose physics, can't detach).
--   * Visual: segments never collide or take raycasts; the client animator (OttiAnimator) bends the
--     joints for walking, running, balancing, counter-rotation and attack telegraphs.
--   * Gameplay: the tail is NOT a damage hitbox. Tail attacks are validated on the server with
--     parametric volumes that follow the same timeline as the animation: the body turns during a
--     sweep, so the tail volume is the sector swept behind Otti between two server steps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OttiBossConfig = require(ReplicatedStorage.Shared.OttiBossConfig)

export type TailRig = {
	segments: { BasePart },
	motors: { Motor6D },
}

type MakePart = (name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, mesh: string?) -> BasePart

-- Unscaled segment lengths and widths: thick at the base, tapered to the tip.
local LENGTHS = { 1.7, 1.6, 1.5, 1.35, 1.2, 1.05 }
local WIDTHS = { 1.35, 1.15, 0.95, 0.78, 0.6, 0.42 }
local FLATTEN = 0.62 -- otter tails are slightly flattened
local REST_PITCH = { -35, -22, -10, 0, 6, 10 } -- degrees from horizontal: down to the sand, tip lifted

local OttiTailService = {}

-- Builds the tail on the pelvis. basePoint is unscaled (rig space, feet at y = 0, facing -Z).
function OttiTailService.build(pelvis: BasePart, basePoint: Vector3, scale: number, fur: Color3, makePart: MakePart): TailRig
	local segments: { BasePart } = {}
	local motors: { Motor6D } = {}
	local start = basePoint * scale
	local parent: BasePart = pelvis
	for i, length in LENGTHS do
		local pitch = math.rad(REST_PITCH[i])
		local direction = Vector3.new(0, math.sin(pitch), math.cos(pitch)) -- backwards (+Z), tilted
		local len = length * scale
		local joint = CFrame.lookAt(start, start + direction) -- -Z of the joint frame runs along the tail
		local width = WIDTHS[i] * scale
		local segment = makePart("Tail" .. i, Vector3.new(width, width * FLATTEN, len * 1.35), joint * CFrame.new(0, 0, -len / 2), fur, Enum.Material.SmoothPlastic, "Sphere")
		segment.CanQuery = false
		segment.CanCollide = false
		segment.CanTouch = false
		segment.Massless = true
		local motor = Instance.new("Motor6D")
		motor.Name = "Tail" .. i
		motor.Part0 = parent
		motor.Part1 = segment
		motor.C0 = parent.CFrame:Inverse() * joint
		motor.C1 = segment.CFrame:Inverse() * joint
		motor.Parent = parent
		table.insert(segments, segment)
		table.insert(motors, motor)
		parent = segment
		start += direction * len
	end
	-- A slightly darker tip
	segments[#segments].Color = fur:Lerp(Color3.new(0, 0, 0), 0.2)
	return { segments = segments, motors = motors }
end

------------------------------------------------------------------------------------------
-- Validated tail volumes (server)
------------------------------------------------------------------------------------------

local function wrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Yaw (radians, atan2 of x/z) of the direction the tail points: straight behind the body.
function OttiTailService.tailYaw(root: BasePart): number
	local back = -root.CFrame.LookVector
	return math.atan2(back.X, back.Z)
end

-- True if `position` lies in the sector the tail swept from `fromYaw` to `toYaw` (signed, may
-- exceed 2 pi in total over several steps; one step covers less than pi) within the radii.
function OttiTailService.inSweptSector(center: Vector3, fromYaw: number, toYaw: number, minRadius: number, maxRadius: number, position: Vector3): boolean
	local offset = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	local distance = offset.Magnitude
	if distance < minRadius or distance > maxRadius then
		return false
	end
	local bearing = math.atan2(offset.X, offset.Z)
	local span = toYaw - fromYaw
	local relative = wrap(bearing - fromYaw)
	-- Bodies have width: allow a small angular margin that shrinks with distance
	local margin = math.atan2(1.4, math.max(distance, 1))
	if span >= 0 then
		return relative >= -margin and relative <= span + margin
	end
	return relative <= margin and relative >= span - margin
end

-- Where a tail slam lands: in front of Otti (the tail arcs over his head), clamped.
function OttiTailService.slamPoint(root: BasePart, towards: Vector3): Vector3
	local flat = Vector3.new(towards.X - root.Position.X, 0, towards.Z - root.Position.Z)
	local distance = math.clamp(flat.Magnitude, 4.5, 8.5)
	local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	return root.Position + direction * distance
end

function OttiTailService.reach(): number
	return OttiBossConfig.TailReach
end

return OttiTailService
