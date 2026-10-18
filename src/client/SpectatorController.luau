--!strict
-- Spectator bar (tribune / waiting co-op players): who you are watching, previous / next fighter
-- and EXIT (back to the lobby, same as the RETURN TO LOBBY door). Watching only moves your own
-- camera locally; leaving the spectator state always gives the camera back to your character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameStates = require(Shared:WaitForChild("GameStates"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}

export type Spectator = {
	onStateChanged: (state: string) -> (),
}

local SpectatorController = {}

function SpectatorController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, remote: RemoteEvent?): Spectator
	local player = Players.LocalPlayer
	local frame = group("SpectatorBar", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -16), UDim2.fromOffset(320, 44))
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
		b.Size = UDim2.fromOffset(width, 44)
		b.BackgroundTransparency = 1
		b.Font = Enum.Font.GothamBlack
		b.TextSize = 16
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = text
		b.Parent = back
		return b
	end
	local previous = button("◀", 0, 44)
	local nextButton = button("▶", 196, 44)
	local exit = button("EXIT", 248, 64)
	exit.TextColor3 = UiConfig.Gold
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(44, 0)
	label.Size = UDim2.fromOffset(152, 44)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = "TRIBUNES"
	label.Parent = back

	local watchedIndex = 0
	local function fighters(): { Player }
		local list = {}
		for _, other in Players:GetPlayers() do
			if other ~= player and other:GetAttribute(GameStates.LocationAttribute) == "Arena" and GameStates.isFighter(other:GetAttribute(GameStates.StateAttribute)) then
				table.insert(list, other)
			end
		end
		return list
	end
	local function ownCamera()
		local camera = Workspace.CurrentCamera
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if camera and humanoid then
			camera.CameraSubject = humanoid
		end
		label.Text = "TRIBUNES"
	end
	local function watch(step: number)
		local list = fighters()
		if #list == 0 then
			watchedIndex = 0
			ownCamera()
			return
		end
		watchedIndex = (watchedIndex - 1 + step) % #list + 1
		local target = list[watchedIndex]
		local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
		local camera = Workspace.CurrentCamera
		if camera and humanoid then
			camera.CameraSubject = humanoid
			label.Text = "WATCHING " .. target.DisplayName
		end
	end
	previous.Activated:Connect(function()
		watch(-1)
	end)
	nextButton.Activated:Connect(function()
		watch(1)
	end)
	exit.Activated:Connect(function()
		ownCamera()
		if remote then
			remote:FireServer("LeaveTribune")
		end
	end)
	visibility.register("Spectator", frame)

	return {
		onStateChanged = function(state: string)
			if state ~= "Spectator" and watchedIndex ~= 0 then
				watchedIndex = 0
				ownCamera()
			end
		end,
	}
end

return SpectatorController
