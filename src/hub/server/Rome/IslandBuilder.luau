--!strict
-- The island on the world disc, in Roblox terrain:
--   * a height field on an 8-stud grid, interpolated to the 4-stud voxels (smooth surfaces):
--     the town's terraces inside the walls (just under the paving), the Colosseum's footprint
--     lowered under its floors, gently rolling countryside, higher ground in the forest, a flat
--     sandy bay in the north-west, a coastline that drops just below sea level and a shelf
--     beyond it, the harbour basin cut out of the town
--   * materials: earth in town, grass, leafy grass in the forest, sand on beach and sea floor,
--     rock on steep ground, beaten earth on the outside paths
--   * the sea: water from the shelf up to sea level over the whole disc
--   * the disc's rim: a ring of rock, water spilling over it and falling as a curtain into the
--     depth, mist and clouds far below
-- `heightAt` is exposed for tests and the countryside builder.
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Layout = require(ReplicatedStorage.Shared.ColosseumLayout)
local RomeLayout = require(script.Parent.RomeLayout)
local Parts = require(script.Parent.RomeParts)

local IslandBuilder = {}

local L = RomeLayout.Levels
local GRID = 8
local VOXEL = 4
local X0, X1, Z0, Z1 = -800, 540, -660, 380
local Y0, Y1 = -48, 36
local BEACH = RomeLayout.Anchors.Beach
local FOREST = RomeLayout.Forest
local FIELDS = RomeLayout.Fields

local function smooth(t: number): number
	local c = math.clamp(t, 0, 1)
	return c * c * (3 - 2 * c)
end

local function insideColosseum(x: number, z: number): boolean
	-- the outer facade (offset 93) is close to an ellipse of 169 x 141
	local ex, ez = x / (Layout.SemiAxisX + Layout.facadeEnd() + 1), z / (Layout.SemiAxisZ + Layout.facadeEnd() + 1)
	return ex * ex + ez * ez < 1
end

local function inRect(x: number, z: number, r: any, margin: number): boolean
	return x > r.x0 - margin and x < r.x1 + margin and z > r.z0 - margin and z < r.z1 + margin
end

-- Terrain height at (x, z) (top of the ground) and its kind for the material.
export type Kind = "Town" | "Grass" | "Forest" | "Field" | "Beach" | "Sea" | "Basin"
function IslandBuilder.heightAt(x: number, z: number): (number, Kind)
	if RomeLayout.isWater(x, z) and RomeLayout.isInTown(x, z) then
		return L.Water - 14, "Basin"
	end
	if RomeLayout.isWater(x, z) then
		return L.Water - 16, "Sea"
	end
	if RomeLayout.isInTown(x, z) then
		if insideColosseum(x, z) then
			return -3, "Town"
		end
		return RomeLayout.levelAt(x, z) - 0.3, "Town"
	end
	local inside = RomeLayout.pointInPolygon(x, z, RomeLayout.Coast)
	local dCoast = RomeLayout.distanceToOutline(x, z, RomeLayout.Coast)
	if not inside then
		return L.Water - 2 - math.min(dCoast, 60) / 60 * 26, "Sea"
	end
	-- countryside: gentle hills, higher in the forest, flatter on the fields
	local base = 3 + 2.6 * math.noise(x / 170, z / 170, 0.3) + 1.2 * math.noise(x / 55, z / 55, 1.7)
	local kind: Kind = "Grass"
	if inRect(x, z, FOREST, 0) then
		local fx = math.min(x - FOREST.x0, FOREST.x1 - x, z - FOREST.z0, FOREST.z1 - z)
		base += smooth(fx / 60) * (5 + 4 * math.noise(x / 90, z / 90, 4.2))
		kind = "Forest"
	elseif inRect(x, z, FIELDS, 30) then
		-- flat fields, blended into the hills over 30 studs round their edge
		local edge = math.min(x - FIELDS.x0, FIELDS.x1 - x, z - FIELDS.z0, FIELDS.z1 - z)
		local flat = 2.6 + 0.6 * math.noise(x / 120, z / 120, 2.2)
		base += (flat - base) * smooth((edge + 30) / 36)
		kind = if edge > -6 then "Field" else "Grass"
	end
	-- the land meets the town walls at the terrace level inside
	local dWall = RomeLayout.distanceToOutline(x, z, RomeLayout.Wall, true)
	if dWall < 50 then
		base = RomeLayout.levelAt(x, z) - 0.3 + (base - RomeLayout.levelAt(x, z) + 0.3) * smooth((dWall - 4) / 46)
	end
	-- the sandy bay in the north-west: a long flat slope into the water
	local dBeach = math.sqrt((x - BEACH.x) ^ 2 + (z - BEACH.z) ^ 2)
	if dBeach < 90 and dCoast < 60 then
		local share = smooth((90 - dBeach) / 40)
		local beachH = L.Water - 1.5 + dCoast / 60 * (base - L.Water + 1.5)
		return base + (beachH - base) * share, if share > 0.4 then "Beach" else kind
	end
	-- the coast drops just below the sea within the last 22 studs
	if dCoast < 22 then
		local h = L.Water - 1.6 + (base - L.Water + 1.6) * smooth(dCoast / 22)
		return h, if h < L.Water + 1.5 then "Beach" else kind
	end
	return base, kind
end

local function onPath(x: number, z: number): boolean
	local half = RomeLayout.PathWidth / 2
	for _, path in RomeLayout.Paths do
		for i = 1, #path.points - 1 do
			local a, b = path.points[i], path.points[i + 1]
			if x > math.min(a.x, b.x) - half and x < math.max(a.x, b.x) + half and z > math.min(a.z, b.z) - half and z < math.max(a.z, b.z) + half then
				if RomeLayout.distanceToSegment(x, z, a, b) < half then
					return true
				end
			end
		end
	end
	return false
end

-- Writes the island and the sea. Yields between chunks.
function IslandBuilder.buildTerrain()
	local terrain = Workspace.Terrain
	terrain:Clear()
	terrain.WaterColor = Color3.fromRGB(38, 112, 132)
	terrain.WaterTransparency = 0.55
	terrain.WaterWaveSize = 0.12
	terrain.WaterReflectance = 0.6
	local disc = RomeLayout.Disc
	-- sea floor and water over the whole disc
	local center = Vector3.new(disc.x, 0, disc.z)
	local axis = CFrame.new(center) -- cylinder axis is the part's Y axis
	terrain:FillCylinder(axis + Vector3.new(0, Y0 + 3, 0), 6, disc.radius, Enum.Material.Sand)
	terrain:FillCylinder(axis + Vector3.new(0, (Y0 + 6 + L.Water) / 2, 0), L.Water - Y0 - 6, disc.radius, Enum.Material.Water)
	task.wait()
	-- height grid
	local nx, nz = math.floor((X1 - X0) / GRID) + 1, math.floor((Z1 - Z0) / GRID) + 1
	local heights: { { number } } = table.create(nx)
	local kinds: { { Kind } } = table.create(nx)
	for i = 1, nx do
		local hs: { number }, ks: { Kind } = table.create(nz), table.create(nz)
		for j = 1, nz do
			local h, k = IslandBuilder.heightAt(X0 + (i - 1) * GRID, Z0 + (j - 1) * GRID)
			hs[j], ks[j] = h, k :: any
		end
		heights[i], kinds[i] = hs, ks
		if i % 24 == 0 then
			task.wait()
		end
	end
	local function heightOf(x: number, z: number): number
		local fx, fz = (x - X0) / GRID, (z - Z0) / GRID
		local i, j = math.clamp(math.floor(fx), 0, nx - 2), math.clamp(math.floor(fz), 0, nz - 2)
		local u, w = fx - i, fz - j
		local a, b = heights[i + 1][j + 1], heights[i + 2][j + 1]
		local c, d = heights[i + 1][j + 2], heights[i + 2][j + 2]
		return (a * (1 - u) + b * u) * (1 - w) + (c * (1 - u) + d * u) * w
	end
	local function kindOf(x: number, z: number): Kind
		local i, j = math.clamp(math.floor((x - X0) / GRID + 0.5), 0, nx - 1), math.clamp(math.floor((z - Z0) / GRID + 0.5), 0, nz - 1)
		return kinds[i + 1][j + 1]
	end
	-- voxels, chunk by chunk
	local CHUNK = 64
	local layers = (Y1 - Y0) / VOXEL
	local air, water = Enum.Material.Air, Enum.Material.Water
	for cx = X0, X1 - 1, CHUNK * VOXEL do
		for cz = Z0, Z1 - 1, CHUNK * VOXEL do
			local sx = math.min(CHUNK, (X1 - cx) // VOXEL)
			local sz = math.min(CHUNK, (Z1 - cz) // VOXEL)
			local materials, occupancy = table.create(sx), table.create(sx)
			for i = 1, sx do
				local mi, oi = table.create(layers), table.create(layers)
				for k = 1, layers do
					mi[k], oi[k] = table.create(sz), table.create(sz)
				end
				materials[i], occupancy[i] = mi, oi
				local x = cx + (i - 0.5) * VOXEL
				for j = 1, sz do
					local z = cz + (j - 0.5) * VOXEL
					local h = heightOf(x, z)
					local kind = kindOf(x, z)
					local slope = math.max(math.abs(heightOf(x + VOXEL, z) - h), math.abs(heightOf(x, z + VOXEL) - h)) / VOXEL
					local solid: Enum.Material = Enum.Material.Grass
					if kind == "Town" then
						solid = Enum.Material.Ground
					elseif kind == "Sea" or kind == "Basin" or kind == "Beach" then
						solid = Enum.Material.Sand
					elseif kind == "Forest" then
						solid = Enum.Material.LeafyGrass
					end
					if kind ~= "Town" and kind ~= "Sea" and kind ~= "Basin" then
						if slope > 0.75 then
							solid = Enum.Material.Rock
						elseif onPath(x, z) then
							solid = Enum.Material.Ground
						end
					end
					for k = 1, layers do
						local y0 = Y0 + (k - 1) * VOXEL
						local occ = math.clamp((h - y0) / VOXEL, 0, 1)
						if occ > 0 then
							mi[k][j], oi[k][j] = solid, occ
						elseif y0 + VOXEL <= L.Water + 0.01 then
							mi[k][j], oi[k][j] = water, 1
						elseif y0 < L.Water then
							mi[k][j], oi[k][j] = water, (L.Water - y0) / VOXEL
						else
							mi[k][j], oi[k][j] = air, 0
						end
					end
				end
			end
			local region = Region3.new(Vector3.new(cx, Y0, cz), Vector3.new(cx + sx * VOXEL, Y1, cz + sz * VOXEL))
			terrain:WriteVoxels(region, VOXEL, materials, occupancy)
			task.wait()
		end
	end
end

-- The rim of the world disc: rock lip, spill-over, falling curtain, mist and clouds below.
function IslandBuilder.buildRim(parent: Instance): Folder
	local folder = Parts.folder(parent, "WorldRim")
	local disc = RomeLayout.Disc
	local R = disc.radius
	local segments = 120
	local W = L.Water
	local rock = Color3.fromRGB(96, 88, 78)
	local fall = Color3.fromRGB(150, 205, 225)
	for i = 0, segments - 1 do
		local a0, a1 = i / segments * 2 * math.pi, (i + 1) / segments * 2 * math.pi
		local am = (a0 + a1) / 2
		local chord = 2 * (R + 12) * math.sin(math.pi / segments) + 1
		local dir = Vector3.new(math.cos(am), 0, math.sin(am))
		local function ringFrame(radius: number, y: number): CFrame
			local p = Vector3.new(disc.x, y, disc.z) + dir * radius
			return CFrame.lookAt(p, p + dir) -- -Z points outward
		end
		-- the lip: rock under the edge, from deep below up to just under the water
		Parts.part(folder, "RimRock", ringFrame(R + 4, (W - 1.2 - 160) / 2), Vector3.new(chord, W - 1.2 + 160, 14), rock, { material = Enum.Material.Rock, shadow = false })
		-- water spilling over: a thin sheet curving down past the lip, then the curtain
		local spill = Parts.wedge(folder, "SpillOver", ringFrame(R + 12, W - 1.6), Vector3.new(chord, 3.2, 6), fall, { collide = false, shadow = false, material = Enum.Material.Glass })
		spill.Transparency = 0.35
		local curtain = Parts.decor(folder, "Waterfall", ringFrame(R + 14.5, W - 3 - 120), Vector3.new(chord, 240, 1.2), fall, Enum.Material.Glass)
		curtain.Transparency = 0.3
		if i % 10 == 0 then
			local mist = Instance.new("ParticleEmitter")
			mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
			mist.Color = ColorSequence.new(Color3.fromRGB(235, 245, 250))
			mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 22) })
			mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
			mist.Lifetime = NumberRange.new(5, 8)
			mist.Rate = 3
			mist.Speed = NumberRange.new(2, 4)
			mist.SpreadAngle = Vector2.new(40, 40)
			mist.Parent = curtain
		end
		-- clouds far below the disc
		if i % 4 == 0 then
			local cloud = Parts.part(folder, "Cloud", ringFrame(R + 40 + (i % 3) * 30, -230 - (i % 5) * 12), Vector3.new(90, 34, 70), Color3.fromRGB(250, 250, 252), { collide = false, shadow = false, shape = Enum.PartType.Ball, material = Enum.Material.SmoothPlastic })
			cloud.Transparency = 0.15
		end
	end
	return folder
end

-- Light for an open island day: a soft haze that still shows the rim from the beach.
function IslandBuilder.setupAtmosphere()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.24
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(214, 222, 230)
	atmosphere.Decay = Color3.fromRGB(150, 170, 190)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 0.6
	atmosphere.Parent = Lighting
	Workspace.FallenPartsDestroyHeight = -900
end

return IslandBuilder
