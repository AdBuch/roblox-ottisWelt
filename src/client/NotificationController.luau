--!strict
-- The single notification queue. Every system posts here instead of creating its own text:
--   push(kind, text, amount?)  small messages in a stack under the top bars (max 3 visible);
--                              Aura and healing amounts are merged when they arrive in quick
--                              succession; a more important message replaces the least important
--   banner(title, subtitle?, detail?, seconds?)  a short, larger message in the upper third
--                              (ROUND 4, ROUND COMPLETE, results); nil seconds = stays until cleared
-- Labels are pooled (no GUI objects created per message). Kinds: NotificationDefinitions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NotificationDefinitions = require(Shared:WaitForChild("NotificationDefinitions"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))

export type Notifier = {
	push: (kind: string, text: string, amount: number?) -> (),
	banner: (title: string?, subtitle: string?, detail: string?, seconds: number?) -> (),
	clear: () -> (),
	stack: Frame,
	bannerFrame: Frame,
}

type Slot = {
	frame: Frame,
	label: TextLabel,
	orb: Frame,
	offset: UIScale,
	kind: string?,
	priority: number,
	amount: number,
	expires: number,
	started: number,
	token: number,
}

local NotificationController = {}

function NotificationController.create(group: (string, Vector2, UDim2, UDim2?) -> Frame, allowed: () -> boolean): Notifier
	local stack = group("Notifications", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 64), UDim2.fromOffset(260, 3 * 30))
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 2)
	list.Parent = stack

	local slots: { Slot } = {}
	for i = 1, UiConfig.MaxNotifications do
		local frame = Instance.new("Frame")
		frame.Name = "Notification" .. i
		frame.Size = UDim2.fromOffset(260, 28)
		frame.BackgroundTransparency = 1
		frame.Visible = false
		frame.LayoutOrder = i
		frame.Parent = stack
		local orb = Instance.new("Frame") -- small Aura orb (only for Aura rewards)
		orb.AnchorPoint = Vector2.new(1, 0.5)
		orb.Size = UDim2.fromOffset(16, 16)
		orb.BackgroundColor3 = UiConfig.Gold
		orb.Visible = false
		orb.Parent = frame
		local orbCorner = Instance.new("UICorner")
		orbCorner.CornerRadius = UDim.new(1, 0)
		orbCorner.Parent = orb
		local orbGlow = Instance.new("UIStroke")
		orbGlow.Color = Color3.fromRGB(255, 240, 160)
		orbGlow.Thickness = 2
		orbGlow.Transparency = 0.3
		orbGlow.Parent = orb
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextSize = 20
		label.TextStrokeTransparency = 0.35
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = frame
		local offset = Instance.new("UIScale")
		offset.Parent = frame
		table.insert(slots, { frame = frame, label = label, orb = orb, offset = offset, kind = nil, priority = 99, amount = 0, expires = 0, started = 0, token = 0 })
	end

	local function render(slot: Slot, text: string)
		slot.label.Text = text
		local width = math.min(240, 14 * #text)
		slot.orb.Position = UDim2.new(0.5, -width / 2 - 4, 0.5, 0)
		slot.orb.Visible = slot.kind == "Aura"
	end

	local function show(slot: Slot, kind: string, text: string, amount: number)
		local def = (NotificationDefinitions :: any)[kind] or (NotificationDefinitions :: any).Info
		local now = os.clock()
		slot.kind = kind
		slot.priority = def.Priority
		slot.amount = amount
		slot.started = now
		slot.expires = now + (def.Seconds or UiConfig.NotificationSeconds)
		slot.token += 1
		local myToken = slot.token
		slot.label.TextColor3 = def.Color
		slot.label.TextTransparency = 0
		slot.label.TextStrokeTransparency = 0.35
		slot.orb.BackgroundTransparency = 0
		render(slot, text)
		slot.frame.Visible = true
		-- Pop in, drift slightly upward (Aura), fade out at the end
		slot.offset.Scale = 0.8
		TweenService:Create(slot.offset, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.spawn(function()
			while slot.token == myToken and os.clock() < slot.expires do
				task.wait(0.1)
			end
			if slot.token ~= myToken then
				return
			end
			local fade = TweenInfo.new(0.3)
			TweenService:Create(slot.label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			TweenService:Create(slot.orb, fade, { BackgroundTransparency = 1 }):Play()
			task.wait(0.3)
			if slot.token == myToken then
				slot.frame.Visible = false
				slot.kind = nil
				slot.priority = 99
			end
		end)
	end

	local function push(kind: string, text: string, amount: number?)
		local def = (NotificationDefinitions :: any)[kind] or (NotificationDefinitions :: any).Info
		if not def.AlwaysShown and not allowed() then
			return
		end
		local now = os.clock()
		-- Merge rapid rewards / heals into one message
		if def.Combine and amount then
			for _, slot in slots do
				if slot.kind == kind and slot.frame.Visible and now - slot.started <= UiConfig.AuraCombineWindow + (def.Seconds or 1) then
					slot.amount += amount
					slot.expires = now + (def.Seconds or UiConfig.NotificationSeconds)
					render(slot, if kind == "Aura" then ("+%d"):format(slot.amount) else ("+%d HEALTH"):format(slot.amount))
					slot.offset.Scale = 1.15
					TweenService:Create(slot.offset, TweenInfo.new(0.15), { Scale = 1 }):Play()
					return
				end
			end
		end
		-- A free slot, or replace the least important one if this message matters more
		local target: Slot? = nil
		for _, slot in slots do
			if not slot.frame.Visible then
				target = slot
				break
			end
		end
		if not target then
			local worst: Slot? = nil
			for _, slot in slots do
				if not worst or slot.priority > worst.priority or (slot.priority == worst.priority and slot.started < worst.started) then
					worst = slot
				end
			end
			if worst and def.Priority <= worst.priority then
				target = worst
			end
		end
		if target then
			show(target, kind, text, amount or 0)
		end
	end

	------------------------------------------------------------------ banner (upper third)
	local bannerFrame = group("Banner", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0.2, 0), UDim2.fromOffset(560, 96))
	local function bannerLabel(name: string, y: number, height: number, size: number, font: Enum.Font, color: Color3): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Position = UDim2.fromOffset(0, y)
		label.Size = UDim2.new(1, 0, 0, height)
		label.BackgroundTransparency = 1
		label.Font = font
		label.TextSize = size
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.3
		label.TextWrapped = true
		label.Text = ""
		label.Parent = bannerFrame
		return label
	end
	local title = bannerLabel("Title", 0, 44, 38, Enum.Font.GothamBlack, UiConfig.Gold)
	local subtitle = bannerLabel("Subtitle", 44, 26, 20, Enum.Font.GothamBold, Color3.new(1, 1, 1))
	local detail = bannerLabel("Detail", 70, 22, 15, Enum.Font.GothamMedium, Color3.fromRGB(230, 230, 230))
	local bannerToken = 0
	bannerFrame.Visible = false

	local function banner(titleText: string?, subtitleText: string?, detailText: string?, seconds: number?)
		bannerToken += 1
		local myToken = bannerToken
		title.Text = titleText or ""
		subtitle.Text = subtitleText or ""
		detail.Text = detailText or ""
		bannerFrame.Visible = titleText ~= nil or subtitleText ~= nil
		if bannerFrame.Visible and seconds then
			task.delay(seconds, function()
				if bannerToken == myToken then
					bannerFrame.Visible = false
				end
			end)
		end
	end

	return {
		push = push,
		banner = banner,
		clear = function()
			for _, slot in slots do
				slot.token += 1
				slot.frame.Visible = false
				slot.kind = nil
				slot.priority = 99
			end
			banner(nil, nil, nil)
		end,
		stack = stack,
		bannerFrame = bannerFrame,
	}
end

return NotificationController
