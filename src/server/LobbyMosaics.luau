--!strict
-- Roman floor mosaics for the lobby's group pads (meeting points that tell the rooms apart).
-- Fine 29 x 29 patterns use individual tesserae, so grout remains visible inside solid colours.
-- The panel keeps its original 15-cell width; added detail does not enlarge the lobby pads.
-- Every tile is anchored, non-colliding, never queried or touched and casts no shadow.
--   Otti    the otter champion's face, cream muzzle and whiskers inside a gold ring
--   Schili  a green turtle with a segmented shell, head, four feet and a small tail
-- Pattern legend: "." = no tile (the base slab shows through), other letters = Palette keys.

local Mosaics = {}

local PALETTE: { [string]: Color3? } = {
	G = Color3.fromRGB(226, 182, 74), -- gold ring
	B = Color3.fromRGB(112, 73, 46), -- Otti fur
	D = Color3.fromRGB(58, 36, 24), -- dark fur / ears
	F = Color3.fromRGB(139, 94, 58), -- forehead highlight
	C = Color3.fromRGB(216, 193, 150), -- cream muzzle / whiskers
	N = Color3.fromRGB(36, 26, 22), -- nose / mouth
	E = Color3.fromRGB(20, 16, 14), -- eyes
	T = Color3.fromRGB(64, 118, 104), -- turtle shell rim
	S = Color3.fromRGB(240, 220, 170), -- muzzle / eye glints
	K = Color3.fromRGB(37, 72, 56), -- turtle outline / shell seams
	L = Color3.fromRGB(166, 190, 102), -- turtle skin / shell highlights
	H = Color3.fromRGB(105, 151, 74), -- shell plates
}

local PATTERNS: { [string]: { string } } = {
	Otti = {
		".............................",
		"...........GGGGGGG...........",
		"........GGG.......GGG........",
		".......GG...........GG.......",
		".....DDD....DBBBD....DDD.....",
		"....DDBDDDBBBFFFBBBDDDBDD....",
		"...DDBBBDBFFFFFFFFFBDBBBDD...",
		"...DBBBDBFFFFFFFFFFFBDBBBD...",
		"..GDDBDBFFFFFFFFFFFFFBDBDDG..",
		"..G.DDBBDDFFFFFFFFDDFBBDD.G..",
		"..G..DBBFFFFFFFFFFFFFBBD..G..",
		".G...DBBESEFFFFFFFESEBBD...G.",
		".G..DBBBEEEFFFFFFFEEEBBBD..G.",
		".G..DBBBEEEBBFFFBBEEEBBBD..G.",
		".G..DBBBBBSSCCCCCSSBBBBBD..G.",
		".G..DBBBSSSSSNNNSSSSSBBBD..G.",
		".G..CCCCNSSSNNNNNSSSNCCCC..G.",
		".G...DBSSSSSSNNNSSSSSSBD...G.",
		"..G..DBSSNSSSSNSSSSNSSBD..G..",
		"..G.CCCCSSSSSNSNSSSSSCCCC.G..",
		"..GG..DDCCSSCCCCCSSCCDD..GG..",
		"...G...DCCCCCCCCCCCCCD...G...",
		"....G...DCCCCCCCCCCCD...G....",
		"....GG...DCCCCCCCCCD...GG....",
		".....GG...G.GCGCG.G...GG.....",
		".......GG...........GG.......",
		"........GGG.......GGG........",
		"...........GGGGGGG...........",
		".............................",
	},
	Schili = {
		".............................",
		"...........GGGGGGG...........",
		"........GGG...L...GGG........",
		".......GG...SLLLS...GG.......",
		".....GG....KELLLEK....GG.....",
		"....GG.....KLLLLLK.....GG....",
		"....G......KKKKKKK......G....",
		"...G......KKTHHHTKK......G...",
		"..GG.....KTHHHHHHHTK.....GG..",
		"..G...K.KTHHHHHHHHHTK.K...G..",
		"..G.KLLKTHHHLHHHLHHHTKLLK.G..",
		".G..KLLKTHKHHHHHHHKHTKLLK..G.",
		".G..KKKTHHHKKKKKKKHHHTKKK..G.",
		".G....KTHHHKHHHHHKHHHTK....G.",
		".G....KTHHLKHHHHHLHHHTK....G.",
		".G....KTHHHKHHHHHKHHHTK....G.",
		".G....KTHHHKHHHHHKHHHTK....G.",
		".G....KTTHHKHHHHHKHHTTK....G.",
		"..G...KTTHHKKKKKKKHHTTK...G..",
		"..G....KTTKHLHHHLHKTTK....G..",
		"..GG.KLKTTTHHHHHHHTTTKLK.GG..",
		"...G.KLLKTTTTHHHTTTTKLLK.G...",
		"....GKKKKKTTTTTTTTTKKKKKG....",
		"....GG.K..KKTTTTTKK..K.GG....",
		".....GG.....KKKKK.....GG.....",
		".......GG.....T.....GG.......",
		"........GGG...T...GGG........",
		"...........GGGGGGG...........",
		".............................",
	},
}

local function tile(parent: Instance, size: Vector3, cframe: CFrame, color: Color3)
	local part = Instance.new("Part")
	part.Name = "Tessera"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Slate
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
end

-- Builds a floor emblem whose -Z points to the top of the picture.
-- tileSize retains the original coarse-pattern scale: panel width = 15 * tileSize.
-- Returns nil for an unknown emblem.
function Mosaics.build(parent: Instance, center: CFrame, emblem: string, tileSize: number, baseColor: Color3): Model?
	local pattern = PATTERNS[emblem]
	if not pattern then
		return nil
	end
	local rows = #pattern
	local cols = #pattern[1]
	local cellSize = tileSize * 15 / cols
	local width, depth = cols * cellSize, rows * cellSize
	local model = Instance.new("Model")
	model.Name = "Mosaic_" .. emblem
	-- Base slab (the "." cells) and a thin dark border, like a set-in panel.
	tile(model, Vector3.new(width + tileSize * 1.2, 0.1, depth + tileSize * 1.2), center * CFrame.new(0, 0.05, 0), Color3.fromRGB(70, 54, 40))
	tile(model, Vector3.new(width + tileSize * 0.4, 0.12, depth + tileSize * 0.4), center * CFrame.new(0, 0.07, 0), baseColor)
	for r, row in pattern do
		assert(#row == cols, "Mosaic rows must have equal widths: " .. emblem)
		local z = -depth / 2 + (r - 0.5) * cellSize
		for c = 1, cols do
			local key = row:sub(c, c)
			local color = PALETTE[key]
			assert(key == "." or color ~= nil, "Unknown mosaic colour: " .. key)
			if color then
				local x = -width / 2 + (c - 0.5) * cellSize
				-- Small, deterministic stone variations; no random flicker or extra texture assets.
				local shade = 0.96 + ((r * 7 + c * 11) % 5) * 0.02
				local stone = Color3.new(
					math.clamp(color.R * shade, 0, 1),
					math.clamp(color.G * shade, 0, 1),
					math.clamp(color.B * shade, 0, 1)
				)
				-- A narrow grout gap on all four sides, including inside same-colour areas.
				tile(model, Vector3.new(cellSize * 0.92, 0.14, cellSize * 0.92), center * CFrame.new(x, 0.09, z), stone)
			end
		end
	end
	model.Parent = parent
	return model
end

function Mosaics.has(emblem: string): boolean
	return PATTERNS[emblem] ~= nil
end

return Mosaics
