--!strict
-- Builds Rome around the Hub's Colosseum: the island and the sea in terrain, the rim of the world
-- disc, the town's shell, streets, forum and temple, harbour, the 80 houses (the smithy with its
-- interior), the countryside, and the three townspeople with their counters. The Colosseum and
-- the lobbies inside it come from LobbyService; only the Arena builder's endless granite plate is
-- removed here (the island replaces it). Nothing of this runs in the Arena place.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local OracleDefinitions = require(ReplicatedStorage.Shared.OracleDefinitions)
local RomeLayout = require(script.Parent.RomeLayout)
local Parts = require(script.Parent.RomeParts)
local IslandBuilder = require(script.Parent.IslandBuilder)
local CityShell = require(script.Parent.CityShell)
local StreetBuilder = require(script.Parent.StreetBuilder)
local ForumTemple = require(script.Parent.ForumTemple)
local Harbor = require(script.Parent.Harbor)
local HouseKit = require(script.Parent.HouseKit)
local Smithy = require(script.Parent.Smithy)
local Countryside = require(script.Parent.Countryside)
local Yards = require(script.Parent.Yards)
local RomeNpc = require(script.Parent.RomeNpc)

local PREFIX = "[OttiArena][Rome]"
local RomeWorld = {}

export type World = {
	folder: Folder,
	forumRespawn: CFrame,
	smith: RomeNpc.Npc,
	oracle: RomeNpc.Npc,
	priest: RomeNpc.Npc,
	houses: { [string]: Model },
	crossings: { [string]: CFrame },
}

local function prompt(host: BasePart, action: string, object: string, onTriggered: (player: Player) -> ())
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.F
	p.Parent = host
	p.Triggered:Connect(onTriggered)
end

-- `openForge` / `openOracle`: the counters (TownServices) a prompt opens.
function RomeWorld.build(openForge: (player: Player) -> (), openOracle: (player: Player) -> ()): World
	local started = os.clock()
	local arena = Workspace:FindFirstChild(Config.ArenaFolderName)
	local plate = arena and arena:FindFirstChild("Ground")
	if plate then
		plate:Destroy() -- the island replaces the endless granite plate
	end
	local old = Workspace:FindFirstChild("Rome")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Rome"
	folder.Parent = Workspace
	IslandBuilder.setupAtmosphere()
	IslandBuilder.buildTerrain()
	IslandBuilder.buildRim(folder)
	CityShell.build(folder)
	local crossings = StreetBuilder.build(folder)
	local forum = ForumTemple.build(folder)
	Harbor.build(folder)
	local houseFolder = Parts.folder(folder, "Houses")
	local houses: { [string]: Model } = {}
	for i, h in RomeLayout.houses() do
		houses[h.id] = HouseKit.build(houseFolder, h, Smithy.build)
		if i % 10 == 0 then
			task.wait()
		end
	end
	Yards.build(folder)
	Countryside.build(folder)
	-- the townspeople
	local people = Parts.folder(folder, "Townspeople")
	local smithy = assert(Smithy.result(), "smithy not built")
	local smith = RomeNpc.spawn(people, "Faber", smithy.smithSpot, { skin = Color3.fromRGB(196, 150, 112), cloth = Color3.fromRGB(120, 92, 70), accent = Color3.fromRGB(88, 60, 40), apron = true })
	smith.model:SetAttribute("Role", "Smith")
	prompt(smith.root, "Waffe verbessern", "Faber · Schmied", function(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			RomeNpc.attend(smith, root.Position, 20)
		end
		openForge(player)
	end)
	local routes = forum.priestRoutes
	local oracle = RomeNpc.spawn(people, "Augur", CFrame.new(routes[1][1]), { skin = Color3.fromRGB(214, 172, 136), cloth = Color3.fromRGB(240, 234, 220), accent = Color3.fromRGB(150, 48, 34) })
	oracle.model:SetAttribute("Role", "Oracle")
	RomeNpc.patrol(oracle, routes[1], 4)
	prompt(oracle.root, ("Weissagung (%d Denarii)"):format(OracleDefinitions.Price), "Augur · Orakel", function(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			RomeNpc.attend(oracle, root.Position, 25)
		end
		openOracle(player)
	end)
	local priest = RomeNpc.spawn(people, "Flamen", CFrame.new(routes[2][1]), { skin = Color3.fromRGB(180, 132, 98), cloth = Color3.fromRGB(232, 226, 210), accent = Color3.fromRGB(176, 125, 60) })
	priest.model:SetAttribute("Role", "TemplePriest")
	RomeNpc.patrol(priest, routes[2], 3)
	print(PREFIX, ("Rome built in %.1f s: %d houses, %d streets, %d crossings"):format(os.clock() - started, #RomeLayout.houses(), #RomeLayout.Streets, #RomeLayout.Crossings))
	return { folder = folder, forumRespawn = forum.respawn, smith = smith, oracle = oracle, priest = priest, houses = houses, crossings = crossings }
end

return RomeWorld
