--!strict
-- Validates attack requests. The client only says "I attacked"; the server decides
-- the target, range, cooldown and damage. Any extra arguments from the client are ignored.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Dummy = require(script.Parent.Dummy)

local PREFIX = "[OttiArena][Server]"

local Combat = {}

local lastAttack: { [Player]: number } = {}
local announced: { [Player]: boolean } = {}

local function onAttack(player: Player)
	if not announced[player] then
		announced[player] = true
		print(PREFIX, "First attack request received from", player.Name, "(RemoteEvent works)")
	end

	local now = os.clock()
	local last = lastAttack[player]
	if last and now - last < Config.AttackCooldown then
		return
	end
	lastAttack[player] = now

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end

	local target = Dummy.getTargetPosition()
	if not target or (root.Position - target).Magnitude > Config.AttackRange then
		return
	end

	Dummy.applyDamage(Config.AttackDamage, player)
end

function Combat.init(attackRemote: RemoteEvent)
	attackRemote.OnServerEvent:Connect(onAttack)
	Players.PlayerRemoving:Connect(function(player)
		lastAttack[player] = nil
		announced[player] = nil
	end)
end

return Combat
