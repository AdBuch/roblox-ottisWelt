--!strict
-- Pompeian streets as modules (RomeLayout.Streets / Sections / Crossings):
--   * carriageway of dark, irregular stone paving, one smooth slab per street piece (no physics per
--     cobble); wheel ruts are painted detail
--   * raised sidewalks on both sides, framed by lighter kerb stones. An invisible wedge along every
--     kerb turns the visible step into a flat ramp, so walking never needs a jump and the camera
--     does not hop
--   * the cross section continues at junctions: a sidewalk stops where another street's
--     carriageway begins, a carriageway gives way to the one with priority (main streets first)
--   * ramps between the terraces keep the section; a filled body carries them and low parapets
--     edge the drop
--   * stepping-stone crossings: a row of rounded stones across the street, their tops level with
--     the sidewalks, open wheel gaps between them; one invisible plank at sidewalk height with
--     flat run-ins carries every walker over them. Lowered crossings beside the important ones.
-- Main streets are lit by bronze lamp posts; lanes are narrower, lower and unlit.
local RomeLayout = require(script.Parent.RomeLayout)
local Parts = require(script.Parent.RomeParts)

type Street = RomeLayout.Street
local C = Parts.Colors

local StreetBuilder = {}

local PRIORITY = { Shore = 3, Main = 2, Lane = 1 }

type Segment = { street: Street, index: number, ax: number, az: number, ay: number, bx: number, bz: number, by: number, length: number, dx: number, dz: number }

local function segmentsOf(street: Street): { Segment }
	local list = {}
	for i = 1, #street.points - 1 do
		local a, b = street.points[i], street.points[i + 1]
		local dx, dz = b.x - a.x, b.z - a.z
		local length = math.sqrt(dx * dx + dz * dz)
		table.insert(list, { street = street, index = i, ax = a.x, az = a.z, ay = a.y, bx = b.x, bz = b.z, by = b.y, length = length, dx = dx / length, dz = dz / length })
	end
	return list
end

local allSegments: { Segment } = {}
local function rebuildIndex()
	table.clear(allSegments)
	for _, street in RomeLayout.Streets do
		for _, s in segmentsOf(street) do
			table.insert(allSegments, s)
		end
	end
end

local function order(street: Street): number
	for i, s in RomeLayout.Streets do
		if s == street then
			return i
		end
	end
	return 0
end

-- Is (x, z) on the carriageway of another street (one that wins over `own` when `priorityOnly`)?
local function onOtherRoad(x: number, z: number, own: Street, priorityOnly: boolean, margin: number): boolean
	for _, s in allSegments do
		if s.street ~= own then
			local section = RomeLayout.Sections[s.street.kind]
			local wins = PRIORITY[s.street.kind] > PRIORITY[own.kind] or (PRIORITY[s.street.kind] == PRIORITY[own.kind] and order(s.street) < order(own))
			if not priorityOnly or wins then
				local d = RomeLayout.distanceToSegment(x, z, { x = s.ax, z = s.az }, { x = s.bx, z = s.bz })
				if d < section.road / 2 + margin then
					return true
				end
			end
		end
	end
	return false
end

local function inRect(x: number, z: number, r: any, margin: number): boolean
	return x > r.x0 - margin and x < r.x1 + margin and z > r.z0 - margin and z < r.z1 + margin
end

-- Areas where no sidewalk is built (squares and platforms with their own edges).
local function openArea(x: number, z: number): boolean
	return inRect(x, z, RomeLayout.Forum, 0.5) or inRect(x, z, RomeLayout.Forecourt, 0)
end

-- Height of a street piece at distance u along it.
local function heightAt(s: Segment, u: number): number
	return s.ay + (s.by - s.ay) * math.clamp(u / s.length, 0, 1)
end

-- A slab following the piece from u0 to u1, offset `side` across, `width` wide, top `lift` above
-- the street surface, `thickness` deep.
local function slab(parent: Instance, name: string, s: Segment, u0: number, u1: number, side: number, width: number, lift: number, thickness: number, color: Color3, material: Enum.Material, collide: boolean): BasePart
	local nx, nz = -s.dz, s.dx
	local function point(u: number): Vector3
		return Vector3.new(s.ax + s.dx * u + nx * side, heightAt(s, u) + lift, s.az + s.dz * u + nz * side)
	end
	local a, b = point(u0), point(u1)
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	local frame = CFrame.lookAt(mid, b)
	local p = Parts.part(parent, name, frame * CFrame.new(0, -thickness / 2, 0), Vector3.new(width, thickness, length), color, { material = material, collide = collide, shadow = false })
	return p
end

-- Intervals [u0, u1] along a piece where `free(u)` holds (sampled every half stud).
local function intervals(from: number, to: number, free: (u: number) -> boolean): { { number } }
	local list = {}
	local start: number? = nil
	local u = from
	while u <= to + 1e-6 do
		local ok = free(u)
		if ok and not start then
			start = u
		elseif not ok and start then
			if u - 0.5 - start >= 0.9 then
				table.insert(list, { start, u - 0.5 })
			end
			start = nil
		end
		u += 0.5
	end
	if start and to - start >= 0.9 then
		table.insert(list, { start, to })
	end
	return list
end

-- How far a piece reaches past a bend: covers the outer corner of the turn.
local function jointExtension(street: Street, index: number, atEnd: boolean, reach: number): number
	local points = street.points
	local p = if atEnd then index + 1 else index
	if p <= 1 or p >= #points then
		return 0
	end
	local a, b, c = points[p - 1], points[p], points[p + 1]
	local ux, uz = b.x - a.x, b.z - a.z
	local vx, vz = c.x - b.x, c.z - b.z
	local lu, lv = math.sqrt(ux * ux + uz * uz), math.sqrt(vx * vx + vz * vz)
	local cos = math.clamp((ux * vx + uz * vz) / (lu * lv), -1, 1)
	local turn = math.acos(cos)
	return reach * math.tan(math.min(turn, math.rad(80)) / 2) + 0.3
end

local function crossingsOn(street: Street, index: number): { RomeLayout.Crossing }
	local list = {}
	for _, crossing in RomeLayout.Crossings do
		if crossing.street == street.id and crossing.segment == index then
			table.insert(list, crossing)
		end
	end
	return list
end

-- One rounded stepping stone: a stadium of two half-round ends and a block (visual only).
local function stone(parent: Instance, base: CFrame, length: number, width: number, height: number)
	local color = C.Kerb
	Parts.decor(parent, "SteppingStone", base * CFrame.new(0, height / 2, 0), Vector3.new(width, height, length - width), color, Enum.Material.Limestone)
	for _, s in { -1, 1 } do
		Parts.column(parent, "SteppingStoneEnd", base * CFrame.new(0, 0, s * (length - width) / 2), height, width, color, { collide = false, shadow = false, material = Enum.Material.Limestone })
	end
end

-- The crossing on piece `s` at distance u: stones across, the flat walking profile over them.
local function buildCrossing(parent: Instance, s: Segment, u: number, crossing: RomeLayout.Crossing)
	local section = RomeLayout.Sections[s.street.kind]
	local model = Parts.model(parent, "Crossing_" .. crossing.id)
	model:SetAttribute("Label", crossing.label)
	model:SetAttribute("Stones", crossing.stones)
	local y = heightAt(s, u)
	local center = Vector3.new(s.ax + s.dx * u, y, s.az + s.dz * u)
	-- frame: -Z along the street, X across it
	local frame = CFrame.lookAt(center, center + Vector3.new(s.dx, 0, s.dz))
	local stoneLength = if s.street.kind == "Main" then 3.4 else 2.8
	local stoneWidth = if s.street.kind == "Main" then 2.2 else 1.8
	local gap = if s.street.kind == "Main" then 1.6 else 1.1
	local count = crossing.stones
	local pitch = stoneWidth + gap
	for i = 1, count do
		local x = (i - (count + 1) / 2) * pitch
		-- stones stand across the street (their long side along it), tops level with the sidewalks
		stone(model, frame * CFrame.new(x, 0, 0), stoneLength, stoneWidth, section.kerb)
	end
	-- the walking profile: one plank at sidewalk height, flat run-ins along the street both ways
	local run = 2.6
	Parts.collider(model, "CrossingDeck", frame * CFrame.new(0, section.kerb / 2, 0), Vector3.new(section.road + 0.2, section.kerb, stoneLength))
	for _, dir in { -1, 1 } do
		-- the wedge rises toward the deck: its +Z must point at the deck
		local at = frame * CFrame.new(0, section.kerb / 2, dir * (stoneLength / 2 + run / 2))
		Parts.colliderWedge(model, "CrossingRunIn", at * CFrame.Angles(0, if dir > 0 then math.pi else 0, 0), Vector3.new(section.road + 0.2, section.kerb, run))
	end
	-- and across the street at both ends: step-free even where no sidewalk meets the stones
	-- (a lane's mouth); where a sidewalk does, the run-in stays under its surface
	for _, dir in { -1, 1 } do
		local at = frame * CFrame.new(dir * (section.road / 2 + 0.1 + run / 2), section.kerb / 2, 0)
		Parts.colliderWedge(model, "CrossingRunIn", at * CFrame.Angles(0, if dir > 0 then -math.pi / 2 else math.pi / 2, 0), Vector3.new(stoneLength, section.kerb, run))
	end
	if crossing.id == "Forumseingang" then
		-- the clearest example: a bronze inlay and a lamp at each end
		Parts.decor(model, "BronzeInlay", frame * CFrame.new(0, 0.02, stoneLength / 2 + 0.8), Vector3.new(section.road - 1, 0.04, 0.35), C.Bronze, Enum.Material.Metal)
		for _, side in { -1, 1 } do
			Parts.lampPost(model, frame * CFrame.new(side * (section.road / 2 + section.walk / 2 + 0.6), section.kerb, 0))
		end
	end
end

-- Builds every street of the town into `parent`. Returns the crossing CFrames by id.
function StreetBuilder.build(parent: Instance): { [string]: CFrame }
	rebuildIndex()
	local folder = Parts.folder(parent, "Streets")
	local crossingFrames: { [string]: CFrame } = {}
	for _, street in RomeLayout.Streets do
		local section = RomeLayout.Sections[street.kind]
		local model = Parts.model(folder, "Street_" .. street.id)
		model:SetAttribute("Name", street.name)
		model:SetAttribute("Kind", street.kind)
		local half = section.road / 2
		local lampTurn = 0
		for _, s in segmentsOf(street) do
			local parity = (s.index % 2) * 0.012 -- overlapping joints never share a surface
			local reach = half + section.walk
			local e0 = jointExtension(street, s.index, false, reach)
			local e1 = jointExtension(street, s.index, true, reach)
			local ramp = s.ay ~= s.by
			-- lowered crossings: gaps in both sidewalks, 6 studs past each crossing that has one
			local lowered: { number } = {}
			for _, crossing in crossingsOn(street, s.index) do
				local u = s.length * crossing.t
				buildCrossing(model, s, u, crossing)
				crossingFrames[crossing.id] = CFrame.new(s.ax + s.dx * u, heightAt(s, u), s.az + s.dz * u)
				if crossing.lowered then
					table.insert(lowered, u + 6)
				end
			end
			-- the carriageway, minus where a street with priority crosses
			local road = intervals(-e0, s.length + e1, function(u: number): boolean
				local x, z = s.ax + s.dx * u, s.az + s.dz * u
				return not onOtherRoad(x, z, street, true, -0.25)
			end)
			for _, span in road do
				local material = if street.kind == "Shore" then Enum.Material.Slate else Enum.Material.Cobblestone
				local color = if street.kind == "Shore" then C.Limestone else C.Paving
				slab(model, "Carriageway", s, span[1], span[2], 0, section.road + 0.05, -parity, 1.6, color, material, true)
				if street.kind == "Main" then
					for _, rut in { -1.7, 1.7 } do
						slab(model, "WheelRut", s, span[1] + 0.5, span[2] - 0.5, rut, 0.3, 0.02 - parity, 0.04, Color3.fromRGB(62, 58, 54), Enum.Material.Slate, false)
					end
				end
			end
			if ramp then
				-- the body under a ramp, down to the lower terrace, and parapets along the drop
				local low = math.min(s.ay, s.by)
				local high = math.max(s.ay, s.by)
				local upAtEnd = s.by > s.ay
				local width = section.road + 2 * section.walk
				local mid = Vector3.new((s.ax + s.bx) / 2, low + (high - low) / 2 - 1.6, (s.az + s.bz) / 2)
				local dir = Vector3.new(s.dx, 0, s.dz) * (if upAtEnd then 1 else -1)
				Parts.wedge(model, "RampBody", CFrame.lookAt(mid, mid - dir), Vector3.new(width, high - low, s.length), C.Stone, { material = Enum.Material.Limestone, shadow = false })
				for _, side in { -1, 1 } do
					slab(model, "RampParapet", s, 1, s.length - 1, side * (width / 2 - 0.35), 0.7, section.kerb + 1.1, 1.1, C.Kerb, Enum.Material.Limestone, true)
				end
			end
			-- sidewalks and kerbs on both sides
			if section.walk > 0 then
				for _, side in { -1, 1 } do
					local offset = half + section.walk / 2
					local spans = intervals(-e0, s.length + e1, function(u: number): boolean
						local nx, nz = -s.dz * side, s.dx * side
						local x, z = s.ax + s.dx * u + nx * offset, s.az + s.dz * u + nz * offset
						local kx, kz = s.ax + s.dx * u + nx * (half + 0.3), s.az + s.dz * u + nz * (half + 0.3)
						if openArea(x, z) or onOtherRoad(x, z, street, false, 0.1) or onOtherRoad(kx, kz, street, false, 0.1) then
							return false
						end
						for _, gapAt in lowered do
							if math.abs(u - gapAt) < 1.75 then
								return false
							end
						end
						return true
					end)
					for _, span in spans do
						local u0, u1 = span[1], span[2]
						slab(model, "Sidewalk", s, u0, u1, side * offset, section.walk, section.kerb - parity, 1.6 + section.kerb, C.Sidewalk, Enum.Material.Pavement, true)
						-- the visible kerb (lighter stone) and the invisible ramp over the step
						slab(model, "Kerb", s, u0, u1, side * (half + 0.3), 0.7, section.kerb + 0.04 - parity, 1.6 + section.kerb, C.Kerb, Enum.Material.Limestone, false)
						local kerbRun = 1.2
						local nx, nz = -s.dz * side, s.dx * side
						local ua, ub = u0, u1
						local a = Vector3.new(s.ax + s.dx * ua + nx * (half - kerbRun / 2), heightAt(s, ua), s.az + s.dz * ua + nz * (half - kerbRun / 2))
						local b = Vector3.new(s.ax + s.dx * ub + nx * (half - kerbRun / 2), heightAt(s, ub), s.az + s.dz * ub + nz * (half - kerbRun / 2))
						local along = b - a
						local mid = (a + b) / 2 + Vector3.new(0, section.kerb / 2, 0)
						-- X along the street (sloped on ramps), +Z across toward the sidewalk (the wedge's high side)
						local across = Vector3.new(nx, 0, nz)
						local ax = along.Unit
						if across:Cross(ax).Y < 0 then
							ax = -ax -- keep the wedge upright on both sides of the street
						end
						local frame = CFrame.fromMatrix(mid, ax, across:Cross(ax))
						Parts.colliderWedge(model, "KerbRamp", frame, Vector3.new(along.Magnitude, section.kerb, kerbRun))
						-- the end faces of a sidewalk get a short run-down as well
						for _, endU in { u0, u1 } do
							local inward = if endU == u0 then 1 else -1
							local ex = s.ax + s.dx * endU + nx * offset
							local ez = s.az + s.dz * endU + nz * offset
							local ey = heightAt(s, endU) + section.kerb / 2
							local p = Vector3.new(ex - s.dx * inward * 0.6, ey, ez - s.dz * inward * 0.6)
							Parts.colliderWedge(model, "WalkEnd", CFrame.lookAt(p, p - Vector3.new(s.dx, 0, s.dz) * inward), Vector3.new(section.walk - 0.6, section.kerb, 1.2))
						end
					end
					-- lamp posts on main streets, every 26 studs on alternating sides
					if street.kind == "Main" and not ramp then
						local u = 8
						while u < s.length - 4 do
							lampTurn += 1
							if lampTurn % 2 == (if side > 0 then 0 else 1) then
								local nx, nz = -s.dz * side, s.dx * side
								local x, z = s.ax + s.dx * u + nx * (half + section.walk - 0.9), s.az + s.dz * u + nz * (half + section.walk - 0.9)
								if not openArea(x, z) and not onOtherRoad(x, z, street, false, 1.5) then
									Parts.lampPost(model, CFrame.new(x, heightAt(s, u) + section.kerb, z))
								end
							end
							u += 26
						end
					end
				end
			end
		end
	end
	return crossingFrames
end

-- The flat walking profile of a crossing, for tests: deck height and run-in length.
StreetBuilder.CrossingRunIn = 2.6

return StreetBuilder
