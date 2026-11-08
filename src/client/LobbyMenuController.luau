--!strict
-- The CENTRAL LOBBY MENU (Hub): one compact, clearly visible access button (top left, "MENÜ"; also
-- the M key, gamepad Y, or the level capsule) opens one big menu (MenuSystem) with six tabs:
--   ÜBERSICHT      player name, ONE character preview, "Level 24 / 150", title, total Aura, Denarii,
--                  progress bar, Aura reached / needed in the level, exact Aura remaining, next title /
--                  rank, Aura + Denarii of this session, rewards of the last battle, total earned
--                  (own persistent counters - "since tracking began" for older profiles) and an
--                  optional play-time ESTIMATE that only appears with enough real active play data.
--   AUSRÜSTUNG     only OWNED weapons / shields / armor (buying stays in the Gladiator Armory):
--                  tile with a small static item preview (a clone of the armory display, no
--                  character per tile), name, AUSGERÜSTET tag; the selected item shows description,
--                  real values, a comparison with the equipped item and AUSRÜSTEN. The change is shown
--                  only after the server confirmed it (LoadoutRequest -> LoadoutRequestService).
--   LAUFBAHN       rank groups, current rank, milestones with the real gear unlocks, all 150 levels.
--   SPIELMODI      opens the existing mode menu (zombies, team battles, the three boss test fights)
--                  and LIVE IN THE COLOSSEUM - the same controllers as before, no second mode menu.
--   EINSTELLUNGEN  camera shake and HUD mode (the existing saved preferences).
--   STEUERUNG      the controls of every input device.
-- Presentation only: every value comes from server-owned player attributes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmorDefinitions = require(Shared:WaitForChild("ArmorDefinitions"))
local Config = require(Shared:WaitForChild("Config"))
local GameStates = require(Shared:WaitForChild("GameStates"))
local GladiatorLevelDefinitions = require(Shared:WaitForChild("GladiatorLevelDefinitions"))
local ShieldDefinitions = require(Shared:WaitForChild("ShieldDefinitions"))
local WeaponDefinitions = require(Shared:WaitForChild("WeaponDefinitions"))
local ItemInfo = require(script.Parent:WaitForChild("ItemInfo"))
local MenuSystem = require(script.Parent:WaitForChild("MenuSystem"))

local THEME = MenuSystem.Theme
local make = MenuSystem.make

export type Deps = {
	gui: ScreenGui,
	loadoutRemote: RemoteFunction?,
	notify: (text: string) -> (),
	openModes: (tab: string?) -> (),
	openLive: () -> (),
	getCameraShake: () -> string,
	setCameraShake: (value: string) -> (),
	getHudMode: () -> string,
	setHudMode: (value: string) -> (),
	controlLines: () -> { string },
}

export type LobbyMenu = {
	open: (tab: string?) -> (),
	close: () -> (),
	isOpen: () -> boolean,
	accessButton: TextButton,
}

type Kind = "Weapon" | "Shield" | "Armor"

local LobbyMenuController = {}
LobbyMenuController.active = nil :: LobbyMenu?

local KIND_TABS: { { kind: Kind, label: string } } = {
	{ kind = "Weapon", label = "WAFFEN" },
	{ kind = "Shield", label = "SCHILDE" },
	{ kind = "Armor", label = "RÜSTUNGEN" },
}
local KIND_WORD: { [string]: string } = { Weapon = "Waffe", Shield = "Schild", Armor = "Rüstung" }
local MODE_NAMES: { [string]: string } = {
	Solo = "Solo-Arena",
	Coop = "Co-op-Legionen",
	TIME_BATTLE = "Zeitschlacht",
	FIRST_TO = "Erster bis 20",
	ELIMINATION = "Eliminierung",
	BOSS_OTTI = "Bosskampf Otti",
	BOSS_KROKO = "Bosskampf Kroko",
	BOSS_SCHILI = "Bosskampf Schili",
}

-- 12345 -> "12.345" (German thousands separator)
local function fmt(n: number): string
	local whole = tostring(math.floor(math.max(0, n)))
	local reversed = whole:reverse():gsub("(%d%d%d)", "%1.")
	local out = (reversed :: string):reverse()
	if out:sub(1, 1) == "." then
		out = out:sub(2)
	end
	return out
end
LobbyMenuController.format = fmt

local function splitSet(value: unknown): { [string]: boolean }
	local set = {}
	if typeof(value) == "string" then
		for id in value:gmatch("[^,]+") do
			set[id] = true
		end
	end
	return set
end

local function definitionsOf(kind: Kind): { any }
	return if kind == "Weapon" then WeaponDefinitions.Ordered :: any elseif kind == "Shield" then ShieldDefinitions.Ordered :: any else ArmorDefinitions.Ordered :: any
end

local function attrNames(kind: Kind): (string, string)
	if kind == "Weapon" then
		return Config.OwnedWeaponsAttribute, Config.EquippedWeaponAttribute
	elseif kind == "Shield" then
		return Config.OwnedShieldsAttribute, Config.EquippedShieldAttribute
	end
	return Config.OwnedArmorAttribute, Config.EquippedArmorAttribute
end

-- An honest play-time text: only with enough real active play data, rounded, marked as an estimate.
function LobbyMenuController.estimateText(remaining: number, auraPerHour: number): string
	if auraPerHour <= 0 then
		return "Für eine Zeitschätzung gibt es noch nicht genug Kampfdaten."
	end
	local minutes = remaining / auraPerHour * 60
	if minutes < 10 then
		return "Schätzung: weniger als 10 Minuten aktive Kampfzeit"
	elseif minutes < 90 then
		return ("Schätzung: etwa %d Minuten aktive Kampfzeit"):format(math.max(10, math.floor(minutes / 5 + 0.5) * 5))
	end
	local hours = minutes / 60
	local text = if hours < 10 then (("%.1f"):format(hours):gsub("%.", ",")) else tostring(math.floor(hours + 0.5))
	return ("Schätzung: etwa %s Stunden aktive Kampfzeit"):format(text)
end

------------------------------------------------------------------------------------------
-- Previews (one character preview; static item previews from the armory displays)
------------------------------------------------------------------------------------------

local function viewport(parent: Instance, size: UDim2, order: number?): (ViewportFrame, Camera)
	local frame = make("ViewportFrame", {
		Size = size,
		BackgroundColor3 = THEME.Surface,
		Ambient = Color3.fromRGB(170, 160, 150),
		LightColor = Color3.fromRGB(255, 244, 228),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
		LayoutOrder = order or 0,
	}, parent)
	MenuSystem.corner(frame, 8)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = frame
	frame.CurrentCamera = camera
	return frame, camera
end

local function stripClone(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("BillboardGui") or d:IsA("ProximityPrompt") or d:IsA("Highlight") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

-- Points `camera` at `model` from `direction` (unit, from the model toward the camera).
local function frameModel(camera: Camera, model: Model, direction: Vector3, fill: number)
	local box, size = model:GetBoundingBox()
	local extent = math.max(size.X, size.Y, size.Z)
	local distance = (extent / 2) / math.tan(math.rad(camera.FieldOfView / 2)) * fill
	camera.CFrame = CFrame.lookAt(box.Position + direction.Unit * distance, box.Position)
end

export type CharacterPreview = { frame: ViewportFrame, refresh: () -> () }

local function characterPreview(): CharacterPreview
	local player = Players.LocalPlayer
	local frame, camera = viewport(nil :: any, UDim2.fromOffset(150, 200))
	frame.Name = "CharacterPreview"
	local world = Instance.new("WorldModel")
	world.Parent = frame
	local token = 0
	local function refresh()
		token += 1
		local myToken = token
		task.delay(0.35, function() -- let server-built gear models replicate first
			if myToken ~= token then
				return
			end
			world:ClearAllChildren()
			local character = player.Character
			if not character then
				return
			end
			local archivable = character.Archivable
			character.Archivable = true
			local ok, clone = pcall(function()
				return character:Clone()
			end)
			character.Archivable = archivable
			if not ok or not clone then
				return
			end
			local model = clone :: Model
			stripClone(model)
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
			model:PivotTo(CFrame.new())
			model.Parent = world
			-- the character looks along -Z: camera in front, slightly from the side and above
			frameModel(camera, model, Vector3.new(0.35, 0.18, -1), 1.15)
		end)
	end
	return { frame = frame, refresh = refresh }
end

local function armoryItem(kind: Kind, id: string): Model?
	for _, item in CollectionService:GetTagged(Config.ShopItemTag) do
		if item:IsA("Model") and item:GetAttribute("ItemKind") == kind and item:GetAttribute("ItemId") == id then
			return item
		end
	end
	return nil
end

-- A small static preview of one item (the armory display's model; no per-frame updates).
local function itemPreview(parent: Instance, kind: Kind, id: string, size: UDim2, order: number?): ViewportFrame
	local frame, camera = viewport(parent, size, order)
	local source = armoryItem(kind, id)
	local display = source and source:FindFirstChild("Display")
	if source and display then
		local model = Instance.new("Model")
		local copy = display:Clone()
		copy.Parent = model
		if kind == "Armor" then
			local mannequin = source:FindFirstChild("Mannequin")
			if mannequin then
				mannequin:Clone().Parent = model
			end
		end
		stripClone(model)
		model.Parent = frame
		local base = source:FindFirstChild("Plinth") or source:FindFirstChild("Stand")
		local look = if base and base:IsA("BasePart") then base.CFrame.LookVector else Vector3.new(0, 0, -1)
		frameModel(camera, model, look + Vector3.new(0, 0.25, 0), if kind == "Armor" then 1.05 else 1.2)
	else
		-- no armory nearby (e.g. not streamed): a clear text symbol instead of an empty box
		make("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = THEME.TitleFont,
			TextScaled = true,
			TextColor3 = THEME.Bronze,
			Text = if kind == "Weapon" then "⚔" elseif kind == "Shield" then "🛡" else "⛨",
		}, frame)
	end
	return frame
end

------------------------------------------------------------------------------------------

function LobbyMenuController.start(deps: Deps): LobbyMenu
	local player = Players.LocalPlayer

	------------------------------------------------------------------ access button
	local accessGui = make("ScreenGui", { Name = "LobbyMenuAccess", ResetOnSpawn = false, DisplayOrder = 15, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, nil)
	pcall(function()
		accessGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	local access = make("TextButton", {
		Name = "MenuButton",
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.fromOffset(112, THEME.TouchTarget),
		BackgroundColor3 = THEME.Panel,
		BackgroundTransparency = 0.05,
		Font = THEME.TitleFont,
		TextSize = 15,
		TextColor3 = THEME.Gold,
		Text = "MENÜ",
	}, accessGui)
	MenuSystem.corner(access, 10)
	MenuSystem.stroke(access, THEME.Bronze, 0.1, 2)
	accessGui.Parent = player:WaitForChild("PlayerGui")
	-- narrow phones: a compact button, so it never touches the level capsule (top right).
	-- Plain text only: icon glyphs like ☰ have no font fallback on Roblox and show as a box.
	local function fitAccess()
		local camera = workspace.CurrentCamera
		local narrow = camera ~= nil and camera.ViewportSize.X < 460
		access.Size = UDim2.fromOffset(if narrow then 64 else 112, THEME.TouchTarget)
		access.TextSize = if narrow then 13 else 15
	end
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitAccess)
	end
	fitAccess()

	local window = MenuSystem.window(deps.gui, { name = "LobbyMenu", title = "GLADIATORENSCHULE" })
	local pages: { [string]: Frame } = {
		Overview = window.addTab("Overview", "ÜBERSICHT"),
		Gear = window.addTab("Gear", "AUSRÜSTUNG", false),
		Career = window.addTab("Career", "LAUFBAHN"),
		Modes = window.addTab("Modes", "SPIELMODI"),
		Settings = window.addTab("Settings", "EINSTELLUNGEN"),
		Controls = window.addTab("Controls", "STEUERUNG"),
	}
	local preview = characterPreview()

	local function aura(): number
		return tonumber(player:GetAttribute(Config.AuraAttribute)) or 0
	end
	local function denarii(): number
		return tonumber(player:GetAttribute(Config.DenariiAttribute)) or 0
	end

	-- Why the gear can't change right now (mirrors LoadoutRequestService; the server decides).
	local function lockText(): string?
		local status = player:GetAttribute(Config.DataStatusAttribute)
		if status == "Loading" then
			return "Deine Ausrüstung wird noch geladen …"
		elseif status == "Transferring" then
			return "Reise in die Arena · kein Wechsel möglich"
		end
		local state = player:GetAttribute(GameStates.StateAttribute)
		local location = player:GetAttribute(GameStates.LocationAttribute)
		if not GameStates.canChangeEquipment(state) or (location ~= nil and location ~= "Lobby") then
			return "Gesperrt während eines Kampfes"
		end
		if player:GetAttribute(Config.MatchTransitionAttribute) == true then
			return "Der Kampf wird vorbereitet · kein Wechsel möglich"
		end
		return nil
	end

	local function clear(page: Instance)
		if preview.frame:IsDescendantOf(page) then
			preview.frame.Parent = nil -- the one preview is reused, never destroyed
		end
		for _, child in page:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	------------------------------------------------------------------ ÜBERSICHT
	local function renderOverview()
		local page = pages.Overview
		clear(page)
		local progress = GladiatorLevelDefinitions.progressFor(aura())
		local level = progress.level
		local group = GladiatorLevelDefinitions.groupOf(level.Level)
		local narrow = page.AbsoluteSize.X < 430

		local top = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = THEME.Surface, LayoutOrder = 1 }, page)
		MenuSystem.corner(top, 10)
		MenuSystem.padding(top, 10)
		local info: Frame
		if narrow then
			MenuSystem.list(top, 8)
			preview.frame.Size = UDim2.new(1, 0, 0, 170)
			preview.frame.LayoutOrder = 1
			preview.frame.Parent = top
			info = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, top)
		else
			preview.frame.Size = UDim2.fromOffset(150, 200)
			preview.frame.Position = UDim2.fromOffset(0, 0)
			preview.frame.Parent = top
			info = make("Frame", { Position = UDim2.fromOffset(162, 0), Size = UDim2.new(1, -162, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, top)
			make("UISizeConstraint", { MinSize = Vector2.new(0, 200) }, info)
		end
		MenuSystem.list(info, 4)
		preview.refresh()

		MenuSystem.label(info, ("%s  <font color=\"#C6BAA8\">@%s</font>"):format(player.DisplayName, player.Name), 15, THEME.LabelFont, THEME.Text, 1)
		MenuSystem.label(info, ("LEVEL %d / %d"):format(level.Level, GladiatorLevelDefinitions.MaxLevel), 13, THEME.LabelFont, THEME.TextMuted, 2)
		MenuSystem.label(info, level.Title, 24, THEME.TitleFont, THEME.Gold, 3)
		if group then
			MenuSystem.label(info, group.Description, 13, THEME.BodyFont, THEME.TextMuted, 4)
		end
		local bar = MenuSystem.progressBar(info, 5, 16)
		bar.set(progress.share)
		if progress.isMax then
			MenuSystem.label(info, "<b>Höchster Rang erreicht.</b> Aura und Denarii verdienst du weiterhin.", 14, THEME.BodyFont, THEME.Text, 6)
		else
			local nextLevel = progress.nextLevel :: any
			MenuSystem.label(info, ("%s / %s Aura in diesem Level"):format(fmt(progress.inLevel), fmt(progress.needed)), 13, THEME.BodyFont, THEME.TextMuted, 6)
			MenuSystem.label(info, ("<b>Noch %s Aura</b> bis Level %d · %s"):format(fmt(progress.remaining), nextLevel.Level, nextLevel.Title), 15, THEME.BodyFont, THEME.Text, 7)
			local nextRank = progress.nextRank
			if nextRank and nextRank.Level ~= nextLevel.Level then
				MenuSystem.label(info, ("Nächster Rangaufstieg: %s ab Level %d (noch %s Aura)"):format(nextRank.Title, nextRank.Level, fmt(nextRank.Aura - aura())), 13, THEME.BodyFont, THEME.TextMuted, 8)
			elseif nextRank then
				MenuSystem.label(info, "Mit dem nächsten Level steigst du in einen neuen Rang auf!", 13, THEME.BodyFont, THEME.Gold, 8)
			end
		end

		local balance = MenuSystem.card(page, 2)
		MenuSystem.heading(balance, "KONTOSTAND", 1)
		MenuSystem.label(balance, ("Gesamte Aura: <b>%s</b>  ·  Denarii: <b>%s</b>"):format(fmt(aura()), fmt(denarii())), 15, THEME.BodyFont, THEME.Text, 2)
		MenuSystem.label(balance, "Aura wird nie ausgegeben und bestimmt dein Level. Denarii kaufen Ausrüstung in der Waffenkammer.", 12, THEME.BodyFont, THEME.TextMuted, 3)

		local earned = MenuSystem.card(page, 3)
		MenuSystem.heading(earned, "VERDIENST", 1)
		MenuSystem.label(earned, ("Diese Sitzung: <b>+%s Aura</b> · <b>+%s Denarii</b>"):format(fmt(tonumber(player:GetAttribute(Config.SessionAuraAttribute)) or 0), fmt(tonumber(player:GetAttribute(Config.SessionDenariiAttribute)) or 0)), 14, THEME.BodyFont, THEME.Text, 2)
		local lastAura = player:GetAttribute(Config.LastBattleAuraAttribute)
		if typeof(lastAura) == "number" then
			local mode = tostring(player:GetAttribute(Config.LastBattleModeAttribute) or "")
			MenuSystem.label(earned, ("Letzter Kampf (%s): <b>+%s Aura</b> · <b>+%s Denarii</b>"):format(MODE_NAMES[mode] or "Kampf", fmt(lastAura), fmt(tonumber(player:GetAttribute(Config.LastBattleDenariiAttribute)) or 0)), 14, THEME.BodyFont, THEME.Text, 3)
		else
			MenuSystem.label(earned, "Letzter Kampf: noch keine Belohnungen erfasst", 14, THEME.BodyFont, THEME.TextMuted, 3)
		end
		local totalAura = fmt(tonumber(player:GetAttribute(Config.EarnedAuraAttribute)) or 0)
		local totalDenarii = fmt(tonumber(player:GetAttribute(Config.EarnedDenariiAttribute)) or 0)
		if player:GetAttribute(Config.EarnedCompleteAttribute) == true then
			MenuSystem.label(earned, ("Insgesamt verdient: <b>%s Aura</b> · <b>%s Denarii</b>"):format(totalAura, totalDenarii), 14, THEME.BodyFont, THEME.Text, 4)
		else
			local since = tonumber(player:GetAttribute(Config.EarnedSinceAttribute))
			local date = if since then os.date("%d.%m.%Y", since) else "?"
			MenuSystem.label(earned, ("Seit Beginn der Erfassung (%s): <b>%s Aura</b> · <b>%s Denarii</b>"):format(tostring(date), totalAura, totalDenarii), 14, THEME.BodyFont, THEME.Text, 4)
			MenuSystem.label(earned, "Ältere Verdienste wurden vorher nicht gezählt und werden nicht geschätzt.", 12, THEME.BodyFont, THEME.TextMuted, 5)
		end

		local time = MenuSystem.card(page, 4)
		MenuSystem.heading(time, "BIS ZUM NÄCHSTEN LEVEL", 1)
		if progress.isMax then
			MenuSystem.label(time, "Level 150 · CÄSAR. Es gibt kein weiteres Level.", 14, THEME.BodyFont, THEME.Text, 2)
		else
			MenuSystem.label(time, ("<b>Noch %s Aura</b>"):format(fmt(progress.remaining)), 16, THEME.BodyFont, THEME.Text, 2)
			MenuSystem.label(time, LobbyMenuController.estimateText(progress.remaining, tonumber(player:GetAttribute(Config.AuraPerHourAttribute)) or 0), 12, THEME.BodyFont, THEME.TextMuted, 3)
		end
	end

	------------------------------------------------------------------ AUSRÜSTUNG
	local gearKind: Kind = "Weapon"
	local selectedId: { [string]: string } = {}
	local pending: { kind: Kind, id: string }? = nil
	local confirmed: { [string]: string } = {} -- server-confirmed equips until the attribute arrives

	local function equippedId(kind: Kind): string
		local _, equippedAttr = attrNames(kind)
		local attr = tostring(player:GetAttribute(equippedAttr) or "")
		local fresh = confirmed[kind]
		if fresh and fresh ~= attr then
			return fresh
		end
		confirmed[kind] = nil
		if attr ~= "" then
			return attr
		end
		return if kind == "Weapon" then WeaponDefinitions.Starter elseif kind == "Shield" then ShieldDefinitions.Starter else ArmorDefinitions.Starter
	end

	local function ownedList(kind: Kind): ({ any }, number)
		local ownedAttr = attrNames(kind)
		local owned = splitSet(player:GetAttribute(ownedAttr))
		local starter = if kind == "Weapon" then WeaponDefinitions.Starter elseif kind == "Shield" then ShieldDefinitions.Starter else ArmorDefinitions.Starter
		owned[starter] = true -- the starter can never be lost
		local list = {}
		local all = definitionsOf(kind)
		for _, def in all do
			if owned[def.Id] then
				table.insert(list, def)
			end
		end
		return list, #all
	end

	local renderGear: () -> ()

	local function equip(kind: Kind, id: string)
		local remote = deps.loadoutRemote
		if pending or not remote then
			return
		end
		pending = { kind = kind, id = id }
		renderGear()
		task.spawn(function()
			local ok, response = pcall(function()
				return remote:InvokeServer("Equip", kind, id)
			end)
			pending = nil
			local card = ItemInfo.describe(kind, id)
			local name = if card then card.title else id
			if ok and typeof(response) == "table" and response.ok == true then
				confirmed[kind] = id
				deps.notify(if response.code == "ALREADY" then ("%s ist bereits ausgerüstet"):format(name) else ("%s ausgerüstet"):format(name))
			elseif ok and typeof(response) == "table" then
				deps.notify(tostring(response.message or "Wechsel nicht möglich"))
			else
				deps.notify("Keine Antwort vom Server · bitte erneut versuchen")
			end
			if window.isOpen() and window.selected() == "Gear" then
				renderGear()
			end
		end)
	end

	renderGear = function()
		local page = pages.Gear
		clear(page)
		local width = page.AbsoluteSize.X
		local stacked = width < 560

		-- category row
		local row = make("Frame", { Size = UDim2.new(1, 0, 0, THEME.TouchTarget), BackgroundTransparency = 1 }, page)
		MenuSystem.list(row, 6, true)
		for i, entry in KIND_TABS do
			local b = MenuSystem.button(row, entry.label, "Tab", i)
			b.Size = UDim2.new(1 / #KIND_TABS, -4, 1, 0)
			MenuSystem.setState(b, if entry.kind == gearKind then "Selected" else "Normal")
			b.Activated:Connect(function()
				gearKind = entry.kind
				renderGear()
			end)
		end

		local body = make("Frame", { Position = UDim2.fromOffset(0, THEME.TouchTarget + 8), Size = UDim2.new(1, 0, 1, -(THEME.TouchTarget + 8)), BackgroundTransparency = 1 }, page)
		local list, total = ownedList(gearKind)
		local equipped = equippedId(gearKind)
		local selected = selectedId[gearKind]
		local valid = false
		for _, def in list do
			if def.Id == selected then
				valid = true
			end
		end
		if not valid then
			selected = equipped
			selectedId[gearKind] = equipped
		end

		local gridHolder = make("ScrollingFrame", {
			Size = if stacked then UDim2.new(1, 0, 0.42, 0) else UDim2.new(0.5, -6, 1, 0),
			BackgroundTransparency = 1,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = THEME.Bronze,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Selectable = false,
		}, body)
		local cell = if stacked then 104 else 112
		make("UIGridLayout", { CellSize = UDim2.fromOffset(cell, cell + 22), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, gridHolder)
		make("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2) }, gridHolder)
		local firstTile: GuiObject? = nil
		for i, def in list do
			local tile = make("TextButton", { BackgroundColor3 = THEME.Surface, Text = "", AutoButtonColor = true, LayoutOrder = i }, gridHolder)
			tile:SetAttribute("MenuStyle", "Ghost")
			MenuSystem.corner(tile, 8)
			MenuSystem.setState(tile, if def.Id == selected then "Selected" else "Normal")
			tile.Active = true
			itemPreview(tile, gearKind, def.Id, UDim2.new(1, -8, 0, cell - 40), 0).Position = UDim2.fromOffset(4, 4)
			make("TextLabel", {
				Position = UDim2.new(0, 4, 0, cell - 34),
				Size = UDim2.new(1, -8, 0, 32),
				BackgroundTransparency = 1,
				Font = THEME.LabelFont,
				TextSize = 12,
				TextWrapped = true,
				TextColor3 = THEME.Text,
				Text = def.DisplayName,
			}, tile)
			if def.Id == equipped then
				local tag = make("TextLabel", {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -3),
					Size = UDim2.new(1, -10, 0, 18),
					BackgroundColor3 = THEME.Equipped,
					Font = THEME.TitleFont,
					TextSize = 10,
					TextColor3 = THEME.Text,
					Text = "AUSGERÜSTET",
				}, tile)
				MenuSystem.corner(tag, 9)
			end
			tile.Activated:Connect(function()
				selectedId[gearKind] = def.Id
				renderGear()
			end)
			if def.Id == selected then
				firstTile = tile
			end
		end
		local hint = make("TextLabel", {
			BackgroundTransparency = 1,
			Font = THEME.BodyFont,
			TextSize = 12,
			TextWrapped = true,
			TextColor3 = THEME.TextMuted,
			Text = ("%d von %d im Besitz · weitere in der Gladiatorenwaffenkammer"):format(#list, total),
			LayoutOrder = #list + 1,
		}, gridHolder)
		hint.Size = UDim2.fromOffset(cell, cell)

		-- detail column
		local detail = make("ScrollingFrame", {
			Position = if stacked then UDim2.new(0, 0, 0.42, 8) else UDim2.new(0.5, 6, 0, 0),
			Size = if stacked then UDim2.new(1, 0, 0.58, -8) else UDim2.new(0.5, -6, 1, 0),
			BackgroundColor3 = THEME.Surface,
			BackgroundTransparency = 0.3,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = THEME.Bronze,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Selectable = false,
		}, body)
		MenuSystem.corner(detail, 8)
		MenuSystem.padding(detail, 10)
		MenuSystem.list(detail, 6)

		local card = ItemInfo.describe(gearKind, selected)
		if not card then
			MenuSystem.label(detail, "Kein Gegenstand ausgewählt.", 14, nil, THEME.TextMuted, 1)
			return
		end
		local isEquipped = selected == equipped
		local isPending = pending ~= nil and pending.kind == gearKind and pending.id == selected
		local lock = lockText()

		-- the action first: always visible without scrolling
		local action = MenuSystem.button(detail, "", "Primary", 1)
		if isEquipped then
			action.Text = "✓  AUSGERÜSTET"
			MenuSystem.setState(action, "Equipped")
		elseif isPending then
			action.Text = "WIRD AUSGERÜSTET …"
			MenuSystem.setState(action, "Pending")
		elseif lock then
			action.Text = "🔒  " .. lock
			MenuSystem.setState(action, "Locked")
		elseif pending then
			action.Text = "AUSRÜSTEN"
			MenuSystem.setState(action, "Unavailable")
		else
			action.Text = "AUSRÜSTEN"
			MenuSystem.setState(action, "Normal")
			action.Activated:Connect(function()
				equip(gearKind, selected)
			end)
		end

		MenuSystem.label(detail, card.section, 11, THEME.LabelFont, THEME.Bronze, 2)
		MenuSystem.label(detail, card.title, 20, THEME.TitleFont, THEME.Gold, 3)
		MenuSystem.label(detail, card.description, 13, THEME.BodyFont, THEME.TextMuted, 4)
		local hand = ItemInfo.handRule(gearKind, selected, equippedId("Weapon"))
		if hand then
			MenuSystem.label(detail, "✋ " .. hand, 12, THEME.BodyFont, THEME.Gold, 5)
		end

		local values = MenuSystem.card(detail, 6)
		MenuSystem.label(values, "WERTE", 12, THEME.TitleFont, THEME.Bronze, 0)
		for i, v in card.values do
			MenuSystem.label(values, ("%s: <b>%s</b>"):format(v.label, v.text), 13, THEME.BodyFont, THEME.Text, i)
		end
		for i, note in card.notes do
			MenuSystem.label(values, note, 12, THEME.BodyFont, THEME.TextMuted, 10 + i)
		end

		if not isEquipped then
			local equippedCard = ItemInfo.describe(gearKind, equipped)
			local compare = MenuSystem.card(detail, 7)
			MenuSystem.label(compare, ("IM VERGLEICH ZU: %s"):format(if equippedCard then equippedCard.title else "–"), 12, THEME.TitleFont, THEME.Bronze, 0)
			for i, diff in ItemInfo.compare(gearKind, selected, equipped) do
				local color = if diff.verdict > 0 then "#82DC82" elseif diff.verdict < 0 then "#F08278" else "#C6BAA8"
				MenuSystem.label(compare, ("%s: %s → <b>%s</b>  <font color=\"%s\">(%s)</font>"):format(diff.label, diff.from, diff.to, color, diff.change), 13, THEME.BodyFont, THEME.Text, i)
			end
		end

		-- the one character preview, showing the CONFIRMED loadout
		MenuSystem.label(detail, "DEIN GLADIATOR (bestätigte Ausrüstung)", 11, THEME.LabelFont, THEME.Bronze, 8)
		preview.frame.Size = UDim2.new(1, 0, 0, 180)
		preview.frame.LayoutOrder = 9
		preview.frame.Parent = detail
		preview.refresh()

		if firstTile then
			MenuSystem.focus(firstTile)
		end
	end

	------------------------------------------------------------------ LAUFBAHN
	local function renderCareer()
		local page = pages.Career
		clear(page)
		local current = GladiatorLevelDefinitions.levelFor(aura())
		local progress = GladiatorLevelDefinitions.progressFor(aura())

		local summary = MenuSystem.card(page, 1)
		MenuSystem.heading(summary, "DEINE GLADIATORENLAUFBAHN", 1)
		MenuSystem.label(summary, ("Aktueller Rang: <b>%s</b> · Level %d / %d"):format(current.Title, current.Level, GladiatorLevelDefinitions.MaxLevel), 14, THEME.BodyFont, THEME.Text, 2)
		if progress.nextRank then
			local nextRank = progress.nextRank :: any
			MenuSystem.label(summary, ("Nächster Rang: %s ab Level %d (%s Aura gesamt)"):format(nextRank.Title, nextRank.Level, fmt(nextRank.Aura)), 13, THEME.BodyFont, THEME.TextMuted, 3)
		else
			MenuSystem.label(summary, if progress.isMax then "Höchster Rang erreicht: CÄSAR." else "Letzte Ranggruppe vor CÄSAR.", 13, THEME.BodyFont, THEME.Gold, 3)
		end

		-- rank groups
		local groups = MenuSystem.card(page, 2)
		MenuSystem.heading(groups, "RANGGRUPPEN", 1)
		for i, group in GladiatorLevelDefinitions.Groups do
			local reached = current.Level >= group.First
			local active = current.Level >= group.First and current.Level <= group.Last
			local mark = if active then "▶" elseif reached then "✓" else "·"
			local color = if active then THEME.Gold elseif reached then THEME.Text else THEME.TextMuted
			local range = if group.First == group.Last then ("Level %d"):format(group.First) else ("Level %d–%d"):format(group.First, group.Last)
			MenuSystem.label(groups, ("%s  <b>%s</b>  ·  %s  ·  %s"):format(mark, group.Name, range, group.Description), 13, THEME.BodyFont, color, 1 + i)
		end

		-- milestones: the real gear unlocks
		local unlocks: { [number]: { string } } = {}
		local sources: { { kind: string, defs: { any } } } = {
			{ kind = "Weapon", defs = WeaponDefinitions.Ordered :: any },
			{ kind = "Shield", defs = ShieldDefinitions.Ordered :: any },
			{ kind = "Armor", defs = ArmorDefinitions.Ordered :: any },
		}
		for _, entry in sources do
			for _, def in entry.defs do
				if def.LevelRequired > 1 then
					unlocks[def.LevelRequired] = unlocks[def.LevelRequired] or {}
					table.insert(unlocks[def.LevelRequired], ("%s (%s)"):format(def.DisplayName, KIND_WORD[entry.kind]))
				end
			end
		end
		local milestones = MenuSystem.card(page, 3)
		MenuSystem.heading(milestones, "MEILENSTEINE & FREISCHALTUNGEN", 1)
		MenuSystem.label(milestones, "Freigeschaltete Ausrüstung kannst du in der Waffenkammer kaufen; gekaufte Ausrüstung bleibt immer nutzbar.", 12, THEME.BodyFont, THEME.TextMuted, 2)
		local levelsWithUnlocks = {}
		for levelNumber in unlocks do
			table.insert(levelsWithUnlocks, levelNumber)
		end
		table.sort(levelsWithUnlocks)
		for i, levelNumber in levelsWithUnlocks do
			local reached = current.Level >= levelNumber
			local def = GladiatorLevelDefinitions.get(levelNumber) :: any
			MenuSystem.label(milestones, ("%s  Level %d %s: %s"):format(if reached then "✓" else "🔒", levelNumber, def.Title, table.concat(unlocks[levelNumber], ", ")), 13, THEME.BodyFont, if reached then THEME.Text else THEME.TextMuted, 2 + i)
		end

		-- all 150 levels
		local all = MenuSystem.card(page, 4)
		MenuSystem.heading(all, "ALLE 150 LEVEL", 1)
		for _, def in GladiatorLevelDefinitions.Levels do
			local isCurrent = def.Level == current.Level
			local reached = def.Level <= current.Level
			local rowFrame = make("Frame", {
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundColor3 = if isCurrent then THEME.Primary else THEME.Panel,
				BackgroundTransparency = if isCurrent then 0 elseif def.Level % 2 == 0 then 0.6 else 1,
				LayoutOrder = 1 + def.Level,
			}, all)
			MenuSystem.corner(rowFrame, 4)
			local color = if isCurrent then THEME.Gold elseif reached then THEME.Text else THEME.TextMuted
			make("TextLabel", { Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0, 44, 1, 0), BackgroundTransparency = 1, Font = THEME.LabelFont, TextSize = 12, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(def.Level) }, rowFrame)
			make("TextLabel", { Position = UDim2.fromOffset(50, 0), Size = UDim2.new(1, -150, 1, 0), BackgroundTransparency = 1, Font = if def.SubRank <= 1 then THEME.LabelFont else THEME.BodyFont, TextSize = 12, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextWrapped = true, Text = def.Title }, rowFrame)
			make("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Size = UDim2.new(0, 96, 1, 0), BackgroundTransparency = 1, Font = THEME.BodyFont, TextSize = 12, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Right, Text = fmt(def.Aura) .. " Aura" }, rowFrame)
		end
	end

	------------------------------------------------------------------ SPIELMODI
	local function renderModes()
		local page = pages.Modes
		clear(page)
		local entries = {
			{ title = "ZOMBIE-KÄMPFE", text = "Sechs Runden, dann der Bosskampf in Runde 7 · Solo, Co-op mit deiner Gruppe oder Mitspielersuche", action = function() deps.openModes("ZOMBIES") end },
			{ title = "TEAMKÄMPFE", text = "Zeitschlacht, Erster bis 20 und Eliminierung · 1 gegen 1 bis 4 gegen 4", action = function() deps.openModes("TEAMS") end },
			{ title = "BOSS-TESTKÄMPFE", text = "Solo gegen Otti, Kroko oder Schili", action = function() deps.openModes("BOSS") end },
			{ title = "LIVE ZUSCHAUEN", text = "Laufende Kämpfe im Kolosseum von der Tribüne aus ansehen", action = deps.openLive },
		}
		for i, entry in entries do
			local card = MenuSystem.card(page, i)
			MenuSystem.heading(card, entry.title, 1)
			MenuSystem.label(card, entry.text, 13, THEME.BodyFont, THEME.TextMuted, 2)
			local b = MenuSystem.button(card, "ÖFFNEN", "Primary", 3)
			b.Activated:Connect(entry.action)
		end
	end

	------------------------------------------------------------------ EINSTELLUNGEN
	local renderSettings: () -> ()
	local function segmented(parent: Instance, order: number, options: { { string } }, current: string, onPick: (string) -> ())
		local row = make("Frame", { Size = UDim2.new(1, 0, 0, THEME.TouchTarget), BackgroundTransparency = 1, LayoutOrder = order }, parent)
		MenuSystem.list(row, 6, true)
		for i, option in options do
			local b = MenuSystem.button(row, option[2], "Tab", i)
			b.Size = UDim2.new(1 / #options, -4, 1, 0)
			MenuSystem.setState(b, if option[1] == current then "Selected" else "Normal")
			b.Activated:Connect(function()
				onPick(option[1])
				renderSettings()
			end)
		end
	end
	renderSettings = function()
		local page = pages.Settings
		clear(page)
		local camera = MenuSystem.card(page, 1)
		MenuSystem.heading(camera, "KAMERA-ERSCHÜTTERUNG", 1)
		MenuSystem.label(camera, "Wie stark die Kamera bei Treffern und Landungen wackelt.", 12, THEME.BodyFont, THEME.TextMuted, 2)
		segmented(camera, 3, { { "Full", "VOLL" }, { "Reduced", "REDUZIERT" }, { "Off", "AUS" } }, deps.getCameraShake(), deps.setCameraShake)
		local hud = MenuSystem.card(page, 2)
		MenuSystem.heading(hud, "ANZEIGE (HUD)", 1)
		MenuSystem.label(hud, "Voll, minimal oder versteckt · auch über das Auge am rechten Rand oder die Taste H.", 12, THEME.BodyFont, THEME.TextMuted, 2)
		segmented(hud, 3, { { "Full", "VOLL" }, { "Minimal", "MINIMAL" }, { "Hidden", "VERSTECKT" } }, deps.getHudMode(), deps.setHudMode)
		MenuSystem.label(page, "Einstellungen werden mit deinem Profil gespeichert.", 12, THEME.BodyFont, THEME.TextMuted, 3)
	end

	------------------------------------------------------------------ STEUERUNG
	local function renderControls()
		local page = pages.Controls
		clear(page)
		local card = MenuSystem.card(page, 1)
		MenuSystem.heading(card, "STEUERUNG", 1)
		for i, line in deps.controlLines() do
			MenuSystem.label(card, line, 13, THEME.BodyFont, THEME.Text, 1 + i)
		end
	end

	------------------------------------------------------------------ wiring
	local renderers: { [string]: () -> () } = {
		Overview = renderOverview,
		Gear = renderGear,
		Career = renderCareer,
		Modes = renderModes,
		Settings = renderSettings,
		Controls = renderControls,
	}
	local function renderCurrent()
		local id = window.selected()
		local render = id and renderers[id]
		if window.isOpen() and render then
			render()
		end
	end
	window.onSelect(function(id: string)
		local render = renderers[id]
		if render then
			render()
		end
	end)
	for _, page in pages do
		page:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if page.Visible then
				renderCurrent() -- narrow / wide layout follows the real size
			end
		end)
	end

	local refreshQueued = false
	local function queueRefresh()
		if refreshQueued then
			return
		end
		refreshQueued = true
		task.delay(0.15, function()
			refreshQueued = false
			renderCurrent()
		end)
	end
	for _, attribute in {
		Config.AuraAttribute, Config.DenariiAttribute, Config.EquippedWeaponAttribute, Config.EquippedShieldAttribute,
		Config.EquippedArmorAttribute, Config.OwnedWeaponsAttribute, Config.OwnedShieldsAttribute, Config.OwnedArmorAttribute,
		Config.DataStatusAttribute, Config.SessionAuraAttribute, Config.EarnedAuraAttribute, Config.LastBattleAuraAttribute,
		Config.AuraPerHourAttribute, Config.MatchTransitionAttribute, GameStates.StateAttribute, GameStates.LocationAttribute,
	} do
		player:GetAttributeChangedSignal(attribute):Connect(queueRefresh)
	end
	player.CharacterAdded:Connect(function()
		if window.isOpen() then
			preview.refresh()
		end
	end)

	local function open(tab: string?)
		window.open(tab)
	end
	access.Activated:Connect(function()
		if window.isOpen() then
			window.close()
		else
			open(nil)
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.KeyCode == THEME.GamepadToggle or (not processed and input.KeyCode == THEME.ToggleKey) then
			if window.isOpen() then
				window.close()
			elseif not MenuSystem.isOpen() then
				open(nil)
			end
		end
	end)
	window.onOpenChanged(function(isOpen: boolean)
		access.Visible = not isOpen
		if not isOpen then
			preview.frame.Parent = nil -- no hidden 3D preview while the menu is closed
		end
	end)

	local menu: LobbyMenu = {
		open = open,
		close = window.close,
		isOpen = window.isOpen,
		accessButton = access,
	}
	LobbyMenuController.active = menu -- the running menu (read by the Studio menu QA script only)
	return menu
end

return LobbyMenuController
