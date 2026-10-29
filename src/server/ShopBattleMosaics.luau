--!strict
-- Asset-free Roman battle murals. A small indexed canvas becomes horizontal colour runs
-- on a SurfaceGui, with a tessera grout lattice. Nine pictures need only nine physical Parts.
local ShopBattleMosaics = {}
local W, H = 96, 48
local COLORS = {
    Color3.fromRGB(227, 208, 161), -- 1 ivory field
    Color3.fromRGB(57, 43, 34), -- 2 charcoal outlines
    Color3.fromRGB(205, 158, 61), -- 3 gold
    Color3.fromRGB(140, 44, 37), -- 4 imperial red
    Color3.fromRGB(91, 61, 39), -- 5 otter fur
    Color3.fromRGB(237, 219, 176), -- 6 muzzle / limestone
    Color3.fromRGB(73, 119, 85), -- 7 jade scales
    Color3.fromRGB(45, 78, 65), -- 8 dark shell
    Color3.fromRGB(157, 177, 95), -- 9 shell highlights
    Color3.fromRGB(137, 166, 164), -- 10 steel
    Color3.fromRGB(179, 130, 84), -- 11 bronze
    Color3.fromRGB(95, 132, 145), -- 12 blue
    Color3.fromRGB(182, 165, 121), -- 13 distant stone
    Color3.fromRGB(106, 119, 88), -- 14 undead
}

local function scene(first: string, second: string?, theme: string): { { number } }
    local grid: { { number } } = {}
    for y = 1, H do grid[y] = table.create(W, 1) end
    local function dot(x: number, y: number, color: number)
        x, y = math.floor(x + 0.5), math.floor(y + 0.5)
        if x >= 1 and x <= W and y >= 1 and y <= H then grid[y][x] = color end
    end
    local function rect(x0: number, y0: number, x1: number, y1: number, color: number)
        for y = y0, y1 do for x = x0, x1 do dot(x, y, color) end end
    end
    local function ellipse(cx: number, cy: number, rx: number, ry: number, color: number)
        for y = math.floor(cy - ry), math.ceil(cy + ry) do
            for x = math.floor(cx - rx), math.ceil(cx + rx) do
                if ((x - cx) / rx)^2 + ((y - cy) / ry)^2 <= 1 then dot(x, y, color) end
            end
        end
    end
    local function line(x0: number, y0: number, x1: number, y1: number, color: number, radius: number?)
        local count = math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1)
        for i = 0, count do
            local x, y = x0 + (x1 - x0) * i / count, y0 + (y1 - y0) * i / count
            local r = radius or 0
            rect(math.floor(x - r), math.floor(y - r), math.floor(x + r), math.floor(y + r), color)
        end
    end
    -- Colosseum arches, a sun disc, banners and a dust-covered arena establish the battle.
    ellipse(48, 10, 8, 7, 3)
    for x = 10, 90, 16 do
        ellipse(x, 19, 6, 9, 13)
        ellipse(x, 20, 4, 7, 1)
        rect(x - 6, 19, x - 5, 31, 13)
        rect(x + 5, 19, x + 6, 31, 13)
    end
    rect(5, 34, 92, 44, 13)
    for _, x in { 13, 83 } do
        rect(x, 8, x + 5, 17, 4)
        rect(x, 9, x + 5, 9, 3)
        line(x + 2, 10, x + 2, 15, 3)
    end
    -- Readable opposing undead silhouettes: helmets, raised spears, shields, bent legs.
    for _, enemy in { { 9, 1 }, { 20, 1 }, { 77, -1 }, { 88, -1 } } do
        local x, direction = enemy[1], enemy[2]
        ellipse(x, 25, 3, 3, 2)
        ellipse(x, 25, 2, 2, 14)
        rect(x - 3, 21, x + 3, 23, 11)
        rect(x - 2, 28, x + 2, 35, 8)
        line(x, 34, x - 3, 41, 2, 1)
        line(x, 34, x + 3, 39, 2, 1)
        line(x, 30, x + direction * 5, 28, 14, 1)
        line(x + direction * 5, 33, x + direction * 7, 15, 2)
        dot(x + direction * 7, 14, 10)
    end
    local function hero(id: string, cx: number, facing: number)
        local function x(dx: number): number return cx + facing * dx end
        local skin = if id == "Otti" then 5 else 7
        -- Fluttering red cape, broad stance and a raised weapon silhouette.
        for row = 26, 37 do line(x(-4), row, x(-7 - (row - 26) / 3), row, 4) end
        line(x(-2), 35, x(-6), 41, 2, 2)
        line(x(2), 35, x(7), 40, 2, 2)
        line(x(-2), 35, x(-6), 40, skin, 1)
        line(x(2), 35, x(7), 39, skin, 1)
        ellipse(cx, 30, 6, 8, 2)
        ellipse(cx, 30, 5, 7, if theme == "Armor" then 11 else 4)
        rect(cx - 5, 31, cx + 5, 32, 3)
        if id == "Schili" then
            ellipse(x(-3), 29, 6, 8, 8)
            ellipse(x(-3), 29, 4, 6, 9)
            line(x(-3), 24, x(-3), 34, 8)
            line(x(-6), 28, x(0), 31, 8)
            line(x(-6), 32, x(0), 27, 8)
            line(cx, 25, x(2), 19, 7, 2)
            ellipse(x(3), 18, 4, 4, 2)
            ellipse(x(3), 18, 3, 3, 9)
            ellipse(x(5), 20, 3, 1, 6)
        elseif id == "Krokero" then
            line(x(-4), 34, x(-13), 38, 7, 2)
            ellipse(cx, 21, 5, 5, 8)
            ellipse(cx, 21, 4, 4, 7)
            rect(math.min(x(1), x(10)), 21, math.max(x(1), x(10)), 24, 7)
            line(x(2), 24, x(10), 24, 6)
            for dx = 3, 9, 2 do dot(x(dx), 23, 6) end
            for dx = -4, 2, 2 do dot(x(dx), 16, 3) end
        else
            ellipse(cx, 20, 6, 6, 2)
            ellipse(cx, 20, 5, 5, 5)
            ellipse(x(-4), 15, 2, 2, 5)
            ellipse(x(4), 15, 2, 2, 5)
            ellipse(x(3), 23, 4, 3, 6)
            dot(x(6), 22, 2)
            line(x(1), 24, x(-2), 23, 6)
            line(x(1), 25, x(-2), 26, 6)
        end
        dot(x(3), 19, 2)
        dot(x(4), 18, 6)
        line(x(3), 27, x(8), 22, skin, 1)
        -- Theme equipment connects each mural to its shop.
        if theme == "Shields" then
            ellipse(x(8), 27, 5, 7, 2)
            ellipse(x(8), 27, 4, 6, 3)
            ellipse(x(8), 27, 3, 5, if id == "Schili" then 12 else 4)
            line(x(8), 23, x(8), 31, 3)
            line(x(6), 27, x(10), 27, 3)
        else
            line(x(8), 25, x(13), 10, 2, 1)
            line(x(8), 23, x(13), 10, if id == "Krokero" then 11 else 10)
            line(x(5), 24, x(11), 26, 3)
        end
        if theme == "Armor" then
            line(x(-4), 25, x(4), 25, 3, 1)
            rect(cx - 2, 27, cx + 2, 30, 3)
        end
        -- Impact sparks around the clash, without blood.
        for _, offset in { {10,17},{15,19},{12,14} } do
            line(x(offset[1]), offset[2], x(offset[1]+2), offset[2]-2, 3)
        end
    end
    if second then hero(first, 34, 1); hero(second, 62, -1)
    else hero(first, 48, 1) end
    if theme == "Armor" then
        for x = 26, 70, 11 do line(x, 10, x - 4, 15, 2); dot(x - 4, 16, 10) end
    end
    -- Double gold frame and a repeating Roman meander, rendered as actual tessera cells.
    for _, inset in { 1, 4 } do
        rect(inset, inset, W-inset+1, inset, 3)
        rect(inset, H-inset+1, W-inset+1, H-inset+1, 3)
        rect(inset, inset, inset, H-inset+1, 3)
        rect(W-inset+1, inset, W-inset+1, H-inset+1, 3)
    end
    for x = 6, W-8, 6 do
        for _, y in { 2, H-2 } do rect(x,y,x+3,y,2); dot(x+3,y+1,2) end
    end
    return grid
end

local function frame(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3)
    local cell = Instance.new("Frame")
    cell.Name = name
    cell.BorderSizePixel = 0
    cell.Position = UDim2.fromScale(x, y)
    cell.Size = UDim2.fromScale(w, h)
    cell.BackgroundColor3 = color
    cell.Parent = parent
end

local function panel(parent: Instance, cf: CFrame, size: Vector2, first: string, second: string?, theme: string, title: string)
    local host = Instance.new("Part")
    host.Name = "BattleMosaic_" .. theme .. "_" .. first .. (if second then "_" .. second else "")
    host.Anchored = true
    host.CanCollide, host.CanQuery, host.CanTouch, host.CastShadow = false, false, false, false
    host.Size = Vector3.new(size.X, size.Y, 0.06)
    host.CFrame = cf
    host.Color = COLORS[2]
    host.Material = Enum.Material.Slate
    host:SetAttribute("FirstHero", first)
    host:SetAttribute("SecondHero", second)
    host:SetAttribute("BattleTheme", theme)
    local gui = Instance.new("SurfaceGui")
    gui.Name = "BattleTesserae"
    gui.Face = Enum.NormalId.Front
    gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    gui.PixelsPerStud = 32
    gui.LightInfluence = 0.65
    gui.MaxDistance = 100
    gui.AlwaysOnTop = false
    gui.Parent = host
    local art = Instance.new("Frame")
    art.Name = "BattleScene"
    art.Size = UDim2.fromScale(1, 0.88)
    art.BorderSizePixel = 0
    art.BackgroundColor3 = COLORS[1]
    art.Parent = gui
    local grid = scene(first, second, theme)
    for y, row in grid do
        local x = 1
        while x <= W do
            local start, color = x, row[x]
            while x <= W and row[x] == color do x += 1 end
            frame(art, "StoneRun", (start-1)/W, (y-1)/H, (x-start)/W, 1/H, COLORS[color])
        end
    end
    -- Thin grout over the runs keeps even large colour fields visibly tiled.
    for x = 0, W do frame(art, "Grout", x/W, 0, 0.065/W, 1, COLORS[2]) end
    for y = 0, H do frame(art, "Grout", 0, y/H, 1, 0.065/H, COLORS[2]) end
    local label = Instance.new("TextLabel")
    label.Name = "BattleInscription"
    label.Position = UDim2.fromScale(0, 0.88)
    label.Size = UDim2.fromScale(1, 0.12)
    label.BackgroundColor3 = COLORS[2]
    label.TextColor3 = COLORS[3]
    label.Font = Enum.Font.Garamond
    label.TextScaled = true
    label.Text = title
    label.Parent = gui
    host.Parent = parent
end

function ShopBattleMosaics.build(parent: Instance, shop: CFrame, theme: string, first: string, second: string)
    local names = { Otti = "OTTI", Schili = "SCHILI", Krokero = "KROKERO" }
    local stories = { Shields = "THE UNBROKEN SHIELD WALL", Armor = "STAND AGAINST THE LEGION", Weapons = "CHAMPIONS OF THE ARENA" }
    local title = (names :: { [string]: string })[first] .. " & " .. (names :: { [string]: string })[second]
    -- The floor panel sits above the existing rug, clear of every display plinth.
    local floor = shop * CFrame.new(0, 0.11, -3) * CFrame.Angles(math.pi/2, 0, 0) * CFrame.Angles(0, 0, math.pi)
    panel(parent, floor, Vector2.new(36, 18), first, second, theme, title .. " · " .. (stories :: { [string]: string })[theme])
    -- The side walls now have connecting doors. Paint the solid front / rear walls instead.
    panel(parent, shop * CFrame.new(0, 10, 21.92), Vector2.new(38, 11), first, nil, theme, (names :: { [string]: string })[first] .. " · ARENA LEGEND")
    panel(parent, shop * CFrame.new(0, 10, -21.92) * CFrame.Angles(0, math.pi, 0), Vector2.new(38, 11), second, nil, theme, (names :: { [string]: string })[second] .. " · ARENA LEGEND")
end

return ShopBattleMosaics
