--!strict
-- Places the animal crowd on the tribunes in small natural groups.
--   1. Seats are generated INSIDE the explicit zones (SpectatorZoneDefinitions): along each zone's
--      rows on seating tiers 2 / 4, spaced by SeatSpacing, skipping exclusions (staircases, return
--      door, imperial box).
--   2. Every seat is validated: a downward raycast must hit the seating, the point must lie outside
--      the arena floor bounds, clear of real-spectator spots, Otti's imperial seat and other animals.
--   3. Groups of 2-7 neighbours with 1-4 empty seats in between, one or two species per group,
--      small position / rotation variation, all facing the arena centre.
--   4. Each group gets a load priority (1 always, 2 from Normal, 3 at High importance); groups above
--      the current importance wait unparented in ServerStorage (not replicated, no cost).
-- Animals are anchored, non-colliding, CanQuery = false and CanTouch = false: they never affect
-- raycasts, projectiles, pathfinding or combat, and they are never combat targets.
--
-- Root cause of the old "spectators in the arena centre" bug: the server placed them correctly,
-- but the client cached each model's pivot (GetPivot) for its idle animation as soon as the tag
-- replicated - before PrimaryPart and the parts had arrived - so the cached pivot was the world
-- origin (= arena centre) and every animation frame moved the model there. Each animal now
-- carries its authoritative seat as the "BaseCFrame" attribute (replicated with the instance) and
-- a "PartCount"; the client only animates complete models from that attribute.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CrowdQualityConfig = require(ReplicatedStorage.Shared.CrowdQualityConfig)
local SpectatorZoneDefinitions = require(ReplicatedStorage.Shared.SpectatorZoneDefinitions)
local Arena = require(script.Parent.Arena)

type Zone = SpectatorZoneDefinitions.Zone
type Level = SpectatorZoneDefinitions.Level

type Species = {
	name: string,
	body: Color3,
	belly: Color3,
	ears: string, -- Round | Big | Long | Tuft | Pointy | None
	snout: number, -- snout length factor
	tail: string?, -- Bushy | Thin | nil
	shell: Color3?, -- tortoise
	beak: Color3?, -- bird
	scale: number,
}

local HIGH_IMPORTANCE: number = (CrowdQualityConfig.Importance :: any).High

local SPECIES: { Species } = {
	{ name = "Otter", body = Color3.fromRGB(110, 72, 46), belly = Color3.fromRGB(230, 210, 175), ears = "Round", snout = 1, scale = 1 },
	{ name = "Mouse", body = Color3.fromRGB(150, 150, 158), belly = Color3.fromRGB(225, 220, 220), ears = "Big", snout = 0.9, tail = "Thin", scale = 0.85 },
	{ name = "Rabbit", body = Color3.fromRGB(236, 230, 218), belly = Color3.fromRGB(250, 246, 240), ears = "Long", snout = 0.8, scale = 0.95 },
	{ name = "Squirrel", body = Color3.fromRGB(196, 106, 50), belly = Color3.fromRGB(240, 210, 170), ears = "Tuft", snout = 0.9, tail = "Bushy", scale = 0.9 },
	{ name = "Fox", body = Color3.fromRGB(214, 112, 46), belly = Color3.fromRGB(248, 236, 220), ears = "Pointy", snout = 1.5, tail = "Bushy", scale = 1 },
	{ name = "Wolf", body = Color3.fromRGB(122, 124, 130), belly = Color3.fromRGB(210, 210, 212), ears = "Pointy", snout = 1.6, tail = "Bushy", scale = 1.1 },
	{ name = "Bear", body = Color3.fromRGB(104, 70, 44), belly = Color3.fromRGB(160, 120, 86), ears = "Round", snout = 1.2, scale = 1.3 },
	{ name = "Crocodile", body = Color3.fromRGB(78, 112, 62), belly = Color3.fromRGB(196, 200, 140), ears = "None", snout = 2.4, tail = "Thin", scale = 1.1 },
	{ name = "Tortoise", body = Color3.fromRGB(128, 140, 96), belly = Color3.fromRGB(200, 190, 140), ears = "None", snout = 0.8, shell = Color3.fromRGB(110, 86, 52), scale = 0.95 },
	{ name = "Bird", body = Color3.fromRGB(70, 110, 170), belly = Color3.fromRGB(235, 225, 190), ears = "None", snout = 0, beak = Color3.fromRGB(240, 170, 60), scale = 0.8 },
}

type Seat = { cframe: CFrame, zone: Zone, row: number }

local SpectatorPlacementService = {}

local crowdFolder: Folder? = nil
local reserve: Folder? = nil
local groups: { { model: Folder, priority: number } } = {}
local importance: CrowdQualityConfig.Importance = "Normal"

local function part(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

-- One low-cost animal (8-14 anchored parts, no Humanoid).
local function buildAnimal(parent: Instance, base: CFrame, species: Species, rng: Random): Model
	local model = Instance.new("Model")
	model.Name = "Spectator_" .. species.name
	local s = species.scale * rng:NextNumber(0.9, 1.1)
	local BALL = Enum.PartType.Ball
	local body = part(model, "Body", Vector3.new(1.6, 1.9, 1.3) * s, base * CFrame.new(0, 0.95 * s, 0), species.body)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	part(model, "Belly", Vector3.new(1.0, 1.2, 0.3) * s, base * CFrame.new(0, 0.9 * s, -0.55 * s), species.belly, BALL)
	local headCF = base * CFrame.new(0, 2.15 * s, -0.05)
	part(model, "Head", Vector3.one * 1.25 * s, headCF, species.body, BALL)
	if species.snout > 0 then
		local length = 0.55 * species.snout
		part(model, "Snout", Vector3.new(0.55, 0.45, length) * s, headCF * CFrame.new(0, -0.18 * s, -(0.45 + length * 0.4) * s), species.belly, if species.snout < 1.3 then BALL else nil)
		part(model, "Nose", Vector3.one * 0.18 * s, headCF * CFrame.new(0, -0.08 * s, -(0.55 + length * 0.8) * s), Color3.fromRGB(40, 28, 24), BALL)
	end
	if species.beak then
		part(model, "Beak", Vector3.new(0.3, 0.25, 0.55) * s, headCF * CFrame.new(0, -0.1 * s, -0.7 * s), species.beak)
	end
	for _, side in { -1, 1 } do
		part(model, "Eye", Vector3.one * 0.16 * s, headCF * CFrame.new(side * 0.25 * s, 0.15 * s, -0.55 * s), Color3.fromRGB(20, 16, 14), BALL)
		if species.ears == "Long" then
			part(model, "Ear", Vector3.new(0.25, 1.1, 0.15) * s, headCF * CFrame.new(side * 0.3 * s, 0.95 * s, 0) * CFrame.Angles(0, 0, side * math.rad(-10)), species.body)
		elseif species.ears == "Big" then
			part(model, "Ear", Vector3.one * 0.6 * s, headCF * CFrame.new(side * 0.55 * s, 0.55 * s, 0), species.body, BALL)
		elseif species.ears == "Tuft" then
			part(model, "Ear", Vector3.new(0.25, 0.5, 0.15) * s, headCF * CFrame.new(side * 0.4 * s, 0.65 * s, 0), species.body)
		elseif species.ears == "Pointy" then
			part(model, "Ear", Vector3.new(0.3, 0.55, 0.15) * s, headCF * CFrame.new(side * 0.38 * s, 0.68 * s, 0) * CFrame.Angles(0, 0, side * math.rad(-15)), species.body)
		elseif species.ears == "Round" then
			part(model, "Ear", Vector3.one * 0.3 * s, headCF * CFrame.new(side * 0.5 * s, 0.45 * s, 0), species.body, BALL)
		end
		local arm = part(model, "Arm", Vector3.new(0.35, 0.9, 0.35) * s, base * CFrame.new(side * 0.85 * s, 1.1 * s, -0.2), species.body)
		arm:SetAttribute("Side", side)
	end
	if species.tail == "Bushy" then
		part(model, "Tail", Vector3.new(0.8, 1.8, 0.6) * s, base * CFrame.new(0, 1.3 * s, 0.8 * s) * CFrame.Angles(math.rad(-20), 0, 0), species.body)
	elseif species.tail == "Thin" then
		part(model, "Tail", Vector3.new(0.3, 0.3, 1.4) * s, base * CFrame.new(0, 0.5 * s, 0.9 * s), species.body)
	end
	if species.shell then
		part(model, "Shell", Vector3.new(1.9, 1.6, 1.5) * s, base * CFrame.new(0, 1.1 * s, 0.35 * s), species.shell, BALL)
	end
	model.PrimaryPart = body
	local count = 0
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			count += 1
		end
	end
	model:SetAttribute("BaseCFrame", model:GetPivot()) -- authoritative seat for the client animation
	model:SetAttribute("PartCount", count)
	model:SetAttribute("Seed", rng:NextNumber())
	model.Parent = parent
	CollectionService:AddTag(model, Config.CrowdSpectatorTag)
	return model
end

-- Seats of one zone, along its rows, validated against the real seating geometry.
local function seatsFor(zone: Zone, taken: { Vector3 }, params: RaycastParams): { { Seat } }
	local layout = Arena.Layout
	local tier = if zone.Level == "Lower" then 2 else 4
	local rows: { number } = if zone.Level == "Lower" then { SpectatorZoneDefinitions.FrontRow, SpectatorZoneDefinitions.BackRow }
		elseif zone.Level == "Middle" then { SpectatorZoneDefinitions.FrontRow }
		else { SpectatorZoneDefinitions.BackRow }
	local seatTop = layout.FloorTop + layout.PodiumHeight + tier * layout.SeatRise
	local result: { { Seat } } = {}
	local realSpots = {}
	for i = 0, 11 do
		table.insert(realSpots, Arena.getTribuneCFrame(i).Position)
	end
	local imperial = layout.ImperialSeat.Position
	for rowIndex, share in rows do
		local offset = layout.PodiumThickness + (tier - 1) * layout.SeatDepth + layout.SeatDepth * share
		local rowSeats: { Seat } = {}
		local degrees = zone.CenterDegrees - zone.SpanDegrees / 2
		local stop = zone.CenterDegrees + zone.SpanDegrees / 2
		local last: Vector3? = nil
		while degrees <= stop do
			local frame = Arena.frameAt(math.rad(degrees), offset, seatTop)
			local position = frame.Position
			local spaced = last == nil or (position - (last :: Vector3)).Magnitude >= zone.SeatSpacing
			if spaced then
				last = position
				local valid = not SpectatorZoneDefinitions.isExcluded(degrees, zone.Level)
					and not Arena.isInside(position, layout.PodiumThickness + 1) -- never on (or next to) the sand
				if valid then
					local hit = Workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -6, 0), params)
					valid = hit ~= nil and hit.Instance:IsDescendantOf(Workspace) and math.abs(hit.Position.Y - seatTop) < 1.2
					if valid and hit then
						frame = CFrame.new(Vector3.new(position.X, hit.Position.Y, position.Z)) * frame.Rotation
					end
				end
				if valid then
					for _, spot in realSpots do
						if (spot - position).Magnitude < 4 then
							valid = false
						end
					end
					if (imperial - position).Magnitude < 14 then
						valid = false
					end
				end
				if valid then
					for _, other in taken do
						if (other - position).Magnitude < SpectatorZoneDefinitions.MinSeatSpacing then
							valid = false
							break
						end
					end
				end
				if valid then
					table.insert(rowSeats, { cframe = frame, zone = zone, row = rowIndex })
				else
					table.insert(rowSeats, { cframe = CFrame.identity, zone = zone, row = -1 }) -- a gap keeps groups apart
				end
			end
			degrees += 0.5
		end
		table.insert(result, rowSeats)
	end
	return result
end

local function applyImportance()
	local level = if importance == "Low" then 1 elseif importance == "Normal" then 2 else 3
	for _, group in groups do
		local wanted = group.priority <= level
		local parent = if wanted then crowdFolder else reserve
		if group.model.Parent ~= parent then
			group.model.Parent = parent
		end
	end
end

-- Low (early rounds) / Normal / High (final round, Otti, sudden death, match point).
function SpectatorPlacementService.setImportance(level: CrowdQualityConfig.Importance)
	if level ~= importance then
		importance = level
		applyImportance()
	end
end

function SpectatorPlacementService.build(folder: Instance, seed: number)
	local crowd = Instance.new("Folder")
	crowd.Name = "Crowd"
	crowd.Parent = folder
	crowdFolder = crowd
	local hidden = Instance.new("Folder")
	hidden.Name = "CrowdReserve"
	hidden.Parent = ServerStorage
	reserve = hidden
	table.clear(groups)

	local seating = folder:FindFirstChild("Seating")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { seating or folder }
	local rng = Random.new(seed)
	local taken: { Vector3 } = {}
	local placed = 0

	for _, zone in SpectatorZoneDefinitions.Zones do
		local density = math.min(CrowdQualityConfig.MaxDensity, zone.Density * HIGH_IMPORTANCE)
		for _, row in seatsFor(zone, taken, params) do
			local i = 1 + rng:NextInteger(0, SpectatorZoneDefinitions.MaxGap)
			while i <= #row do
				local size = rng:NextInteger(SpectatorZoneDefinitions.MinGroup, SpectatorZoneDefinitions.MaxGroup)
				local fill = rng:NextNumber() < density
				if fill then
					local group = Instance.new("Folder")
					group.Name = "Group"
					local primary = SPECIES[rng:NextInteger(1, #SPECIES)]
					local secondary = if rng:NextNumber() < SpectatorZoneDefinitions.SecondSpeciesChance then SPECIES[rng:NextInteger(1, #SPECIES)] else primary
					local members = 0
					for k = i, math.min(#row, i + size - 1) do
						local seat = row[k]
						if seat.row < 0 then
							break -- a gap / invalid seat ends the group
						end
						-- leave the occasional empty seat inside a group
						if members > 0 and rng:NextNumber() < 0.12 then
							continue
						end
						local jitter = CFrame.new(rng:NextNumber(-0.25, 0.25), 0, rng:NextNumber(-0.2, 0.2)) * CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0)
						local species = if rng:NextNumber() < 0.7 then primary else secondary
						local model = buildAnimal(group, seat.cframe * jitter, species, rng)
						table.insert(taken, model:GetPivot().Position)
						members += 1
					end
					if members >= 2 then
						-- Priority: most groups always, some only at Normal / High importance
						local roll = rng:NextNumber()
						local priority = if roll < 0.55 / HIGH_IMPORTANCE then 1 elseif roll < 0.85 then 2 else 3
						group.Parent = hidden
						table.insert(groups, { model = group, priority = priority })
						placed += members
					else
						group:Destroy()
					end
				end
				i += size + rng:NextInteger(SpectatorZoneDefinitions.MinGap, SpectatorZoneDefinitions.MaxGap)
			end
		end
	end
	applyImportance()
	print("[OttiArena][Crowd]", ("%d animal spectators in %d groups across %d zones"):format(placed, #groups, #SpectatorZoneDefinitions.Zones))
end

return SpectatorPlacementService
