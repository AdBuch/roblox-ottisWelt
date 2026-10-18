--!strict
-- Crowd control around each target player:
--   * CrowdSlotCount melee slots on a ring (CrowdSlotRadius) around the player. A zombie close
--     to the player claims the free slot nearest to it; others circle on an outer ring.
--   * At most MaxSimultaneousAttackers zombies may be attacking (wind-up or strike) the same
--     player at once, and new wind-ups are spaced by AttackStartSpacing.
-- Keys are opaque zombie objects; everything is released when a zombie dies or is removed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)

type Key = any

type TargetState = {
	slots: { [number]: Key },
	attackers: { [Key]: boolean },
	attackerCount: number,
	lastAttackStart: number,
}

local ZombieCrowdService = {}

local targets: { [Player]: TargetState } = {}
local slotOf: { [Key]: { target: Player, index: number } } = {}
local attackingTarget: { [Key]: Player } = {}

local function getTarget(player: Player): TargetState
	local state = targets[player]
	if not state then
		state = { slots = {}, attackers = {}, attackerCount = 0, lastAttackStart = 0 }
		targets[player] = state
	end
	return state
end

-- `radius`: long weapons stand farther out (defaults to CrowdSlotRadius).
function ZombieCrowdService.slotPosition(targetRoot: BasePart, index: number, radius: number?): Vector3
	local angle = (index - 1) / CombatConfig.CrowdSlotCount * 2 * math.pi
	return targetRoot.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (radius or CombatConfig.CrowdSlotRadius)
end

function ZombieCrowdService.releaseSlot(key: Key)
	local current = slotOf[key]
	if current then
		local state = targets[current.target]
		if state and state.slots[current.index] == key then
			state.slots[current.index] = nil
		end
		slotOf[key] = nil
	end
end

-- Returns the zombie's slot index around this target, claiming the nearest free one if needed.
function ZombieCrowdService.claimSlot(key: Key, target: Player, targetRoot: BasePart, fromPosition: Vector3): number?
	local current = slotOf[key]
	if current and current.target == target then
		return current.index
	end
	ZombieCrowdService.releaseSlot(key)

	local state = getTarget(target)
	local bestIndex, bestDistance = nil, math.huge
	for index = 1, CombatConfig.CrowdSlotCount do
		if state.slots[index] == nil then
			local distance = (ZombieCrowdService.slotPosition(targetRoot, index) - fromPosition).Magnitude
			if distance < bestDistance then
				bestIndex, bestDistance = index, distance
			end
		end
	end
	if bestIndex then
		state.slots[bestIndex] = key
		slotOf[key] = { target = target, index = bestIndex }
	end
	return bestIndex
end

-- Moves the zombie to a neighbouring free slot (used to reposition around a blocking player).
function ZombieCrowdService.shiftSlot(key: Key, direction: number)
	local current = slotOf[key]
	if not current then
		return
	end
	local state = getTarget(current.target)
	local count = CombatConfig.CrowdSlotCount
	local nextIndex = (current.index - 1 + direction) % count + 1
	if state.slots[nextIndex] == nil then
		state.slots[current.index] = nil
		state.slots[nextIndex] = key
		current.index = nextIndex
	end
end

-- Where a zombie without a melee slot should wait: on the outer ring, drifting sideways (circling).
function ZombieCrowdService.waitPosition(targetRoot: BasePart, fromPosition: Vector3, drift: number): Vector3
	local offset = fromPosition - targetRoot.Position
	local angle = math.atan2(offset.Z, offset.X) + drift
	return targetRoot.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * CombatConfig.CrowdWaitRadius
end

-- Attack token: true if this zombie may start (or continue) an attack on the target now.
function ZombieCrowdService.tryStartAttack(key: Key, target: Player): boolean
	if attackingTarget[key] == target then
		return true
	end
	local state = getTarget(target)
	local now = os.clock()
	if state.attackerCount >= CombatConfig.MaxSimultaneousAttackers then
		return false
	end
	if now - state.lastAttackStart < CombatConfig.AttackStartSpacing then
		return false
	end
	state.attackers[key] = true
	state.attackerCount += 1
	state.lastAttackStart = now
	attackingTarget[key] = target
	return true
end

function ZombieCrowdService.endAttack(key: Key)
	local target = attackingTarget[key]
	if target then
		local state = targets[target]
		if state and state.attackers[key] then
			state.attackers[key] = nil
			state.attackerCount -= 1
		end
		attackingTarget[key] = nil
	end
end

function ZombieCrowdService.release(key: Key)
	ZombieCrowdService.releaseSlot(key)
	ZombieCrowdService.endAttack(key)
end

function ZombieCrowdService.reset()
	table.clear(targets)
	table.clear(slotOf)
	table.clear(attackingTarget)
end

return ZombieCrowdService
