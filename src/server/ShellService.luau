--!strict
-- Healing golden shells. 12 symmetric spots exist; the active match decides how many are in
-- play (Solo 8, Co-op 4 + 2 per player up to 12, Team Battle 0 by default).
-- Touch -> server validates (active, available, fighting player, really there, not at full
-- health) -> heals exactly Config.ShellHealAmount (never above MaxHealth), hides the shell and
-- respawns it after Config.ShellRespawnSeconds (not right beneath a player). Healing only
-- affects the collecting player. Also counts leaderstats.Shells.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatRules = require(script.Parent.CombatRules)
local CombatUtil = require(script.Parent.CombatUtil)
local Remotes = require(script.Parent.Remotes)
local ZombieService = require(script.Parent.ZombieService)

local PREFIX = "[OttiArena][Server]"
local GOLD = Color3.fromRGB(255, 200, 60)
local CLEARANCE = 4 -- never respawn a shell this close to a player

type Shell = {
	id: number,
	part: BasePart,
	light: PointLight,
	active: boolean, -- part of the current match's set
	available: boolean, -- can be collected right now
	token: number,
}

local ShellService = {}

local shells: { Shell } = {}

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

local function playerNear(position: Vector3): boolean
	for _, player in Players:GetPlayers() do
		local _, _, root = CombatUtil.getLivingCharacter(player)
		if root and CombatUtil.flatDistance(root.Position, position) < CLEARANCE then
			return true
		end
	end
	return false
end

local function addScore(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild("Shells")
	if stat and stat:IsA("IntValue") then
		stat.Value += 1
	end
end

local function scheduleRespawn(shell: Shell, delay: number)
	local token = shell.token
	task.delay(delay, function()
		if shell.token ~= token or not shell.active then
			return
		end
		if playerNear(shell.part.Position) then
			scheduleRespawn(shell, 1) -- don't pop up right beneath someone
			return
		end
		shell.available = true
		setVisible(shell, true)
	end)
end

local function tryCollect(shell: Shell, player: Player)
	if not shell.active or not shell.available then
		return
	end
	local context = CombatRules.getContext(player)
	if context ~= "Zombies" and context ~= "PvP" then
		return -- only match fighters
	end
	local _, humanoid, root = CombatUtil.getLivingCharacter(player)
	if not humanoid or not root then
		return
	end
	if (root.Position - shell.part.Position).Magnitude > Config.ShellPickupRange then
		return -- touch events come from client physics; check the player is really there
	end
	if humanoid.Health >= humanoid.MaxHealth then
		return -- full health: the shell stays for later
	end

	shell.available = false -- claimed: can't be collected twice
	local before = humanoid.Health
	humanoid.Health = math.min(humanoid.MaxHealth, before + Config.ShellHealAmount)
	local healed = humanoid.Health - before
	addScore(player)
	setVisible(shell, false)
	CombatEffects.burst(shell.part.Position, Color3.fromRGB(140, 255, 140), 1)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Heal, healed)
	ZombieService.onPlayerHealed(player, healed)
	print(PREFIX, ("%s collected shell %d: +%d health (%d/%d)"):format(player.Name, shell.id, math.round(healed), math.round(humanoid.Health), humanoid.MaxHealth))
	scheduleRespawn(shell, Config.ShellRespawnSeconds)
end

local function buildShell(id: number, position: Vector3, parent: Instance): Shell
	local part = Instance.new("Part")
	part.Name = Config.ShellNamePrefix .. id
	part.Size = Vector3.new(2.4, 1.1, 2.4)
	part.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(-20), 0, 0)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- never blocks combat line-of-sight raycasts
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

	part.Parent = parent
	local shell: Shell = { id = id, part = part, light = light, active = false, available = false, token = 0 }
	setVisible(shell, false)
	return shell
end

function ShellService.init(parent: Instance, positions: { Vector3 })
	for id, position in positions do
		local shell = buildShell(id, position, parent)
		table.insert(shells, shell)
		shell.part.Touched:Connect(function(hit: BasePart)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				tryCollect(shell, player)
			end
		end)
	end
end

-- Activates the first `count` shell spots (symmetric by construction) and hides the rest.
function ShellService.setActiveCount(count: number)
	for index, shell in shells do
		shell.token += 1
		shell.active = index <= count
		shell.available = shell.active
		setVisible(shell, shell.active)
	end
end

function ShellService.activeCount(): number
	local count = 0
	for _, shell in shells do
		if shell.active then
			count += 1
		end
	end
	return count
end

return ShellService
