--!strict
-- One architectural source for the playable Arena and the Hub's arena / approaches.
local Layout = {
    SemiAxisX = 70, SemiAxisZ = 55, FloorTop = 1,
    PodiumHeight = 10, PodiumThickness = 4,
    SeatTiers = 4, SeatDepth = 6, SeatRise = 4.5,
    GateWidth = 18, GateHeight = 10,
    -- "Grille" keeps sight lines open; "Solid" uses opaque timber leaves.
    GateStyle = "Grille",
    LobbyFloor = -20, HypogeumFloor = -52, ConcourseOffset = 100,
    HeroAngles = table.freeze({ 90, 210, 330 }), -- ellipse angles, in degrees
}
function Layout.normal(theta: number): Vector3
    return Vector3.new(math.cos(theta) / Layout.SemiAxisX, 0, math.sin(theta) / Layout.SemiAxisZ).Unit
end
function Layout.point(theta: number, offset: number): Vector3
    return Vector3.new(Layout.SemiAxisX * math.cos(theta), 0, Layout.SemiAxisZ * math.sin(theta)) + Layout.normal(theta) * offset
end
function Layout.frame(theta: number, offset: number, y: number): CFrame
    local p = Layout.point(theta, offset) + Vector3.new(0, y, 0)
    return CFrame.lookAt(p, p - Layout.normal(theta))
end
return table.freeze(Layout)
