-- Checks the deterministic plan of Rome (src/hub/server/Rome/RomeLayout.luau) outside Roblox:
-- house counts per type, stable ids, no overlapping houses, every house inside the walls, on its
-- terrace, clear of streets, squares, the forum, the temple and the water, every crossing on its
-- street, the outlines nested (town inside the island inside the world disc), and the area.
-- Run: scripts/test-rome-layout.ps1 -LuauPath <luau.exe>
local checks, failures = 0, {}
local function check(value, message)
	checks += 1
	if not value then table.insert(failures, message) end
end

-- INSERT_LAYOUT
local R = RomeLayout

local houses = R.houses()
local counts = {}
local ids = {}
for _, h in houses do
	counts[h.type] = (counts[h.type] or 0) + 1
	check(not ids[h.id], "unique house id " .. h.id)
	ids[h.id] = true
end
check(#houses == 80, "80 houses besides temple and Colosseum, got " .. #houses)
for kind, target in R.TypeTargets do
	check(counts[kind] == target, ("%s: %d houses (target %d)"):format(kind, counts[kind] or 0, target))
end
local specials = {}
for _, h in houses do
	if h.special then specials[h.special] = (specials[h.special] or 0) + 1 end
	check(h.open == (h.special == "Smithy"), "only the smithy is open in the MVP: " .. h.id)
	check(h.door.fx == h.fx and h.door.fz == h.fz and math.abs(h.fx) + math.abs(h.fz) == 1, "door anchor faces the street: " .. h.id)
end
check(specials.Smithy == 1 and specials.Bakery == 1 and specials.Tavern == 3, "smithy, bakery and three taverns among the 80")
for _, name in { "ZUM GOLDENEN KORN", "ZUM LETZTEN MEILENSTEIN", "ZUM SALZIGEN ANKER" } do
	local found = false
	for _, h in houses do if h.name == name then found = true end end
	check(found, "tavern " .. name)
end

-- footprints (axis-aligned: w along the street, d into the block)
local function box(h)
	local hx = if h.fx ~= 0 then h.d / 2 else h.w / 2
	local hz = if h.fx ~= 0 then h.w / 2 else h.d / 2
	return h.x - hx, h.x + hx, h.z - hz, h.z + hz
end
for i, a in houses do
	local ax0, ax1, az0, az1 = box(a)
	for j = i + 1, #houses do
		local b = houses[j]
		local bx0, bx1, bz0, bz1 = box(b)
		check(ax1 <= bx0 + 0.01 or bx1 <= ax0 + 0.01 or az1 <= bz0 + 0.01 or bz1 <= az0 + 0.01, "houses overlap: " .. a.id .. " / " .. b.id)
	end
end

local function corners(h)
	local x0, x1, z0, z1 = box(h)
	return { { x0, z0 }, { x1, z0 }, { x0, z1 }, { x1, z1 }, { (x0 + x1) / 2, z0 }, { (x0 + x1) / 2, z1 }, { x0, (z0 + z1) / 2 }, { x1, (z0 + z1) / 2 } }
end
local plaza = R.Plaza.outer
for _, h in houses do
	local x0, x1, z0, z1 = box(h)
	for _, c in corners(h) do
		check(R.isInTown(c[1], c[2]), "house inside the walls: " .. h.id)
		check(R.distanceToOutline(c[1], c[2], R.Wall, true) >= R.WallThickness / 2 + 0.5, "house clear of the wall: " .. h.id)
		check(not R.isWater(c[1], c[2]) and R.distanceToOutline(c[1], c[2], R.Basin) >= R.QuayWidth - 0.01 or not R.isWater(c[1], c[2]) and h.district ~= "Hafen" and R.distanceToOutline(c[1], c[2], R.Basin) > 20, "house behind the quay: " .. h.id)
		check(R.levelAt(c[1], c[2]) == h.level, "house on one terrace: " .. h.id)
		-- outside the Colosseum's paved ring
		local ex, ez = c[1] / (76 + plaza), c[2] / (48 + plaza)
		check(ex * ex + ez * ez > 1, "house outside the Colosseum plaza: " .. h.id)
	end
	-- clear of every street corridor (centreline distance > half width), sampled along the outline
	for _, street in R.Streets do
		local half = R.halfWidth(street.kind)
		for s = 0, 1, 0.05 do
			for _, edge in { { x0 + (x1 - x0) * s, z0 }, { x0 + (x1 - x0) * s, z1 }, { x0, z0 + (z1 - z0) * s }, { x1, z0 + (z1 - z0) * s } } do
				for k = 1, #street.points - 1 do
					local a, b = street.points[k], street.points[k + 1]
					local d = R.distanceToSegment(edge[1], edge[2], { x = a.x, z = a.z }, { x = b.x, z = b.z })
					check(d >= half + 0.4, ("house %s stands in street %s (%.1f)"):format(h.id, street.id, d))
				end
			end
		end
	end
	-- the forum, the temple with its stairs and ramp, the forecourt
	local F, T, C = R.Forum, R.Temple, R.Forecourt
	local function apart(ax0, ax1, az0, az1) return x1 <= ax0 or ax1 <= x0 or z1 <= az0 or az1 <= z0 end
	check(apart(F.x0, F.x1, F.z0 - 2, F.z1 + 2), "house clear of the forum: " .. h.id)
	check(apart(T.x0 - 2, T.stairsTo, T.z0 - 2, T.ramp.z1 + 1), "house clear of the temple: " .. h.id)
	check(apart(C.x0, C.x1, C.z0, C.z1), "house clear of the forecourt: " .. h.id)
	-- the facade looks at a street within a few studs (or the forum / quay)
	local dx, dz = h.door.x + h.fx * 3, h.door.z + h.fz * 3
	local near = R.nearestStreet(dx, dz)
	if h.square then
		local square = R.Squares[h.square]
		check(square and (R.pointInPolygon(dx, dz, square) or R.distanceToOutline(dx, dz, square) < 4), "house faces its square: " .. h.id)
	else
		check(near < 14 or h.district == "Hafen" or h.district == "Kolosseum", "house faces a street: " .. h.id .. " (" .. math.floor(near) .. ")")
	end
end

-- work yards, garden walls and quay arcades: clear of streets, houses and water, on one terrace
local function clearOfStreets(x, z, margin)
	for _, street in R.Streets do
		for k = 1, #street.points - 1 do
			local a, b = street.points[k], street.points[k + 1]
			if R.distanceToSegment(x, z, { x = a.x, z = a.z }, { x = b.x, z = b.z }) < R.halfWidth(street.kind) + margin then return false, street.id end
		end
	end
	return true
end
local function inHouse(x, z, margin)
	for _, h in houses do
		local x0, x1, z0, z1 = box(h)
		if x > x0 + margin and x < x1 - margin and z > z0 + margin and z < z1 - margin then return h.id end
	end
	return nil
end
for _, yard in R.Yards do
	for x = yard.x0, yard.x1, 2 do
		for z = yard.z0, yard.z1, 2 do
			check(inHouse(x, z, 0.01) == nil, "work yard outside the houses: " .. yard.id)
			check((clearOfStreets(x, z, 0.4)), "work yard off the street: " .. yard.id)
			check(R.levelAt(x, z) == yard.level and R.isInTown(x, z), "work yard on its terrace: " .. yard.id)
		end
	end
end
for _, w in R.YardWalls do
	local length = math.sqrt((w.b.x - w.a.x) ^ 2 + (w.b.z - w.a.z) ^ 2)
	for t = 0, length, 0.5 do
		local x, z = w.a.x + (w.b.x - w.a.x) * t / length, w.a.z + (w.b.z - w.a.z) * t / length
		local ok, street = clearOfStreets(x, z, 0.4 + 0.4)
		check(ok, "garden wall " .. w.id .. " in street " .. tostring(street))
		check(inHouse(x, z, 0.45) == nil, "garden wall " .. w.id .. " through house " .. tostring(inHouse(x, z, 0.45)))
		check(R.levelAt(x, z) == w.level and R.isInTown(x, z) and not R.isWater(x, z), "garden wall on its terrace: " .. w.id)
	end
end
for _, arcade in R.QuayArcades do
	for x = arcade.x0, arcade.x1, 1 do
		for z = arcade.z0, arcade.z1, 2 do
			check(inHouse(x, z, 0.01) == nil and (clearOfStreets(x, z, 0.3)), "quay arcade clear of houses and streets: " .. arcade.id)
			check(not R.isWater(x, z) and R.distanceToOutline(x, z, R.Basin) >= R.QuayWidth, "quay arcade behind the quay: " .. arcade.id)
			check(R.levelAt(x, z) == R.Levels.Harbor, "quay arcade on the harbour terrace: " .. arcade.id)
		end
	end
end

-- terraces: no house straddles a retaining wall; streets ramp only where they cross one
for _, street in R.Streets do
	for k = 1, #street.points - 1 do
		local a, b = street.points[k], street.points[k + 1]
		local length = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		local slope = math.abs(b.y - a.y) / length
		check(slope <= 0.14, ("ramp of %s segment %d is gentle (%.1f%%)"):format(street.id, k, slope * 100))
		if a.y == b.y then
			check(R.levelAt(a.x, a.z) == a.y or street.id == "Landtorstrasse" and k == 3, ("street %s point %d lies on its terrace"):format(street.id, k))
		end
	end
	for _, p in street.points do
		check(R.isInTown(p.x, p.z) or street.id == "Landtorstrasse", "street inside the town: " .. street.id)
	end
end

-- crossings: on a straight, level stretch of their street
for _, crossing in R.Crossings do
	local street = R.street(crossing.street)
	check(street ~= nil, "crossing street exists: " .. crossing.id)
	if street then
		local a, b = street.points[crossing.segment], street.points[crossing.segment + 1]
		check(a and b and a.y == b.y, "crossing on a level stretch: " .. crossing.id)
		check(crossing.stones >= 1 and crossing.stones <= 3 and (street.kind == "Main") == (crossing.stones == 3), "three stones on main streets, one or two in lanes: " .. crossing.id)
	end
end

-- anchors inside the town / on the island
for name, anchor in R.Anchors do
	if name == "Berth" then
		check(R.isWater(anchor.x, anchor.z), "berth on the water")
	elseif name == "SecretRuin" or name == "Viewpoint" or name == "Clearing" or name == "Beach" then
		check(R.isOnIsland(anchor.x, anchor.z) and not R.isInTown(anchor.x, anchor.z), "outside anchor on the island: " .. name)
	else
		check(R.isInTown(anchor.x, anchor.z) and not R.isWater(anchor.x, anchor.z), "anchor in town: " .. name)
	end
end
-- the trireme berth: free water along the straight north quay
local berth = R.Anchors.Berth
for _, dx in { -R.Trireme.length / 2, 0, R.Trireme.length / 2 } do
	for _, dz in { -R.Trireme.beam / 2, R.Trireme.beam / 2 } do
		check(R.isWater(berth.x + dx, berth.z + dz) and R.distanceToOutline(berth.x + dx, berth.z + dz, R.Basin) >= 1, "trireme outline on free water")
	end
end

-- outlines nest: wall inside the coast, coast inside the disc with open sea around it
for _, p in R.Wall do check(R.pointInPolygon(p.x, p.z, R.Coast), ("wall point %d,%d on the island"):format(p.x, p.z)) end
local disc = R.Disc
local closest = math.huge
for _, p in R.Coast do
	local d = disc.radius - math.sqrt((p.x - disc.x) ^ 2 + (p.z - disc.z) ^ 2)
	closest = math.min(closest, d)
end
check(closest >= 300, "at least 300 studs of sea between coast and rim, got " .. math.floor(closest))
for _, gate in R.Gates do
	check(R.distanceToOutline(gate.x, gate.z, R.Wall, true) < 1, "gate on the wall: " .. gate.name)
end
for _, path in R.Paths do
	for _, p in path.points do
		check(R.isOnIsland(p.x, p.z), "path point on the island: " .. path.id)
	end
end

local area, walled, basin = R.cityArea()
local island = R.polygonArea(R.Coast)
check(island - walled >= 1.8 * area, "the countryside is clearly larger than the town")
print(("town %.0f stud^2 (walled %.0f minus basin water %.0f), island %.0f stud^2, countryside %.1fx the town"):format(area, walled, basin, island, (island - walled) / area))
for kind, n in counts do print(("  %-10s %2d"):format(kind, n)) end
for i, message in failures do
	if i <= 40 then print("FAIL " .. message) end
end
assert(#failures == 0, #failures .. " layout checks failed")
print(("PASS: Rome layout, %d houses, %d streets, %d crossings (%d checks)"):format(#houses, #R.Streets, #R.Crossings, checks))
