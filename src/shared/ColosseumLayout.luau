--!strict
-- One architectural source for the playable Arena and the Hub's arena / approaches.
local Layout = {
    SemiAxisX = 70, SemiAxisZ = 55, FloorTop = 1,
    PodiumHeight = 10, PodiumThickness = 4,
    -- Eight seating tiers in two storeys (maeniana): tiers 5-8 start UpperRise higher, above a
    -- parapet. The stands are deep enough to cover the hero halls and shops below.
    SeatTiers = 8, SeatDepth = 14, SeatRise = 7, UpperRise = 3,
    -- Behind the top tier: the vaulted galleries (ambulatory), then the arcaded outer facade
    -- (three storeys of arches with a statue in every upper arch, attic on top), then the granite
    -- ground: a ring of slabs GroundRingWidth wide (stairwells cut into it), endless tiles beyond.
    GalleryWidth = 14, FacadeThickness = 5, AtticHeight = 24, GroundRingWidth = 295, FacadeArches = 64,
    GateWidth = 18, GateHeight = 10,
    -- "Grille" keeps sight lines open; "Solid" uses opaque timber leaves.
    GateStyle = "Grille",
    -- Basement: hall vaults stay below the ground (y 0), the hypogeum one hall-stair lower.
    LobbyFloor = -28, HypogeumFloor = -60, ConcourseOffset = 100,
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
-- Top of seating tier k (1 = lowest).
function Layout.tierTop(k: number): number
    return Layout.FloorTop + Layout.PodiumHeight + k * Layout.SeatRise + (if k > Layout.SeatTiers / 2 then Layout.UpperRise else 0)
end
-- Offsets (outward from the sand's edge) of the rings behind the seats.
function Layout.seatsEnd(): number
    return Layout.PodiumThickness + Layout.SeatTiers * Layout.SeatDepth
end
function Layout.facadeEnd(): number
    return Layout.seatsEnd() + Layout.GalleryWidth + Layout.FacadeThickness
end
return table.freeze(Layout)
