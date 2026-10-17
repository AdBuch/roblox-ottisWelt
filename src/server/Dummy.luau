--!strict
-- The stationary "Roman Zombie" training dummy built from Parts.
-- Health is owned by the server and mirrored to clients via model attributes (Health, MaxHealth, Alive).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PREFIX = "[OttiArena][Server]"

local SKIN = Color3.fromRGB(122, 158, 96)
local TUNIC = Color3.fromRGB(150, 30, 30)
local LEGS = Color3.fromRGB(95, 70, 50)
local HELMET = Color3.fromRGB(190, 160, 80)
local CREST = Color3.fromRGB(200, 20, 20)

local Dummy = {}

local model: Model? = nil
local torso: BasePart? = nil
local highlight: Highlight? = nil
local nameTag: BillboardGui? = nil
local nameLabel: TextLabel? = nil
local health = Config.DummyMaxHealth
local alive = false
local flashId = 0
local damagedBy: { [Player]: boolean } = {}
local originalTransparency: { [BasePart]: number } = {}

local function addPart(parent: Model, name: string, size: Vector3, base: CFrame, offset: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = base * CFrame.new(offset)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	originalTransparency[part] = part.Transparency
	return part
end

local function updateLabel()
	if nameLabel then
		nameLabel.Text = ("Roman Zombie  %d / %d"):format(health, Config.DummyMaxHealth)
	end
end

local function setVisible(visible: boolean)
	for part, transparency in originalTransparency do
		part.Transparency = if visible then transparency else 1
		part.CanCollide = visible
		part.CanQuery = visible
	end
	if nameTag then
		nameTag.Enabled = visible
	end
end

local function flash()
	local hl = highlight
	if not hl then
		return
	end
	flashId += 1
	local myId = flashId
	hl.Enabled = true
	task.delay(0.15, function()
		if flashId == myId then
			hl.Enabled = false
		end
	end)
end

local function respawn()
	local m = model
	if not m then
		return
	end
	health = Config.DummyMaxHealth
	alive = true
	m:SetAttribute("Health", health)
	m:SetAttribute("Alive", true)
	setVisible(true)
	updateLabel()
	print(PREFIX, "Roman Zombie respawned")
end

local function defeat()
	local m = model
	if not m then
		return
	end
	alive = false
	m:SetAttribute("Alive", false)
	setVisible(false)

	-- Everyone who landed a hit during this life gets credit.
	for player in damagedBy do
		if player.Parent then
			player:SetAttribute(Config.ZombieDefeatedAttribute, true)
		end
	end
	table.clear(damagedBy)

	print(PREFIX, ("Roman Zombie defeated, respawning in %ds"):format(Config.DummyRespawnSeconds))
	task.delay(Config.DummyRespawnSeconds, respawn)
end

function Dummy.init(parent: Instance, position: Vector3, facing: Vector3)
	local base = CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z))

	local m = Instance.new("Model")
	m.Name = Config.DummyName
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- Offsets are relative to the feet; -Z is forward, so the arms reach out zombie-style.
	addPart(m, "LeftLeg", Vector3.new(1, 2, 1), base, Vector3.new(-0.5, 1, 0), LEGS)
	addPart(m, "RightLeg", Vector3.new(1, 2, 1), base, Vector3.new(0.5, 1, 0), LEGS)
	local body = addPart(m, "Torso", Vector3.new(2, 2, 1), base, Vector3.new(0, 3, 0), TUNIC)
	addPart(m, "LeftArm", Vector3.new(1, 1, 2.2), base, Vector3.new(-1.5, 3.5, -0.6), SKIN)
	addPart(m, "RightArm", Vector3.new(1, 1, 2.2), base, Vector3.new(1.5, 3.5, -0.6), SKIN)
	local head = addPart(m, "Head", Vector3.new(1.6, 1.4, 1.2), base, Vector3.new(0, 4.7, 0), SKIN)
	addPart(m, "Helmet", Vector3.new(1.8, 0.5, 1.4), base, Vector3.new(0, 5.6, 0), HELMET)
	addPart(m, "Crest", Vector3.new(0.4, 0.7, 1.6), base, Vector3.new(0, 6.2, 0), CREST)
	m.PrimaryPart = body

	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.new(1, 1, 1)
	hl.FillTransparency = 0.1
	hl.OutlineColor = Color3.fromRGB(255, 60, 60)
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Enabled = false
	hl.Parent = m

	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Adornee = head
	tag.Size = UDim2.fromOffset(180, 30)
	tag.StudsOffset = Vector3.new(0, 3, 0)
	tag.MaxDistance = 80
	tag.Parent = m

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = tag

	model, torso, highlight, nameTag, nameLabel = m, body, hl, tag, label
	m:SetAttribute("MaxHealth", Config.DummyMaxHealth)
	m.Parent = parent
	respawn()
end

-- Position the server measures attack range against, or nil while the dummy is down.
function Dummy.getTargetPosition(): Vector3?
	if alive and torso then
		return torso.Position
	end
	return nil
end

function Dummy.applyDamage(amount: number, attacker: Player)
	local m = model
	if not alive or not m then
		return
	end
	health = math.max(0, health - amount)
	damagedBy[attacker] = true
	m:SetAttribute("Health", health)
	updateLabel()
	flash()
	if health <= 0 then
		defeat()
	end
end

return Dummy
