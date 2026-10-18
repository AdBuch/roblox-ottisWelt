--!strict
-- Aura Points: a compact orb + number in the upper-right corner, only in the lobby (where the
-- shop is, so it is visible while buying). In combat there is no permanent counter: earned Aura
-- shows as a short "+n" with the orb in the notification queue (rapid rewards are merged).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiConfig"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}

export type AuraDisplay = {
	set: (amount: number) -> (),
	reward: (amount: number) -> (),
}

local AuraDisplayController = {}

function AuraDisplayController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, notify: (kind: string, text: string, amount: number?) -> ()): AuraDisplay
	local frame = group("Aura", Vector2.new(1, 0), UDim2.new(1, -8, 0, 6), UDim2.fromOffset(96, 28))
	local capsule = Instance.new("Frame")
	capsule.Size = UDim2.fromScale(1, 1)
	capsule.BackgroundColor3 = Color3.new(0, 0, 0)
	capsule.BackgroundTransparency = 0.55
	capsule.Parent = frame
	local capsuleCorner = Instance.new("UICorner")
	capsuleCorner.CornerRadius = UDim.new(1, 0)
	capsuleCorner.Parent = capsule
	local orb = Instance.new("Frame")
	orb.AnchorPoint = Vector2.new(0, 0.5)
	orb.Position = UDim2.new(0, 6, 0.5, 0)
	orb.Size = UDim2.fromOffset(16, 16)
	orb.BackgroundColor3 = UiConfig.Gold
	orb.Parent = capsule
	local orbCorner = Instance.new("UICorner")
	orbCorner.CornerRadius = UDim.new(1, 0)
	orbCorner.Parent = orb
	local orbGlow = Instance.new("UIStroke")
	orbGlow.Color = Color3.fromRGB(255, 240, 160)
	orbGlow.Thickness = 2
	orbGlow.Transparency = 0.3
	orbGlow.Parent = orb
	local count = Instance.new("TextLabel")
	count.Position = UDim2.fromOffset(28, 0)
	count.Size = UDim2.new(1, -34, 1, 0)
	count.BackgroundTransparency = 1
	count.Font = Enum.Font.GothamBlack
	count.TextSize = 16
	count.TextColor3 = UiConfig.Gold
	count.TextXAlignment = Enum.TextXAlignment.Left
	count.Text = "0"
	count.Parent = capsule
	local bump = Instance.new("UIScale")
	bump.Parent = capsule
	visibility.register("Aura", frame)

	return {
		set = function(amount: number)
			if count.Text ~= tostring(amount) then
				count.Text = tostring(amount)
				bump.Scale = 1.12
				TweenService:Create(bump, TweenInfo.new(0.25), { Scale = 1 }):Play()
			end
		end,
		reward = function(amount: number)
			if amount > 0 then
				notify("Aura", ("+%d"):format(amount), amount)
			end
		end,
	}
end

return AuraDisplayController
