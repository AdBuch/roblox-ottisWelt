--!strict
-- Chooses a zombie's next attack SEQUENCE (ZombieAttackDefinitions) on the server. ZombieService
-- executes the steps; clients only see the replicated poses, telegraphs and effects.
-- Selection considers: distance window, the zombie's health condition, whether it still has its
-- shield arm, the target's block (PreferVsBlock), per-sequence cooldowns, and variety (the same
-- sequence never more than MaxRepeats times in a row). Critical zombies block less.
-- Heavy steps of different zombies on the same player are spaced by HeavySpacing so several
-- brutes can never land unavoidable synchronized heavy blows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZombieAttackDefinitions = require(ReplicatedStorage.Shared.ZombieAttackDefinitions)

type Sequence = ZombieAttackDefinitions.Sequence

export type Context = {
	distance: number,
	reach: number,
	targetBlocking: boolean,
	condition: string, -- Healthy | Wounded | Critical
	canBlock: boolean,
	unarmed: boolean,
	now: number,
}

local ZombieAttackSequenceService = {}

local heavyAt: { [Player]: number } = {}

-- A weak bite / kick for zombies that lost their weapon arm.
local BITE: Sequence = table.freeze({
	Id = "Bite",
	Name = "BITE",
	Weight = 1,
	Cooldown = 0,
	Condition = "Any",
	Steps = table.freeze({ table.freeze({ Kind = "Hit", Anim = "Bite", WindUp = 1.2, Damage = 0.55, Arc = 90 }) }),
}) :: any

local function conditionOk(condition: string, state: string): boolean
	if condition == "Any" then
		return true
	elseif condition == "Healthy" then
		return state == "Healthy"
	elseif condition == "Wounded" then
		return state ~= "Healthy"
	elseif condition == "Critical" then
		return state == "Critical"
	elseif condition == "NotCritical" then
		return state ~= "Critical"
	end
	return false
end

local function hasBlock(sequence: Sequence): boolean
	for _, step in sequence.Steps do
		if step.Kind == "Block" then
			return true
		end
	end
	return false
end

function ZombieAttackSequenceService.choose(z: any, ctx: Context): Sequence?
	if ctx.unarmed then
		return BITE
	end
	local recent: { string } = z.recentSequences
	local readyAt: { [string]: number } = z.sequenceReadyAt
	local candidates: { { sequence: Sequence, weight: number } } = {}
	local total = 0
	for _, sequence in ZombieAttackDefinitions.forZombie(z.definition.Id) do
		if not conditionOk(sequence.Condition, ctx.condition) then
			continue
		end
		if sequence.NeedsShield and not ctx.canBlock then
			continue
		end
		if ctx.now < (readyAt[sequence.Id] or 0) then
			continue
		end
		local minDistance = sequence.MinDistance or 0
		local maxDistance = sequence.MaxDistance or (ctx.reach + 0.5)
		if ctx.distance < minDistance or ctx.distance > maxDistance then
			continue -- never start a sequence the target is already out of range for
		end
		local repeats = 0
		for i = #recent, math.max(1, #recent - ZombieAttackDefinitions.MaxRepeats + 1), -1 do
			if recent[i] == sequence.Id then
				repeats += 1
			end
		end
		if repeats >= ZombieAttackDefinitions.MaxRepeats then
			continue
		end
		local weight = sequence.Weight
		if ctx.targetBlocking and sequence.PreferVsBlock then
			weight *= 2.5
		end
		if ctx.condition == "Critical" and hasBlock(sequence) then
			weight *= 0.3 -- critical zombies block less
		end
		if #recent > 0 and recent[#recent] == sequence.Id then
			weight *= 0.5
		end
		total += weight
		table.insert(candidates, { sequence = sequence, weight = weight })
	end
	if total <= 0 then
		return nil
	end
	local roll = z.rng:NextNumber() * total
	for _, entry in candidates do
		roll -= entry.weight
		if roll <= 0 then
			return entry.sequence
		end
	end
	return candidates[#candidates].sequence
end

function ZombieAttackSequenceService.markUsed(z: any, sequence: Sequence, now: number)
	local recent: { string } = z.recentSequences
	table.insert(recent, sequence.Id)
	while #recent > 4 do
		table.remove(recent, 1)
	end
	z.sequenceReadyAt[sequence.Id] = now + sequence.Cooldown
end

-- May a heavy step land on this player now? (spaced between different zombies)
function ZombieAttackSequenceService.claimHeavy(player: Player, now: number): boolean
	if now - (heavyAt[player] or -math.huge) < ZombieAttackDefinitions.HeavySpacing then
		return false
	end
	heavyAt[player] = now
	return true
end

function ZombieAttackSequenceService.forget(player: Player)
	heavyAt[player] = nil
end

return ZombieAttackSequenceService
