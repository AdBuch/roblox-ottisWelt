--!strict
-- Contextual world-space health bars (BillboardGui, pooled; never AlwaysOnTop, so walls hide them):
--   zombies / dummies  only when you hit them, they hit you, you aim at them or they are very close;
--                      they disappear ~3 s after the last interaction and immediately on death;
--                      at most UiConfig.MaxEnemyBarsPhone / Desktop, nearest relevant first
--   Team Battle        teammates within range (team-coloured outline, short name); opponents only
--                      after a hit either way or while you aim at them
--   Co-op              party members within range (tiny bar)
--   Lobby              short names of nearby players, no bars
-- Line of sight and distances are checked a few times per second, not every frame. Otti uses the
-- boss bar instead. Roblox's default overhead names/health are turned off for other players.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiConfig = require(Shared:WaitForChild("UiConfig"))

export type Options = {
	zombieTag: string,
	dummyTag: string,
	teamAttribute: string,
	isPhone: () -> boolean,
	allowed: () -> boolean, -- the "Context" HUD group is allowed right now
	uiState: () -> string,
}

export type ContextHealth = {
	markInteraction: (model: Instance) -> (),
	markAttackerNear: (position: Vector3) -> (),
}

type Bar = {
	gui: BillboardGui,
	name: TextLabel,
	fill: Frame,
	back: Frame,
	number: TextLabel,
	stroke: UIStroke,
	model: Instance?,
}

type Candidate = { model: Model, root: BasePart, kind: string, priority: number, distance: number, aimed: boolean, player: Player? }

local ContextHealthController = {}

function ContextHealthController.start(playerGui: Instance, options: Options): ContextHealth
	local localPlayer = Players.LocalPlayer
	local interactions: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
	local pool: { Bar } = {}
	local assigned: { [Instance]: Bar } = {}

	local folder = Instance.new("Folder")
	folder.Name = "ContextHealthBars"
	folder.Parent = playerGui

	local function newBar(): Bar
		local gui = Instance.new("BillboardGui")
		gui.Name = "ContextBar"
		gui.Size = UDim2.new(3.4, 0, 0.75, 0) -- studs: shrinks with distance automatically
		gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
		gui.AlwaysOnTop = false -- never through walls
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		gui.Enabled = false
		gui.Parent = folder
		local name = Instance.new("TextLabel")
		name.Size = UDim2.fromScale(1, 0.5)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.TextColor3 = Color3.new(1, 1, 1)
		name.TextStrokeTransparency = 0.4
		name.Parent = gui
		local back = Instance.new("Frame")
		back.Position = UDim2.fromScale(0.08, 0.58)
		back.Size = UDim2.fromScale(0.84, 0.32)
		back.BackgroundColor3 = Color3.fromRGB(30, 18, 16)
		back.BackgroundTransparency = 0.2
		back.BorderSizePixel = 0
		back.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = back
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Transparency = 1
		stroke.Parent = back
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BorderSizePixel = 0
		fill.Parent = back
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0.5, 0)
		fillCorner.Parent = fill
		local number = Instance.new("TextLabel")
		number.Size = UDim2.fromScale(1, 1)
		number.BackgroundTransparency = 1
		number.Font = Enum.Font.GothamBold
		number.TextScaled = true
		number.TextColor3 = Color3.new(1, 1, 1)
		number.TextStrokeTransparency = 0.5
		number.Parent = back
		return { gui = gui, name = name, fill = fill, back = back, number = number, stroke = stroke, model = nil }
	end

	local function release(model: Instance)
		local bar = assigned[model]
		if bar then
			assigned[model] = nil
			bar.model = nil
			bar.gui.Enabled = false
			(bar.gui :: any).Adornee = nil
			table.insert(pool, bar)
		end
	end

	local function acquire(model: Instance): Bar
		local existing: Bar? = assigned[model]
		if existing then
			return existing
		end
		local bar: Bar = table.remove(pool) or newBar()
		bar.model = model
		assigned[model] = bar
		return bar
	end

	-- Hide Roblox's default overhead name/health for other players (replaced by these bars)
	local function hideDefault(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
	local function watchPlayer(player: Player)
		if player == localPlayer then
			return
		end
		player.CharacterAdded:Connect(hideDefault)
		if player.Character then
			task.spawn(hideDefault, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			release(player.Character)
		end
	end)

	local function aimedModel(): Instance?
		local camera = Workspace.CurrentCamera
		local character = localPlayer.Character
		if not camera then
			return nil
		end
		local ray: Ray
		local lastInput = UserInputService:GetLastInputType()
		if UserInputService.MouseEnabled and lastInput ~= Enum.UserInputType.Touch and lastInput.Name:sub(1, 7) ~= "Gamepad" then
			local mouse = UserInputService:GetMouseLocation()
			ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		else
			ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = if character then { character } else {}
		local result = Workspace:Raycast(ray.Origin, ray.Direction * UiConfig.ContextMaxDistance, params)
		if result then
			return result.Instance:FindFirstAncestorOfClass("Model")
		end
		return nil
	end

	local function visible(fromPosition: Vector3, root: BasePart, model: Instance): boolean
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore: { Instance } = { model }
		if localPlayer.Character then
			table.insert(ignore, localPlayer.Character)
		end
		params.FilterDescendantsInstances = ignore
		params.RespectCanCollide = true
		local result = Workspace:Raycast(fromPosition, root.Position - fromPosition, params)
		if result == nil then
			return true
		end
		-- Other fighters in between don't hide a bar; walls and solid geometry do
		local blocker = result.Instance:FindFirstAncestorOfClass("Model")
		return blocker ~= nil and blocker:FindFirstChildOfClass("Humanoid") ~= nil
	end

	local function healthOf(candidate: Candidate): (number, number)
		if candidate.player then
			local humanoid = candidate.model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				return humanoid.Health, humanoid.MaxHealth
			end
			return 0, 1
		end
		return tonumber(candidate.model:GetAttribute("Health")) or 0, tonumber(candidate.model:GetAttribute("MaxHealth")) or 1
	end

	local function update()
		local camera = Workspace.CurrentCamera
		local character = localPlayer.Character
		local myRoot = character and character:FindFirstChild("HumanoidRootPart")
		if not camera or not myRoot or not myRoot:IsA("BasePart") or not options.allowed() then
			for model in assigned do
				release(model)
			end
			return
		end
		local now = os.clock()
		local state = options.uiState()
		local aimed = aimedModel()
		local myTeam = localPlayer:GetAttribute(options.teamAttribute)
		local enemies: { Candidate } = {}
		local friends: { Candidate } = {}
		local eye = camera.CFrame.Position

		local function consider(model: Instance, kind: string, player: Player?)
			if not model:IsA("Model") then
				return
			end
			local root = model:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then
				return
			end
			local distance = (root.Position - myRoot.Position).Magnitude
			if distance > UiConfig.ContextMaxDistance then
				return
			end
			local isAimed = aimed ~= nil and (aimed == model or aimed:IsDescendantOf(model))
			local interacted = now - (interactions[model] or -100) <= UiConfig.ContextBarTimeout
			local candidate: Candidate = { model = model, root = root, kind = kind, priority = 0, distance = distance, aimed = isAimed, player = player }
			if kind == "Teammate" then
				if distance <= UiConfig.TeammateBarDistance then
					table.insert(friends, candidate)
				end
			elseif kind == "Name" then
				if distance <= 30 then
					table.insert(friends, candidate)
				end
			elseif interacted or isAimed or (kind ~= "Opponent" and distance <= UiConfig.ContextNearDistance) then
				candidate.priority = if interacted then 0 elseif isAimed then 1 else 2
				table.insert(enemies, candidate)
			end
		end

		if state ~= "Lobby" then
			for _, model in CollectionService:GetTagged(options.zombieTag) do
				consider(model, "Zombie", nil)
			end
		else
			for _, model in CollectionService:GetTagged(options.dummyTag) do
				consider(model, "Dummy", nil)
			end
		end
		for _, other in Players:GetPlayers() do
			local otherCharacter = other.Character
			if other ~= localPlayer and otherCharacter then
				local humanoid = otherCharacter:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					local otherTeam = other:GetAttribute(options.teamAttribute)
					if state == "TeamBattle" and (otherTeam == "Red" or otherTeam == "Blue") then
						consider(otherCharacter, if otherTeam == myTeam then "Teammate" else "Opponent", other)
					elseif state == "Coop" or state == "Boss" then
						consider(otherCharacter, "Teammate", other)
					elseif state == "Lobby" then
						consider(otherCharacter, "Name", other)
					end
				end
			end
		end

		table.sort(enemies, function(a, b)
			if a.priority ~= b.priority then
				return a.priority < b.priority
			end
			return a.distance < b.distance
		end)
		local limit = if options.isPhone() then UiConfig.MaxEnemyBarsPhone else UiConfig.MaxEnemyBarsDesktop
		local shown: { [Instance]: Candidate } = {}
		local count = 0
		for _, candidate in enemies do
			if count >= limit then
				break
			end
			if visible(eye, candidate.root, candidate.model) then
				shown[candidate.model] = candidate
				count += 1
			end
		end
		for _, candidate in friends do
			shown[candidate.model] = candidate
		end

		for model in assigned do
			if not shown[model] then
				release(model)
			end
		end
		local phone = options.isPhone()
		for model, candidate in shown do
			local bar = acquire(model)
			bar.gui.Adornee = candidate.root
			bar.gui.Enabled = true
			local health, maxHealth = healthOf(candidate)
			local share = math.clamp(health / math.max(1, maxHealth), 0, 1)
			bar.fill.Size = UDim2.fromScale(share, 1)
			bar.fill.BackgroundColor3 = if share > 0.5 then UiConfig.HealthHigh elseif share > UiConfig.LowHealthShare then UiConfig.HealthMid else UiConfig.HealthLow
			local teamColor = if candidate.player then (if candidate.player:GetAttribute(options.teamAttribute) == "Red" then UiConfig.Red elseif candidate.player:GetAttribute(options.teamAttribute) == "Blue" then UiConfig.Blue else nil) else nil
			bar.stroke.Color = teamColor or Color3.new(0, 0, 0)
			bar.stroke.Transparency = if teamColor then 0 else 1
			local label = if candidate.player then (candidate.player :: Player).DisplayName else tostring(model:GetAttribute("ZombieType") or "")
			if #label > 12 then
				label = label:sub(1, 11) .. "…"
			end
			bar.name.Text = label
			bar.name.Visible = candidate.kind ~= "Zombie" or not phone -- zombie names are omitted on phones
			bar.name.TextColor3 = teamColor or Color3.new(1, 1, 1)
			bar.back.Visible = candidate.kind ~= "Name"
			bar.number.Text = if candidate.aimed or candidate.distance < 10 then ("%d"):format(math.ceil(health)) else ""
		end
	end

	task.spawn(function()
		while true do
			task.wait(UiConfig.ContextUpdateInterval)
			local ok, err = pcall(update :: any)
			if not ok then
				warn("[OttiArena][Client] Context health bars:", err)
			end
		end
	end)

	local function mark(model: Instance)
		local owner = model
		local ancestor = model:FindFirstAncestorOfClass("Model")
		while ancestor and ancestor ~= Workspace do
			if ancestor:FindFirstChild("HumanoidRootPart") then
				owner = ancestor
			end
			ancestor = ancestor:FindFirstAncestorOfClass("Model")
		end
		interactions[owner] = os.clock()
	end

	return {
		markInteraction = mark,
		-- Something hit us from this position: mark the zombie/player standing there
		markAttackerNear = function(position: Vector3)
			local best, bestDistance = nil, 4
			for _, model in CollectionService:GetTagged(options.zombieTag) do
				local root = model:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and (root.Position - position).Magnitude < bestDistance then
					best, bestDistance = model, (root.Position - position).Magnitude
				end
			end
			for _, other in Players:GetPlayers() do
				local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
				if other ~= localPlayer and root and root:IsA("BasePart") and (root.Position - position).Magnitude < bestDistance then
					best, bestDistance = other.Character, (root.Position - position).Magnitude
				end
			end
			if best then
				interactions[best] = os.clock()
			end
		end,
	}
end

return ContextHealthController
