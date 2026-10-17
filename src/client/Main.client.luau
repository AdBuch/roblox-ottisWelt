--!strict
-- Client entry point: HUD, attack input and local display of server state.
-- The client never decides damage or targets; it only sends "attack" requests.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local PREFIX = "[OttiArena][Client]"
local WAIT_TIMEOUT = 10

local player = Players.LocalPlayer
print(PREFIX, "Client script started for", player.Name)

local function waitFor(parent: Instance, name: string): Instance?
	local child = parent:WaitForChild(name, WAIT_TIMEOUT)
	if not child then
		warn(PREFIX, ("Missing %s.%s after %ds"):format(parent:GetFullName(), name, WAIT_TIMEOUT))
	end
	return child
end

local shared = waitFor(ReplicatedStorage, "Shared")
local configModule = shared and waitFor(shared, "Config")
local hudModule = waitFor(script.Parent, "Hud")
if not (configModule and configModule:IsA("ModuleScript") and hudModule and hudModule:IsA("ModuleScript")) then
	warn(PREFIX, "Cannot start without Shared.Config and Client.Hud. Is Rojo synced?")
	return
end

local Config = require(configModule) :: any
local Hud = require(hudModule) :: any

local hud = Hud.create(player:WaitForChild("PlayerGui"))

-- Goal tracking (values come from the server via leaderstats and attributes)
local shellCount = 0
local announcedComplete = false

local function refreshGoal()
	local complete = shellCount >= Config.ShellCount and player:GetAttribute(Config.ZombieDefeatedAttribute) == true
	hud.setComplete(complete)
	if complete and not announcedComplete then
		announcedComplete = true
		print(PREFIX, "Setup successful — Rojo, client and server are working!")
	end
end

-- Attack input
local remotes = waitFor(ReplicatedStorage, Config.RemotesFolderName)
local attackRemote = remotes and waitFor(remotes, Config.AttackRemoteName)
if attackRemote and attackRemote:IsA("RemoteEvent") then
	local remote: RemoteEvent = attackRemote
	local lastSent = 0
	local attacksSent = 0
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local now = os.clock()
		if now - lastSent < Config.AttackCooldown then
			return
		end
		lastSent = now
		attacksSent += 1
		remote:FireServer()
		hud.setAttacksSent(attacksSent)
	end)
else
	warn(PREFIX, "Attack RemoteEvent not found; left-click attacks are disabled")
end

-- Shell counter
task.spawn(function()
	local leaderstats = waitFor(player, "leaderstats")
	local stat = leaderstats and waitFor(leaderstats, "Shells")
	if not (stat and stat:IsA("IntValue")) then
		return
	end
	local function update()
		shellCount = stat.Value
		hud.setShells(shellCount, Config.ShellCount)
		refreshGoal()
	end
	stat.Changed:Connect(update)
	update()
end)

-- Arena: dummy health and hiding shells this player already collected
task.spawn(function()
	local arena = waitFor(Workspace, Config.ArenaFolderName)
	if not arena then
		return
	end

	local function hideCollectedShells()
		for id = 1, Config.ShellCount do
			if player:GetAttribute(Config.ShellAttributePrefix .. id) == true then
				local shell = arena:FindFirstChild(Config.ShellNamePrefix .. id)
				if shell and shell:IsA("BasePart") then
					-- Local-only change: other players still see their own shells.
					shell.Transparency = 1
					local light = shell:FindFirstChildOfClass("PointLight")
					if light then
						light.Enabled = false
					end
				end
			end
		end
	end
	player.AttributeChanged:Connect(function()
		hideCollectedShells()
		refreshGoal()
	end)
	arena.ChildAdded:Connect(hideCollectedShells)
	hideCollectedShells()

	local dummy = waitFor(arena, Config.DummyName)
	if not dummy then
		return
	end
	local function updateDummy()
		local health = tonumber(dummy:GetAttribute("Health")) or 0
		local maxHealth = tonumber(dummy:GetAttribute("MaxHealth")) or Config.DummyMaxHealth
		hud.setDummyHealth(health, maxHealth, dummy:GetAttribute("Alive") == true)
	end
	dummy:GetAttributeChangedSignal("Health"):Connect(updateDummy)
	dummy:GetAttributeChangedSignal("Alive"):Connect(updateDummy)
	updateDummy()
end)

print(PREFIX, "Ready: HUD created and left-click attack bound")
