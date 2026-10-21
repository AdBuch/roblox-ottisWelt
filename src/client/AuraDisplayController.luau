--!strict
-- Gladiator level and Denarii: two compact capsules in the upper-right corner, only in the lobby
-- (where the armory is, so both are visible while buying).
--   LEVEL (gold)          "LV 3  GLADIATOR" with a thin bar: progress of the total Aura toward the next
--                         level (GladiatorLevelDefinitions; Aura is experience and is never spent)
--   DENARII (silver coin) the money for gear
-- In combat there is no permanent counter: earned amounts show as short "+n" notifications (rapid
-- rewards are merged), and a level-up shows a short banner-style notice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GladiatorLevelDefinitions = require(Shared:WaitForChild("GladiatorLevelDefinitions"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}

export type AuraDisplay = {
	set: (aura: number, denarii: number) -> (),
	reward: (aura: number, denarii: number?) -> (),
}

local AuraDisplayController = {}

local SILVER = Color3.fromRGB(214, 222, 232)
local LEVEL_WIDTH = 150
local COIN_WIDTH = 96
local GAP = 6

local function capsuleFrame(parent: Frame, x: number, width: number): Frame
	local frame = Instance.new("Frame")
	frame.Position = UDim2.fromOffset(x, 0)
	frame.Size = UDim2.fromOffset(width, 30)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.55
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	return frame
end

local function label(parent: Instance, position: UDim2, size: UDim2, textSize: number, color: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.Position = position
	text.Size = size
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextSize = textSize
	text.TextColor3 = color
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.Text = ""
	text.Parent = parent
	return text
end

function AuraDisplayController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, notify: (kind: string, text: string, amount: number?) -> ()): AuraDisplay
	local frame = group("Aura", Vector2.new(1, 0), UDim2.new(1, -8, 0, 6), UDim2.fromOffset(LEVEL_WIDTH + GAP + COIN_WIDTH, 30))

	-- LEVEL capsule: number + title, Aura progress bar underneath
	local levelCapsule = capsuleFrame(frame, 0, LEVEL_WIDTH)
	local levelText = label(levelCapsule, UDim2.fromOffset(12, 2), UDim2.new(1, -20, 0, 16), 13, UiConfig.Gold)
	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 12, 1, -9)
	track.Size = UDim2.new(1, -24, 0, 4)
	track.BackgroundColor3 = Color3.fromRGB(70, 56, 40)
	track.BorderSizePixel = 0
	track.Parent = levelCapsule
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track
	local progress = Instance.new("Frame")
	progress.Size = UDim2.fromScale(0, 1)
	progress.BackgroundColor3 = UiConfig.Gold
	progress.BorderSizePixel = 0
	progress.Parent = track
	local progressCorner = Instance.new("UICorner")
	progressCorner.CornerRadius = UDim.new(1, 0)
	progressCorner.Parent = progress

	-- DENARII capsule: silver coin + number
	local coinCapsule = capsuleFrame(frame, LEVEL_WIDTH + GAP, COIN_WIDTH)
	local coin = Instance.new("Frame")
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, 6, 0.5, 0)
	coin.Size = UDim2.fromOffset(16, 16)
	coin.BackgroundColor3 = SILVER
	coin.Parent = coinCapsule
	local coinCorner = Instance.new("UICorner")
	coinCorner.CornerRadius = UDim.new(1, 0)
	coinCorner.Parent = coin
	local coinMark = label(coin, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 10, Color3.fromRGB(110, 116, 126))
	coinMark.TextXAlignment = Enum.TextXAlignment.Center
	coinMark.Text = "D"
	local coinText = label(coinCapsule, UDim2.fromOffset(28, 0), UDim2.new(1, -34, 1, 0), 16, SILVER)
	local bump = Instance.new("UIScale")
	bump.Parent = coinCapsule
	visibility.register("Aura", frame)

	local shownLevel = 0
	return {
		set = function(aura: number, denarii: number)
			local current, nextLevel, share = GladiatorLevelDefinitions.levelFor(aura)
			levelText.Text = ("LV %d  %s"):format(current.Level, current.Title)
			TweenService:Create(progress, TweenInfo.new(0.25), { Size = UDim2.fromScale(if nextLevel then share else 1, 1) }):Play()
			if shownLevel ~= 0 and current.Level > shownLevel then
				notify("Info", ("LEVEL UP · LV %d %s"):format(current.Level, current.Title))
			end
			shownLevel = current.Level
			local text = tostring(denarii)
			if coinText.Text ~= text then
				coinText.Text = text
				bump.Scale = 1.12
				TweenService:Create(bump, TweenInfo.new(0.25), { Scale = 1 }):Play()
			end
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
