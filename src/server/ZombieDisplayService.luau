--!strict
-- ZOMBIE ARCHIVE: one display zombie per type (six) inside an iron-barred cage in the lobby.
-- Display zombies use the same ZombieFactory model as the arena, but they are anchored (they
-- can't escape even if physics misbehave), tagged ZombieDisplay (never the enemy tag), have no
-- AI or pathfinding, can't be damaged or deal damage, give no Aura and never count for waves.
-- A light idle loop turns them toward nearby players, rattles the bars or shows a signature pose.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local ZombieDefinitions = require(ReplicatedStorage.Shared.ZombieDefinitions)
local ZombieFactory = require(script.Parent.ZombieFactory)

type ZombieDefinition = ZombieDefinitions.ZombieDefinition

local GOLD = Color3.fromRGB(240, 196, 80)

local ZombieDisplayService = {}

type Display = {
	def: ZombieDefinition,
	rig: ZombieFactory.ZombieRig,
	home: CFrame,
}

local displays: { Display } = {}

local function plaque(parent: Instance, cframe: CFrame, def: ZombieDefinition)
	local board = Instance.new("Part")
	board.Name = "ArchivePlaque"
	board.Anchored = true
	board.CanCollide = false
	board.Size = Vector3.new(6, 4.4, 0.3)
	board.CFrame = cframe
	board.Color = Color3.fromRGB(60, 40, 26)
	board.Material = Enum.Material.Wood
	board.Parent = parent
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = gui
	type Line = { text: string, color: Color3, scale: number, font: Enum.Font }
	local lines: { Line } = {
		{ text = def.DisplayName:upper(), color = GOLD, scale = 0.2, font = Enum.Font.GothamBlack },
		{ text = def.Role, color = Color3.new(1, 1, 1), scale = 0.13, font = Enum.Font.GothamBold },
		{ text = ("Health: %d  ·  Damage: %d"):format(def.Health, def.Damage), color = Color3.new(1, 1, 1), scale = 0.13, font = Enum.Font.Gotham },
		{ text = ("Reward: %d Aura + Denarii  ·  From round %d"):format(def.Coins, def.AvailableFromRound), color = Color3.fromRGB(255, 220, 120), scale = 0.13, font = Enum.Font.Gotham },
		{ text = def.SpecialText, color = Color3.fromRGB(255, 190, 150), scale = 0.13, font = Enum.Font.GothamMedium },
	}
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.LayoutOrder = i
		label.Size = UDim2.fromScale(0.95, line.scale)
		label.BackgroundTransparency = 1
		label.Text = line.text
		label.TextColor3 = line.color
		label.Font = line.font
		label.TextScaled = true
		label.Parent = gui
	end
end

local function nearestPlayer(position: Vector3, radius: number): Vector3?
	local best, bestDistance = nil, radius
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = root.Position, distance
			end
		end
	end
	return best
end

local function pose(motor: Motor6D, rest: CFrame, degrees: number, seconds: number)
	TweenService:Create(motor, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { C0 = rest * CFrame.Angles(math.rad(degrees), 0, 0) }):Play()
end

local function idle(display: Display, rng: Random)
	local rig = display.rig
	local root = rig.root
	while rig.model.Parent do
		task.wait(rng:NextNumber(2, 4.5))
		local roll = rng:NextNumber()
		local viewer = nearestPlayer(root.Position, 24)
		if viewer and roll < 0.45 then
			-- Turn to inspect the player (within the cage, around its own spot)
			local look = Vector3.new(viewer.X, display.home.Position.Y, viewer.Z)
			TweenService:Create(root, TweenInfo.new(0.6), { CFrame = CFrame.lookAt(display.home.Position, look) }):Play()
		elseif roll < 0.75 then
			-- Rattle the bars
			pose(rig.rightShoulder, rig.rightShoulderRest, 140, 0.25)
			task.wait(0.3)
			pose(rig.rightShoulder, rig.rightShoulderRest, 30, 0.12)
			task.wait(0.35)
			pose(rig.rightShoulder, rig.rightShoulderRest, 0, 0.3)
		else
			-- Signature pose
			local id = display.def.AIProfile
			if id == "Tank" then
				pose(rig.rightShoulder, rig.rightShoulderRest, 120, 0.25)
				pose(rig.leftShoulder, rig.leftShoulderRest, 120, 0.25)
			elseif id == "Elite" or id == "Disciplined" then
				pose(rig.leftShoulder, rig.leftShoulderRest, 75, 0.25)
				if rig.guardGlow then
					rig.guardGlow.Enabled = true
				end
			elseif id == "Controller" then
				pose(rig.leftShoulder, rig.leftShoulderRest, 160, 0.3)
			elseif id == "Marksman" then
				-- Draws its bow at the visitor (never shoots in the archive)
				pose(rig.leftShoulder, rig.leftShoulderRest, 90, 0.3)
				pose(rig.rightShoulder, rig.rightShoulderRest, 95, 0.5)
			else
				TweenService:Create(root, TweenInfo.new(0.3), { CFrame = display.home * CFrame.Angles(0, math.rad(rng:NextNumber(-40, 40)), 0) }):Play()
			end
			task.wait(1.2)
			pose(rig.rightShoulder, rig.rightShoulderRest, 0, 0.3)
			pose(rig.leftShoulder, rig.leftShoulderRest, 0, 0.3)
			if rig.guardGlow then
				rig.guardGlow.Enabled = false
			end
		end
	end
end

-- slots[i]: floor CFrame in the middle of cage i, LookVector toward the gallery.
-- plaqueSlots[i]: plaque CFrame outside cage i (front face toward the gallery).
function ZombieDisplayService.build(parent: Instance, slots: { CFrame }, plaqueSlots: { CFrame })
	local folder = Instance.new("Folder")
	folder.Name = "ZombieArchive"
	folder.Parent = parent
	for i, def in ZombieDefinitions.Ordered do
		local slot = slots[i]
		if not slot then
			break
		end
		local rig = ZombieFactory.build(def)
		local model = rig.model
		model.Name = "Display_" .. def.Id
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanTouch = false
				part.CanQuery = false
			end
		end
		rig.root.Anchored = true -- can never walk or be pushed out of its cage
		rig.humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		rig.humanoid.WalkSpeed = 0
		local height = rig.humanoid.HipHeight + rig.root.Size.Y / 2
		local home = slot + Vector3.new(0, height, 0)
		model:PivotTo(home)
		model.Parent = folder
		CollectionService:AddTag(model, Config.ZombieDisplayTag)
		if plaqueSlots[i] then
			plaque(folder, plaqueSlots[i], def)
		end
		local display: Display = { def = def, rig = rig, home = home }
		table.insert(displays, display)
		task.spawn(idle, display, Random.new())
	end
end

return ZombieDisplayService
