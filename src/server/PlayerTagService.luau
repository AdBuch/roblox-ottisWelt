--!strict
-- Overhead indicators above every player: name, health bar and a role tag (team colour in
-- Team Battle, party marker in Co-op, spectator marker on the tribune, training in the lobby).
-- BillboardGuis are not AlwaysOnTop, so they never reveal players through walls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GameStates = require(ReplicatedStorage.Shared.GameStates)

local PlayerTagService = {}

type Tag = { gui: BillboardGui, name: TextLabel, role: TextLabel, fill: Frame }

local tags: { [Player]: Tag } = {}

local function roleFor(player: Player): (string, Color3)
	local team = player:GetAttribute(Config.TeamAttribute)
	local state = player:GetAttribute(GameStates.StateAttribute)
	if team == "Red" then
		return "RED GLADIATOR", Color3.fromRGB(255, 110, 110)
	elseif team == "Blue" then
		return "BLUE GLADIATOR", Color3.fromRGB(120, 170, 255)
	elseif state == GameStates.Spectating then
		return "SPECTATOR", Color3.fromRGB(200, 200, 255)
	elseif player:GetAttribute(Config.InPartyAttribute) == true then
		return "CO-OP LEGION", Color3.fromRGB(255, 210, 120)
	end
	return "", Color3.new(1, 1, 1)
end

local function refresh(player: Player)
	local tag = tags[player]
	if not tag then
		return
	end
	local text, color = roleFor(player)
	tag.role.Text = text
	tag.role.TextColor3 = color
	tag.name.TextColor3 = if text ~= "" then color else Color3.new(1, 1, 1)
end

local function attach(player: Player, character: Model)
	local head = character:WaitForChild("Head", 5)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not head or not head:IsA("BasePart") or not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- replaced by our tag

	local gui = Instance.new("BillboardGui")
	gui.Name = "OttiTag"
	gui.Size = UDim2.fromOffset(140, 44)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 80
	gui.AlwaysOnTop = false
	gui.Adornee = head
	gui.Parent = head

	local role = Instance.new("TextLabel")
	role.Size = UDim2.new(1, 0, 0, 12)
	role.BackgroundTransparency = 1
	role.Font = Enum.Font.GothamBold
	role.TextSize = 11
	role.TextStrokeTransparency = 0.4
	role.Parent = gui
	local name = Instance.new("TextLabel")
	name.Position = UDim2.fromOffset(0, 12)
	name.Size = UDim2.new(1, 0, 0, 18)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 15
	name.Text = player.DisplayName
	name.TextStrokeTransparency = 0.4
	name.Parent = gui
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(20, 32)
	back.Size = UDim2.new(1, -40, 0, 6)
	back.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = back

	tags[player] = { gui = gui, name = name, role = role, fill = fill }
	local function updateHealth()
		fill.Size = UDim2.fromScale(math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1), 1)
	end
	humanoid.HealthChanged:Connect(updateHealth)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateHealth)
	updateHealth()
	refresh(player)
end

function PlayerTagService.init()
	local function setup(player: Player)
		player.CharacterAdded:Connect(function(character)
			attach(player, character)
		end)
		if player.Character then
			task.spawn(attach, player, player.Character)
		end
		for _, attribute in { Config.TeamAttribute, Config.InPartyAttribute, GameStates.StateAttribute } do
			player:GetAttributeChangedSignal(attribute):Connect(function()
				refresh(player)
			end)
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		tags[player] = nil
	end)
end

return PlayerTagService
