--!strict
-- The fortified harbour inside the walls: quays of big stone plates round the basin (the
-- Uferstrasse) with a clearly marked edge, bollards and ropes, the moles out to the watch posts,
-- the straight berth on the north quay kept free for a later trireme (only its outline is drawn,
-- non-colliding), the reserved travel point, and cargo along the warehouses. Fishing boats float
-- beside the south quay.
local RomeLayout = require(script.Parent.RomeLayout)
local Parts = require(script.Parent.RomeParts)

local C = Parts.Colors
local Harbor = {}

export type Result = { berth: CFrame, travelPoint: BasePart }

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

function Harbor.build(parent: Instance): Result
	local model = Parts.model(parent, "Harbor")
	local H, W = RomeLayout.Levels.Harbor, RomeLayout.Levels.Water
	local basin = RomeLayout.Basin
	local n = #basin
	local function bollard(x: number, z: number)
		Parts.column(model, "Bollard", CFrame.new(x, H, z), 1.6, 1, C.StoneDark, { material = Enum.Material.Basalt })
		Parts.column(model, "BollardCap", CFrame.new(x, H + 1.6, z), 0.3, 1.3, C.StoneDark, { collide = false, material = Enum.Material.Basalt })
	end
	-- quays: one slab per basin edge (the mouth between the mole heads stays open)
	for i = 1, n - 1 do
		local a, b = basin[i], basin[i + 1]
		local pa, pb = v(a.x, H, a.z), v(b.x, H, b.z)
		local along = (pb - pa)
		local length = along.Magnitude
		local dir = along.Unit
		local normal = v(-dir.Z, 0, dir.X)
		local mid = (pa + pb) / 2
		if RomeLayout.isWater(mid.X + normal.X * 2, mid.Z + normal.Z * 2) then
			normal = -normal -- the quay lies on the land side
		end
		local mole = i <= 2 or i >= n - 2
		local width = if mole then RomeLayout.MoleWidth else RomeLayout.QuayWidth
		local extend = width * 0.5 + 1
		local center = mid + normal * (width / 2)
		local frame = CFrame.lookAt(center, center + dir)
		local parity = (i % 2) * 0.01
		Parts.part(model, "Quay", frame * CFrame.new(0, -(H - W + 6) / 2 - parity, 0), v(width, H - W + 6, length + extend * 2), C.Limestone, { material = Enum.Material.Slate, shadow = false })
		-- the quay edge: a light coping band level with the plates, a dark waterline below
		local edge = CFrame.lookAt(mid + normal * 0.6, mid + normal * 0.6 + dir)
		Parts.decor(model, "QuayCoping", edge * CFrame.new(0, 0.03, 0), v(1.2, 0.08, length), C.Kerb, Enum.Material.Limestone)
		Parts.decor(model, "Waterline", edge * CFrame.new(0, W - H + 0.4, -0.0) * CFrame.new(-0.61, 0, 0), v(0.05, 1, length), Color3.fromRGB(70, 84, 70), Enum.Material.Slate)
		local count = math.max(1, math.floor(length / 12))
		for k = 1, count do
			local t = (k - 0.5) / count
			local p = pa + along * t + normal * 1.4
			bollard(p.X, p.Z)
		end
	end
	-- the berth on the straight north quay: free water, a sign, a gangway mark and the outline
	local berthAnchor = RomeLayout.Anchors.Berth
	local berth = CFrame.new(berthAnchor.x, W, berthAnchor.z)
	local outline = Parts.model(model, "TriremeBerth")
	outline:SetAttribute("Reserved", "Trireme")
	local len, beam = RomeLayout.Trireme.length, RomeLayout.Trireme.beam
	for _, p in { { 0, -beam / 2, len, 0.3 }, { 0, beam / 2, len, 0.3 }, { -len / 2, 0, 0.3, beam }, { len / 2, 0, 0.3, beam } } do
		local mark = Parts.decor(outline, "BerthOutline", berth * CFrame.new(p[1], 0.15, p[2]), v(p[3], 0.1, p[4]), C.Gold, Enum.Material.Neon)
		mark.Transparency = 0.55
	end
	local tp = RomeLayout.Anchors.TravelPoint
	local travel = Parts.part(model, "TravelPoint", CFrame.new(tp.x, tp.y + 2.5, tp.z), v(4, 5, 4), C.Gold, { collide = false, transparency = 1, shadow = false })
	travel:SetAttribute("Reserved", "Travel")
	Parts.decor(model, "GangwayMark", CFrame.new(tp.x, tp.y + 0.04, tp.z + 4), v(4, 0.08, 5), C.Bronze, Enum.Material.Metal)
	local signPost = CFrame.new(tp.x + 5, tp.y, tp.z - 3)
	Parts.part(model, "BerthSignPost", signPost * CFrame.new(0, 3, 0), v(0.5, 6, 0.5), C.Timber, { material = Enum.Material.Wood })
	Parts.sign(model, "BerthSign", signPost * CFrame.new(0, 5.6, 0) * CFrame.Angles(0, math.pi, 0), Vector2.new(8, 2), "LIEGEPLATZ", "Die Trireme folgt · Reisen bald", C.TimberDark)
	-- cargo along the warehouses and the harbour tavern
	for i, p in { { -590, -95 }, { -584, -96 }, { -560, -95 }, { -575, 96 }, { -540, 97 }, { -592, 96 } } do
		local base = CFrame.new(p[1], H, p[2]) * CFrame.Angles(0, i * 0.4, 0)
		if i % 2 == 0 then
			Parts.part(model, "Crate", base * CFrame.new(0, 1, 0), v(2, 2, 2), C.Timber, { material = Enum.Material.WoodPlanks })
			Parts.decor(model, "Crate", base * CFrame.new(0.3, 2.6, 0.2), v(1.4, 1.2, 1.4), C.TimberDark, Enum.Material.WoodPlanks)
		else
			for k = 0, 2 do
				Parts.part(model, "Amphora", base * CFrame.new(k * 1.2, 1.1, 0), v(1, 2.2, 1), C.Terracotta, { collide = false, shape = Enum.PartType.Ball, material = Enum.Material.Slate })
			end
		end
	end
	-- two small fishing boats by the south quay
	for i, x in { -600, -630 } do
		local boat = CFrame.new(x, W + 0.4, 66) * CFrame.Angles(0, 0.1 * i, 0)
		Parts.decor(model, "BoatHull", boat, v(3.6, 1.2, 10), C.Timber, Enum.Material.WoodPlanks)
		Parts.decor(model, "BoatMast", boat * CFrame.new(0, 4, -1), v(0.3, 7, 0.3), C.TimberDark, Enum.Material.Wood)
	end
	return { berth = berth, travelPoint = travel }
end

return Harbor
