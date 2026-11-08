--!strict
-- MENU QA (Studio only; scripts/build-menu-qa.ps1). Measures the real UI after it was built:
--   * touch rhombus: four equal buttons around one centre at distance r, no overlaps
--   * MENÜ access button vs. the level capsule (no overlap)
--   * every lobby-menu tab: clipped text, interactive elements smaller than 44 px, horizontal overflow
--   * equipping: owned item OK, not owned / unknown refused, locked during a fight, two-handed rule,
--     display only after the server answered
--   * one big menu at a time, prompts disabled while open, restored after closing
-- Every result is printed as "[MenuQA] PASS|FAIL ..." (read from the Studio log).
-- Run it once per Device emulator size (phone / tablet / desktop) by restarting Play.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local passed, failed = 0, 0
local function check(ok: boolean, message: string)
	if ok then
		passed += 1
	else
		failed += 1
	end
	print(("[MenuQA] %s %s"):format(if ok then "PASS" else "FAIL", message))
end

local camera = workspace.CurrentCamera :: Camera

repeat
	task.wait(0.25)
until player:GetAttribute("MenuQAReady") == true
task.wait(1)
print(("[MenuQA] viewport %dx%d · touch %s"):format(camera.ViewportSize.X, camera.ViewportSize.Y, tostring(game:GetService("UserInputService").TouchEnabled)))
local client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local LobbyMenuController = require(client:WaitForChild("LobbyMenuController")) :: any
local MenuSystem = require(client:WaitForChild("MenuSystem")) :: any
repeat
	task.wait(0.25)
until LobbyMenuController.active ~= nil
local menu = LobbyMenuController.active
local gui = player:WaitForChild("PlayerGui")
task.wait(2)

------------------------------------------------------------------ touch rhombus
local hud = gui:WaitForChild("OttiArenaHud")
local touch = hud:WaitForChild("TouchControls") :: Frame
local centres: { [string]: Vector2 } = {}
local size: Vector2? = nil
local equalSize = true
for _, name in { "Block", "Attack", "Jump", "Special" } do
	local b = touch:WaitForChild(name) :: GuiObject
	centres[name] = b.AbsolutePosition + b.AbsoluteSize / 2
	if size and (b.AbsoluteSize - size).Magnitude > 0.5 then
		equalSize = false
	end
	size = size or b.AbsoluteSize
end
local s = size :: Vector2
check(equalSize and math.abs(s.X - s.Y) < 0.5, ("four equal, undistorted buttons (%.1f x %.1f)"):format(s.X, s.Y))
local c = (centres.Block + centres.Attack + centres.Jump + centres.Special) / 4
local r = (centres.Attack.X - c.X)
local function near(a: Vector2, b: Vector2): boolean
	return (a - b).Magnitude < 0.75
end
check(near(centres.Block, c + Vector2.new(0, -r)), "BLOCK = C + (0, -r)")
check(near(centres.Attack, c + Vector2.new(r, 0)), "ATTACK = C + (r, 0)")
check(near(centres.Jump, c + Vector2.new(0, r)), "JUMP = C + (0, r)")
check(near(centres.Special, c + Vector2.new(-r, 0)), "SPECIAL = C + (-r, 0)")
check(r * math.sqrt(2) > s.X, ("neighbours do not overlap (r = %.1f px)"):format(r))
local right = touch.AbsolutePosition.X + touch.AbsoluteSize.X
local bottom = touch.AbsolutePosition.Y + touch.AbsoluteSize.Y
local inset = hud:IsA("ScreenGui") and hud.AbsoluteSize or camera.ViewportSize
check(right <= inset.X - 8 and bottom <= inset.Y - 8, "rhombus keeps a margin to the screen edge / safe area")
local edgeColumn = hud:FindFirstChild("EdgeButtons")
if edgeColumn then
	local hits = {}
	for _, name in { "Block", "Attack", "Jump", "Special" } do
		local b = touch:FindFirstChild(name) :: GuiObject
		local a0, a1 = b.AbsolutePosition, b.AbsolutePosition + b.AbsoluteSize
		for _, child in edgeColumn:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				local c0, c1 = child.AbsolutePosition, child.AbsolutePosition + child.AbsoluteSize
				if a0.X < c1.X + 4 and c0.X < a1.X + 4 and a0.Y < c1.Y + 4 and c0.Y < a1.Y + 4 then
					table.insert(hits, name .. "/" .. child.Name)
				end
			end
		end
	end
	check(#hits == 0, ("rhombus clear of the right edge buttons (%s)"):format(table.concat(hits, ", ")))
end

------------------------------------------------------------------ access button vs. level capsule
local accessButton = menu.accessButton :: GuiObject
local aura = hud:FindFirstChild("Aura") :: GuiObject?
if aura then
	local a0, a1 = accessButton.AbsolutePosition, accessButton.AbsolutePosition + accessButton.AbsoluteSize
	local b0, b1 = aura.AbsolutePosition, aura.AbsolutePosition + aura.AbsoluteSize
	local overlap = a0.X < b1.X and b0.X < a1.X and a0.Y < b1.Y and b0.Y < a1.Y
	check(not overlap, "MENÜ button does not overlap the level capsule")
end
check(accessButton.AbsoluteSize.Y >= 44, "MENÜ button is a 44 px touch target")

------------------------------------------------------------------ menu audit
local function shown(object: GuiObject, root: Instance): boolean
	local current: Instance? = object
	while current and current ~= root do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

local function audit(tab: string)
	local menus = gui:FindFirstChild("MatchMenus")
	local panel = if menus then menus:FindFirstChild("LobbyMenu") :: Frame? else nil
	if not panel then
		check(false, tab .. ": panel not found")
		return
	end
	local p0, p1 = panel.AbsolutePosition, panel.AbsolutePosition + panel.AbsoluteSize
	check(p0.X >= -1 and p0.Y >= -1 and p1.X <= camera.ViewportSize.X + 1 and p1.Y <= camera.ViewportSize.Y + 1, tab .. ": panel inside the screen")
	local clipped, small, overflow = {}, {}, {}
	for _, object in panel:GetDescendants() do
		if object:IsA("GuiObject") and shown(object, panel) then
			if (object:IsA("TextLabel") or object:IsA("TextButton")) and object.Text ~= "" and not object.TextScaled and not object.TextFits then
				table.insert(clipped, object.Text:sub(1, 40))
			end
			if object:IsA("GuiButton") and object.Active and object.Name ~= "ModalCatcher" and (object.AbsoluteSize.Y < 43.5 or object.AbsoluteSize.X < 43.5) then
				table.insert(small, ("%s %dx%d"):format(object:IsA("TextButton") and object.Text:sub(1, 20) or object.Name, object.AbsoluteSize.X, object.AbsoluteSize.Y))
			end
			local scrolling = object:FindFirstAncestorWhichIsA("ScrollingFrame")
			local horizontal = scrolling and scrolling.ScrollingDirection ~= Enum.ScrollingDirection.Y
			if not horizontal and object.AbsoluteSize.X > 0 and (object.AbsolutePosition.X < p0.X - 1 or object.AbsolutePosition.X + object.AbsoluteSize.X > p1.X + 1) then
				table.insert(overflow, object:GetFullName():sub(-60))
			end
		end
	end
	check(#clipped == 0, ("%s: no clipped text (%d) %s"):format(tab, #clipped, table.concat(clipped, " | "):sub(1, 300)))
	check(#small == 0, ("%s: touch targets >= 44 px (%d) %s"):format(tab, #small, table.concat(small, " | "):sub(1, 300)))
	check(#overflow == 0, ("%s: nothing sticks out sideways (%d) %s"):format(tab, #overflow, table.concat(overflow, " | "):sub(1, 300)))
end

menu.open("Overview")
task.wait(0.5)
check(MenuSystem.isOpen() and MenuSystem.current() == "LobbyMenu", "lobby menu registered as the one big menu")
check(ProximityPromptService.Enabled == false, "armory prompts disabled while the menu is open")
check(touch.Visible == false, "touch buttons hidden while the menu is open")
for _, tab in { "Overview", "Gear", "Career", "Modes", "Settings", "Controls" } do
	menu.open(tab)
	task.wait(1.2)
	audit(tab)
end

------------------------------------------------------------------ equipping through the server
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LoadoutRequest") :: RemoteFunction
local control = ReplicatedStorage:WaitForChild("MenuQAControl") :: RemoteEvent
local denariiBefore = player:GetAttribute("Denarii")
local function ask(kind: string, id: string): any
	task.wait(0.5) -- rate limit
	return remote:InvokeServer("Equip", kind, id)
end
local answer = ask("Weapon", "LegionSword")
check(answer.ok == true and player:GetAttribute("EquippedWeapon") == "LegionSword", "owned weapon equipped: " .. tostring(answer.message))
check(player:GetAttribute("Denarii") == denariiBefore, "equipping costs no Denarii")
-- an item this profile really does not own (Studio profiles may already own everything)
local owned: { [string]: boolean } = {}
for id in tostring(player:GetAttribute("OwnedWeapons") or ""):gmatch("[^,]+") do
	owned[id] = true
end
local notOwned: string? = nil
for _, id in { "BattleAxe", "HopliteSpear", "Trident", "MorningStar", "TwinDaggers", "HunterBow", "LegionSword" } do
	if not owned[id] then
		notOwned = id
		break
	end
end
if notOwned then
	answer = ask("Weapon", notOwned)
	check(answer.ok == false and answer.code == "NOT_OWNED", ("not owned weapon refused (%s: %s)"):format(notOwned, tostring(answer.code)))
else
	print("[MenuQA] SKIP not-owned check: this Studio profile owns every weapon")
end
answer = ask("Weapon", "NoSuchSword")
check(answer.ok == false and answer.code == "INVALID", "unknown id refused")
answer = ask("Armor", "MurmilloArmor")
check(answer.ok == true and player:GetAttribute("EquippedArmor") == "MurmilloArmor", "owned armor equipped")
task.wait(1)
local character = player.Character
local armorModels = 0
if character then
	for _, child in character:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("OttiEquipment") then
			armorModels += 1
		end
	end
end
check(armorModels >= 2, ("weapon / shield / armor models rebuilt on the character (%d)"):format(armorModels))
answer = ask("Weapon", "TwinDaggers")
answer = ask("Shield", "TowerShield")
check(answer.ok == true and player:GetAttribute("EquippedShield") == "TowerShield", "shield choice kept with a two-handed weapon")
control:FireServer("Lock")
repeat
	task.wait(0.1)
until player:GetAttribute("MenuQAState") == "Lock"
answer = ask("Weapon", "RustyGladius")
check(answer.ok == false and answer.code == "IN_BATTLE" and player:GetAttribute("EquippedWeapon") == "TwinDaggers", "equipping locked during a fight")
control:FireServer("Unlock")
repeat
	task.wait(0.1)
until player:GetAttribute("MenuQAState") == "Unlock"
answer = ask("Weapon", "RustyGladius")
check(answer.ok == true, "equipping works again in the lobby")

------------------------------------------------------------------ closing restores the game
menu.close()
task.wait(0.5)
check(not MenuSystem.isOpen(), "menu closed")
check(ProximityPromptService.Enabled == true, "prompts back after closing")
check(touch.Visible == game:GetService("UserInputService").TouchEnabled, "touch buttons back after closing (touch devices)")

print(("[MenuQA] DONE %d passed, %d failed"):format(passed, failed))
menu.open("Gear") -- left open for the screenshot
