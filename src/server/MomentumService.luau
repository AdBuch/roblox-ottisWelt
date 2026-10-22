--!strict
-- Time-based special energy. All regeneration and spending are server-owned.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MomentumConfig = require(ReplicatedStorage.Shared.MomentumConfig)
local CombatRules = require(script.Parent.CombatRules)

type State = { value: number, updatedAt: number }
local MomentumService = {}
local states: { [Player]: State } = {}
local initialized = false

local function publish(player: Player, state: State)
	if player.Parent then
		-- Round down: the UI must never advertise a tier the server cannot afford.
		local value = math.floor(state.value)
		if player:GetAttribute(Config.MomentumAttribute) ~= value then
			player:SetAttribute(Config.MomentumAttribute, value)
		end
	end
end

local function getState(player: Player): State
	local state = states[player]
	if not state then
		state = { value = 0, updatedAt = os.clock() }
		states[player] = state
	end
	return state
end

local function advance(player: Player): State
	local state = getState(player)
	local now = os.clock()
	local dt = math.max(0, now - state.updatedAt)
	state.updatedAt = now
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and CombatRules.getContext(player) ~= nil then
		state.value = math.min(MomentumConfig.Max, state.value + MomentumConfig.RegenPerSecond * dt)
	end
	publish(player, state)
	return state
end

function MomentumService.trySpend(player: Player, cost: number): boolean
	local state = advance(player)
	if cost ~= cost or cost < 0 or cost == math.huge or state.value < cost then
		return false
	end
	state.value -= cost
	publish(player, state)
	return true
end

function MomentumService.get(player: Player): number
	return advance(player).value
end

function MomentumService.reset(player: Player, value: number?)
	local state = getState(player)
	state.value = math.clamp(value or 0, 0, MomentumConfig.Max)
	state.updatedAt = os.clock()
	publish(player, state)
end

function MomentumService.init()
	if initialized then
		return
	end
	initialized = true
	Players.PlayerAdded:Connect(function(player)
		MomentumService.reset(player)
	end)
	for _, player in Players:GetPlayers() do
		MomentumService.reset(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(MomentumConfig.UpdateSeconds)
			for player in states do
				advance(player)
			end
		end
	end)
end
return MomentumService
