--!strict
-- The Hub intro on the client (LobbyIntroService decides the stage):
--   * signs of the start hall marked with an IntroStage attribute stay hidden (locally: board,
--     text and F prompt) until the player's IntroStage attribute reaches that stage
--   * MatchEvent "IntroHint": a banner with the stage's hint and a gold floor arrow from the
--     player towards the place it is about; the arrow goes once it is reached or after a while
-- Display only: hidden prompts still work on the server, which checks everything itself.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LobbyIntroController = {}

local ARROW_LENGTH = 40 -- studs of chevrons on the player's floor; the beacon marks the target
local ARROW_SECONDS = 25
local GOLD = Color3.fromRGB(240, 196, 80)

local function decor(name: string, size: Vector3, cframe: CFrame, parent: Instance, transparency: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = GOLD
	part.Transparency = transparency
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

function LobbyIntroController.start(lobbyFolder: Instance?, events: RemoteEvent?, banner: (title: string, text: string) -> ())
	local player = Players.LocalPlayer

	local function stage(): number
		local value = player:GetAttribute("IntroStage")
		return if type(value) == "number" then value else 0
	end

	local function applyTo(part: BasePart)
		local needed = part:GetAttribute("IntroStage")
		if type(needed) ~= "number" then
			return
		end
		local visible = stage() >= needed
		part.LocalTransparencyModifier = if visible then 0 else 1
		for _, child in part:GetDescendants() do
			if child:IsA("SurfaceGui") then
				child.Enabled = visible
			elseif child:IsA("ProximityPrompt") then
				child.Enabled = visible
			end
		end
	end

	local function applyAll()
		if not lobbyFolder then
			return
		end
		for _, item in lobbyFolder:GetDescendants() do
			if item:IsA("BasePart") then
				applyTo(item)
			end
		end
	end

	if lobbyFolder then
		-- prompts are added by the server after the build: hide them as they replicate
		lobbyFolder.DescendantAdded:Connect(function(item: Instance)
			local host = if item:IsA("BasePart") then item else item:FindFirstAncestorWhichIsA("BasePart")
			if host then
				applyTo(host)
			end
		end)
	end
	player:GetAttributeChangedSignal("IntroStage"):Connect(applyAll)
	applyAll()

	local arrow: Model? = nil
	local function clearArrow()
		if arrow then
			arrow:Destroy()
			arrow = nil
		end
	end

	local function showArrow(target: Vector3)
		clearArrow()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return
		end
		local model = Instance.new("Model")
		model.Name = "IntroArrow"
		local floorY = root.Position.Y - 3
		local flat = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
		local distance = math.min(flat.Magnitude - 4, ARROW_LENGTH)
		if flat.Magnitude > 1 then
			local direction = flat.Unit
			for d = 4, distance, 4 do
				local at = Vector3.new(root.Position.X, floorY + 0.08, root.Position.Z) + direction * d
				local frame = CFrame.lookAt(at, at + direction)
				for _, side in { -1, 1 } do
					decor("Chevron", Vector3.new(0.35, 0.06, 1.8), frame * CFrame.new(side * 0.55, 0, 0.3) * CFrame.Angles(0, side * math.rad(-35), 0), model, 0.15)
				end
			end
		end
		decor("Beacon", Vector3.new(14, 2.4, 2.4), CFrame.new(target + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90)), model, 0.6).Shape = Enum.PartType.Cylinder
		model.Parent = Workspace
		arrow = model
		local deadline = os.clock() + ARROW_SECONDS
		task.spawn(function()
			while arrow == model and os.clock() < deadline do
				local current = player.Character
				local position = current and current:FindFirstChild("HumanoidRootPart")
				if position and position:IsA("BasePart") and (Vector3.new(position.Position.X, 0, position.Position.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude < 7 then
					break
				end
				task.wait(0.25)
			end
			if arrow == model then
				clearArrow()
			end
		end)
	end

	if events then
		events.OnClientEvent:Connect(function(kind: string, data: any)
			if kind == "IntroHint" and type(data) == "table" then
				banner(tostring(data.title or ""), tostring(data.text or ""))
				if typeof(data.target) == "Vector3" then
					showArrow(data.target)
				end
			elseif kind == "Teleport" then
				clearArrow()
			end
		end)
	end
end

return LobbyIntroController
