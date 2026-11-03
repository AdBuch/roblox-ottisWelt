--!strict
-- Safe training area in the lobby: straw dummies that take hits from basic attacks, specials and
-- combos. They show damage numbers (via the normal Hit feedback), never die permanently, never
-- give Aura, statistics or eliminations. They refill after a short pause. The last dummy is a
-- SPARRING dummy that swings (Mid / High / Low, telegraphed) for Block / Perfect Block practice.

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
}

local TrainingService = {}

local dummies: { [Model]: Dummy } = {}
local zoneCFrame = CFrame.identity
local zoneSize = Vector3.zero
local startSparring: (dummy: Dummy) -> ()

-- The client shows a contextual health bar from these attributes (ContextHealthController).
local function updateLabel(dummy: Dummy)
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

	model.Parent = parent
	CollectionService:AddTag(model, Config.TrainingDummyTag)
	local dummy: Dummy = { model = model, root = root, health = DUMMY_HEALTH, lastHit = 0 }
	dummies[model] = dummy
	updateLabel(dummy)
	return dummy
end

function TrainingService.build(parent: Instance, slots: { CFrame }, areaCFrame: CFrame, areaSize: Vector3)
	zoneCFrame = areaCFrame
	zoneSize = areaSize
	for index, slot in slots do
		local dummy = buildDummy(parent, slot, index)
		if index == #slots then
			dummy.model:SetAttribute("ZombieType", "Sparring Dummy")
			dummy.model:SetAttribute("Sparring", true)
			startSparring(dummy)
		end
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
-- `label` / `direction` show what hit it (training overlay: move name + attack direction).
function TrainingService.hit(dummy: Dummy, damage: number, label: string?, direction: string?)
	dummy.health = math.max(0, dummy.health - damage)
	dummy.lastHit = os.clock()
	updateLabel(dummy)
	dummy.model:SetAttribute("LastHitLabel", label or "")
	dummy.model:SetAttribute("LastHitDirection", direction or "")
	dummy.model:SetAttribute("LastHitDamage", damage)
	dummy.model:SetAttribute("LastHitAt", os.clock())
end

-- The sparring dummy swings at a player standing in front of it (telegraphed), so Block and
-- Perfect Block timing can be practised. The handler (PlayerCombatService.trainingSwing)
-- evaluates the swing like a real attack but never deals damage.
local sparringHandler: ((player: Player, fromPosition: Vector3, height: string?) -> ())? = nil

function TrainingService.setSparringHandler(handler: (player: Player, fromPosition: Vector3, height: string?) -> ())
	sparringHandler = handler
end

startSparring = function(dummy: Dummy)
	local Players = game:GetService("Players")
	local arms = dummy.model:FindFirstChild("Arms")
	local rest = if arms and arms:IsA("BasePart") then arms.CFrame else CFrame.identity
	local heights = { "Mid", "High", "Low" }
	local turn = 0
	task.spawn(function()
		while dummy.model.Parent do
			task.wait(3.2)
			local target: Player? = nil
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local offset = root.Position - dummy.root.Position
					if Vector3.new(offset.X, 0, offset.Z).Magnitude <= 7 and TrainingService.isInTrainingArea(root.Position) then
						target = player
						break
					end
				end
			end
			local handler = sparringHandler
			if target and handler and arms and arms:IsA("BasePart") then
				turn = turn % #heights + 1
				local height = heights[turn]
				-- Telegraph: the arms swing back (0.7 s), then forward
				dummy.model:SetAttribute("SparringTelegraph", height)
				arms.CFrame = rest * CFrame.Angles(0, math.rad(35), 0)
				task.wait(0.7)
				arms.CFrame = rest * CFrame.Angles(0, math.rad(-40), 0)
				handler(target, dummy.root.Position, height)
				task.wait(0.3)
				arms.CFrame = rest
				dummy.model:SetAttribute("SparringTelegraph", "")
			end
		end
	end)
end

return TrainingService
