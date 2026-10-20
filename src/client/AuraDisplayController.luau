--!strict
-- Aura and Denarii: two compact capsules in the upper-right corner, only in the lobby (where the
-- armory is, so both are visible while buying).
--   AURA (gold orb)       progress, never spent: unlocks gear
--   DENARII (silver coin) money: buys unlocked gear
-- In combat there is no permanent counter: earned amounts show as short "+n" notifications (rapid
-- rewards are merged).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiConfig"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}

export type AuraDisplay = {
	set: (aura: number, denarii: number) -> (),
	reward: (aura: number, denarii: number?) -> (),
}

local AuraDisplayController = {}

local SILVER = Color3.fromRGB(214, 222, 232)
local CAPSULE_WIDTH = 96
local GAP = 6

type Capsule = { label: TextLabel, bump: UIScale }

local function capsule(parent: Frame, x: number, color: Color3, glow: Color3, coin: boolean): Capsule
	local frame = Instance.new("Frame")
	frame.Position = UDim2.fromOffset(x, 0)
	frame.Size = UDim2.fromOffset(CAPSULE_WIDTH, 28)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.55
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	local icon = Instance.new("Frame")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 6, 0.5, 0)
	icon.Size = UDim2.fromOffset(16, 16)
	icon.BackgroundColor3 = color
	icon.Parent = frame
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = icon
	local stroke = Instance.new("UIStroke")
	stroke.Color = glow
	stroke.Thickness = if coin then 1.5 else 2
	stroke.Transparency = if coin then 0 else 0.3
	stroke.Parent = icon
	if coin then
		-- a small "D" stamped on the coin
		local mark = Instance.new("TextLabel")
		mark.Size = UDim2.fromScale(1, 1)
		mark.BackgroundTransparency = 1
		mark.Font = Enum.Font.GothamBlack
		mark.TextSize = 10
		mark.TextColor3 = Color3.fromRGB(110, 116, 126)
		mark.Text = "D"
		mark.Parent = icon
	end
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(28, 0)
	label.Size = UDim2.new(1, -34, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 16
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "0"
	label.Parent = frame
	local bump = Instance.new("UIScale")
	bump.Parent = frame
	return { label = label, bump = bump }
end

local function show(c: Capsule, amount: number)
	local text = tostring(amount)
	if c.label.Text ~= text then
		c.label.Text = text
		c.bump.Scale = 1.12
		TweenService:Create(c.bump, TweenInfo.new(0.25), { Scale = 1 }):Play()
	end
end

function AuraDisplayController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, notify: (kind: string, text: string, amount: number?) -> ()): AuraDisplay
	local frame = group("Aura", Vector2.new(1, 0), UDim2.new(1, -8, 0, 6), UDim2.fromOffset(CAPSULE_WIDTH * 2 + GAP, 28))
	local aura = capsule(frame, 0, UiConfig.Gold, Color3.fromRGB(255, 240, 160), false)
	local denarii = capsule(frame, CAPSULE_WIDTH + GAP, SILVER, Color3.fromRGB(150, 156, 166), true)
	visibility.register("Aura", frame)

	return {
		set = function(auraAmount: number, denariiAmount: number)
			show(aura, auraAmount)
			show(denarii, denariiAmount)
		end,
		reward = function(auraAmount: number, denariiAmount: number?)
			if auraAmount > 0 then
				notify("Aura", ("+%d"):format(auraAmount), auraAmount)
			end
			if denariiAmount and denariiAmount > 0 then
				notify("Denarii", ("+%d DENARII"):format(denariiAmount), denariiAmount)
			end
		end,
	}
end

return AuraDisplayController
