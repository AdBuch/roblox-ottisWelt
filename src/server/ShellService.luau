--!strict
-- Healing golden shells. Touch -> server validates -> heals exactly Config.ShellHealAmount
-- (never above MaxHealth, never consumed at full health), hides the shell and respawns it
-- at the same spot after Config.ShellRespawnSeconds. Also counts leaderstats.Shells as score.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local CombatUtil = require(script.Parent.CombatUtil)
local Remotes = require(script.Parent.Remotes)

local PREFIX = "[OttiArena][Server]"
local GOLD = Color3.fromRGB(255, 200, 60)

type Shell = {
	id: number,
	part: BasePart,
	light: PointLight,
	burst: ParticleEmitter,
	available: boolean,
}

local ShellService = {}

local function setVisible(shell: Shell, visible: boolean)
	shell.part.Transparency = if visible then 0 else 1
	shell.part.CanTouch = visible
	shell.light.Enabled = visible
	for _, child in shell.part:GetChildren() do
		if child:IsA("BasePart") then
			child.Transparency = if visible then 0 else 1
		end
	end
end

local function addScore(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild("Shells")
	if stat and stat:IsA("IntValue") then
		stat.Value += 1
	end
end

local function tryCollect(shell: Shell, player: Player)
	if not shell.available then
		return
	end
	if not GameStates.isFighter(player:GetAttribute(GameStates.StateAttribute)) then
		return -- shells are part of the fight
	end
	local _, humanoid, root = CombatUtil.getLivingCharacter(player)
	if not humanoid or not root then
		return
	end
	-- Touch events come from client physics; check the player is really there
	if (root.Position - shell.part.Position).Magnitude > Config.ShellPickupRange then
		return
	end
	if humanoid.Health >= humanoid.MaxHealth then
		return -- full health: the shell stays for later
	end

	shell.available = false -- claim it before anything else can
	local before = humanoid.Health
	humanoid.Health = math.min(humanoid.MaxHealth, before + Config.ShellHealAmount)
	local healed = humanoid.Health - before
	addScore(player)
	setVisible(shell, false)
	shell.burst.Enabled = true
	task.delay(0.2, function()
		shell.burst.Enabled = false
	end)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Heal, healed)
	print(PREFIX, ("%s collected shell %d: +%d health (%d/%d)"):format(player.Name, shell.id, math.round(healed), math.round(humanoid.Health), humanoid.MaxHealth))

	task.delay(Config.ShellRespawnSeconds, function()
		if shell.part.Parent then
			shell.available = true
			setVisible(shell, true)
		end
	end)
end

local function buildShell(id: number, position: Vector3, parent: Instance): Shell
	-- A flattened golden scallop shell with a small hinge
	local part = Instance.new("Part")
	part.Name = Config.ShellNamePrefix .. id
	part.Size = Vector3.new(2.4, 1.1, 2.4)
	part.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(-20), 0, 0)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- never blocks combat line-of-sight raycasts
	part.CanTouch = true
	part.Color = GOLD
	part.Material = Enum.Material.Neon
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part

	local hinge = Instance.new("Part")
	hinge.Name = "Hinge"
	hinge.Size = Vector3.new(0.8, 0.4, 0.5)
	hinge.CFrame = part.CFrame * CFrame.new(0, -0.1, 1.15)
	hinge.Anchored = true
	hinge.CanCollide = false
	hinge.CanQuery = false
	hinge.CanTouch = false
	hinge.Color = Color3.fromRGB(220, 160, 50)
	hinge.Material = Enum.Material.Metal
	hinge.Parent = part

	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 10
	light.Parent = part

	local burst = Instance.new("ParticleEmitter")
	burst.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(140, 255, 140))
	burst.LightEmission = 1
	burst.Size = NumberSequence.new(0.5, 0)
	burst.Lifetime = NumberRange.new(0.4, 0.7)
	burst.Speed = NumberRange.new(6, 12)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Rate = 150
	burst.Enabled = false
	burst.Parent = part

	part.Parent = parent
	return { id = id, part = part, light = light, burst = burst, available = true }
end

function ShellService.init(parent: Instance, positions: { Vector3 })
	if #positions < Config.ShellCount then
		warn(PREFIX, ("Only %d shell positions for %d shells"):format(#positions, Config.ShellCount))
	end
	for id = 1, math.min(Config.ShellCount, #positions) do
		local shell = buildShell(id, positions[id], parent)
		shell.part.Touched:Connect(function(hit: BasePart)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				tryCollect(shell, player)
			end
		end)
	end
end

return ShellService
