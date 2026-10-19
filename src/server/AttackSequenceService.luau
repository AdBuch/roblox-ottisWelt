--!strict
-- Picks the NEXT normal attack, server-side, from the context (WeaponAttackDefinitions):
--   priority  parry counter window > slide (one slide attack) > airborne > movement / gesture > chain
--   Classic   movement relative to the facing (replicated physics, not client claims): forward ->
--             Up slot, sideways -> the matching side slash, backward -> Retreat; three or more
--             zombies in reach -> Wide; otherwise the weapon's chain
--   Wild      the gesture's direction picks the slot (airborne: Air slots, Down = the aerial dive)
-- The chain never repeats the exact same move back to back and resets after ChainResetSeconds,
-- weapon changes, stuns, knockdowns, death and leaving combat (reset()).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local SpecialMoveDefinitions = require(ReplicatedStorage.Shared.SpecialMoveDefinitions)
local WeaponAttackDefinitions = require(ReplicatedStorage.Shared.WeaponAttackDefinitions)
local CombatUtil = require(script.Parent.CombatUtil)

export type Choice = { moveId: string, slot: string, kind: "Basic" | "Aerial" | "Slide" | "Counter" }

export type Context = {
	weaponBasic: string, -- WeaponDefinitions.Basic
	weaponAerial: string,
	root: BasePart,
	counter: boolean,
	slide: boolean,
	airborne: boolean, -- an aerial is allowed now (JumpAttackService.tryAerial already passed)
	gesture: string?, -- Wild: Left | Right | Up | Down | Circle
}

type State = { index: number, lastTime: number, lastMove: string? }

local AttackSequenceService = {}

local states: { [Player]: State } = {}

local function get(player: Player): State
	local state = states[player]
	if not state then
		state = { index = 0, lastTime = 0, lastMove = nil }
		states[player] = state
	end
	return state
end

local function exists(id: string): boolean
	return (SpecialMoveDefinitions :: any)[id] ~= nil
end

local function nearbyZombies(root: BasePart, range: number): number
	local count = 0
	local look = CombatUtil.flat(root.CFrame.LookVector)
	for _, model in CollectionService:GetTagged(CombatConfig.ZombieTag) do
		local zroot = model:IsA("Model") and model.PrimaryPart
		if zroot then
			local offset = CombatUtil.flat(zroot.Position - root.Position)
			if offset.Magnitude <= range and (offset.Magnitude < 0.1 or look.Magnitude < 0.1 or look.Unit:Dot(offset.Unit) > -0.2) then
				count += 1
			end
		end
	end
	return count
end

-- Movement relative to the facing: "Up" (forward), "Back", "Left", "Right" or nil (standing).
local function movementSlot(root: BasePart): string?
	local velocity = CombatUtil.flat(root.AssemblyLinearVelocity)
	if velocity.Magnitude < WeaponAttackDefinitions.MovementThreshold then
		return nil
	end
	local look = CombatUtil.flat(root.CFrame.LookVector)
	local right = CombatUtil.flat(root.CFrame.RightVector)
	if look.Magnitude < 0.1 then
		return nil
	end
	local f = velocity.Unit:Dot(look.Unit)
	local r = velocity.Unit:Dot(right.Unit)
	if f > 0.6 then
		return "Up"
	elseif f < -0.6 then
		return "Back"
	end
	return if r > 0 then "Right" else "Left"
end

function AttackSequenceService.choose(player: Player, ctx: Context): Choice?
	local attacks = WeaponAttackDefinitions.forBasic(ctx.weaponBasic)
	if not attacks then
		return { moveId = ctx.weaponBasic, slot = "Basic", kind = "Basic" }
	end
	local prefix = attacks.Prefix
	local state = get(player)
	local now = os.clock()
	if now - state.lastTime > WeaponAttackDefinitions.ChainResetSeconds then
		state.index = 0
		state.lastMove = nil
	end

	local function pick(slot: string, kind: "Basic" | "Aerial" | "Slide" | "Counter"): Choice?
		local id = WeaponAttackDefinitions.moveId(prefix, slot)
		if exists(id) then
			return { moveId = id, slot = slot, kind = kind }
		end
		return nil
	end

	local choice: Choice? = nil
	if ctx.counter then
		choice = pick("Counter", "Counter")
	end
	if not choice and ctx.slide then
		choice = pick("Slide", "Slide")
	end
	if not choice and ctx.airborne then
		local gesture = ctx.gesture
		if gesture == "Left" then
			choice = pick("AirLeft", "Aerial")
		elseif gesture == "Right" then
			choice = pick("AirRight", "Aerial")
		elseif gesture == "Up" then
			choice = pick("AirUp", "Aerial")
		end
		if not choice then
			choice = { moveId = ctx.weaponAerial, slot = "AirDown", kind = "Aerial" }
		end
	end
	if not choice and ctx.gesture then
		local slotName = (attacks :: any)[ctx.gesture]
		if typeof(slotName) == "string" then
			choice = pick(slotName, "Basic")
		end
	end
	if not choice then
		local moving = movementSlot(ctx.root)
		if moving then
			local slotName = (attacks :: any)[moving]
			if typeof(slotName) == "string" then
				choice = pick(slotName, "Basic")
			end
		elseif attacks.Wide then
			local wide = (SpecialMoveDefinitions :: any)[WeaponAttackDefinitions.moveId(prefix, attacks.Wide)]
			if wide and nearbyZombies(ctx.root, wide.Range + 1.5) >= WeaponAttackDefinitions.CrowdForWide then
				choice = pick(attacks.Wide, "Basic")
			end
		end
	end
	if not choice or choice.moveId == state.lastMove then
		-- The chain: next entry, never the same move twice in a row
		for _ = 1, #attacks.Chain do
			state.index = state.index % #attacks.Chain + 1
			local candidate = pick(attacks.Chain[state.index], "Basic")
			if candidate and candidate.moveId ~= state.lastMove then
				choice = candidate
				break
			end
		end
	end
	if choice then
		state.lastMove = choice.moveId
		state.lastTime = now
	end
	return choice
end

function AttackSequenceService.reset(player: Player)
	local state = get(player)
	state.index = 0
	state.lastMove = nil
	state.lastTime = 0
end

function AttackSequenceService.forget(player: Player)
	states[player] = nil
end

return AttackSequenceService
