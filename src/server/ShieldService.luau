--!strict
-- "Roman Shield" Tool. The client only says "I want to block / stop blocking";
-- the server decides whether the player is actually blocking and whether a hit is blocked.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local CombatUtil = require(script.Parent.CombatUtil)
local Remotes = require(script.Parent.Remotes)

local BRONZE = Color3.fromRGB(176, 125, 60)
local SHIELD_WOOD = Color3.fromRGB(128, 44, 32)
local PLANK_LINE = Color3.fromRGB(80, 30, 22)

-- Handle frame when held: +Y up, -Z forward (away from the player), +X to the player's right.
local IDLE_GRIP = CFrame.new(0, 0.4, 0) * CFrame.Angles(0, math.rad(70), 0)
local BLOCK_GRIP = CFrame.new(0.9, -0.4, 0.3)

type BlockState = {
	active: boolean,
	token: number,
}

local ShieldService = {}

local shields: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local states: { [Player]: BlockState } = {}

local function getState(player: Player): BlockState
	local state = states[player]
	if not state then
		state = { active = false, token = 0 }
		states[player] = state
	end
	return state
end

local function getEquippedShield(player: Player): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and shields[tool] then
		return tool
	end
	return nil
end

local function setBlocking(player: Player, active: boolean)
	local state = getState(player)
	if state.active == active then
		return
	end
	state.active = active
	state.token += 1

	local tool = getEquippedShield(player)
	if tool then
		tool.Grip = if active then BLOCK_GRIP else IDLE_GRIP
	end
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Block, active)

	if active then
		-- Exploit safeguard: a block can't be held forever
		local myToken = state.token
		task.delay(CombatConfig.ShieldMaxBlockSeconds, function()
			if state.token == myToken and state.active then
				setBlocking(player, false)
			end
		end)
	end
end

local function onBlockRequest(player: Player, wantsBlock: unknown)
	if typeof(wantsBlock) ~= "boolean" then
		return
	end
	if wantsBlock then
		local _, humanoid = CombatUtil.getLivingCharacter(player)
		if not humanoid or not getEquippedShield(player) then
			return
		end
	end
	setBlocking(player, wantsBlock)
end

local function weld(handle: BasePart, part: BasePart)
	local w = Instance.new("Weld")
	w.Part0 = handle
	w.Part1 = part
	w.C0 = handle.CFrame:Inverse() * part.CFrame
	w.Parent = part
end

local function buildTool(owner: Player): Tool
	local tool = Instance.new("Tool")
	tool.Name = CombatConfig.ShieldToolName
	tool.ToolTip = "Hold click to block"
	tool.CanBeDropped = false
	tool.Grip = IDLE_GRIP
	tool:SetAttribute(CombatConfig.ToolAttribute, "Shield")

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.8, 0.3)
	handle.Color = BRONZE
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Massless = true
	handle.CFrame = CFrame.identity
	handle.Parent = tool

	local function add(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = cframe
		part.Color = color
		part.Material = material
		part.CanCollide = false
		part.Massless = true
		if shape then
			part.Shape = shape
		end
		part.Parent = tool
		weld(handle, part)
		return part
	end

	-- Cylinders run along X, so turn them to face forward (-Z)
	local faceForward = CFrame.Angles(0, math.rad(90), 0)
	local rim = add("Rim", Vector3.new(0.25, 3.4, 3.4), CFrame.new(0, 0, -0.45) * faceForward, BRONZE, Enum.Material.Metal, Enum.PartType.Cylinder)
	add("Wood", Vector3.new(0.3, 3.0, 3.0), CFrame.new(0, 0, -0.55) * faceForward, SHIELD_WOOD, Enum.Material.WoodPlanks, Enum.PartType.Cylinder)
	add("Boss", Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, 0, -0.75), BRONZE, Enum.Material.Metal, Enum.PartType.Ball)
	for _, x in { -0.75, 0.75 } do
		add("PlankLine", Vector3.new(0.06, 2.6, 0.04), CFrame.new(x, 0, -0.72), PLANK_LINE, Enum.Material.Wood)
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "BlockFlash"
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.2
	highlight.OutlineTransparency = 1
	highlight.Enabled = false
	highlight.Parent = tool

	local sound = Instance.new("Sound")
	sound.Name = "BlockSound"
	sound.SoundId = CombatConfig.ShieldSoundId
	sound.Volume = 0.6
	sound.Parent = rim

	tool.Unequipped:Connect(function()
		setBlocking(owner, false)
		tool.Grip = IDLE_GRIP
	end)

	return tool
end

local function feedback(tool: Tool)
	local highlight = tool:FindFirstChild("BlockFlash")
	if highlight and highlight:IsA("Highlight") then
		highlight.Enabled = true
		task.delay(0.15, function()
			highlight.Enabled = false
		end)
	end
	local rim = tool:FindFirstChild("Rim")
	local sound = rim and rim:FindFirstChild("BlockSound")
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

function ShieldService.init()
	Remotes.ShieldBlock.OnServerEvent:Connect(onBlockRequest)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

function ShieldService.give(player: Player, backpack: Instance)
	if backpack:FindFirstChild(CombatConfig.ShieldToolName) then
		return
	end
	local state = states[player]
	if state then
		state.active = false
		state.token += 1
	end
	local tool = buildTool(player)
	shields[tool] = true
	tool.Parent = backpack
end

-- True while the server considers the player's shield raised.
function ShieldService.isBlocking(player: Player): boolean
	local state = states[player]
	if not state or not state.active then
		return false
	end
	local _, humanoid = CombatUtil.getLivingCharacter(player)
	return humanoid ~= nil and getEquippedShield(player) ~= nil
end

-- Called by the attacker: returns true if this hit is blocked (raised, facing the attacker, close).
function ShieldService.tryBlock(player: Player, attackerPosition: Vector3): boolean
	if not ShieldService.isBlocking(player) then
		return false
	end
	local _, _, root = CombatUtil.getLivingCharacter(player)
	if not root then
		return false
	end
	if CombatUtil.flatDistance(root.Position, attackerPosition) > CombatConfig.ShieldBlockDistance then
		return false
	end
	if not CombatUtil.isFacing(root.CFrame, attackerPosition, CombatConfig.ShieldFacingDot) then
		return false
	end
	local tool = getEquippedShield(player)
	if tool then
		feedback(tool)
	end
	return true
end

return ShieldService
