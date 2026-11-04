--!strict
-- The one menu system of the client (presentation only; every decision stays on the server).
--   * Theme: warm stone, dark surfaces, discreet bronze / gold accents (UiConfig.Menu), the same
--     headings, tabs, spacing, touch targets (>= 44 px) and close button for every big menu.
--   * Coordinator: only ONE big menu is open at a time. Opening one closes the other. While any is
--     open: combat input is suspended (Main -> InputController.suspend / canAct), Roblox's movement
--     controls are disabled (thumbstick + native jump hidden, held movement released), the mouse is
--     freed (Modal) and gamepad navigation starts on the first tab. Closing the last one restores
--     movement, the previous camera type and the gamepad focus.
--   * Builders: window (backdrop, panel, stone header band, title, close, tab rail or tab row,
--     scrolling pages), buttons with consistent states (Normal / Selected / Equipped / Locked /
--     Unavailable), labels, cards and progress bars.
-- Used by LobbyMenuController (the central lobby menu), GameModeMenuController, ActiveBattlesController
-- and InfoPanelController.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiConfig"))

local MenuSystem = {}

local THEME = UiConfig.Menu
MenuSystem.Theme = THEME

export type ButtonState = "Normal" | "Selected" | "Equipped" | "Locked" | "Unavailable" | "Pending"
export type ButtonStyle = "Primary" | "Secondary" | "Tab" | "Ghost"

------------------------------------------------------------------------------------------
-- Coordinator
------------------------------------------------------------------------------------------

local closers: { [string]: () -> () } = {}
local openName: string? = nil
local listeners: { (open: boolean, name: string?) -> () } = {}
local savedCameraType: Enum.CameraType? = nil
local controlsDisabled = false

local function playerControls(): any
	local player = Players.LocalPlayer
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(function()
		return (require(module) :: any):GetControls()
	end)
	return if ok then result else nil
end

local function setMovement(enabled: boolean)
	local controls = playerControls()
	if not controls then
		return
	end
	pcall(function()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
	controlsDisabled = not enabled
end

local function fire()
	for _, callback in listeners do
		task.spawn(callback, openName ~= nil, openName)
	end
end

-- A big menu registers its close function once.
function MenuSystem.register(name: string, close: () -> ())
	closers[name] = close
end

-- Called by a menu right before it becomes visible: closes any other big menu first.
-- `keepMovement`: an information overlay that may stay open in a fight (the "i" panel): it is
-- still exclusive, but movement and combat input keep working (isOpen() stays false for it).
local keepsMovement = false
function MenuSystem.opening(name: string, keepMovement: boolean?)
	if openName == name then
		return
	end
	local previous = openName
	if previous then
		openName = nil
		local close = closers[previous]
		if close then
			close() -- calls MenuSystem.closed(previous), which keeps the session (see below)
		end
	end
	openName = name
	keepsMovement = keepMovement == true
	if not keepsMovement and not controlsDisabled then
		local camera = Workspace.CurrentCamera
		savedCameraType = if camera then camera.CameraType else nil
		setMovement(false)
	elseif keepsMovement and controlsDisabled then
		setMovement(true)
	end
	fire()
end

-- Called by a menu after it was hidden.
function MenuSystem.closed(name: string)
	if openName ~= name then
		return
	end
	openName = nil
	keepsMovement = false
	task.defer(function()
		if openName ~= nil then
			return -- another menu took over in the same frame (menu change): keep the session
		end
		if controlsDisabled then
			setMovement(true)
		end
		local camera = Workspace.CurrentCamera
		if camera and savedCameraType and camera.CameraType ~= savedCameraType then
			camera.CameraType = savedCameraType
		end
		savedCameraType = nil
		local selected = GuiService.SelectedObject
		local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
		if selected and playerGui and selected:IsDescendantOf(playerGui) then
			GuiService.SelectedObject = nil -- gamepad focus back to the game
		end
		fire()
	end)
end

-- True while a big menu that pauses the game input is open (all but keepMovement overlays).
function MenuSystem.isOpen(): boolean
	return openName ~= nil and not keepsMovement
end

-- True while ANY big menu (including the "i" overlay) is open.
function MenuSystem.anyOpen(): boolean
	return openName ~= nil
end

function MenuSystem.current(): string?
	return openName
end

function MenuSystem.closeAll()
	local name = openName
	if name and closers[name] then
		closers[name]()
	end
end

function MenuSystem.onChanged(callback: (open: boolean, name: string?) -> ())
	table.insert(listeners, callback)
end

function MenuSystem.usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad" or GuiService:IsTenFootInterface()
end

-- Gamepad: put the selection on `object` (only when a gamepad is in use).
function MenuSystem.focus(object: GuiObject?)
	if object and MenuSystem.usingGamepad() then
		GuiService.SelectedObject = object
	end
end

------------------------------------------------------------------------------------------
-- Builders
------------------------------------------------------------------------------------------

function MenuSystem.make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end
local make = MenuSystem.make

function MenuSystem.corner(parent: Instance, radius: number?)
	make("UICorner", { CornerRadius = UDim.new(0, radius or THEME.Corner) }, parent)
end

function MenuSystem.stroke(parent: Instance, color: Color3?, transparency: number?, thickness: number?): UIStroke
	return make("UIStroke", { Color = color or THEME.Bronze, Transparency = transparency or 0.45, Thickness = thickness or 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

function MenuSystem.padding(parent: Instance, all: number?)
	local p = UDim.new(0, all or THEME.Padding)
	make("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p }, parent)
end

function MenuSystem.list(parent: Instance, gap: number?, horizontal: boolean?): UIListLayout
	return make("UIListLayout", {
		Padding = UDim.new(0, gap or THEME.Gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
	}, parent)
end

-- A text label that wraps instead of being cut off.
function MenuSystem.label(parent: Instance, text: string, size: number?, font: Enum.Font?, color: Color3?, order: number?): TextLabel
	return make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = font or THEME.BodyFont,
		TextSize = size or 14,
		TextColor3 = color or THEME.Text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
		Text = text,
		LayoutOrder = order or 0,
	}, parent)
end

function MenuSystem.heading(parent: Instance, text: string, order: number?): TextLabel
	local l = MenuSystem.label(parent, text, 16, THEME.TitleFont, THEME.Gold, order)
	return l
end

local STYLE_COLORS: { [string]: Color3 } = {
	Primary = THEME.Primary,
	Secondary = THEME.SurfaceRaised,
	Tab = THEME.SurfaceRaised,
	Ghost = THEME.Surface,
}

function MenuSystem.button(parent: Instance, text: string, style: ButtonStyle?, order: number?, height: number?): TextButton
	local b = make("TextButton", {
		Size = UDim2.new(1, 0, 0, math.max(THEME.TouchTarget, height or THEME.TouchTarget)),
		BackgroundColor3 = STYLE_COLORS[style or "Secondary"],
		AutoButtonColor = true,
		Font = THEME.LabelFont,
		TextSize = 14,
		TextColor3 = THEME.Text,
		TextWrapped = true,
		Text = text,
		LayoutOrder = order or 0,
	}, parent)
	b:SetAttribute("MenuStyle", style or "Secondary")
	MenuSystem.corner(b, 8)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, b)
	return b
end

-- Consistent states: Selected (gold outline) · Equipped (green) · Locked (grey, inactive) ·
-- Unavailable (dimmed, inactive) · Pending (waiting for the server, inactive).
function MenuSystem.setState(b: GuiButton, state: ButtonState)
	local style = tostring(b:GetAttribute("MenuStyle") or "Secondary")
	local existing = b:FindFirstChild("StateStroke")
	local o: UIStroke
	if existing and existing:IsA("UIStroke") then
		o = existing
	else
		o = MenuSystem.stroke(b, THEME.Gold, 1, 2)
		o.Name = "StateStroke"
	end
	local base = STYLE_COLORS[style] or THEME.SurfaceRaised
	b.BackgroundColor3 = base
	b.BackgroundTransparency = 0
	b.Active = true
	b.AutoButtonColor = true
	o.Transparency = 1
	if state == "Selected" then
		o.Color = THEME.Gold
		o.Transparency = 0
		if style == "Tab" then
			b.BackgroundColor3 = THEME.Primary
		end
	elseif state == "Equipped" then
		b.BackgroundColor3 = THEME.Equipped
		b.Active = false
		b.AutoButtonColor = false
	elseif state == "Locked" then
		b.BackgroundColor3 = THEME.Locked
		b.Active = false
		b.AutoButtonColor = false
	elseif state == "Unavailable" or state == "Pending" then
		b.BackgroundTransparency = 0.45
		b.Active = false
		b.AutoButtonColor = false
	end
	b:SetAttribute("MenuState", state)
end

function MenuSystem.card(parent: Instance, order: number?, height: number?): Frame
	local frame = make("Frame", {
		Size = UDim2.new(1, 0, 0, height or 0),
		AutomaticSize = if height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.Surface,
		LayoutOrder = order or 0,
	}, parent)
	MenuSystem.corner(frame, 8)
	MenuSystem.padding(frame, 10)
	MenuSystem.list(frame, 4)
	return frame
end

export type Bar = { frame: Frame, set: (share: number) -> () }

function MenuSystem.progressBar(parent: Instance, order: number?, height: number?): Bar
	local frame = make("Frame", { Size = UDim2.new(1, 0, 0, height or 14), BackgroundColor3 = THEME.StoneDark, LayoutOrder = order or 0 }, parent)
	MenuSystem.corner(frame, 7)
	local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = THEME.Gold, BorderSizePixel = 0 }, frame)
	MenuSystem.corner(fill, 7)
	MenuSystem.stroke(frame, THEME.Bronze, 0.3, 1)
	return {
		frame = frame,
		set = function(share: number)
			fill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
		end,
	}
end

------------------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------------------

export type Window = {
	name: string,
	panel: Frame,
	backdrop: TextButton,
	title: TextLabel,
	closeButton: TextButton,
	addTab: (id: string, label: string, scroll: boolean?) -> Frame,
	select: (id: string) -> (),
	selected: () -> string?,
	tabButton: (id: string) -> TextButton?,
	onSelect: (callback: (id: string) -> ()) -> (),
	open: (tab: string?) -> (),
	close: () -> (),
	isOpen: () -> boolean,
	onOpenChanged: (callback: (open: boolean) -> ()) -> (),
}

export type WindowOptions = {
	name: string,
	title: string,
	maxSize: Vector2?,
	zIndex: number?,
	tabs: boolean?, -- false: no tab rail (a single page)
}

-- A themed big menu: backdrop (tap outside closes), panel with a stone header band, title, a
-- 44 px close button, a tab rail (left; on portrait phones a scrolling row on top) and pages.
function MenuSystem.window(gui: ScreenGui, options: WindowOptions): Window
	local z = options.zIndex or 40
	local backdrop = make("TextButton", {
		Name = options.name .. "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.Backdrop,
		BackgroundTransparency = THEME.BackdropTransparency,
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Visible = false,
		ZIndex = z,
	}, gui)
	local panel = make("Frame", {
		Name = options.name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 1, -24),
		BackgroundColor3 = THEME.Panel,
		Visible = false,
		ZIndex = z + 1,
	}, gui)
	MenuSystem.corner(panel, 12)
	MenuSystem.stroke(panel, THEME.Bronze, 0.25, 2)
	local maxSize = options.maxSize or THEME.MaxSize
	make("UISizeConstraint", { MaxSize = maxSize }, panel)
	-- frees the mouse in first person / shift lock while the menu is visible
	make("TextButton", { Name = "ModalCatcher", Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Text = "", Modal = true, Selectable = false }, panel)

	-- Header: warm stone band, title, close button
	local header = make("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = THEME.Stone, ZIndex = z + 2 }, panel)
	MenuSystem.corner(header, 12)
	make("Frame", { Name = "HeaderFoot", Position = UDim2.new(0, 0, 1, -12), Size = UDim2.new(1, 0, 0, 12), BackgroundColor3 = THEME.Stone, BorderSizePixel = 0, ZIndex = z + 2 }, header)
	make("Frame", { Name = "BronzeLine", Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = THEME.Bronze, BorderSizePixel = 0, ZIndex = z + 3 }, header)
	local title = make("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -76, 1, 0),
		BackgroundTransparency = 1,
		Font = THEME.TitleFont,
		TextSize = 20,
		TextColor3 = Color3.fromRGB(40, 28, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.None,
		TextScaled = false,
		Text = options.title,
		ZIndex = z + 3,
	}, header)
	local closeButton = make("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(THEME.TouchTarget, THEME.TouchTarget),
		BackgroundColor3 = THEME.Panel,
		Font = THEME.TitleFont,
		TextSize = 18,
		TextColor3 = THEME.Gold,
		Text = "✕",
		ZIndex = z + 3,
	}, header)
	MenuSystem.corner(closeButton, 8)

	local showTabs = options.tabs ~= false
	local rail = make("ScrollingFrame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.XY,
		CanvasSize = UDim2.new(),
		Visible = showTabs,
		ZIndex = z + 2,
		Selectable = false,
	}, panel)
	local railList = MenuSystem.list(rail, 6)
	local content = make("Frame", { Name = "Content", BackgroundTransparency = 1, ZIndex = z + 2, ClipsDescendants = true }, panel)

	local pages: { [string]: GuiObject } = {}
	local buttons: { [string]: TextButton } = {}
	local order: { string } = {}
	local current: string? = nil
	local selectListeners: { (id: string) -> () } = {}
	local openListeners: { (open: boolean) -> () } = {}
	local isOpen = false

	-- Landscape / desktop: tab rail on the left. Portrait phones: scrolling tab row on top.
	local function layout()
		local camera = Workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local portrait = viewport.Y > viewport.X
		local top = 62
		if not showTabs then
			content.Position = UDim2.fromOffset(12, top)
			content.Size = UDim2.new(1, -24, 1, -(top + 12))
		elseif portrait then
			railList.FillDirection = Enum.FillDirection.Horizontal
			rail.Position = UDim2.fromOffset(12, top)
			rail.Size = UDim2.new(1, -24, 0, THEME.TouchTarget + 4)
			for _, b in buttons do
				b.Size = UDim2.fromOffset(math.max(104, b.TextBounds.X + 28), THEME.TouchTarget)
			end
			content.Position = UDim2.fromOffset(12, top + THEME.TouchTarget + 12)
			content.Size = UDim2.new(1, -24, 1, -(top + THEME.TouchTarget + 24))
		else
			railList.FillDirection = Enum.FillDirection.Vertical
			local railWidth = if viewport.X < 700 then 128 else 156
			rail.Position = UDim2.fromOffset(12, top)
			rail.Size = UDim2.new(0, railWidth, 1, -(top + 12))
			for _, b in buttons do
				b.Size = UDim2.new(1, 0, 0, THEME.TouchTarget)
			end
			content.Position = UDim2.fromOffset(railWidth + 24, top)
			content.Size = UDim2.new(1, -(railWidth + 36), 1, -(top + 12))
		end
		title.TextSize = if viewport.X < 500 then 17 else 20
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end

	local window: Window
	local function select(id: string)
		if not pages[id] then
			return
		end
		current = id
		for tabId, page in pages do
			page.Visible = tabId == id
		end
		for tabId, b in buttons do
			MenuSystem.setState(b, if tabId == id then "Selected" else "Normal")
		end
		for _, callback in selectListeners do
			task.spawn(callback, id)
		end
	end

	local function close()
		if not isOpen then
			return
		end
		isOpen = false
		panel.Visible = false
		backdrop.Visible = false
		MenuSystem.closed(options.name)
		for _, callback in openListeners do
			task.spawn(callback, false)
		end
	end

	local function open(tab: string?)
		MenuSystem.opening(options.name)
		isOpen = true
		layout()
		panel.Visible = true
		backdrop.Visible = true
		select(tab or current or order[1])
		for _, callback in openListeners do
			task.spawn(callback, true)
		end
		local focusTarget = if current then buttons[current] else nil
		MenuSystem.focus(focusTarget or closeButton)
	end

	closeButton.Activated:Connect(close)
	backdrop.Activated:Connect(close)
	MenuSystem.register(options.name, close)

	window = {
		name = options.name,
		panel = panel,
		backdrop = backdrop,
		title = title,
		closeButton = closeButton,
		addTab = function(id: string, label: string, scroll: boolean?): Frame
			local page: any
			if scroll ~= false then
				page = make("ScrollingFrame", {
					Name = id,
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ScrollBarThickness = 5,
					ScrollBarImageColor3 = THEME.Bronze,
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(),
					ScrollingDirection = Enum.ScrollingDirection.Y,
					Visible = false,
					Selectable = false,
				}, content)
				make("UIPadding", { PaddingRight = UDim.new(0, 8) }, page)
				MenuSystem.list(page, THEME.Gap)
			else
				page = make("Frame", { Name = id, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, content)
			end
			pages[id] = page
			table.insert(order, id)
			local b = MenuSystem.button(rail, label, "Tab", #order)
			b.TextSize = 13
			buttons[id] = b
			b.Activated:Connect(function()
				select(id)
			end)
			return page
		end,
		select = select,
		selected = function()
			return current
		end,
		tabButton = function(id: string)
			return buttons[id]
		end,
		onSelect = function(callback: (id: string) -> ())
			table.insert(selectListeners, callback)
		end,
		open = open,
		close = close,
		isOpen = function()
			return isOpen
		end,
		onOpenChanged = function(callback: (open: boolean) -> ())
			table.insert(openListeners, callback)
		end,
	}
	layout()
	return window
end

-- Gamepad B closes the open big menu (Roblox's own selection handling keeps working).
UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.ButtonB and openName ~= nil then
		MenuSystem.closeAll()
	end
end)

return MenuSystem
