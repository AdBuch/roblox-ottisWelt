--!strict
-- Rome's counters on the client: the smith's offer and the oracle's prophecy as a compact dialog
-- (UiConfig.Menu theme, touch-sized buttons). Every number comes from the server's offer; a
-- confirmation sends one request and the dialog shows only what the server answered. While a
-- request runs, all buttons are locked (no double confirmation from the client either).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiConfig = require(Shared:WaitForChild("UiConfig"))
local THEME = UiConfig.Menu
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local request = remotes:WaitForChild("RomeRequest", 60) :: RemoteFunction?
local event = remotes:WaitForChild("RomeEvent", 60) :: RemoteEvent?
if not request or not event then
	return
end
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "RomeDialog"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.new(0.92, 0, 0, 380)
panel.BackgroundColor3 = THEME.Panel
panel.BorderSizePixel = 0
panel.Parent = gui
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(560, 520)
limit.Parent = panel
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, THEME.Corner)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = THEME.Bronze
stroke.Thickness = 2
stroke.Parent = panel
local padding = Instance.new("UIPadding")
for _, side in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
	(padding :: any)[side] = UDim.new(0, THEME.Padding)
end
padding.Parent = panel

local function text(parent: Instance, name: string, size: number, font: Enum.Font, color: Color3, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, height)
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local title = text(panel, "Title", 24, THEME.TitleFont, THEME.Gold, 30)
local subtitle = text(panel, "Subtitle", 15, THEME.BodyFont, THEME.TextMuted, 40)
subtitle.Position = UDim2.fromOffset(0, 32)
local list = Instance.new("ScrollingFrame")
list.Name = "Rows"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.fromOffset(0, 78)
list.Size = UDim2.new(1, 0, 1, -78 - THEME.TouchTarget - 34)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.ScrollBarThickness = 6
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, THEME.Gap)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list
local status = text(panel, "Status", 15, THEME.LabelFont, THEME.Text, 30)
status.AnchorPoint = Vector2.new(0, 1)
status.Position = UDim2.new(0, 0, 1, -THEME.TouchTarget - 4)

local function button(parent: Instance, label: string, color: Color3, width: UDim): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(width, UDim.new(0, THEME.TouchTarget))
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = THEME.LabelFont
	b.TextSize = 16
	b.TextColor3 = THEME.Text
	b.Text = label
	b.AutoButtonColor = true
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	return b
end

local close = button(panel, "SCHLIESSEN", THEME.SurfaceRaised, UDim.new(0, 150))
close.AnchorPoint = Vector2.new(1, 1)
close.Position = UDim2.fromScale(1, 1)

local pending = false
local actionButtons: { TextButton } = {}
local function lock(locked: boolean)
	pending = locked
	for _, b in actionButtons do
		b.Active = not locked
		b.AutoButtonColor = not locked
		b.BackgroundTransparency = if locked then 0.5 else 0
	end
end
local function clear()
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	table.clear(actionButtons)
	status.Text = ""
end
local function open()
	gui.Enabled = true
end
local function hide()
	gui.Enabled = false
	clear()
end
close.Activated:Connect(hide)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and gui.Enabled and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
		hide()
	end
end)

local function row(height: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = THEME.Surface
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, -8, 0, height)
	f.Parent = list
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = f
	return f
end

local function showForge(payload: any)
	clear()
	title.Text = "SCHMIEDE · FABER"
	subtitle.Text = ("Erste Verbesserungsstufe: +%d %% Schaden gegen Zombies und Bosse. Im PvP bleibt jede Waffe ausgeglichen. Helme folgen später."):format(math.floor(payload.bonus * 100 + 0.5))
	local function fill(items: { any }, denarii: number)
		clear()
		status.Text = ("Dein Guthaben: %d Denarii"):format(denarii)
		if #items == 0 then
			local empty = text(list, "Empty", 15, THEME.BodyFont, THEME.TextMuted, 40)
			empty.Text = "Du besitzt noch keine Waffe, die der Schmied verbessern kann."
		end
		for i, item in items do
			local r = row(70)
			r.LayoutOrder = i
			local name = text(r, "Name", 17, THEME.LabelFont, THEME.Text, 24)
			name.Position = UDim2.fromOffset(10, 6)
			name.Size = UDim2.new(1, -180, 0, 24)
			name.Text = item.name .. (if item.level >= item.maxLevel then "  · verbessert" else "")
			local values = text(r, "Values", 14, THEME.BodyFont, THEME.TextMuted, 36)
			values.Position = UDim2.fromOffset(10, 30)
			values.Size = UDim2.new(1, -180, 0, 36)
			if item.level >= item.maxLevel then
				values.Text = ("Grundschlag gegen Zombies: %d (höchste Stufe)"):format(item.basicNow)
			else
				values.Text = ("Grundschlag gegen Zombies: %d → %d\nPreis: %d Denarii"):format(item.basicNow, item.basicNext, item.price)
			end
			if item.level < item.maxLevel then
				local b = button(r, "VERBESSERN", THEME.Primary, UDim.new(0, 150))
				b.AnchorPoint = Vector2.new(1, 0.5)
				b.Position = UDim2.new(1, -10, 0.5, 0)
				table.insert(actionButtons, b)
				b.Activated:Connect(function()
					if pending then
						return
					end
					lock(true)
					status.Text = "Der Schmied arbeitet ..."
					local ok, result = pcall(function()
						return request:InvokeServer("ForgeUpgrade", { token = payload.token, weaponId = item.weaponId, level = item.level })
					end)
					lock(false)
					if not ok or typeof(result) ~= "table" then
						status.Text = "Keine Antwort vom Server."
						return
					end
					if result.items then
						fill(result.items, result.denarii or denarii)
					end
					status.Text = result.message
					status.TextColor3 = if result.ok then THEME.Positive else THEME.Negative
				end)
			end
		end
	end
	fill(payload.items, payload.denarii)
	status.TextColor3 = THEME.Text
	open()
end

local function showOracle(payload: any)
	clear()
	title.Text = "ORAKEL · AUGUR"
	subtitle.Text = ("Eine Weissagung kostet %d Denarii. Die Götter sprechen über deinen Weg zum nächsten Titel."):format(payload.price)
	status.TextColor3 = THEME.Text
	status.Text = ("Dein Guthaben: %d Denarii"):format(payload.denarii)
	local r = row(60)
	local info = text(r, "Offer", 15, THEME.BodyFont, THEME.TextMuted, 50)
	info.Position = UDim2.fromOffset(10, 5)
	info.Size = UDim2.new(1, -190, 0, 50)
	info.Text = ("Opfergabe: %d Denarii"):format(payload.price)
	local b = button(r, "BEFRAGEN", THEME.Primary, UDim.new(0, 160))
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -10, 0.5, 0)
	table.insert(actionButtons, b)
	b.Activated:Connect(function()
		if pending then
			return
		end
		lock(true)
		status.Text = "Der Rauch steigt auf ..."
		local ok, result = pcall(function()
			return request:InvokeServer("Oracle", { token = payload.token })
		end)
		if not ok or typeof(result) ~= "table" then
			lock(false)
			status.Text = "Keine Antwort vom Server."
			return
		end
		if result.ok then
			clear()
			local answer = row(150)
			local saying = text(answer, "Saying", 16, Enum.Font.Garamond, THEME.Gold, 50)
			saying.Position = UDim2.fromOffset(10, 6)
			saying.Size = UDim2.new(1, -20, 0, 50)
			saying.Text = "«" .. result.saying .. "»"
			local hint = text(answer, "Hint", 16, THEME.LabelFont, THEME.Text, 86)
			hint.Position = UDim2.fromOffset(10, 58)
			hint.Size = UDim2.new(1, -20, 0, 86)
			hint.Text = result.hint
			status.TextColor3 = THEME.Positive
			status.Text = ("Bezahlt. Guthaben: %d Denarii"):format(result.denarii)
		else
			lock(false)
			status.TextColor3 = THEME.Negative
			status.Text = result.message
		end
	end)
	open()
end

event.OnClientEvent:Connect(function(kind: string, payload: any)
	if kind == "ForgeOffer" then
		showForge(payload)
	elseif kind == "OracleOffer" then
		showOracle(payload)
	elseif kind == "Refused" then
		clear()
		title.Text = payload.title
		subtitle.Text = payload.text
		open()
	elseif kind == "Respawned" and payload and payload.kind == "Edge" then
		clear()
		title.Text = "AM RAND DER WELT"
		subtitle.Text = "Das Meer hat dich über die Kante getragen. Die Götter haben dich am Forumsbrunnen abgesetzt."
		open()
		task.delay(5, function()
			if title.Text == "AM RAND DER WELT" then
				hide()
			end
		end)
	end
end)
