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
panel.Size = UDim2.new(0.94, 0, 0.86, 0)
panel.BackgroundColor3 = THEME.Panel
panel.BorderSizePixel = 0
panel.Parent = gui
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(660, 640)
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

-- A wrapping row of action buttons inside a card.
local function actionBar(parent: Instance): Frame
	local bar = Instance.new("Frame")
	bar.Name = "Actions"
	bar.BackgroundTransparency = 1
	bar.Size = UDim2.new(1, -20, 0, 0)
	bar.AutomaticSize = Enum.AutomaticSize.Y
	bar.LayoutOrder = 10
	bar.Parent = parent
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(138, THEME.TouchTarget)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = bar
	return bar
end

-- A card that grows with its content (title line, value lines, action buttons).
local function card(order: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = THEME.Surface
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, -8, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.LayoutOrder = order
	f.Parent = list
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = f
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 6), UDim.new(0, 8)
	pad.Parent = f
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 4)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = f
	return f
end

local function line(parent: Instance, order: number, value: string, size: number, color: Color3, font: Enum.Font?)
	local label = text(parent, "Line", size, font or THEME.BodyFont, color, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, -20, 0, 0)
	label.LayoutOrder = order
	label.Text = value
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(s // 60, s % 60)
end

local MarketplaceService = game:GetService("MarketplaceService")
local forgeToken: string? = nil
local forgeOpen = false
local renderForge: (state: any) -> () = function() end

-- Sends one smith request; renders the answer; follows a Robux or Denarii hint.
local function forgeCall(action: string, data: { [string]: any })
	if pending then
		return
	end
	lock(true)
	status.TextColor3 = THEME.Text
	status.Text = "Der Schmied hört zu ..."
	data.token = forgeToken
	local ok, result = pcall(function()
		return request:InvokeServer(action, data)
	end)
	lock(false)
	if not ok or typeof(result) ~= "table" then
		status.Text = "Keine Antwort vom Server."
		return
	end
	if result.state then
		renderForge(result.state)
	end
	if result.productId then
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, result.productId)
		end)
	end
	status.Text = result.message or ""
	status.TextColor3 = if result.ok then THEME.Positive else THEME.Negative
	if result.needProduct then
		-- the server remembered what this purchase is for; confirm the Robux purchase
		local state = result.state
		for _, p in (if state then state.products else {}) :: { any } do
			if p.key == result.needProduct then
				local c = card(-1)
				line(c, 1, ("%s für %d Robux?"):format(p.label, p.robux), 15, THEME.Gold, THEME.LabelFont)
				local bar = actionBar(c)
				local buy = button(bar, if p.ready then ("KAUFEN · R$%d"):format(p.robux) else "NOCH NICHT VERFÜGBAR", THEME.Primary, UDim.new(0, 0))
				table.insert(actionButtons, buy)
				buy.Activated:Connect(function()
					if p.ready then
						forgeCall("Buy", { key = p.key })
					end
				end)
			end
		end
	elseif result.needDenarii then
		status.Text ..= (" Es fehlen %d Denarii: unten kannst du Denarii kaufen."):format(result.needDenarii)
	end
end

renderForge = function(state: any)
	if not forgeOpen or not gui.Enabled then
		return
	end
	clear()
	title.Text = "SCHMIEDE · FABER"
	subtitle.Text = ("Härten +%d %% gegen Zombies und Bosse · Schleifen und Reparieren gegen Verschleiss · Designs und Vorspulen mit Robux. Ein Exemplar beim Schmied kannst du nicht benutzen."):format(math.floor(state.bonus * 100 + 0.5))
	status.Text = ("Guthaben: %d Denarii · Gutschriften: %d× Vorspulen, %d× Design"):format(state.denarii, state.credits.Skip, state.credits.Design)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local note = card(nextOrder())
	line(note, 1, state.note, 12, THEME.TextMuted)
	for _, weapon in state.weapons :: { any } do
		for _, c in weapon.copies :: { any } do
			local box = card(nextOrder())
			local head = ("%s · Exemplar %d%s"):format(weapon.name, c.index, if c.inHand then " · in der Hand" elseif c.active then " · gewählt" else "")
			line(box, 1, head, 16, THEME.Text, THEME.LabelFont)
			line(box, 2, ("Härtung %d/%d · Zustand %s (%d %% Verschleiss) · Design: %s"):format(c.forge, state.maxLevel, c.wearLabel, c.wear, c.designText), 13, THEME.TextMuted)
			line(box, 3, ("Grundschlag gegen Zombies: %d%s"):format(c.basic, if c.prices.Harden then (" · gehärtet %d"):format(c.basicHardened) else ""), 13, THEME.TextMuted)
			local bar = actionBar(box)
			if c.job then
				local timer = text(box, "Job", 14, THEME.LabelFont, THEME.Gold, 20)
				timer.LayoutOrder = 4
				local started, remaining = os.clock(), c.job.remaining
				timer.Text = ("Beim Schmied: %s · noch %s"):format(c.job.label, clock(remaining))
				task.spawn(function()
					while timer.Parent and forgeOpen do
						task.wait(1)
						timer.Text = ("Beim Schmied: %s · noch %s"):format(c.job.label, clock(remaining - (os.clock() - started)))
					end
				end)
				local skip = button(bar, "VORSPULEN · ROBUX", THEME.Primary, UDim.new(0, 0))
				table.insert(actionButtons, skip)
				skip.Activated:Connect(function()
					forgeCall("Skip", { weaponId = weapon.weaponId, uid = c.uid })
				end)
			else
				local function job(label: string, kind: string, price: number?)
					if price then
						local b = button(bar, ("%s · %d D"):format(label, price), THEME.SurfaceRaised, UDim.new(0, 0))
						table.insert(actionButtons, b)
						b.Activated:Connect(function()
							forgeCall("ForgeJob", { weaponId = weapon.weaponId, uid = c.uid, kind = kind })
						end)
					end
				end
				job("HÄRTEN", "Harden", c.prices.Harden)
				job("SCHLEIFEN", "Sharpen", c.prices.Sharpen)
				job("REPARIEREN", "Repair", c.prices.Repair)
				if not c.active then
					local choose = button(bar, "BENUTZEN", THEME.SurfaceRaised, UDim.new(0, 0))
					table.insert(actionButtons, choose)
					choose.Activated:Connect(function()
						forgeCall("SetActive", { weaponId = weapon.weaponId, uid = c.uid })
					end)
				end
				-- designs: one button per option, grouped by slot (paid with Robux)
				for _, slot in state.slots :: { any } do
					for _, option in slot.options :: { any } do
						if c.design[slot.id] ~= option.id then
							local d = button(bar, option.label, Color3.fromRGB(70, 58, 40), UDim.new(0, 0))
							d.TextSize = 13
							table.insert(actionButtons, d)
							d.Activated:Connect(function()
								forgeCall("ForgeJob", { weaponId = weapon.weaponId, uid = c.uid, kind = "Design", slot = slot.id, option = option.id })
							end)
						end
					end
				end
			end
		end
		if weapon.copyPrice then
			local more = card(nextOrder())
			line(more, 1, ("Weiteres Exemplar %s: %d Denarii (jedes weitere kostet das Doppelte)"):format(weapon.name, weapon.copyPrice), 13, THEME.TextMuted)
			local bar = actionBar(more)
			local b = button(bar, "SCHMIEDEN LASSEN", THEME.Primary, UDim.new(0, 0))
			table.insert(actionButtons, b)
			b.Activated:Connect(function()
				forgeCall("ForgeJob", { weaponId = weapon.weaponId, kind = "Copy" })
			end)
		end
	end
	for _, shield in state.shields :: { any } do
		local box = card(nextOrder())
		line(box, 1, ("%s · Bemalung: %s"):format(shield.name, shield.paintText), 15, THEME.Text, THEME.LabelFont)
		local bar = actionBar(box)
		for _, option in state.paints :: { any } do
			if shield.paint ~= option.id then
				local b = button(bar, option.label, Color3.fromRGB(70, 58, 40), UDim.new(0, 0))
				b.TextSize = 13
				table.insert(actionButtons, b)
				b.Activated:Connect(function()
					forgeCall("Paint", { shieldId = shield.shieldId, option = option.id })
				end)
			end
		end
	end
	local packs = card(nextOrder())
	line(packs, 1, "Denarii kaufen", 15, THEME.Gold, THEME.LabelFont)
	local bar = actionBar(packs)
	for _, p in state.products :: { any } do
		if p.denarii then
			local b = button(bar, if p.ready then ("%s · R$%d"):format(p.label, p.robux) else (p.label .. " · bald"), if p.ready then THEME.Primary else THEME.Locked, UDim.new(0, 0))
			b.TextSize = 13
			table.insert(actionButtons, b)
			b.Activated:Connect(function()
				if p.ready then
					forgeCall("Buy", { key = p.key })
				end
			end)
		end
	end
end

local function showForge(payload: any)
	forgeToken = payload.token
	forgeOpen = true
	open()
	status.TextColor3 = THEME.Text
	renderForge(payload)
end

local function showOracle(payload: any)
	clear()
	forgeOpen = false
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
	elseif kind == "ForgeUpdate" then
		-- a job ended or a Robux purchase was granted: refresh the open smith dialog
		if forgeOpen and gui.Enabled and payload.state then
			renderForge(payload.state)
			status.Text = payload.message or ""
			status.TextColor3 = THEME.Positive
		end
	elseif kind == "OracleOffer" then
		showOracle(payload)
	elseif kind == "Refused" then
		forgeOpen = false
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
