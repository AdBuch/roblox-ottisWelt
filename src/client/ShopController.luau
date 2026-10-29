--!strict
-- Gladiator Armory presentation (all decisions happen on the server):
--   * The displays' ProximityPrompts use the Custom style. When Roblox shows the closest one
--     (PromptShown), this highlights that display and opens a compact information card: name,
--     section, the stats of its kind, the gladiator level unlock (LOCKED until reached), the price in Denarii and
--     OWNED / EQUIPPED state, an action button (LOCKED / BUY / EQUIP / EQUIPPED) and an optional
--     INFO line (special / projectile properties).
--   * F (keyboard), X (gamepad) or the card's button (touch / mouse) trigger the same prompt;
--     the server validates and answers through the Shop feedback notification.
--   * Equipped items keep a green outline. No large permanent text panels in the world.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmorDefinitions = require(Shared:WaitForChild("ArmorDefinitions"))
local DamageConfig = require(Shared:WaitForChild("DamageConfig"))
local GladiatorLevelDefinitions = require(Shared:WaitForChild("GladiatorLevelDefinitions"))
local ShieldDefinitions = require(Shared:WaitForChild("ShieldDefinitions"))
local SpecialMoveDefinitions = require(Shared:WaitForChild("SpecialMoveDefinitions"))
local WeaponAttackDefinitions = require(Shared:WaitForChild("WeaponAttackDefinitions"))
local WeaponSpecialDefinitions = require(Shared:WaitForChild("WeaponSpecialDefinitions"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))
local WeaponDefinitions = require(Shared:WaitForChild("WeaponDefinitions"))

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

local GREEN = Color3.fromRGB(120, 255, 140)
local MUTED = Color3.fromRGB(200, 200, 200)
local ROW_NAMES = { Blades = "BLADES", Heavy = "HEAVY & REACH", Ranged = "RANGED & SPECIAL" }

local function splitSet(value: unknown): { [string]: boolean }
	local set = {}
	if typeof(value) == "string" then
		for id in value:gmatch("[^,]+") do
			set[id] = true
		end
	end
	return set
end

local function pct(value: number): string
	return ("%d%%"):format(math.round(value * 100))
end

local function speedWord(cooldown: number): string
	return if cooldown <= 0.45 then "fast" elseif cooldown <= 0.75 then "medium" else "slow"
end

local function describe(kind: string, id: string): Card?
	if kind == "Weapon" then
		local weapon = WeaponDefinitions.ById[id]
		if not weapon then
			return nil
		end
		local aerial = (SpecialMoveDefinitions :: any)[weapon.Aerial]
		-- Special families of this weapon (gesture tiers: 25 / 50 / 75 Momentum, Ultimate 100)
		local specials = {}
		local families = WeaponSpecialDefinitions.forPrefix(WeaponAttackDefinitions.prefixOf(weapon.Basic))
		for _, family in { "Left", "Right", "Up", "Down", "Circle", "Ultimate" } do
			local moveId = families and (families :: any)[family]
			local move = moveId and (SpecialMoveDefinitions :: any)[moveId]
			if move then
				local Practice = require(ReplicatedStorage.Shared.SpecialPracticeDefinitions)
				local unlock = if family == "Up" then " · air Lv5" elseif family == "Circle" then " · block Lv9" else ""
				table.insert(specials, move.Name .. " (" .. Practice.label(Players.LocalPlayer, weapon.Id, moveId) .. unlock .. ")")
			end
		end
		local stats = { ("DAMAGE  %d"):format(weapon.Damage) }
		local info = weapon.Description
		if weapon.Kind == "Bow" then
			table.insert(stats, ("RANGE  %d studs"):format(weapon.Range))
			table.insert(stats, ("FIRING SPEED  %.2fs (%s)"):format(weapon.Cooldown, speedWord(weapon.Cooldown)))
			info ..= " · Projectile: flies to your aim point, stopped by walls and raised shields"
		else
			table.insert(stats, ("ATTACK SPEED  %.2fs (%s)"):format(weapon.Cooldown, speedWord(weapon.Cooldown)))
			table.insert(stats, ("%s  %g studs"):format(if weapon.Row == "Heavy" then "REACH" else "RANGE", weapon.Range))
		end
		if weapon.TwoHanded then
			table.insert(stats, "TWO-HANDED · no shield, built-in parry")
		end
		if aerial then
			info ..= " · Jump attack: " .. aerial.Name
		end
		if #specials > 0 then
			info ..= " · Specials: " .. table.concat(specials, ", ")
		end
		return { title = weapon.DisplayName, section = ROW_NAMES[weapon.Row] or "WEAPONS", stats = stats, info = info }
	elseif kind == "Shield" then
		local shield = ShieldDefinitions.ById[id]
		if not shield then
			return nil
		end
		local angle = math.deg(math.acos(math.clamp(shield.FacingDot, -1, 1))) * 2
		return {
			title = shield.DisplayName,
			section = ShieldDefinitions.classOf(shield):upper() .. " SHIELD",
			stats = {
				("FRONT BLOCK  %s · arrows %s"):format(pct(shield.Reduction), pct(shield.ProjectileReduction)),
				("BLOCK ANGLE  %d°"):format(math.round(angle)),
				("MOVEMENT  %s while blocking · raise %.2fs"):format(pct(shield.BlockSpeedMultiplier), shield.RaiseSeconds),
			},
			info = shield.Description .. " · One shield equipped at a time (unused with Twin Arena Daggers)",
		}
	elseif kind == "Armor" then
		local armor = ArmorDefinitions.ById[id]
		if not armor then
			return nil
		end
		return {
			title = armor.DisplayName,
			section = "ARMOR",
			stats = {
				("DAMAGE REDUCTION  %s (PvP %s)"):format(pct(armor.Reduction), pct(armor.Reduction * DamageConfig.PvPArmorEffectiveness)),
				("MOVEMENT  %s"):format(if armor.MovePenalty > 0 then "-" .. pct(armor.MovePenalty) else "no penalty"),
			},
			info = armor.Description .. " · One set equipped; changed only in the lobby, never during a match",
		}
	end
	return nil
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
	frame.BackgroundColor3 = UiConfig.Panel
	frame.BackgroundTransparency = 0.12
	frame.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiConfig.Gold
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

	local section = label(frame, "Section", 1, 14, 11, Enum.Font.GothamBold, Color3.fromRGB(255, 190, 150))
	local title = label(frame, "Title", 2, 22, 19, Enum.Font.Garamond, UiConfig.Gold)
	title.TextScaled = true
	local statLabels: { TextLabel } = {}
	for i = 1, 4 do
		statLabels[i] = label(frame, "Stat" .. i, 2 + i, 16, 13, Enum.Font.Gotham, Color3.new(1, 1, 1))
	end
	local status = label(frame, "Status", 8, 18, 14, Enum.Font.GothamBold, MUTED)
	local info = label(frame, "Info", 9, 0, 12, Enum.Font.Gotham, Color3.fromRGB(230, 220, 200))
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
	action.BackgroundColor3 = Color3.fromRGB(150, 40, 34)
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
	infoButton.BackgroundColor3 = Color3.fromRGB(70, 56, 40)
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
			status.Text = "EQUIPPED"
			status.TextColor3 = GREEN
			action.Text = "EQUIPPED"
			action.BackgroundColor3 = Color3.fromRGB(46, 90, 52)
			action.Active = false
		elseif owned then
			status.Text = "OWNED"
			status.TextColor3 = Color3.fromRGB(200, 230, 255)
			action.Text = keyHint() .. "EQUIP"
			action.BackgroundColor3 = Color3.fromRGB(46, 96, 150)
			action.Active = true
		elseif not unlocked then
			-- the gladiator level (from total Aura, never spent) unlocks gear; until then it can't be bought
			local needed = GladiatorLevelDefinitions.get(required)
			status.Text = ("LOCKED · needs LV %d %s · you are LV %d"):format(required, if needed then needed.Title else "", level)
			status.TextColor3 = Color3.fromRGB(190, 190, 200)
			action.Text = ("LOCKED · LV %d"):format(required)
			action.BackgroundColor3 = Color3.fromRGB(70, 66, 64)
			action.Active = false
		else
			local affordable = denarii >= price
			status.Text = if price > 0 then ("PRICE  %d DENARII · you have %d"):format(price, denarii) else "FREE"
			status.TextColor3 = if affordable then Color3.fromRGB(214, 222, 232) else Color3.fromRGB(255, 130, 120)
			action.Text = keyHint() .. (if price > 0 then ("BUY · %d DENARII"):format(price) else "TAKE")
			action.BackgroundColor3 = if affordable then Color3.fromRGB(150, 40, 34) else Color3.fromRGB(90, 60, 56)
			action.Active = true
		end
		if loading then
			action.Text = "LOADING GEAR..."
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
