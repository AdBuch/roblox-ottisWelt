--!strict
-- ARENA MOMENTUM, server only. Gains come exclusively from server-validated events (a landed hit,
-- a real attack blocked, a perfect block, a slide dodge, a kill); clients can't report anything.
-- Variety pays: repeating the same attack slot shrinks the gain (RepeatFactor per repeat), a
-- different slot adds Diversity, a thrust / overhead right after a side slash adds Sequence.
-- Decay starts DecayDelay seconds after the last meaningful action. Spending is atomic (never
-- below 0). Published as the "Momentum" player attribute; never saved.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MomentumConfig = require(ReplicatedStorage.Shared.MomentumConfig)

type State = {
	value: number,
	lastActive: number,
	lastSlot: string?,
	repeats: number,
	variedSlots: { [string]: boolean }, -- distinct slots since the last kill
}

local MomentumService = {}

local states: { [Player]: State } = {}

local function get(player: Player): State
	local state = states[player]
	if not state then
		state = { value = 0, lastActive = 0, lastSlot = nil, repeats = 0, variedSlots = {} }
		states[player] = state
	end
	return state
end

local function publish(player: Player, state: State)
	if player.Parent then
		player:SetAttribute(Config.MomentumAttribute, math.floor(state.value + 0.5))
	end
end

local function add(player: Player, amount: number)
	local state = get(player)
	state.value = math.clamp(state.value + amount, 0, MomentumConfig.Max)
	state.lastActive = os.clock()
	publish(player, state)
end

-- A validated hit of an attack slot (Momentum variety rules apply).
function MomentumService.onHit(player: Player, slot: string, kind: "Basic" | "Aerial" | "Slide" | "Counter" | "Special")
	local state = get(player)
	local gains = MomentumConfig.Gains
	if kind == "Special" then
		state.lastActive = os.clock() -- keeps Momentum from decaying, never refunds it
		return
	end
	local base = if kind == "Aerial" then gains.AerialHit elseif kind == "Slide" then gains.SlideHit elseif kind == "Counter" then gains.CounterHit else gains.BasicHit
	local bonus = 0
	if state.lastSlot == slot then
		state.repeats += 1
	else
		if state.lastSlot ~= nil then
			bonus += gains.Diversity
		end
		local sideBefore = state.lastSlot == "SlashRL" or state.lastSlot == "SlashLR"
		if sideBefore and (slot == "Thrust" or slot == "Overhead") then
			bonus += gains.Sequence
		end
		state.repeats = 0
	end
	state.lastSlot = slot
	state.variedSlots[slot] = true
	add(player, (base + bonus) * (MomentumConfig.RepeatFactor ^ state.repeats))
end

function MomentumService.onKill(player: Player)
	local state = get(player)
	local distinct = 0
	for _ in state.variedSlots do
		distinct += 1
	end
	table.clear(state.variedSlots)
	if distinct >= 3 then
		add(player, MomentumConfig.Gains.VariedKill)
	end
end

-- Defensive events: "Block" | "PerfectBlock" | "SlideDodge"
function MomentumService.onDefense(player: Player, event: string)
	local gain = (MomentumConfig.Gains :: any)[event]
	if typeof(gain) == "number" and gain > 0 then
		add(player, gain)
	end
end

-- Spends `cost` if available. Returns false (and changes nothing) otherwise.
function MomentumService.trySpend(player: Player, cost: number): boolean
	local state = get(player)
	if cost < 0 or state.value + 0.001 < cost then
		return false
	end
	state.value = math.max(0, state.value - cost)
	state.lastActive = os.clock()
	publish(player, state)
	return true
end

function MomentumService.get(player: Player): number
	return get(player).value
end

-- Match start / end, Elimination rounds.
function MomentumService.reset(player: Player, value: number?)
	local state = get(player)
	state.value = math.clamp(value or 0, 0, MomentumConfig.Max)
	state.lastSlot = nil
	state.repeats = 0
	table.clear(state.variedSlots)
	state.lastActive = os.clock()
	publish(player, state)
end

function MomentumService.init()
	Players.PlayerAdded:Connect(function(player)
		MomentumService.reset(player, 0)
	end)
	for _, player in Players:GetPlayers() do
		MomentumService.reset(player, 0)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.25)
			local now = os.clock()
			local dt = now - last
			last = now
			for player, state in states do
				if state.value > 0 and now - state.lastActive > MomentumConfig.DecayDelay then
					state.value = math.max(0, state.value - MomentumConfig.DecayPerSecond * dt)
					publish(player, state)
				end
			end
		end
	end)
end

return MomentumService
