--!strict
-- Client entry point: HUD, tool input and visual feedback.
-- The client never decides damage, targets, health, cooldowns or block state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PREFIX = "[OttiArena][Client]"
local WAIT_TIMEOUT = 10
local ATTACK_DISPLAY_SECONDS = 0.4
local HIT_DISPLAY_SECONDS = 0.5

local player = Players.LocalPlayer
print(PREFIX, "Client script started for", player.Name)

local function waitFor(parent: Instance, name: string): Instance?
	local child = parent:WaitForChild(name, WAIT_TIMEOUT)
	if not child then
		warn(PREFIX, ("Missing %s.%s after %ds"):format(parent:GetFullName(), name, WAIT_TIMEOUT))
	end
	return child
end

local function waitForModule(parent: Instance?, name: string): ModuleScript?
	local child = parent and waitFor(parent, name)
	if child and child:IsA("ModuleScript") then
		return child
	end
	return nil
end

local shared = waitFor(ReplicatedStorage, "Shared")
local configModule = waitForModule(shared, "Config")
local combatConfigModule = waitForModule(shared, "CombatConfig")
local hudModule = waitForModule(script.Parent, "Hud")
local toolInputModule = waitForModule(script.Parent, "ToolInput")
local animatorModule = waitForModule(script.Parent, "ZombieAnimator")
if not (configModule and combatConfigModule and hudModule and toolInputModule and animatorModule) then
	warn(PREFIX, "Cannot start without Shared.Config, Shared.CombatConfig and the Client modules. Is Rojo synced?")
	return
end

local Config = require(configModule) :: any
local CombatConfig = require(combatConfigModule) :: any
local Hud = require(hudModule) :: any
local ToolInput = require(toolInputModule) :: any
local ZombieAnimator = require(animatorModule) :: any

local hud = Hud.create(player:WaitForChild("PlayerGui"))

-- Combat state shown on the HUD (all driven by server feedback)
local blocking = false
local attackingUntil = 0
local hitUntil = 0
local zombieAlive = true
local announcedComplete = false

local function hasDefeatedZombie(): boolean
	return player:GetAttribute(Config.ZombieDefeatedAttribute) == true
end

local function refreshState()
	local now = os.clock()
	local state = "READY"
	if blocking then
		state = "BLOCKING"
	elseif now < hitUntil then
		state = "HIT"
	elseif now < attackingUntil then
		state = "ATTACKING"
	elseif hasDefeatedZombie() and not zombieAlive then
		state = "VICTORY"
	end
	hud.setState(state)
	hud.setBlocking(blocking)

	local complete = hasDefeatedZombie()
	hud.setComplete(complete)
	if complete and not announcedComplete then
		announcedComplete = true
		print(PREFIX, "SETUP COMPLETE — Otti Arena combat works!")
	end
end

-- Remotes
local remotes = waitFor(ReplicatedStorage, Config.RemotesFolderName)
local swordAttack = remotes and waitFor(remotes, Config.SwordAttackRemoteName)
local shieldBlock = remotes and waitFor(remotes, Config.ShieldBlockRemoteName)
local feedback = remotes and waitFor(remotes, Config.CombatFeedbackRemoteName)

if swordAttack and swordAttack:IsA("RemoteEvent") and shieldBlock and shieldBlock:IsA("RemoteEvent") then
	ToolInput.bind(player, CombatConfig.ToolAttribute, { swordAttack = swordAttack, shieldBlock = shieldBlock })
else
	warn(PREFIX, "Sword/Shield RemoteEvents not found; tool input is disabled")
end

if feedback and feedback:IsA("RemoteEvent") then
	feedback.OnClientEvent:Connect(function(kind: string, a: any, b: any)
		if kind == CombatConfig.Feedback.Swing then
			attackingUntil = os.clock() + ATTACK_DISPLAY_SECONDS
		elseif kind == CombatConfig.Feedback.Block then
			blocking = a == true
		elseif kind == CombatConfig.Feedback.PlayerHit then
			hitUntil = os.clock() + HIT_DISPLAY_SECONDS
			hud.flashHit(b == true)
		end
		refreshState()
	end)
else
	warn(PREFIX, "CombatFeedback RemoteEvent not found; HUD state will stay READY")
end

-- Player health
local function watchCharacter(character: Model)
	blocking = false
	local humanoid = character:WaitForChild("Humanoid", WAIT_TIMEOUT)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local function update()
		hud.setPlayerHealth(humanoid.Health, humanoid.MaxHealth)
	end
	humanoid.HealthChanged:Connect(update)
	update()
	refreshState()
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	task.spawn(watchCharacter, player.Character)
end

-- Shell counter (bonus)
task.spawn(function()
	local leaderstats = waitFor(player, "leaderstats")
	local stat = leaderstats and waitFor(leaderstats, "Shells")
	if not (stat and stat:IsA("IntValue")) then
		return
	end
	local function update()
		hud.setShells(stat.Value, Config.ShellCount)
	end
	stat.Changed:Connect(update)
	update()
end)

-- Arena: zombie health (mirrored as arena attributes), hiding collected shells, walk animation
task.spawn(function()
	local arena = waitFor(Workspace, Config.ArenaFolderName)
	if not arena then
		return
	end

	local function updateZombie()
		local health = tonumber(arena:GetAttribute(CombatConfig.ZombieHealthAttribute)) or 0
		local maxHealth = tonumber(arena:GetAttribute(CombatConfig.ZombieMaxHealthAttribute)) or CombatConfig.ZombieMaxHealth
		zombieAlive = arena:GetAttribute(CombatConfig.ZombieAliveAttribute) == true
		hud.setZombieHealth(health, maxHealth, zombieAlive)
		refreshState()
	end
	arena:GetAttributeChangedSignal(CombatConfig.ZombieHealthAttribute):Connect(updateZombie)
	arena:GetAttributeChangedSignal(CombatConfig.ZombieAliveAttribute):Connect(updateZombie)
	updateZombie()

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
		refreshState()
	end)
	arena.ChildAdded:Connect(hideCollectedShells)
	hideCollectedShells()

	ZombieAnimator.start(arena, CombatConfig.ZombieName)
end)

-- Expire timed states (ATTACKING/HIT) without per-frame work
task.spawn(function()
	while true do
		task.wait(0.1)
		if os.clock() < math.max(attackingUntil, hitUntil) + 0.2 then
			refreshState()
		end
	end
end)

print(PREFIX, "Ready: HUD created, sword/shield input bound")
