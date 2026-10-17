--!strict
-- Golden shells: touched on the server, validated, and counted once per player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PREFIX = "[OttiArena][Server]"
local GOLD = Color3.fromRGB(255, 200, 60)

local Shells = {}

local function getShellsStat(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild("Shells")
	if stat and stat:IsA("IntValue") then
		return stat
	end
	return nil
end

local function tryCollect(player: Player, shell: BasePart, id: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	-- Touch events come from the client's physics; double-check the player is actually there.
	if (root.Position - shell.Position).Magnitude > Config.ShellPickupRange then
		return
	end

	local attribute = Config.ShellAttributePrefix .. id
	if player:GetAttribute(attribute) == true then
		return
	end

	local stat = getShellsStat(player)
	if not stat then
		warn(PREFIX, player.Name, "has no leaderstats.Shells; shell not counted")
		return
	end
	player:SetAttribute(attribute, true)
	stat.Value += 1
	print(PREFIX, ("%s collected shell %d (%d/%d)"):format(player.Name, id, stat.Value, Config.ShellCount))
end

function Shells.init(parent: Instance, positions: { Vector3 })
	if #positions < Config.ShellCount then
		warn(PREFIX, ("Only %d shell positions for %d shells"):format(#positions, Config.ShellCount))
	end

	for id = 1, math.min(Config.ShellCount, #positions) do
		local shell = Instance.new("Part")
		shell.Name = Config.ShellNamePrefix .. id
		shell.Shape = Enum.PartType.Ball
		shell.Size = Vector3.new(2, 2, 2)
		shell.Position = positions[id]
		shell.Anchored = true
		shell.CanCollide = false
		shell.CanTouch = true
		shell.Color = GOLD
		shell.Material = Enum.Material.Neon
		shell:SetAttribute("ShellId", id)

		local light = Instance.new("PointLight")
		light.Color = GOLD
		light.Range = 10
		light.Parent = shell

		shell.Touched:Connect(function(hit: BasePart)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				tryCollect(player, shell, id)
			end
		end)

		shell.Parent = parent
	end
end

return Shells
