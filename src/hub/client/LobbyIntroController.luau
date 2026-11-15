--!strict
-- The Hub intro on the client (LobbyIntroService decides the stage):
--   * signs of the start hall marked with an IntroStage attribute stay hidden (locally: board,
--     text and F prompt) until the player's IntroStage attribute reaches that stage
--   * MatchEvent "IntroHint": a banner with the stage's hint and gold TUTORIAL ARROWS on the
--     floor. They start at the player's feet and follow the stage's waypoints (round the hall,
--     through the west arch, down the street ...), are redrawn as the player walks, and go once
--     the place is reached, a fight starts, or after a few minutes. A beacon marks the place.
-- Display only: hidden prompts still work on the server, which checks everything itself.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LobbyIntroController = {}

local ARROW_LENGTH = 44 -- studs of chevrons ahead of the player; the beacon marks the target
local ARROW_STEP = 4
local ARROW_SECONDS = 240
local ARROW_REFRESH = 0.3
local REACHED = 8 -- studs (flat) to the last waypoint
local PASSED = 9 -- a waypoint this close counts as passed
local GOLD = Color3.fromRGB(240, 196, 80)

local function flat(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

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

	-- `path`: waypoints on the floor; the last one is the place the hint is about.
	local function showArrow(path: { Vector3 })
		clearArrow()
		if #path == 0 then
			return
		end
		local target = path[#path]
		local model = Instance.new("Model")
		model.Name = "IntroArrow"
		decor("Beacon", Vector3.new(14, 2.4, 2.4), CFrame.new(target + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90)), model, 0.6).Shape = Enum.PartType.Cylinder
		-- a fixed set of chevrons, moved every refresh (two bars each)
		local chevrons: { { Part } } = {}
		for _ = 1, ARROW_LENGTH // ARROW_STEP do
			table.insert(chevrons, {
				decor("Chevron", Vector3.new(0.4, 0.06, 2), CFrame.identity, model, 1),
				decor("Chevron", Vector3.new(0.4, 0.06, 2), CFrame.identity, model, 1),
			})
		end
		model.Parent = Workspace
		arrow = model
		-- start with the waypoint that lies ahead: the nearest one, or the one after it when the
		-- player is already closer to the following waypoint than that one is
		local function firstAhead(position: Vector3): number
			local best, bestDistance = 1, math.huge
			for i, point in path do
				local distance = flat(position, point)
				if distance < bestDistance then
					best, bestDistance = i, distance
				end
			end
			if best < #path and (bestDistance < PASSED or flat(position, path[best + 1]) < flat(path[best], path[best + 1])) then
				best += 1
			end
			return best
		end
		local nextIndex: number? = nil
		local deadline = os.clock() + ARROW_SECONDS
		local pulse = 0
		task.spawn(function()
			while arrow == model and os.clock() < deadline do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local position = root.Position
					if flat(position, target) < REACHED and math.abs(position.Y - target.Y) < 12 then
						break
					end
					local index = nextIndex or firstAhead(position)
					while index < #path and flat(position, path[index]) < PASSED do
						index += 1
					end
					nextIndex = index
					-- lay the chevrons along the way: from the feet to the next waypoint, then on
					local from = Vector3.new(position.X, position.Y - 3, position.Z)
					local used, travelled, skip = 0, 0, ARROW_STEP
					pulse = (pulse + 1) % 4
					for i = index, #path do
						local to = path[i]
						local leg = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
						local length = leg.Magnitude
						if length > 0.5 then
							local direction = leg.Unit
							local d = skip
							while d <= length - 1 and used < #chevrons and travelled + d <= ARROW_LENGTH do
								used += 1
								local height = from.Y + (to.Y - from.Y) * (d / length) + 0.1
								local at = Vector3.new(from.X, height, from.Z) + direction * d
								local frame = CFrame.lookAt(at, at + direction)
								local glow = if (used + pulse) % 4 == 0 then 0 else 0.25
								for n, side in { -1, 1 } do
									local bar = chevrons[used][n]
									bar.CFrame = frame * CFrame.new(side * 0.62, 0, 0.3) * CFrame.Angles(0, side * math.rad(-35), 0)
									bar.Transparency = glow
								end
								d += ARROW_STEP
							end
							skip = math.max(ARROW_STEP - (length - (d - ARROW_STEP)), 1)
							travelled += length
						end
						from = to
						if used >= #chevrons or travelled >= ARROW_LENGTH then
							break
						end
					end
					for i = used + 1, #chevrons do
						chevrons[i][1].Transparency, chevrons[i][2].Transparency = 1, 1
					end
				end
				task.wait(ARROW_REFRESH)
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
				local path: { Vector3 } = {}
				if type(data.path) == "table" then
					for _, point in data.path do
						if typeof(point) == "Vector3" then
							table.insert(path, point)
						end
					end
				end
				if #path == 0 and typeof(data.target) == "Vector3" then
					path = { data.target }
				end
				showArrow(path)
			elseif kind == "Teleport" then
				clearArrow()
			end
		end)
	end
end

return LobbyIntroController
