--!strict
-- LIVE IN THE COLOSSEUM: the embedded active-battle overlay of the Hub.
--   * opens from WATCH LIVE (mode menu), the WATCH LIVE door / live board (MatchEvent "OpenLive")
--   * dark translucent panel over the Hub view, centred, compact (max 440 wide, 76 % high on
--     desktop, nearly full width on phones), vertically scrollable, big tap targets
--   * top controls: WATCH RANDOM · refresh · filter · close
--   * sections in this order: FRIENDS IN BATTLE (hidden when empty), FEATURED BATTLES, ALL LIVE BATTLES
--   * refresh when opened, on the refresh button and every Registry.ListRefreshSeconds while
--     open; nothing runs and nothing catches input while it is closed
-- The server builds and sanitizes every card (LiveBattlesService); WATCH only sends the public
-- match id, WATCH RANDOM nothing at all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExperienceConfig = require(Shared:WaitForChild("ExperienceConfig"))
local MatchDefinitions = require(Shared:WaitForChild("MatchDefinitions"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))

export type ActiveBattles = {
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
}

local ActiveBattlesController = {}

local GOLD = UiConfig.Gold
local CARD = Color3.fromRGB(44, 34, 26)

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function round(parent: Instance, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function button(parent: Instance, text: string, color: Color3, size: UDim2, order: number?): TextButton
	local b = make("TextButton", {
		Size = size,
		BackgroundColor3 = color,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		Text = text,
		AutoButtonColor = true,
		LayoutOrder = order or 0,
	}, parent)
	round(b, 8)
	return b
end

function ActiveBattlesController.start(gui: ScreenGui, request: RemoteFunction?, events: RemoteEvent?, onBack: (() -> ())?): ActiveBattles
	local isOpen = false
	local filter = "All"
	local refreshToken = 0
	local busy = false

	local backdrop = make("TextButton", {
		Name = "LiveBackdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 20,
	}, gui)
	local panel = make("Frame", {
		Name = "LiveBattles",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.78, 0),
		BackgroundColor3 = Color3.fromRGB(22, 18, 14),
		BackgroundTransparency = 0.08,
		Visible = false,
		ZIndex = 21,
	}, gui)
	round(panel, 12)
	make("UISizeConstraint", { MaxSize = Vector2.new(440, 640) }, panel)
	make("UIStroke", { Color = GOLD, Transparency = 0.5, Thickness = 1.5 }, panel)
	make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, panel)

	make("TextLabel", {
		Size = UDim2.new(1, -44, 0, 26),
		BackgroundTransparency = 1,
		Font = Enum.Font.Garamond,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GOLD,
		Text = "LIVE IN THE COLOSSEUM",
		ZIndex = 22,
	}, panel)
	local close = button(panel, "✕", Color3.fromRGB(80, 60, 50), UDim2.fromOffset(36, 30))
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.ZIndex = 22

	-- Top controls
	local controls = make("Frame", { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ZIndex = 22 }, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, controls)
	local random = button(controls, "WATCH RANDOM", Color3.fromRGB(150, 40, 34), UDim2.new(0.5, -6, 1, 0), 1)
	local refreshButton = button(controls, "⟳", Color3.fromRGB(70, 56, 40), UDim2.new(0.18, 0, 1, 0), 2)
	local filterButton = button(controls, "FILTER", Color3.fromRGB(70, 56, 40), UDim2.new(0.32, -6, 1, 0), 3)
	for _, b in { random, refreshButton, filterButton } do
		b.ZIndex = 22
	end

	-- Filter chips (horizontal scroll, shown on demand)
	local chips = make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Visible = false,
		ZIndex = 22,
	}, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	local chipButtons: { [string]: TextButton } = {}

	-- Card list
	local list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 1, -80),
		BackgroundTransparency = 1,
		ScrollBarThickness = 5,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 22,
	}, panel)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	local function setChipsVisible(visible: boolean)
		chips.Visible = visible
		list.Position = UDim2.fromOffset(0, if visible then 118 else 80)
		list.Size = UDim2.new(1, 0, 1, if visible then -118 else -80)
	end

	local function invoke(action: string, arg: any?): any
		if not request then
			return nil
		end
		local ok, result = pcall(function()
			return request:InvokeServer(action, arg)
		end)
		return if ok then result else nil
	end

	local refresh: () -> ()

	local function header(text: string, order: number)
		make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(255, 190, 150),
			Text = text,
			LayoutOrder = order,
			ZIndex = 23,
		}, list)
	end

	local function watch(matchId: string, label: TextButton)
		label.Text = "…"
		task.spawn(function()
			local result = invoke("Watch", matchId)
			label.Text = if result and result.ok then "JOINING" else "WATCH"
			if result and not result.ok and result.message then
				label.Text = "WATCH"
			end
		end)
	end

	local function card(info: any, order: number)
		local frame = make("Frame", {
			Size = UDim2.new(1, -6, 0, 78),
			BackgroundColor3 = CARD,
			BackgroundTransparency = 0.05,
			LayoutOrder = order,
			ZIndex = 23,
		}, list)
		round(frame, 8)
		local left = 10
		if #info.friends > 0 then
			for i, friend in info.friends do
				make("ImageLabel", {
					Position = UDim2.fromOffset(8 + (i - 1) * 18, 8),
					Size = UDim2.fromOffset(28, 28),
					BackgroundColor3 = Color3.fromRGB(70, 56, 40),
					Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(friend.userId),
					ZIndex = 24 + i,
				}, frame)
			end
			left = 8 + (#info.friends - 1) * 18 + 34
		end
		local names = {}
		for _, friend in info.friends do
			table.insert(names, friend.name)
		end
		local titleText = info.title
		if #names > 0 then
			titleText = table.concat(names, ", ") .. (if info.friendExtra > 0 then (" +%d"):format(info.friendExtra) else "") .. " · " .. info.title
		elseif info.featured then
			titleText = info.featured
		end
		make("TextLabel", {
			Position = UDim2.fromOffset(left, 6),
			Size = UDim2.new(1, -left - 96, 0, 20),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = if info.featured then GOLD else Color3.new(1, 1, 1),
			Text = titleText,
			ZIndex = 24,
		}, frame)
		make("TextLabel", {
			Position = UDim2.fromOffset(left, 27),
			Size = UDim2.new(1, -left - 96, 0, 18),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = Color3.fromRGB(235, 225, 205),
			Text = info.score .. (if info.detail ~= "" then "  ·  " .. info.detail else ""),
			ZIndex = 24,
		}, frame)
		make("TextLabel", {
			Position = UDim2.fromOffset(left, 48),
			Size = UDim2.new(1, -left - 96, 0, 18),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(190, 180, 165),
			Text = ("%d Fighter%s · %d Watching%s"):format(info.fighters, if info.fighters == 1 then "" else "s", info.spectators, if info.mock then " · MOCK" else ""),
			ZIndex = 24,
		}, frame)
		local watchButton = button(frame, if info.joinable then "WATCH" else "FULL", if info.joinable then Color3.fromRGB(150, 40, 34) else Color3.fromRGB(70, 60, 55), UDim2.fromOffset(84, 44))
		watchButton.AnchorPoint = Vector2.new(1, 0.5)
		watchButton.Position = UDim2.new(1, -8, 0.5, 0)
		watchButton.ZIndex = 25
		watchButton.Active = info.joinable
		if info.joinable then
			watchButton.Activated:Connect(function()
				watch(info.matchId, watchButton)
			end)
		end
	end

	local function render(data: any)
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local order = 0
		local function section(title: string, cards: { any }, hideWhenEmpty: boolean, emptyText: string?)
			if #cards == 0 and hideWhenEmpty then
				return
			end
			order += 1
			header(title, order)
			if #cards == 0 and emptyText then
				order += 1
				make("TextLabel", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(170, 160, 150), Text = emptyText, LayoutOrder = order, ZIndex = 23 }, list)
			end
			for _, info in cards do
				order += 1
				card(info, order)
			end
		end
		if not data or data.total == 0 then
			order += 1
			make("TextLabel", { Size = UDim2.new(1, 0, 0, 60), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = Color3.new(1, 1, 1), Text = "NO LIVE BATTLES RIGHT NOW", LayoutOrder = order, ZIndex = 23 }, list)
			local row = make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = order + 1, ZIndex = 23 }, list)
			make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8) }, row)
			local again = button(row, "REFRESH", Color3.fromRGB(70, 56, 40), UDim2.fromOffset(120, 40))
			local back = button(row, "MODE SELECTION", Color3.fromRGB(150, 40, 34), UDim2.fromOffset(150, 40))
			again.ZIndex, back.ZIndex = 24, 24
			again.Activated:Connect(function()
				refresh()
			end)
			back.Activated:Connect(function()
				if onBack then
					onBack()
				end
			end)
			return
		end
		section("FRIENDS IN BATTLE", data.friends, true, nil)
		section("FEATURED BATTLES", data.featured, true, nil)
		section("ALL LIVE BATTLES", data.all, false, if #data.friends + #data.featured > 0 then "No other battles" else nil)
	end

	refresh = function()
		if busy or not isOpen then
			return
		end
		busy = true
		refreshButton.Text = "…"
		task.spawn(function()
			local result = invoke("ListBattles", filter)
			busy = false
			refreshButton.Text = "⟳"
			if isOpen then
				render(if result and result.ok then result.data else nil)
			end
		end)
	end

	for i, name in MatchDefinitions.Filters do
		local chip = button(chips, name, if name == filter then Color3.fromRGB(150, 40, 34) else Color3.fromRGB(70, 56, 40), UDim2.fromOffset(math.max(64, #name * 8 + 18), 30), i)
		chip.ZIndex = 23
		chipButtons[name] = chip
		chip.Activated:Connect(function()
			filter = name
			for other, b in chipButtons do
				b.BackgroundColor3 = if other == filter then Color3.fromRGB(150, 40, 34) else Color3.fromRGB(70, 56, 40)
			end
			filterButton.Text = if filter == "All" then "FILTER" else filter:upper()
			refresh()
		end)
	end

	local function closePanel()
		isOpen = false
		refreshToken += 1 -- stops the background refresh
		panel.Visible = false
		backdrop.Visible = false -- a closed overlay never catches input
	end

	local function openPanel()
		if isOpen then
			refresh()
			return
		end
		isOpen = true
		panel.Visible = true
		backdrop.Visible = true
		refreshToken += 1
		local myToken = refreshToken
		refresh()
		task.spawn(function()
			while isOpen and refreshToken == myToken do
				task.wait(ExperienceConfig.Registry.ListRefreshSeconds)
				if isOpen and refreshToken == myToken then
					refresh()
				end
			end
		end)
	end

	close.Activated:Connect(closePanel)
	backdrop.Activated:Connect(closePanel)
	refreshButton.Activated:Connect(refresh)
	filterButton.Activated:Connect(function()
		setChipsVisible(not chips.Visible)
	end)
	random.Activated:Connect(function()
		random.Text = "…"
		task.spawn(function()
			local result = invoke("WatchRandom")
			random.Text = "WATCH RANDOM"
			if result and not result.ok then
				refresh()
			end
		end)
	end)
	if events then
		events.OnClientEvent:Connect(function(kind: string)
			if kind == "OpenLive" then
				openPanel()
			end
		end)
	end

	return {
		open = openPanel,
		close = closePanel,
		isOpen = function()
			return isOpen
		end,
	}
end

return ActiveBattlesController
