--!strict
-- Arena spectator bar and camera (spectators, defeated co-op fighters, eliminated players).
-- Camera modes (local camera only, never server state):
--   WALK      your own character: free walking on the tribunes
--   FOLLOW    follow a fighter (◀ / ▶ = previous / next)
--   OVERVIEW  fixed overview points around the Colosseum (◀ / ▶ cycle them)
--   OTTI      follow Otti while he is in the arena
-- Eliminated players (ArenaRole ELIMINATED_SPECTATOR) may only FOLLOW living teammates: no
-- overview, no walking, no enemy cameras. Buttons: ◀ · name · ▶ · CAM · HUB (return to the Hub).
-- Desktop shortcuts: Q previous, E next, C camera mode. No combat controls, no Aura counter.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameStates = require(Shared:WaitForChild("GameStates"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}

export type Spectator = {
	onStateChanged: (state: string) -> (),
}

type Mode = "WALK" | "FOLLOW" | "OVERVIEW" | "OTTI"

local SpectatorController = {}

function SpectatorController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, remote: RemoteEvent?, request: RemoteFunction?): Spectator
	local player = Players.LocalPlayer
	local frame = group("SpectatorBar", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -16), UDim2.fromOffset(340, 46))
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = UiConfig.Panel
	back.BackgroundTransparency = 0.3
	back.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = back
	local function button(text: string, x: number, width: number): TextButton
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(x, 0)
		b.Size = UDim2.fromOffset(width, 46)
		b.BackgroundTransparency = 1
		b.Font = Enum.Font.GothamBlack
		b.TextSize = 16
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = text
		b.Parent = back
		return b
	end
	local previous = button("◀", 0, 44)
	local nextButton = button("▶", 182, 44)
	local camButton = button("CAM", 228, 52)
	camButton.TextSize = 13
	local hub = button("HUB", 282, 56)
	hub.TextColor3 = UiConfig.Gold
	hub.TextSize = 14
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(44, 0)
	label.Size = UDim2.fromOffset(138, 46)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextWrapped = true
	label.Text = "TRIBUNES"
	label.Parent = back

	local mode: Mode = "WALK"
	local index = 0
	local active = false

	local function eliminated(): boolean
		return player:GetAttribute(Config.ArenaRoleAttribute) == "ELIMINATED_SPECTATOR"
	end

	local function fighters(): { Player }
		local list = {}
		local myTeam = player:GetAttribute(Config.TeamAttribute)
		for _, other in Players:GetPlayers() do
			local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			if other ~= player and humanoid and humanoid.Health > 0
				and other:GetAttribute(GameStates.LocationAttribute) == "Arena"
				and GameStates.isFighter(other:GetAttribute(GameStates.StateAttribute))
				and (not eliminated() or other:GetAttribute(Config.TeamAttribute) == myTeam) then
				table.insert(list, other)
			end
		end
		table.sort(list, function(a, b)
			return a.UserId < b.UserId
		end)
		return list
	end

	local function cameraPoints(): { BasePart }
		local list = {}
		for _, part in CollectionService:GetTagged("SpectatorCamera") do
			if part:IsA("BasePart") then
				table.insert(list, part)
			end
		end
		table.sort(list, function(a, b)
			return (tonumber(a:GetAttribute("Order")) or 0) < (tonumber(b:GetAttribute("Order")) or 0)
		end)
		return list
	end

	local function otti(): Model?
		for _, model in CollectionService:GetTagged(Config.OttiTag) do
			if model:IsA("Model") and model.Parent then
				return model
			end
		end
		return nil
	end

	local function ownCamera()
		local camera = Workspace.CurrentCamera
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if camera then
			camera.CameraType = Enum.CameraType.Custom
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end

	local function apply(step: number)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		if eliminated() and mode ~= "FOLLOW" then
			mode = "FOLLOW" -- teammates only
		end
		if mode == "FOLLOW" then
			local list = fighters()
			if #list == 0 then
				index = 0
				if eliminated() then
					label.Text = "NO TEAMMATE LEFT"
					return
				end
				mode = "WALK"
				ownCamera()
				label.Text = "TRIBUNES · no fighter"
				return
			end
			index = (index - 1 + step) % #list + 1
			local target = list[index]
			local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraType = Enum.CameraType.Custom
				camera.CameraSubject = humanoid
				label.Text = "WATCHING " .. target.DisplayName
			end
		elseif mode == "OVERVIEW" then
			local points = cameraPoints()
			if #points == 0 then
				mode = "WALK"
				ownCamera()
				return
			end
			index = (index - 1 + step) % #points + 1
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = points[index].CFrame
			label.Text = "OVERVIEW · " .. tostring(points[index]:GetAttribute("Label") or index)
		elseif mode == "OTTI" then
			local boss = otti()
			local humanoid = boss and boss:FindFirstChildOfClass("Humanoid")
			if not boss or not humanoid then
				mode = "FOLLOW"
				apply(0)
				return
			end
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = humanoid
			label.Text = "WATCHING OTTI"
		else
			ownCamera()
			label.Text = "TRIBUNES · walk freely"
		end
	end

	local function cycleMode()
		if eliminated() then
			apply(1)
			return
		end
		local order: { Mode } = { "WALK", "FOLLOW", "OVERVIEW", "OTTI" }
		local i = table.find(order, mode) or 1
		mode = order[i % #order + 1]
		if mode == "OTTI" and not otti() then
			mode = "WALK"
		end
		index = 0
		apply(1)
	end

	previous.Activated:Connect(function()
		apply(-1)
	end)
	nextButton.Activated:Connect(function()
		apply(1)
	end)
	camButton.Activated:Connect(cycleMode)
	hub.Activated:Connect(function()
		ownCamera()
		mode = "WALK"
		if request then
			task.spawn(function()
				pcall(function()
					request:InvokeServer("ReturnToHub")
				end)
			end)
		elseif remote then
			remote:FireServer("LeaveTribune")
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not active then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q then
			apply(-1)
		elseif input.KeyCode == Enum.KeyCode.E then
			apply(1)
		elseif input.KeyCode == Enum.KeyCode.C then
			cycleMode()
		end
	end)
	player:GetAttributeChangedSignal(Config.ArenaRoleAttribute):Connect(function()
		camButton.Visible = not eliminated()
		if active and eliminated() then
			mode = "FOLLOW"
			index = 0
			apply(1)
		end
	end)
	-- Followed fighter died / left: move on to the next one
	task.spawn(function()
		while true do
			task.wait(1)
			if active and mode == "FOLLOW" then
				local camera = Workspace.CurrentCamera
				local subject = camera and camera.CameraSubject
				if not subject or not subject:IsA("Humanoid") or subject.Health <= 0 or subject.Parent == player.Character then
					apply(1)
				end
			end
		end
	end)
	visibility.register("Spectator", frame)

	return {
		onStateChanged = function(state: string)
			local nowActive = state == "Spectator"
			if nowActive and not active then
				active = true
				camButton.Visible = not eliminated()
				mode = if eliminated() then "FOLLOW" else "WALK"
				index = 0
				apply(1)
			elseif not nowActive and active then
				active = false
				mode = "WALK"
				index = 0
				ownCamera()
			end
		end,
	}
end

return SpectatorController
