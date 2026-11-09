--!strict
-- The smithy on the Handwerksgasse (house BN1-S1): the first building of Rome with a playable
-- interior. A wide open front under a sign, inside a warm forge (hearth, hood, chimney, embers,
-- bellows), the anvil, a workbench with tools, a quench trough and displays of weapons, shields
-- and armour. Helmets have no equipment slot yet: three stand on a shelf as showpieces and mark
-- the prepared expansion point (attribute ExpansionPoint = "Helmets").
-- The smith NPC stands at the anvil (anchor SmithSpot) facing the entrance; ForgeService gives
-- him his prompt and dialog.
local RomeLayout = require(script.Parent.RomeLayout)
local Parts = require(script.Parent.RomeParts)

type House = RomeLayout.House
local C = Parts.Colors

local Smithy = {}

export type Result = { smithSpot: CFrame, entrance: CFrame, interiorCenter: CFrame, interiorSize: Vector3 }

local WALL = 1.2
local HALL = 12 -- interior clear height
local SOCKET = 1.2

local last: Result? = nil

function Smithy.build(model: Model, frame: CFrame, h: House)
	local w, d = h.w, h.d
	local plaster = Parts.Plaster[4]
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local top = SOCKET + HALL
	-- socket and floor (the floor is the socket's top)
	Parts.part(model, "Socket", at(0, (SOCKET - 2) / 2, 0), Vector3.new(w + 0.5, SOCKET + 2, d + 0.5), C.Stone, { shadow = false })
	Parts.decor(model, "WorkshopFloor", at(0, SOCKET + 0.03, 0), Vector3.new(w - 2 * WALL, 0.06, d - 2 * WALL), Color3.fromRGB(120, 104, 88), Enum.Material.Slate)
	-- walls: back, sides, front with a wide opening (10 wide, 9 high)
	local opening, openingHeight = 10, 9
	Parts.part(model, "Wall", at(0, SOCKET + HALL / 2, d / 2 - WALL / 2), Vector3.new(w, HALL, WALL), plaster, { material = Enum.Material.Plaster })
	for _, s in { -1, 1 } do
		Parts.part(model, "Wall", at(s * (w / 2 - WALL / 2), SOCKET + HALL / 2, 0), Vector3.new(WALL, HALL, d), plaster, { material = Enum.Material.Plaster })
		local side = (w - opening) / 2
		Parts.part(model, "Wall", at(s * (opening / 2 + side / 2), SOCKET + HALL / 2, -d / 2 + WALL / 2), Vector3.new(side, HALL, WALL), plaster, { material = Enum.Material.Plaster })
		Parts.decor(model, "OpeningJamb", at(s * (opening / 2 + 0.4), SOCKET + openingHeight / 2, -d / 2 - 0.1), Vector3.new(0.8, openingHeight, 0.5), C.Travertine, Enum.Material.Limestone)
		-- the open shutters, folded back against the facade
		Parts.decor(model, "OpenShutter", at(s * (opening / 2 + 2.6), SOCKET + openingHeight / 2, -d / 2 - 0.15), Vector3.new(3.6, openingHeight - 0.6, 0.15), C.Timber, Enum.Material.WoodPlanks)
	end
	Parts.part(model, "Wall", at(0, SOCKET + openingHeight + (HALL - openingHeight) / 2, -d / 2 + WALL / 2), Vector3.new(opening, HALL - openingHeight, WALL), plaster, { material = Enum.Material.Plaster })
	Parts.decor(model, "OpeningLintel", at(0, SOCKET + openingHeight + 0.4, -d / 2 - 0.1), Vector3.new(opening + 1.6, 0.8, 0.5), C.Travertine, Enum.Material.Limestone)
	-- the threshold: a flat run-in from the sidewalk to the workshop floor
	local run = 2
	Parts.colliderWedge(model, "ThresholdRamp", at(0, SOCKET / 2, -d / 2 - run / 2), Vector3.new(opening, SOCKET, run))
	-- ceiling (collision) and roof with a chimney
	Parts.part(model, "Ceiling", at(0, top + 0.5, 0), Vector3.new(w, 1, d), Color3.fromRGB(92, 72, 52), { material = Enum.Material.WoodPlanks })
	for i = -2, 2 do
		Parts.decor(model, "Beam", at(i * (w / 5), top - 0.4, 0), Vector3.new(0.8, 0.8, d - 2 * WALL), C.TimberDark, Enum.Material.Wood)
	end
	local over, rise = 0.9, 4.2
	for _, s in { -1, 1 } do
		local half = at(0, top + 1 + rise / 2, s * (d / 4 + over / 4)) * (if s > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
		Parts.wedge(model, "Roof", half, Vector3.new(w + over * 2, rise, d / 2 + over / 2), Parts.Roofs[2], { material = Enum.Material.ClayRoofTiles })
	end
	local forge = at(-w / 2 + 5, SOCKET, d / 2 - 4)
	Parts.part(model, "Chimney", forge * CFrame.new(0, HALL + 5, 1), Vector3.new(3, 8, 3), C.TerracottaDark, { material = Enum.Material.Brick })
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(150, 146, 140))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 6) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(4, 6)
	smoke.Rate = 4
	smoke.Speed = NumberRange.new(3, 5)
	smoke.SpreadAngle = Vector2.new(12, 12)
	local smokeHost = Parts.decor(model, "ChimneySmoke", forge * CFrame.new(0, HALL + 9.2, 1), Vector3.new(1, 0.2, 1), C.Stone)
	smokeHost.Transparency = 1
	smoke.Parent = smokeHost
	-- the forge: hearth, hood, embers, fire and bellows
	Parts.part(model, "Hearth", forge * CFrame.new(0, 1.6, 0), Vector3.new(6, 3.2, 4.4), C.TerracottaDark, { material = Enum.Material.Brick })
	Parts.wedge(model, "Hood", forge * CFrame.new(0, 7, 0.6) * CFrame.Angles(0, math.pi, 0), Vector3.new(6.4, 4.4, 3.4), C.StoneDark, { collide = false, shadow = false, material = Enum.Material.Brick })
	Parts.decor(model, "HoodShaft", forge * CFrame.new(0, 10.4, 1.4), Vector3.new(3, 3, 2.2), C.StoneDark, Enum.Material.Brick)
	local embers = Parts.decor(model, "Embers", forge * CFrame.new(0, 3.3, -0.4), Vector3.new(4.2, 0.2, 2.6), Color3.fromRGB(255, 110, 40), Enum.Material.Neon)
	local fire = Instance.new("Fire")
	fire.Heat = 4
	fire.Size = 3
	fire.Color = Color3.fromRGB(255, 140, 60)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
	fire.Parent = embers
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 150, 80)
	glow.Range = 26
	glow.Brightness = 1.6
	glow.Parent = embers
	Parts.wedge(model, "Bellows", forge * CFrame.new(4, 1.4, 0) * CFrame.Angles(0, -math.pi / 2, 0), Vector3.new(1.6, 1.2, 2.6), Color3.fromRGB(110, 74, 46), { collide = false, shadow = false, material = Enum.Material.Leather })
	-- the anvil on its stump in the middle, the smith behind it facing the entrance
	local anvilAt = at(1, SOCKET, 1)
	Parts.column(model, "AnvilStump", anvilAt, 2, 2.2, C.Timber, { material = Enum.Material.Wood })
	Parts.part(model, "AnvilBase", anvilAt * CFrame.new(0, 2.4, 0), Vector3.new(1.2, 0.8, 0.9), C.Iron, { material = Enum.Material.Metal })
	Parts.part(model, "Anvil", anvilAt * CFrame.new(0, 3.05, 0), Vector3.new(2.6, 0.5, 1.1), C.Iron, { material = Enum.Material.Metal })
	Parts.wedge(model, "AnvilHorn", anvilAt * CFrame.new(-1.75, 3.05, 0) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(1.1, 0.5, 0.9), C.Iron, { collide = false, shadow = false, material = Enum.Material.Metal })
	Parts.decor(model, "Hammer", anvilAt * CFrame.new(0.4, 3.45, 0.1) * CFrame.Angles(0, 0.4, 0), Vector3.new(0.3, 0.3, 1.6), C.Timber, Enum.Material.Wood)
	local smithSpot = anvilAt * CFrame.new(0, 0, 3.2) -- -Z (look) toward the entrance
	-- the workbench with tools, the quench trough
	local bench = at(w / 2 - 3.2, SOCKET, 2)
	Parts.part(model, "Workbench", bench * CFrame.new(0, 1.6, 0), Vector3.new(2.8, 0.4, 7), C.Timber, { material = Enum.Material.WoodPlanks })
	for _, z in { -3, 3 } do
		Parts.part(model, "BenchLeg", bench * CFrame.new(0, 0.7, z), Vector3.new(2.4, 1.4, 0.4), C.TimberDark, { material = Enum.Material.Wood })
	end
	for i, size in { Vector3.new(0.3, 0.3, 1.8), Vector3.new(0.25, 0.25, 2.2), Vector3.new(1.2, 0.2, 0.6) } do
		Parts.decor(model, "Tool", bench * CFrame.new(0, 1.95, -2 + i * 1.3) * CFrame.Angles(0, 0.3 * i, 0), size, C.Iron, Enum.Material.Metal)
	end
	Parts.part(model, "QuenchTrough", at(-2, SOCKET + 0.7, d / 2 - 3), Vector3.new(4, 1.4, 1.8), C.Stone, { material = Enum.Material.Limestone })
	Parts.decor(model, "QuenchWater", at(-2, SOCKET + 1.35, d / 2 - 3), Vector3.new(3.4, 0.08, 1.3), C.Water, Enum.Material.Glass)
	-- wall displays: swords and spears on the left wall, shields on the right wall, armour stand
	local left = at(-w / 2 + WALL + 0.3, SOCKET, 0)
	for i, length in { 4.2, 5.4, 4.6, 7.5 } do
		local z = -d / 2 + 4 + i * 2.2
		Parts.decor(model, "WeaponOnWall", left * CFrame.new(0, 4.5, z) * CFrame.Angles(0, 0, 0), Vector3.new(0.25, length, 0.5), if i == 4 then C.Timber else Color3.fromRGB(196, 196, 204), Enum.Material.Metal)
		Parts.decor(model, "WeaponGuard", left * CFrame.new(0.05, 4.5 - length / 2 + 1.1, z), Vector3.new(0.3, 0.25, 1.4), C.Bronze, Enum.Material.Metal)
	end
	local right = at(w / 2 - WALL - 0.3, SOCKET, 0)
	for i, color in { C.RomanRed, C.Bronze, Color3.fromRGB(70, 96, 120) } do
		local z = -d / 2 + 3 + i * 3
		Parts.part(model, "ShieldOnWall", right * CFrame.new(-0.1, 6.5, z) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.3, 2.6, 2.6), color, { collide = false, shadow = false, shape = Enum.PartType.Cylinder, material = Enum.Material.Metal })
		Parts.part(model, "ShieldBoss", right * CFrame.new(-0.25, 6.5, z), Vector3.new(0.5, 0.6, 0.6), C.Gold, { collide = false, shadow = false, shape = Enum.PartType.Ball, material = Enum.Material.Metal })
	end
	local stand = at(-w / 2 + 3.4, SOCKET, -d / 2 + 4)
	Parts.decor(model, "ArmorPole", stand * CFrame.new(0, 2.5, 0), Vector3.new(0.3, 5, 0.3), C.TimberDark, Enum.Material.Wood)
	Parts.decor(model, "Cuirass", stand * CFrame.new(0, 4.4, 0), Vector3.new(2, 2.2, 1.1), C.Bronze, Enum.Material.Metal)
	Parts.decor(model, "Pteruges", stand * CFrame.new(0, 3, 0), Vector3.new(2.1, 0.9, 1.2), Color3.fromRGB(140, 60, 44), Enum.Material.Leather)
	-- the helmet shelf: showpieces only, the prepared point for a later helmet slot
	local shelf = at(w / 2 - WALL - 0.8, SOCKET, d / 2 - 5)
	local shelfBoard = Parts.part(model, "HelmetShelf", shelf * CFrame.new(0, 5.2, 0), Vector3.new(1.4, 0.3, 6), C.Timber, { collide = false, shadow = false, material = Enum.Material.WoodPlanks })
	shelfBoard:SetAttribute("ExpansionPoint", "Helmets")
	for i, color in { C.Bronze, Color3.fromRGB(190, 190, 196), C.Gold } do
		local helmet = shelf * CFrame.new(0, 6, -2 + (i - 1) * 2)
		Parts.part(model, "Helmet", helmet, Vector3.new(1.2, 1.2, 1.2), color, { collide = false, shadow = false, shape = Enum.PartType.Ball, material = Enum.Material.Metal })
		Parts.decor(model, "HelmetCrest", helmet * CFrame.new(0, 0.75, 0), Vector3.new(0.3, 0.6, 1.3), C.RomanRed, Enum.Material.Fabric)
	end
	Parts.sign(model, "HelmetSign", shelf * CFrame.new(-0.75, 7.6, 0) * CFrame.Angles(0, -math.pi / 2, 0), Vector2.new(5, 1.2), "GALEAE · HELME", "bald in der Schmiede", C.TimberDark)
	-- lamps and the street front: sign, awning, crossed hammers
	Parts.flame(model, at(0, top - 1.6, -2), 22, 0.7)
	Parts.flame(model, at(w / 2 - 3, top - 1.6, d / 2 - 4), 18, 0.6)
	Parts.sign(model, "SmithySign", at(0, SOCKET + openingHeight + 1.9, -d / 2 - 0.35) * CFrame.Angles(0, 0, 0), Vector2.new(13, 2.2), h.name or "SCHMIEDE", "Waffen verbessern · Ausrüstung", C.TimberDark)
	for _, s in { -1, 1 } do
		Parts.decor(model, "HammerSign", at(s * 8, SOCKET + openingHeight + 1.9, -d / 2 - 0.4) * CFrame.Angles(0, 0, s * 0.7), Vector3.new(0.3, 2.4, 0.15), C.Bronze, Enum.Material.Metal)
	end
	-- upper storey look from the street: windows above the workshop
	for _, x in { -w / 3, w / 3 } do
		Parts.decor(model, "Window", at(x, top - 1.5, -d / 2 - 0.05), Vector3.new(1.8, 1.4, 0.1), Color3.fromRGB(46, 38, 32), Enum.Material.SmoothPlastic)
	end
	model:SetAttribute("Interior", "Smithy")
	local entrance = at(0, SOCKET, -d / 2 + 1)
	last = {
		smithSpot = smithSpot,
		entrance = entrance,
		interiorCenter = at(0, SOCKET + HALL / 2, 0),
		interiorSize = Vector3.new(w - 2 * WALL, HALL, d - 2 * WALL),
	}
end

-- The anchors of the last smithy built (ForgeService uses the smith's spot).
function Smithy.result(): Result?
	return last
end

return Smithy
