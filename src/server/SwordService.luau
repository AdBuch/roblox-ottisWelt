--!strict
-- "Roman Sword" Tool. The client only requests a swing; the server validates the
-- equipped tool, cooldown, alive state, distance, facing and line of sight, then applies damage.
-- Each accepted request is exactly one swing and can hit at most once.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local CombatUtil = require(script.Parent.CombatUtil)
local Remotes = require(script.Parent.Remotes)
local ShieldService = require(script.Parent.ShieldService)
local ZombieService = require(script.Parent.ZombieService)

local PREFIX = "[OttiArena][Server]"

local BRONZE = Color3.fromRGB(176, 125, 60)
local LEATHER = Color3.fromRGB(74, 46, 26)
local STEEL = Color3.fromRGB(196, 196, 190)

-- Handle frame when held: +Y up (blade direction), -Z forward. Rotating the Grip about X swings the blade.
local REST_GRIP = CFrame.identity
local WINDUP_GRIP = CFrame.Angles(math.rad(-45), 0, 0)
local SLASH_GRIP = CFrame.Angles(math.rad(95), 0, 0)

local SwordService = {}

local swords: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local lastSwing: { [Player]: number } = {}
local announced: { [Player]: boolean } = {}

local function weld(handle: BasePart, part: BasePart)
	local w = Instance.new("Weld")
	w.Part0 = handle
	w.Part1 = part
	w.C0 = handle.CFrame:Inverse() * part.CFrame
	w.Parent = part
end

local function buildTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = CombatConfig.SwordToolName
	tool.ToolTip = "Click to attack"
	tool.CanBeDropped = false
	tool.Grip = REST_GRIP
	tool:SetAttribute(CombatConfig.ToolAttribute, "Sword")

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 1.0, 0.3)
	handle.Color = LEATHER
	handle.Material = Enum.Material.Leather
	handle.CanCollide = false
	handle.Massless = true
	handle.CFrame = CFrame.identity
	handle.Parent = tool

	local function add(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?)
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
	end

	add("Pommel", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, -0.6, 0), BRONZE, Enum.Material.Metal, Enum.PartType.Ball)
	add("Guard", Vector3.new(1.1, 0.22, 0.35), CFrame.new(0, 0.6, 0), BRONZE, Enum.Material.Metal)
	add("Blade", Vector3.new(0.38, 2.6, 0.12), CFrame.new(0, 2.0, 0), STEEL, Enum.Material.Metal)
	add("Tip", Vector3.new(0.27, 0.27, 0.12), CFrame.new(0, 3.3, 0) * CFrame.Angles(0, 0, math.rad(45)), STEEL, Enum.Material.Metal)

	local sound = Instance.new("Sound")
	sound.Name = "SlashSound"
	sound.SoundId = CombatConfig.SwordSoundId
	sound.Volume = 0.5
	sound.Parent = handle

	return tool
end

-- Visible slash: wind back, swing forward, return. Grip changes replicate to everyone.
local function playSlash(tool: Tool)
	tool.Grip = WINDUP_GRIP
	local handle = tool:FindFirstChild("Handle")
	local sound = handle and handle:FindFirstChild("SlashSound")
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
	task.delay(0.08, function()
		TweenService:Create(tool, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Grip = SLASH_GRIP }):Play()
	end)
	task.delay(0.3, function()
		TweenService:Create(tool, TweenInfo.new(0.2), { Grip = REST_GRIP }):Play()
	end)
end

local function onSwingRequest(player: Player)
	if not announced[player] then
		announced[player] = true
		print(PREFIX, "First sword request received from", player.Name, "(RemoteEvent works)")
	end

	local character, _, root = CombatUtil.getLivingCharacter(player)
	if not character or not root then
		return
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or not swords[tool] then
		return
	end
	if ShieldService.isBlocking(player) then
		return
	end
	local now = os.clock()
	local last = lastSwing[player]
	if last and now - last < CombatConfig.SwordCooldown then
		return
	end
	lastSwing[player] = now

	playSlash(tool)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Swing)

	local zombieModel, zombieRoot = ZombieService.getLiving()
	if not zombieModel or not zombieRoot then
		return
	end
	local target = zombieRoot.Position
	if CombatUtil.flatDistance(root.Position, target) > CombatConfig.SwordRange then
		return
	end
	if math.abs(root.Position.Y - target.Y) > 6 then
		return
	end
	if not CombatUtil.isFacing(root.CFrame, target, CombatConfig.SwordFacingDot) then
		return
	end
	if not CombatUtil.hasLineOfSight(root.Position, target, { character, zombieModel }) then
		return
	end

	ZombieService.damage(player, CombatConfig.SwordDamage)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.SwordHit)
end

function SwordService.init()
	Remotes.SwordAttack.OnServerEvent:Connect(onSwingRequest) -- any client arguments are ignored
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
		announced[player] = nil
	end)
end

function SwordService.give(backpack: Instance)
	if backpack:FindFirstChild(CombatConfig.SwordToolName) then
		return
	end
	local tool = buildTool()
	swords[tool] = true
	tool.Parent = backpack
end

return SwordService
