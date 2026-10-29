--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Layout = require(ReplicatedStorage.Shared.ColosseumLayout)
local Gate = {}
function Gate.build(parent: Instance, base: CFrame, style: string?): BasePart
    local selected = style or Layout.GateStyle
    assert(selected == "Grille" or selected == "Solid", "Unknown Colosseum gate style")
    local model = Instance.new("Model")
    model.Name = "ArenaEntrance_" .. selected
    model:SetAttribute("GateStyle", selected)
    local function part(name: string, cf: CFrame, size: Vector3, color: Color3): Part
        local p = Instance.new("Part")
        p.Name, p.Anchored, p.Size, p.CFrame = name, true, size, cf
        p.Color, p.Material = color, Enum.Material.Metal
        p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
        p.Parent = model
        return p
    end
    local iron = Color3.fromRGB(68, 64, 57)
    local w, h = Layout.GateWidth, Layout.GateHeight
    local blocker = part("GateCollision", base * CFrame.new(0, h/2, 0), Vector3.new(w, h, 0.6), iron)
    blocker.Transparency, blocker.CanQuery, blocker.CanTouch = 1, false, false
    if selected == "Solid" then
        local door = part("TimberLeaves", base * CFrame.new(0, h/2, 0), Vector3.new(w, h, 0.5), Color3.fromRGB(88, 55, 32))
        door.Material = Enum.Material.WoodPlanks
    else
        for x = -w/2 + 0.3, w/2, 1.2 do
            part("IronBar", base * CFrame.new(x, h/2, 0), Vector3.new(0.28, h, 0.35), iron)
        end
    end
    for _, y in { 1, h/2, h-1 } do
        part("GateBand", base * CFrame.new(0, y, -0.05), Vector3.new(w, 0.3, 0.45), iron)
    end
    for _, x in { -w/2-1, w/2+1 } do
        local pillar = part("GatePillar", base * CFrame.new(x, h/2, 0), Vector3.new(2, h+2, 3), Color3.fromRGB(210, 186, 143))
        pillar.Material = Enum.Material.Limestone
    end
    part("GateLintel", base * CFrame.new(0, h+1, 0), Vector3.new(w+4, 2, 3), Color3.fromRGB(210, 186, 143)).Material = Enum.Material.Limestone
    model.Parent = parent
    return blocker
end
return Gate
