--!strict
-- Roman floor mosaics for the lobby's group pads (meeting points that tell the rooms apart).
-- A mosaic is a small pixel pattern of tesserae. Neighbouring tiles of the same colour in a row are
-- merged into ONE part, so a 15 x 15 emblem costs about 50-70 parts instead of 225. All tiles are
-- flat, anchored, non-colliding, never queried or touched and cast no shadow.
--   Otti    the otter champion's face (chocolate fur, cream muzzle, dark nose) in a gold ring
--   Schili  PLACEHOLDER emblem (a round bronze shield with an "S"): replace the pattern once the
--           Schili character design is final
-- Pattern legend: "." = no tile (the base slab shows through), other letters = Palette keys.

local Mosaics = {}

local PALETTE: { [string]: Color3 } = {
	G = Color3.fromRGB(226, 182, 74), -- gold ring
	B = Color3.fromRGB(92, 58, 38), -- Otti fur
	D = Color3.fromRGB(58, 36, 24), -- dark fur / ears
	C = Color3.fromRGB(232, 214, 178), -- cream muzzle
	N = Color3.fromRGB(36, 26, 22), -- nose / mouth
	E = Color3.fromRGB(20, 16, 14), -- eyes
	T = Color3.fromRGB(64, 118, 104), -- patina teal (Schili shield)
	S = Color3.fromRGB(240, 220, 170), -- light letter
	R = Color3.fromRGB(150, 40, 34), -- red accent
}

local PATTERNS: { [string]: { string } } = {
	Otti = {
		".....GGGGG.....",
		"...GG.....GG...",
		"..G.DD...DD.G..",
		".G.DBBBBBBBD.G.",
		".G.BBBBBBBBB.G.",
		"G.BBEBBBBBEBB.G",
		"G.BBBBBBBBBBB.G",
		"G.BBCCCNCCCBB.G",
		"G.BCCCCNCCCCB.G",
		".G.BCCNNNCCB.G.",
		".G..BCCCCCB..G.",
		"..G..BBBBB..G..",
		"...GG.....GG...",
		".....GGGGG.....",
	},
	Schili = {
		".....GGGGG.....",
		"...GGTTTTTGG...",
		"..GTTTTTTTTTG..",
		".GTTTSSSSSTTTG.",
		".GTTSSTTTTTTTG.",
		"GTTTSSTTTTTTTTG",
		"GTTTTSSSSSTTTTG",
		"GTTTTTTTTSSTTTG",
		"GTTTTTTTTSSTTTG",
		".GTTTTTTTSSTTG.",
		".GTTSSSSSSTTTG.",
		"..GTTTTTTTTTG..",
		"...GGTTTTTGG...",
		".....GGGGG.....",
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

-- Builds `emblem` flat on the floor. `center` is a CFrame on the floor surface whose -Z points
-- to the top of the picture. Returns the model, or nil for an unknown emblem.
function Mosaics.build(parent: Instance, center: CFrame, emblem: string, tileSize: number, baseColor: Color3): Model?
	local pattern = PATTERNS[emblem]
	if not pattern then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Mosaic_" .. emblem
	local rows = #pattern
	local cols = 0
	for _, row in pattern do
		cols = math.max(cols, #row)
	end
	local width, depth = cols * tileSize, rows * tileSize
	-- Base slab (the "." tiles) and a thin dark border, like a set-in panel
	tile(model, Vector3.new(width + tileSize * 1.2, 0.1, depth + tileSize * 1.2), center * CFrame.new(0, 0.05, 0), Color3.fromRGB(70, 54, 40))
	tile(model, Vector3.new(width + tileSize * 0.4, 0.12, depth + tileSize * 0.4), center * CFrame.new(0, 0.07, 0), baseColor)
	for r, row in pattern do
		local z = -depth / 2 + (r - 0.5) * tileSize
		local c = 1
		while c <= #row do
			local key = row:sub(c, c)
			local runEnd = c
			while runEnd < #row and row:sub(runEnd + 1, runEnd + 1) == key do
				runEnd += 1
			end
			local color = PALETTE[key]
			if color then
				local length = (runEnd - c + 1) * tileSize
				local x = -width / 2 + (c - 1) * tileSize + length / 2
				-- a hair smaller than the run so the grout lines between rows stay visible
				tile(model, Vector3.new(length - tileSize * 0.08, 0.14, tileSize * 0.92), center * CFrame.new(x, 0.09, z), color)
			end
			c = runEnd + 1
		end
	end
	model.Parent = parent
	return model
end

function Mosaics.has(emblem: string): boolean
	return PATTERNS[emblem] ~= nil
end

return Mosaics
