--!strict
-- Small building blocks for Rome: anchored parts, wedges, cylinders, signs, lamps and the town's
-- few material families (warm stone, plaster, terracotta, timber, bronze). Decoration never
-- collides, never casts a query and only a few big pieces cast shadows.
local RomeParts = {}

RomeParts.Colors = table.freeze({
	Travertine = Color3.fromRGB(222, 210, 184),
	Limestone = Color3.fromRGB(205, 192, 166),
	Stone = Color3.fromRGB(168, 152, 128),
	StoneDark = Color3.fromRGB(120, 108, 92),
	Paving = Color3.fromRGB(86, 82, 78), -- dark basalt road paving
	Kerb = Color3.fromRGB(214, 204, 182),
	Sidewalk = Color3.fromRGB(176, 160, 136),
	Terracotta = Color3.fromRGB(184, 96, 58),
	TerracottaDark = Color3.fromRGB(158, 80, 48),
	Timber = Color3.fromRGB(104, 70, 44),
	TimberDark = Color3.fromRGB(78, 52, 34),
	Bronze = Color3.fromRGB(176, 125, 60),
	Gold = Color3.fromRGB(232, 186, 82),
	Cream = Color3.fromRGB(240, 228, 204),
	RomanRed = Color3.fromRGB(150, 48, 34),
	Leaf = Color3.fromRGB(86, 118, 64),
	LeafDark = Color3.fromRGB(58, 88, 50),
	Water = Color3.fromRGB(70, 140, 170),
	Iron = Color3.fromRGB(62, 64, 61),
	Fire = Color3.fromRGB(255, 160, 70),
})
-- Plaster families (Putz): neighbours pick different ones by their seed.
RomeParts.Plaster = table.freeze({
	Color3.fromRGB(236, 222, 194),
	Color3.fromRGB(228, 204, 164),
	Color3.fromRGB(218, 186, 146),
	Color3.fromRGB(232, 214, 186),
	Color3.fromRGB(206, 160, 120),
	Color3.fromRGB(224, 196, 150),
})
RomeParts.Roofs = table.freeze({
	Color3.fromRGB(184, 96, 58),
	Color3.fromRGB(196, 110, 66),
	Color3.fromRGB(168, 86, 52),
})

export type Options = {
	collide: boolean?,
	material: Enum.Material?,
	transparency: number?,
	shadow: boolean?,
	shape: Enum.PartType?,
	query: boolean?,
}

local C = RomeParts.Colors

function RomeParts.part(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, options: Options?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Limestone
	if options then
		if options.material then
			p.Material = options.material
		end
		if options.shape == Enum.PartType.Ball and (math.abs(size.X - size.Y) > 1e-3 or math.abs(size.X - size.Z) > 1e-3) then
			-- Roblox shrinks a Ball to its smallest side: an oblong crown, amphora or cloud is an
			-- ellipsoid instead (a block with a sphere mesh that follows the part's size)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		elseif options.shape then
			p.Shape = options.shape
		end
		if options.collide == false then
			p.CanCollide = false
			p.CanQuery = options.query == true
			p.CanTouch = false
		end
		if options.transparency then
			p.Transparency = options.transparency
		end
		if options.shadow == false then
			p.CastShadow = false
		end
	end
	p.Parent = parent
	return p
end

-- Decoration: no collision, no queries, no shadow.
function RomeParts.decor(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	return RomeParts.part(parent, name, cf, size, color, { collide = false, shadow = false, material = material })
end

-- A wedge whose height grows toward its local +Z (Roblox WedgePart: slope on the front face).
function RomeParts.wedge(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, options: Options?): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = if options and options.material then options.material else Enum.Material.Limestone
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	if options then
		if options.collide == false then
			w.CanCollide = false
			w.CanQuery = false
			w.CanTouch = false
		end
		if options.transparency then
			w.Transparency = options.transparency
		end
		if options.shadow == false then
			w.CastShadow = false
		end
	end
	w.Parent = parent
	return w
end

-- An invisible collision shape (smooth walking surfaces over visible stones and kerbs).
function RomeParts.collider(parent: Instance, name: string, cf: CFrame, size: Vector3): Part
	local p = RomeParts.part(parent, name, cf, size, C.Stone, { transparency = 1, shadow = false })
	p.CanTouch = false
	return p
end
function RomeParts.colliderWedge(parent: Instance, name: string, cf: CFrame, size: Vector3): WedgePart
	local w = RomeParts.wedge(parent, name, cf, size, C.Stone, { transparency = 1, shadow = false })
	w.CanTouch = false
	return w
end

-- An upright cylinder (column, basin, stone) of `height` and `diameter` standing on `base`.
function RomeParts.column(parent: Instance, name: string, base: CFrame, height: number, diameter: number, color: Color3, options: Options?): Part
	local o: Options = table.clone(options or {})
	o.shape = Enum.PartType.Cylinder
	return RomeParts.part(parent, name, base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(height, diameter, diameter), color, o)
end

function RomeParts.model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function RomeParts.folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- A painted board with one or two lines of text on its front (-Z) face.
function RomeParts.sign(parent: Instance, name: string, cf: CFrame, size: Vector2, title: string, subtitle: string?, background: Color3?, textColor: Color3?): Part
	local board = RomeParts.decor(parent, name, cf, Vector3.new(size.X, size.Y, 0.3), background or C.TimberDark, Enum.Material.Wood)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.MaxDistance = 140
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = if subtitle then UDim2.fromScale(0.94, 0.56) else UDim2.fromScale(0.94, 0.9)
	label.Position = UDim2.fromScale(0.03, 0.05)
	label.Font = Enum.Font.Garamond
	label.TextScaled = true
	label.TextColor3 = textColor or C.Gold
	label.Text = title
	label.Parent = gui
	if subtitle then
		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.fromScale(0.94, 0.32)
		sub.Position = UDim2.fromScale(0.03, 0.63)
		sub.Font = Enum.Font.GothamBold
		sub.TextScaled = true
		sub.TextColor3 = C.Cream
		sub.Text = subtitle
		sub.Parent = gui
	end
	return board
end

-- A warm light source (flame + PointLight) at `cf`.
function RomeParts.flame(parent: Instance, cf: CFrame, range: number?, brightness: number?): Part
	local p = RomeParts.decor(parent, "Flame", cf, Vector3.new(0.7, 1, 0.7), C.Fire, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 140)
	light.Range = range or 20
	light.Brightness = brightness or 0.9
	light.Shadows = false
	light.Parent = p
	return p
end

-- A bronze lamp post on the ground at `base` (main streets are lit, lanes are not).
function RomeParts.lampPost(parent: Instance, base: CFrame)
	RomeParts.column(parent, "LampPost", base, 7, 0.45, C.Bronze, { collide = false, shadow = false, material = Enum.Material.Metal })
	RomeParts.decor(parent, "LampBowl", base * CFrame.new(0, 7.1, 0), Vector3.new(1.4, 0.4, 1.4), C.Bronze, Enum.Material.Metal)
	RomeParts.flame(parent, base * CFrame.new(0, 7.7, 0), 22, 0.8)
end

-- Flat frame on the ground at (x, y, z), facing `yaw` degrees (0 = -Z north, 90 = +X east).
function RomeParts.at(x: number, y: number, z: number, yaw: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, -math.rad(yaw or 0), 0)
end

-- Frame at a point whose -Z looks along the horizontal direction (dx, dz).
function RomeParts.facing(x: number, y: number, z: number, dx: number, dz: number): CFrame
	local p = Vector3.new(x, y, z)
	return CFrame.lookAt(p, p + Vector3.new(dx, 0, dz))
end

return RomeParts
