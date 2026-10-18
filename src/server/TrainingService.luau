--!strict
-- Safe training area in the lobby: straw dummies that take hits from basic attacks, specials and
-- combos. They show damage numbers (via the normal Hit feedback), never die permanently, never
-- give Aura and never count as eliminations. They refill after a short pause.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DUMMY_HEALTH = 300
local RESET_DELAY = 3

export type Dummy = {
	model: Model,
	root: BasePart,
	health: number,
	lastHit: number,
	label: TextLabel,
}

local TrainingService = {}

local dummies: { [Model]: Dummy } = {}
local zoneCFrame = CFrame.identity
local zoneSize = Vector3.zero

local function updateLabel(dummy: Dummy)
	dummy.label.Text = ("TRAINING DUMMY  %d / %d"):format(math.ceil(dummy.health), DUMMY_HEALTH)
	dummy.model:SetAttribute("Health", dummy.health)
end

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	if shape then
		part.Shape = shape
	end
	part.Parent = parent
	return part
end

local function buildDummy(parent: Instance, base: CFrame, index: number): Dummy
	local model = Instance.new("Model")
	model.Name = "TrainingDummy" .. index
	makePart("Post", Vector3.new(0.6, 6, 0.6), base * CFrame.new(0, 3, 0), Color3.fromRGB(90, 60, 36), Enum.Material.Wood, model)
	local root = makePart("HumanoidRootPart", Vector3.new(2.4, 2.6, 1.4), base * CFrame.new(0, 3.8, 0), Color3.fromRGB(214, 184, 110), Enum.Material.Fabric, model)
	makePart("Head", Vector3.one * 1.6, base * CFrame.new(0, 5.9, 0), Color3.fromRGB(214, 184, 110), Enum.Material.Fabric, model, Enum.PartType.Ball)
	makePart("Arms", Vector3.new(4.4, 0.5, 0.5), base * CFrame.new(0, 4.6, 0), Color3.fromRGB(90, 60, 36), Enum.Material.Wood, model)
	makePart("Target", Vector3.new(0.1, 1.2, 1.2), base * CFrame.new(0, 3.9, -0.72) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(170, 40, 40), Enum.Material.Fabric, model, Enum.PartType.Cylinder)
	makePart("Base", Vector3.new(3, 0.6, 3), base * CFrame.new(0, 0.3, 0), Color3.fromRGB(110, 98, 86), Enum.Material.Cobblestone, model)
	model.PrimaryPart = root
	model:SetAttribute("ZombieType", "Training Dummy")
	model:SetAttribute("MaxHealth", DUMMY_HEALTH)

	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(180, 24)
	tag.StudsOffset = Vector3.new(0, 4, 0)
	tag.Adornee = root
	tag.MaxDistance = 50
	tag.Parent = model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = tag

	model.Parent = parent
	CollectionService:AddTag(model, Config.TrainingDummyTag)
	local dummy: Dummy = { model = model, root = root, health = DUMMY_HEALTH, lastHit = 0, label = label }
	dummies[model] = dummy
	updateLabel(dummy)
	return dummy
end

function TrainingService.build(parent: Instance, slots: { CFrame }, areaCFrame: CFrame, areaSize: Vector3)
	zoneCFrame = areaCFrame
	zoneSize = areaSize
	for index, slot in slots do
		buildDummy(parent, slot, index)
	end
	-- Refill dummies after a pause (lightweight: twice per second)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for _, dummy in dummies do
				if dummy.health < DUMMY_HEALTH and now - dummy.lastHit >= RESET_DELAY then
					dummy.health = DUMMY_HEALTH
					updateLabel(dummy)
				end
			end
		end
	end)
end

function TrainingService.isInTrainingArea(position: Vector3): boolean
	local localPosition = zoneCFrame:PointToObjectSpace(position)
	return math.abs(localPosition.X) <= zoneSize.X / 2
		and math.abs(localPosition.Y) <= zoneSize.Y / 2
		and math.abs(localPosition.Z) <= zoneSize.Z / 2
end

function TrainingService.getDummies(): { Dummy }
	local list = {}
	for _, dummy in dummies do
		table.insert(list, dummy)
	end
	return list
end

function TrainingService.getByModel(model: Instance): Dummy?
	return dummies[model :: any]
end

-- Applies a training hit; never kills the dummy (it bottoms out at 0 and refills later).
function TrainingService.hit(dummy: Dummy, damage: number)
	dummy.health = math.max(0, dummy.health - damage)
	dummy.lastHit = os.clock()
	updateLabel(dummy)
end

return TrainingService
