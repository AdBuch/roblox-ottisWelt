--!strict
-- Gladiator Armory presentation (all decisions happen on the server):
--   * The displays' ProximityPrompts use the Custom style. When Roblox shows the closest one
--     (PromptShown), this highlights that display and opens a compact information card: name,
--     section, the stats of its kind, the gladiator level unlock (LOCKED until reached), the price in Denarii and
--     IM BESITZ / AUSGERÜSTET state, an action button (GESPERRT / KAUFEN / AUSRÜSTEN / AUSGERÜSTET; MenuSystem theme, values from ItemInfo) and an optional
--     INFO line (special / projectile properties).
--   * F (keyboard), X (gamepad) or the card's button (touch / mouse) trigger the same prompt;
--     the server validates and answers through the Shop feedback notification.
--   * Equipped items keep a green outline. No large permanent text panels in the world.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GladiatorLevelDefinitions = require(Shared:WaitForChild("GladiatorLevelDefinitions"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))
local ItemInfo = require(script.Parent:WaitForChild("ItemInfo"))
local THEME = UiConfig.Menu

local ShopController = {}

type Names = {
	tag: string,
	aura: string,
	denarii: string,
	equippedWeapon: string,
	equippedShield: string,
	equippedArmor: string,
	ownedWeapons: string,
	ownedShields: string,
	ownedArmor: string,
	dataStatus: string,
}

type GroupFn = (name: string, anchor: Vector2, position: UDim2, size: UDim2?) -> Frame

type Card = {
	title: string,
	section: string,
	stats: { string },
	info: string,
}

local GREEN = THEME.Positive
local MUTED = THEME.TextMuted

local function splitSet(value: unknown): { [string]: boolean }
	local set = {}
	if typeof(value) == "string" then
		for id in value:gmatch("[^,]+") do
			set[id] = true
		end
	end
	return set
end

-- The card texts come from ItemInfo (the same real values as the lobby inventory).
local function describe(kind: string, id: string): Card?
	local card = ItemInfo.describe(kind, id)
	if not card then
		return nil
	end
	local stats = {}
	for _, v in card.values do
		table.insert(stats, ("%s  %s"):format(v.label:upper(), v.text))
	end
	local info = card.description
	for _, note in card.notes do
		info ..= " · " .. note
	end
	return { title = card.title, section = card.section, stats = stats, info = info }
end

local function label(parent: Instance, name: string, order: number, height: number, size: number, font: Enum.Font, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.LayoutOrder = order
	l.Size = UDim2.new(1, 0, 0, height)
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = ""
	l.Parent = parent
	return l
end

function ShopController.start(names: Names, group: GroupFn)
	local player = Players.LocalPlayer

	------------------------------------------------------------------ card
	local frame = group("ArmoryCard", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -150), UDim2.fromOffset(300, 0))
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = THEME.Panel
	frame.BackgroundTransparency = 0.12
	frame.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = THEME.Bronze
	stroke.Transparency = 0.35
	stroke.Thickness = 1.5
	stroke.Parent = frame
	local padding = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(padding :: any)[side] = UDim.new(0, 10)
	end
	padding.Parent = frame
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 3)
	list.Parent = frame

	local section = label(frame, "Section", 1, 14, 11, THEME.LabelFont, THEME.Bronze)
	local title = label(frame, "Title", 2, 22, 19, THEME.TitleFont, THEME.Gold)
	title.TextScaled = true
	local statLabels: { TextLabel } = {}
	for i = 1, 5 do
		statLabels[i] = label(frame, "Stat" .. i, 2 + i, 16, 13, THEME.BodyFont, THEME.Text)
		statLabels[i].AutomaticSize = Enum.AutomaticSize.Y
	end
	local status = label(frame, "Status", 8, 18, 14, Enum.Font.GothamBold, MUTED)
	status.AutomaticSize = Enum.AutomaticSize.Y -- longer German states wrap instead of being cut off
	local info = label(frame, "Info", 9, 0, 12, THEME.BodyFont, THEME.TextMuted)
	info.AutomaticSize = Enum.AutomaticSize.Y
	info.Visible = false

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.LayoutOrder = 10
	buttons.Size = UDim2.new(1, 0, 0, 38)
	buttons.BackgroundTransparency = 1
	buttons.Parent = frame
	local action = Instance.new("TextButton")
	action.Name = "Action"
	action.Size = UDim2.new(1, -46, 1, 0)
	action.BackgroundColor3 = THEME.Primary
	action.Font = Enum.Font.GothamBlack
	action.TextSize = 15
	action.TextColor3 = Color3.new(1, 1, 1)
	action.AutoButtonColor = true
	action.Parent = buttons
	local actionCorner = Instance.new("UICorner")
	actionCorner.CornerRadius = UDim.new(0, 8)
	actionCorner.Parent = action
	local infoButton = Instance.new("TextButton")
	infoButton.Name = "InfoToggle"
	infoButton.AnchorPoint = Vector2.new(1, 0)
	infoButton.Position = UDim2.fromScale(1, 0)
	infoButton.Size = UDim2.fromOffset(38, 38)
	infoButton.BackgroundColor3 = THEME.SurfaceRaised
	infoButton.Font = Enum.Font.GothamBlack
	infoButton.TextSize = 18
	infoButton.TextColor3 = Color3.new(1, 1, 1)
	infoButton.Text = "i"
	infoButton.Parent = buttons
	local infoCorner = Instance.new("UICorner")
	infoCorner.CornerRadius = UDim.new(1, 0)
	infoCorner.Parent = infoButton

	------------------------------------------------------------------ state
	local currentPrompt: ProximityPrompt? = nil
	local currentItem: Instance? = nil
	local inputType: Enum.ProximityPromptInputType = Enum.ProximityPromptInputType.Keyboard
	local focus = Instance.new("Highlight")
	focus.Name = "ArmoryFocus"
	focus.FillColor = UiConfig.Gold
	focus.FillTransparency = 0.88
	focus.OutlineColor = UiConfig.Gold
	focus.OutlineTransparency = 0.1
	focus.DepthMode = Enum.HighlightDepthMode.Occluded
	focus.Enabled = false

	-- (kind, id, owned, equipped, price in Denarii, gladiator level required to unlock)
	local function itemInfo(item: Instance): (string, string, boolean, boolean, number, number)
		local kind = tostring(item:GetAttribute("ItemKind"))
		local id = tostring(item:GetAttribute("ItemId"))
		local ownedName = if kind == "Weapon" then names.ownedWeapons elseif kind == "Shield" then names.ownedShields else names.ownedArmor
		local equippedName = if kind == "Weapon" then names.equippedWeapon elseif kind == "Shield" then names.equippedShield else names.equippedArmor
		local owned = splitSet(player:GetAttribute(ownedName))[id] == true
		local equipped = player:GetAttribute(equippedName) == id
		return kind, id, owned, equipped, tonumber(item:GetAttribute("Price")) or 0, tonumber(item:GetAttribute("LevelRequired")) or 1
	end

	local function keyHint(): string
		if inputType == Enum.ProximityPromptInputType.Keyboard then
			return "[F] "
		elseif inputType == Enum.ProximityPromptInputType.Gamepad then
			return "[X] "
		end
		return ""
	end

	local function refreshCard()
		local item = currentItem
		if not item then
			frame.Visible = false
			focus.Enabled = false
			return
		end
		local kind, id, owned, equipped, price, required = itemInfo(item)
		local card = describe(kind, id)
		if not card then
			frame.Visible = false
			return
		end
		section.Text = card.section
		title.Text = card.title
		for i, l in statLabels do
			l.Text = card.stats[i] or ""
			l.Visible = card.stats[i] ~= nil
		end
		info.Text = card.info
		local aura = tonumber(player:GetAttribute(names.aura)) or 0
		local denarii = tonumber(player:GetAttribute(names.denarii)) or 0
		local level = GladiatorLevelDefinitions.levelFor(aura).Level
		local unlocked = level >= required
		local loading = player:GetAttribute(names.dataStatus) == "Loading"
		if equipped then
			status.Text = "AUSGERÜSTET"
			status.TextColor3 = GREEN
			action.Text = "✓ AUSGERÜSTET"
			action.BackgroundColor3 = THEME.Equipped
			action.Active = false
		elseif owned then
			status.Text = "IM BESITZ · auch im MENÜ unter AUSRÜSTUNG wechselbar"
			status.TextColor3 = THEME.Text
			action.Text = keyHint() .. "AUSRÜSTEN"
			action.BackgroundColor3 = THEME.SurfaceRaised
			action.Active = true
		elseif not unlocked then
			-- the gladiator level (from total Aura, never spent) unlocks gear; until then it can't be bought
			local needed = GladiatorLevelDefinitions.get(required)
			status.Text = ("GESPERRT · ab Level %d %s · du bist Level %d"):format(required, if needed then needed.Title else "", level)
			status.TextColor3 = THEME.TextMuted
			action.Text = ("🔒 GESPERRT · LEVEL %d"):format(required)
			action.BackgroundColor3 = THEME.Locked
			action.Active = false
		else
			local affordable = denarii >= price
			status.Text = if price > 0 then ("PREIS  %d DENARII · du hast %d"):format(price, denarii) else "KOSTENLOS"
			status.TextColor3 = if affordable then THEME.Text else THEME.Negative
			action.Text = keyHint() .. (if price > 0 then ("KAUFEN · %d DENARII"):format(price) else "NEHMEN")
			action.BackgroundColor3 = if affordable then THEME.Primary else THEME.Locked
			action.Active = true
		end
		if loading then
			action.Text = "AUSRÜSTUNG LÄDT …"
			action.Active = false
		end
		action.AutoButtonColor = action.Active
		focus.Adornee = item
		focus.Parent = item
		focus.Enabled = true
		frame.Visible = true
	end

	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt, promptInput: Enum.ProximityPromptInputType)
		local item = prompt:FindFirstAncestorWhichIsA("Model")
		if prompt.Name ~= "ShopPrompt" or not item or not CollectionService:HasTag(item, names.tag) then
			return
		end
		currentPrompt = prompt
		currentItem = item
		inputType = promptInput
		info.Visible = false
		refreshCard()
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		if prompt == currentPrompt then
			currentPrompt = nil
			currentItem = nil
			refreshCard()
		end
	end)

	action.Activated:Connect(function()
		local prompt = currentPrompt
		if prompt and action.Active then
			-- The same prompt the F key uses: one server path for every input
			prompt:InputHoldBegin()
			prompt:InputHoldEnd()
		end
	end)
	infoButton.Activated:Connect(function()
		info.Visible = not info.Visible
	end)

	------------------------------------------------------------------ equipped outlines
	local function refreshItem(item: Instance)
		local _, _, _, equipped = itemInfo(item)
		local display = item:FindFirstChild("Display")
		if display then
			local highlight = display:FindFirstChild("EquippedHighlight")
			if equipped and not highlight then
				local h = Instance.new("Highlight")
				h.Name = "EquippedHighlight"
				h.FillTransparency = 1
				h.OutlineColor = GREEN
				h.DepthMode = Enum.HighlightDepthMode.Occluded
				h.Parent = display
			elseif not equipped and highlight then
				highlight:Destroy()
			end
		end
	end

	local function refreshAll()
		for _, item in CollectionService:GetTagged(names.tag) do
			refreshItem(item)
		end
		refreshCard()
	end

	CollectionService:GetInstanceAddedSignal(names.tag):Connect(function(item)
		task.defer(refreshItem, item) -- wait for descendants to replicate
	end)
	for _, attribute in {
		names.aura, names.denarii, names.equippedWeapon, names.equippedShield, names.equippedArmor,
		names.ownedWeapons, names.ownedShields, names.ownedArmor, names.dataStatus,
	} do
		player:GetAttributeChangedSignal(attribute):Connect(refreshAll)
	end
	refreshAll()
end

return ShopController
