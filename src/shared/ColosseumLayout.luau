--!strict
-- One architectural source for the playable Arena and the Hub's arena / approaches.
-- Proportions follow the Flavian Amphitheatre: the sand is an ellipse of about 8 : 5 (87 x 55 m),
-- the cavea is equally wide all around and about as high as it is wide, and its upper storey
-- climbs more steeply than the lower one.
local Layout = {
    SemiAxisX = 76, SemiAxisZ = 48, FloorTop = 1,
    PodiumHeight = 10, PodiumThickness = 4,
    -- Eight seating tiers in two storeys (maeniana): tiers 1-4 are LowerDepth deep and LowerRise
    -- high (about 34 degrees), tiers 5-8 UpperDepth deep and UpperRise high (about 41 degrees).
    -- Tier 5 also climbs the praecinctio wall, so that tier 2, tier 5 and tier 8 lie exactly one
    -- facade storey apart: every gallery level opens level onto its terrace.
    SeatTiers = 8, LowerDepth = 9, LowerRise = 6, UpperDepth = 8.5, UpperRise = 22 / 3, PraecinctioRise = 8 / 3,
    -- The terraces are slabs SlabThickness deep under their risers; below them the substructure
    -- stays open (piers, stair houses) down to the ground.
    SlabThickness = 2,
    -- Behind the top tier: the ambulatories (one per storey), then the arcaded outer facade
    -- (three storeys of arches with a statue in every upper arch, attic on top), then the granite
    -- ground: an endless plate.
    GalleryWidth = 14, FacadeThickness = 5, AtticHeight = 24, FacadeArches = 72,
    GateWidth = 18, GateHeight = 10,
    -- "Grille" keeps sight lines open; "Solid" uses opaque timber leaves.
    GateStyle = "Grille",
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
local LOWER_TIERS = 4
-- Top of seating tier k (1 = lowest; 0 = the podium).
function Layout.tierTop(k: number): number
    local lower = math.min(k, LOWER_TIERS)
    local upper = math.max(0, k - LOWER_TIERS)
    return Layout.FloorTop + Layout.PodiumHeight + lower * Layout.LowerRise + upper * Layout.UpperRise + (if upper > 0 then Layout.PraecinctioRise else 0)
end
-- Depth of tier k and the offset (outward from the sand's edge) of its front.
function Layout.tierDepth(k: number): number
    return if k <= LOWER_TIERS then Layout.LowerDepth else Layout.UpperDepth
end
function Layout.tierFront(k: number): number
    local lower = math.min(k - 1, LOWER_TIERS)
    local upper = math.max(0, k - 1 - LOWER_TIERS)
    return Layout.PodiumThickness + lower * Layout.LowerDepth + upper * Layout.UpperDepth
end
-- Offsets of the rings behind the seats.
function Layout.seatsEnd(): number
    return Layout.tierFront(Layout.SeatTiers + 1)
end
function Layout.facadeEnd(): number
    return Layout.seatsEnd() + Layout.GalleryWidth + Layout.FacadeThickness
end
return table.freeze(Layout)
