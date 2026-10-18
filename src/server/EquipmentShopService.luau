--!strict
-- The equipment wall in the lobby: one pedestal per weapon and shield with a physical model,
-- a plaque (name, stat, price, owned/locked state) and a ProximityPrompt.
-- The prompt is server-side: if the player owns the item it is equipped, otherwise it is
-- bought (and equipped) through InventoryService, which validates coins and ownership.
-- Per-player text (BUY/EQUIP/EQUIPPED, owned/locked) and the equipped highlight are drawn
-- locally by the client's ShopController from the player's inventory attributes.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local ShieldDefinitions = require(ReplicatedStorage.Shared.ShieldDefinitions)
local SpecialMoveDefinitions = require(ReplicatedStorage.Shared.SpecialMoveDefinitions)
local WeaponDefinitions = require(ReplicatedStorage.Shared.WeaponDefinitions)
local EquipmentModels = require(script.Parent.EquipmentModels)
local InventoryService = require(script.Parent.InventoryService)
local PlayerCombatService = require(script.Parent.PlayerCombatService)
local Remotes = require(script.Parent.Remotes)

type ItemKind = InventoryService.ItemKind

local STONE = Color3.fromRGB(156, 140, 118)
local PLAQUE = Color3.fromRGB(60, 40, 26)
local GOLD = Color3.fromRGB(240, 196, 80)

local PREFIX = "[OttiArena][Server]"

local EquipmentShopService = {}

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Parent = parent
	return part
end

local function label(parent: Instance, name: string, text: string, order: number, scale: number, color: Color3, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.LayoutOrder = order
	l.Size = UDim2.fromScale(0.95, scale)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextScaled = true
	l.Font = font
	l.TextColor3 = color
	l.Parent = parent
	return l
end

local function onTriggered(player: Player, kind: ItemKind, id: string)
	local state = player:GetAttribute(GameStates.StateAttribute)
	if not GameStates.canChangeEquipment(state) then
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, "Equipment can't change during a fight", false)
		return
	end
	local ok, message
	if InventoryService.owns(player, kind, id) then
		ok, message = InventoryService.equip(player, kind, id)
	else
		ok, message = InventoryService.purchase(player, kind, id)
		if ok then
			InventoryService.equip(player, kind, id)
			print(PREFIX, player.Name, message)
		end
	end
	if ok then
		PlayerCombatService.refreshEquipment(player)
	end
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, message, ok)
end

local function buildItem(parent: Instance, slot: CFrame, kind: ItemKind, id: string, name: string, statText: string, price: number, note: string)
	local item = Instance.new("Model")
	item.Name = "ShopItem_" .. id
	item:SetAttribute("ItemKind", kind)
	item:SetAttribute("ItemId", id)
	item:SetAttribute("Price", price)

	local pedestal = makePart("Pedestal", Vector3.new(3, 3, 3), slot * CFrame.new(0, 1.5, 0), STONE, Enum.Material.Limestone, item)
	makePart("PedestalTop", Vector3.new(3.4, 0.3, 3.4), slot * CFrame.new(0, 3.15, 0), Color3.fromRGB(176, 125, 60), Enum.Material.Metal, item)

	-- Plaque on the front face (toward the hall)
	local plaque = makePart("Plaque", Vector3.new(2.9, 2.8, 0.2), slot * CFrame.new(0, 1.5, -1.6), PLAQUE, Enum.Material.Wood, item)
	plaque.CanCollide = false
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlaqueGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.Parent = plaque
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = gui
	label(gui, "ItemName", name, 1, 0.2, GOLD, Enum.Font.GothamBold)
	label(gui, "Stat", statText, 2, 0.16, Color3.new(1, 1, 1), Enum.Font.Gotham)
	label(gui, "Note", note, 3, 0.14, Color3.fromRGB(255, 190, 150), Enum.Font.Gotham)
	label(gui, "Price", if price > 0 then ("%d AURA"):format(price) else "FREE", 4, 0.18, Color3.fromRGB(255, 220, 120), Enum.Font.GothamBold)
	label(gui, "Status", "LOCKED", 5, 0.2, Color3.fromRGB(200, 200, 200), Enum.Font.GothamBlack)

	-- Physical display model above the pedestal (anchored, no collisions)
	local display, core
	if kind == "Weapon" then
		display, core = EquipmentModels.buildWeapon(id)
	else
		display, core = EquipmentModels.buildShield(id)
	end
	display.Name = "Display"
	local pose: CFrame
	if kind == "Shield" then
		pose = slot * CFrame.new(0, 5.6, 0) * CFrame.Angles(math.rad(-90), 0, 0) -- face toward the hall
	elseif id == "HunterBow" then
		pose = slot * CFrame.new(0, 6, 0) * CFrame.Angles(math.rad(-90), 0, 0) -- limbs vertical
	else
		pose = slot * CFrame.new(0, 4.2, 0) -- upright, blade up
	end
	display:PivotTo(pose)
	for _, part in display:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	core.Transparency = 1
	display.Parent = item

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Buy / Equip"
	prompt.ObjectText = name
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 8
	prompt.KeyboardKeyCode = Enum.KeyCode.F -- Q/E are special attacks
	prompt.GamepadKeyCode = Enum.KeyCode.DPadUp
	prompt.RequiresLineOfSight = false
	prompt.Parent = pedestal
	prompt.Triggered:Connect(function(player)
		onTriggered(player, kind, id)
	end)

	item.Parent = parent
	CollectionService:AddTag(item, Config.ShopItemTag)
end

function EquipmentShopService.build(parent: Instance, weaponSlots: { CFrame }, shieldSlots: { CFrame })
	local shop = Instance.new("Folder")
	shop.Name = "Shop"
	for i, weapon in WeaponDefinitions.Ordered do
		local slot = weaponSlots[i]
		if slot then
			local stat = if weapon.Kind == "Bow"
				then ("DMG %d · range %d · %.2fs"):format(weapon.Damage, weapon.Range, weapon.Cooldown)
				else ("DMG %d · range %g · %.2fs"):format(weapon.Damage, weapon.Range, weapon.Cooldown)
			local q, e = SpecialMoveDefinitions[weapon.Special1], SpecialMoveDefinitions[weapon.Special2]
			local note = if weapon.TwoHanded
				then "TWO-HANDED: no shield, built-in parry"
				else ("Q %s · E %s"):format(q.Name, e.Name)
			buildItem(shop, slot, "Weapon", weapon.Id, weapon.DisplayName, stat, weapon.Price, note)
		end
	end
	for i, shield in ShieldDefinitions.Ordered do
		local slot = shieldSlots[i]
		if slot then
			local angle = math.deg(math.acos(math.clamp(shield.FacingDot, -1, 1)))
			local stat = ("BLOCK %d%% · arrows %d%% · %d°"):format(math.round(shield.Reduction * 100), math.round(shield.ProjectileReduction * 100), math.round(angle))
			local note = ("Move %d%% while blocking · raise %.2fs"):format(math.round(shield.BlockSpeedMultiplier * 100), shield.RaiseSeconds)
			buildItem(shop, slot, "Shield", shield.Id, shield.DisplayName, stat, shield.Price, note)
		end
	end
	shop.Parent = parent
end

return EquipmentShopService
