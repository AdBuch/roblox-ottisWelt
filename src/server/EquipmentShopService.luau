--!strict
-- The Gladiator Armory displays: every weapon, shield and armor set has its own display with a
-- physical model and a small name plate (no large text panels). Items are spread along the
-- armory's display lines, so new definitions appear automatically:
--   weapons  BLADES / HEAVY & REACH / RANGED & SPECIAL (WeaponDefinitions Row) on wall racks
--   shields  LIGHT / BALANCED / HEAVY (ShieldDefinitions.classOf) on the south wall
--   armor    wooden mannequins on the central dais
-- Each display has one custom-styled ProximityPrompt (F / gamepad / the card's button on touch).
-- The client's ShopController draws the compact info card and the highlight; the decision is
-- made here: lobby state, inside the armory, close to the display, data loaded, then
-- InventoryService buys (never twice, never below 0 Aura) or equips (only owned items).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmorDefinitions = require(ReplicatedStorage.Shared.ArmorDefinitions)
local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local ShieldDefinitions = require(ReplicatedStorage.Shared.ShieldDefinitions)
local WeaponDefinitions = require(ReplicatedStorage.Shared.WeaponDefinitions)
local CombatUtil = require(script.Parent.CombatUtil)
local EquipmentModels = require(script.Parent.EquipmentModels)
local InventoryService = require(script.Parent.InventoryService)
local LobbyService = require(script.Parent.LobbyService)
local PlayerCombatService = require(script.Parent.PlayerCombatService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local Remotes = require(script.Parent.Remotes)

type ItemKind = InventoryService.ItemKind
type DisplayLine = LobbyService.DisplayLine

local STONE = Color3.fromRGB(156, 140, 118)
local WOOD = Color3.fromRGB(116, 78, 46)
local DARK_WOOD = Color3.fromRGB(78, 52, 32)
local BRONZE = Color3.fromRGB(176, 125, 60)
local LEATHER = Color3.fromRGB(92, 58, 32)
local MANNEQUIN = Color3.fromRGB(150, 112, 74)
local PLATE_TEXT = Color3.fromRGB(48, 28, 14)

local PREFIX = "[OttiArena][Server]"
local PROMPT_DISTANCE = 7
local MAX_USE_DISTANCE = 11 -- server check (a little above the prompt distance for latency)
local REQUEST_INTERVAL = 0.3

local EquipmentShopService = {}

local lastRequest: { [Player]: number } = {}

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance, collide: boolean?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if collide == false then
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
	part.Parent = parent
	return part
end

-- Small bronze name plate (the only permanent text on a display).
local function namePlate(parent: Instance, cframe: CFrame, text: string)
	local plate = makePart("NamePlate", Vector3.new(3.2, 0.6, 0.1), cframe, BRONZE, Enum.Material.Metal, parent, false)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.MaxDistance = 40
	gui.Parent = plate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.95, 0.9)
	label.Position = UDim2.fromScale(0.025, 0.05)
	label.BackgroundTransparency = 1
	label.Text = text:upper()
	label.TextScaled = true
	label.Font = Enum.Font.Garamond
	label.TextColor3 = PLATE_TEXT
	label.Parent = gui
end

local function anchorAll(model: Instance)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
end

local function onTriggered(player: Player, kind: ItemKind, id: string, anchor: BasePart)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < REQUEST_INTERVAL then
		return
	end
	lastRequest[player] = now
	local function refuse(message: string)
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, message, false)
	end
	if not InventoryService.isItem(kind, id) then
		return
	end
	local state = player:GetAttribute(GameStates.StateAttribute)
	local location = player:GetAttribute(GameStates.LocationAttribute)
	if not GameStates.canChangeEquipment(state) or (location ~= nil and location ~= "Lobby") then
		refuse("Equipment can only change in the lobby")
		return
	end
	local _, _, root = CombatUtil.getLivingCharacter(player)
	if not root or not LobbyService.isInArmory(root.Position) or (root.Position - anchor.Position).Magnitude > MAX_USE_DISTANCE then
		return -- no remote purchases from outside the armory
	end
	if not PlayerDataService.isReady(player) then
		refuse("Loading your saved gear... try again in a moment")
		return
	end

	local ok, message
	if InventoryService.owns(player, kind, id) then
		if InventoryService.isEquipped(player, kind, id) then
			refuse("Already equipped")
			return
		end
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

local function newItem(kind: ItemKind, id: string, price: number): Model
	local item = Instance.new("Model")
	item.Name = "ShopItem_" .. id
	item:SetAttribute("ItemKind", kind)
	item:SetAttribute("ItemId", id)
	item:SetAttribute("Price", price)
	return item
end

local function addPrompt(item: Model, anchor: BasePart, kind: ItemKind, id: string, name: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.Style = Enum.ProximityPromptStyle.Custom -- the client draws the compact info card
	prompt.ActionText = "Buy / Equip"
	prompt.ObjectText = name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		onTriggered(player, kind, id, anchor)
	end)
	CollectionService:AddTag(item, Config.ShopItemTag)
end

-- Evenly spreads `count` displays along a line (at most `maxSpacing` apart). Returns slot CFrames.
local function slots(line: DisplayLine, count: number, maxSpacing: number): { CFrame }
	local result = {}
	if count <= 0 then
		return result
	end
	local spacing = math.min(maxSpacing, line.length / count)
	for i = 1, count do
		table.insert(result, line.cframe * CFrame.new((i - (count + 1) / 2) * spacing, 0, 0))
	end
	return result
end

-- Lifts a posed display so its lowest point sits `bottom` studs above the slot's floor.
local function rest(display: Model, pose: CFrame, slot: CFrame, bottom: number): (CFrame, Vector3)
	display:PivotTo(pose)
	local box, size = display:GetBoundingBox()
	local floorY = slot.Position.Y
	local lift = bottom - (box.Position.Y - size.Y / 2 - floorY)
	display:PivotTo(pose + Vector3.new(0, lift, 0))
	return box + Vector3.new(0, lift, 0), size
end

------------------------------------------------------------------------------------------
-- Display builders (slot: on the floor, LookVector into the room, the wall at local +Z)
------------------------------------------------------------------------------------------

local function buildWeaponRack(parent: Instance, slot: CFrame, weapon: WeaponDefinitions.WeaponDefinition)
	local item = newItem("Weapon", weapon.Id, weapon.Price)
	local display, core = EquipmentModels.buildWeapon(weapon.Id)
	display.Name = "Display"
	local rotation = if weapon.Kind == "Bow" then CFrame.Angles(math.rad(-90), 0, 0) else CFrame.identity
	anchorAll(display)
	core.Transparency = 1
	local box, size = rest(display, slot * CFrame.new(0, 0, 1.5) * rotation, slot, 1.6)
	display.Parent = item
	local centerY = box.Position.Y - slot.Position.Y
	local boardHeight = size.Y + 2

	-- Wooden wall rack behind the weapon, bronze pegs, a stone plinth in front
	local boardWidth = math.max(3.2, math.max(size.X, size.Z) + 1.6)
	makePart("RackBoard", Vector3.new(boardWidth, boardHeight, 0.3), slot * CFrame.new(0, centerY, 2.3), DARK_WOOD, Enum.Material.WoodPlanks, item)
	makePart("RackTrim", Vector3.new(boardWidth + 0.4, 0.3, 0.45), slot * CFrame.new(0, centerY + boardHeight / 2, 2.25), BRONZE, Enum.Material.Metal, item, false)
	for _, share in { -0.25, 0.25 } do
		makePart("RackPeg", Vector3.new(boardWidth * 0.7, 0.2, 0.2), slot * CFrame.new(0, centerY + size.Y * share, 1.95), WOOD, Enum.Material.Wood, item, false)
	end
	local plinth = makePart("Plinth", Vector3.new(boardWidth, 1, 1.8), slot * CFrame.new(0, 0.5, 1.4), STONE, Enum.Material.Limestone, item)
	namePlate(item, slot * CFrame.new(0, 0.55, 0.47), weapon.DisplayName)

	if weapon.Kind == "Bow" then
		-- Quiver with arrows standing beside the bow
		local quiverCFrame = slot * CFrame.new(boardWidth / 2 + 0.9, 1.0 + 1.3, 1.2)
		makePart("Quiver", Vector3.new(2.6, 0.9, 0.9), quiverCFrame * CFrame.Angles(0, 0, math.rad(90)), LEATHER, Enum.Material.Leather, item, false).Shape = Enum.PartType.Cylinder
		makePart("QuiverRim", Vector3.new(0.2, 1.0, 1.0), quiverCFrame * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.rad(90)), BRONZE, Enum.Material.Metal, item, false).Shape = Enum.PartType.Cylinder
		makePart("QuiverStand", Vector3.new(1.4, 1, 1.4), slot * CFrame.new(boardWidth / 2 + 0.9, 0.5, 1.2), STONE, Enum.Material.Limestone, item)
		for i, offset in { Vector3.new(-0.2, 0, -0.1), Vector3.new(0.2, 0, 0.1), Vector3.new(0, 0, 0.25), Vector3.new(0.15, 0, -0.25) } do
			local arrow = EquipmentModels.buildArrow()
			anchorAll(arrow)
			arrow:PivotTo(quiverCFrame * CFrame.new(offset.X, 1.6 + i * 0.08, offset.Z) * CFrame.Angles(math.rad(90), 0, math.rad(i * 25)))
			arrow.Parent = item
		end
	end

	addPrompt(item, plinth, "Weapon", weapon.Id, weapon.DisplayName)
	item.Parent = parent
end

local function buildShieldDisplay(parent: Instance, slot: CFrame, shield: ShieldDefinitions.ShieldDefinition)
	local item = newItem("Shield", shield.Id, shield.Price)
	local display, core = EquipmentModels.buildShield(shield.Id)
	display.Name = "Display"
	anchorAll(display)
	core.Transparency = 1
	local box, size = rest(display, slot * CFrame.new(0, 0, 1.6) * CFrame.Angles(math.rad(-90), 0, 0), slot, 2.4)
	display.Parent = item
	local centerY = box.Position.Y - slot.Position.Y
	local boardSize = math.max(size.X, size.Y) + 1.2
	makePart("ShieldBoard", Vector3.new(boardSize, boardSize, 0.3), slot * CFrame.new(0, centerY, 2.3), DARK_WOOD, Enum.Material.WoodPlanks, item)
	makePart("ShieldHook", Vector3.new(0.3, 0.3, 0.8), slot * CFrame.new(0, centerY + size.Y / 2 - 0.1, 1.9), BRONZE, Enum.Material.Metal, item, false)
	local plinth = makePart("Plinth", Vector3.new(math.max(3.4, boardSize), 1, 1.8), slot * CFrame.new(0, 0.5, 1.4), STONE, Enum.Material.Limestone, item)
	namePlate(item, slot * CFrame.new(0, 0.55, 0.47), shield.DisplayName)
	addPrompt(item, plinth, "Shield", shield.Id, shield.DisplayName)
	item.Parent = parent
end

-- A simple wooden training mannequin with R15 limb names, so buildArmor fits it like a player.
local function buildMannequin(parent: Instance, base: CFrame): Model
	local body = Instance.new("Model")
	body.Name = "Mannequin"
	local function limb(name: string, size: Vector3, offset: Vector3, shape: Enum.PartType?)
		local part = makePart(name, size, base * CFrame.new(offset), MANNEQUIN, Enum.Material.Wood, body, false)
		if shape then
			part.Shape = shape
		end
	end
	limb("LeftLowerLeg", Vector3.new(0.9, 1.4, 0.9), Vector3.new(-0.5, 1.6, 0))
	limb("RightLowerLeg", Vector3.new(0.9, 1.4, 0.9), Vector3.new(0.5, 1.6, 0))
	limb("LeftUpperLeg", Vector3.new(1, 1.5, 1), Vector3.new(-0.5, 3.05, 0))
	limb("RightUpperLeg", Vector3.new(1, 1.5, 1), Vector3.new(0.5, 3.05, 0))
	limb("LowerTorso", Vector3.new(2, 0.4, 1), Vector3.new(0, 4, 0))
	limb("UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 5, 0))
	limb("LeftUpperArm", Vector3.new(1, 1.2, 1), Vector3.new(-1.5, 5.2, 0))
	limb("RightUpperArm", Vector3.new(1, 1.2, 1), Vector3.new(1.5, 5.2, 0))
	limb("LeftLowerArm", Vector3.new(0.9, 1.1, 0.9), Vector3.new(-1.5, 4.05, 0))
	limb("RightLowerArm", Vector3.new(0.9, 1.1, 0.9), Vector3.new(1.5, 4.05, 0))
	limb("Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 6.5, 0), Enum.PartType.Ball)
	limb("Pole", Vector3.new(0.3, 0.9, 0.3), Vector3.new(0, 0.45, 0))
	body.Parent = parent
	return body
end

local function buildArmorDisplay(parent: Instance, slot: CFrame, armor: ArmorDefinitions.ArmorDefinition)
	local item = newItem("Armor", armor.Id, armor.Price)
	local base = slot * CFrame.new(0, 0.85, 0)
	local stand = makePart("Stand", Vector3.new(3, 0.3, 2.4), base * CFrame.new(0, 0.15, 0), DARK_WOOD, Enum.Material.Wood, item)
	local body = buildMannequin(item, base * CFrame.new(0, 0.3, 0))
	local armorModel = EquipmentModels.buildArmor(armor.Id, body)
	armorModel.Name = "Display"
	armorModel.Parent = item
	anchorAll(armorModel)
	namePlate(item, base * CFrame.new(0, 0.15, -1.25), armor.DisplayName)
	addPrompt(item, stand, "Armor", armor.Id, armor.DisplayName)
	item.Parent = parent
end

------------------------------------------------------------------------------------------

function EquipmentShopService.build(parent: Instance, armory: LobbyService.ArmoryLayout)
	local shop = Instance.new("Folder")
	shop.Name = "ArmoryDisplays"

	local rows: { [string]: { WeaponDefinitions.WeaponDefinition } } = { Blades = {}, Heavy = {}, Ranged = {} }
	for _, weapon in WeaponDefinitions.Ordered do
		table.insert(rows[weapon.Row], weapon)
	end
	for row, line in { Blades = armory.blades, Heavy = armory.heavy, Ranged = armory.ranged } :: { [string]: DisplayLine } do
		local weapons = rows[row]
		local spacing = if row == "Heavy" then 12 elseif row == "Ranged" then 11 else 10
		for i, slot in slots(line, #weapons, spacing) do
			buildWeaponRack(shop, slot, weapons[i])
		end
	end

	local classes: { [string]: { ShieldDefinitions.ShieldDefinition } } = { Light = {}, Balanced = {}, Heavy = {} }
	for _, shield in ShieldDefinitions.Ordered do
		table.insert(classes[ShieldDefinitions.classOf(shield)], shield)
	end
	for class, line in armory.shields :: { [string]: DisplayLine } do
		local shields = classes[class]
		for i, slot in slots(line, #shields, 7.5) do
			buildShieldDisplay(shop, slot, shields[i])
		end
	end

	for i, slot in slots(armory.armor, #ArmorDefinitions.Ordered, 9) do
		buildArmorDisplay(shop, slot, ArmorDefinitions.Ordered[i])
	end

	shop.Parent = parent
	print(PREFIX, ("Gladiator Armory: %d weapons, %d shields, %d armor sets on display"):format(#WeaponDefinitions.Ordered, #ShieldDefinitions.Ordered, #ArmorDefinitions.Ordered))
end

return EquipmentShopService
