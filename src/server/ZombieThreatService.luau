--!strict
-- Per-zombie threat memory and target distribution across players.
--   * Threat rises when a player damages a zombie (proportional to damage), blocks its attack
--     (small) or heals near it (small), and decays over time.
--   * targetCount(player) tells how many zombies currently chase a player, so the AI can spread
--     out instead of everyone chasing the same person.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)

type Key = any

type Memory = {
	threat: { [Player]: number },
	updated: number,
	target: Player?,
}

local ZombieThreatService = {}

local memories: { [Key]: Memory } = {}
local targetCounts: { [Player]: number } = {}

local function getMemory(key: Key): Memory
	local memory = memories[key]
	if not memory then
		memory = { threat = {}, updated = os.clock(), target = nil }
		memories[key] = memory
	end
	return memory
end

local function decay(memory: Memory)
	local now = os.clock()
	local elapsed = now - memory.updated
	memory.updated = now
	if elapsed <= 0 then
		return
	end
	local factor = math.max(0, 1 - CombatConfig.ThreatDecayPerSecond * elapsed)
	for player, value in memory.threat do
		local decayed = value * factor
		if decayed < 0.5 then
			memory.threat[player] = nil
		else
			memory.threat[player] = decayed
		end
	end
end

function ZombieThreatService.add(key: Key, player: Player, amount: number)
	local memory = getMemory(key)
	decay(memory)
	memory.threat[player] = (memory.threat[player] or 0) + amount
end

function ZombieThreatService.get(key: Key, player: Player): number
	local memory = getMemory(key)
	decay(memory)
	return memory.threat[player] or 0
end

-- The player this zombie damaged most recently matters; remember who hit it.
function ZombieThreatService.recentAttackers(key: Key): { Player }
	local memory = getMemory(key)
	decay(memory)
	local list = {}
	for player in memory.threat do
		table.insert(list, player)
	end
	return list
end

function ZombieThreatService.setTarget(key: Key, player: Player?)
	local memory = getMemory(key)
	if memory.target == player then
		return
	end
	local old = memory.target
	if old then
		targetCounts[old] = math.max(0, (targetCounts[old] or 1) - 1)
	end
	memory.target = player
	if player then
		targetCounts[player] = (targetCounts[player] or 0) + 1
	end
end

function ZombieThreatService.targetCount(player: Player): number
	return targetCounts[player] or 0
end

function ZombieThreatService.release(key: Key)
	ZombieThreatService.setTarget(key, nil)
	memories[key] = nil
end

function ZombieThreatService.reset()
	table.clear(memories)
	table.clear(targetCounts)
end

return ZombieThreatService
