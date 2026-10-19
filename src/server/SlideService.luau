--!strict
-- Server-authoritative slide state (SlideDefinitions). PlayerCombatService asks tryStart() with its
-- own checks (alive, not stunned / knocked / held / committed / heavy block reaction); the client
-- then moves its own character (it owns that physics) along the approved direction. Server rules:
--   * must be moving (root horizontal speed >= MinSpeed), grounded, off cooldown
--   * the direction comes from the replicated movement, not from client claims
--   * a short dodge window at the start, one slide attack per slide, no chaining
--   * a rough distance check afterwards (logged) keeps modified clients honest

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SlideDefinitions = require(ReplicatedStorage.Shared.SlideDefinitions)
local CombatUtil = require(script.Parent.CombatUtil)

type State = {
	slideUntil: number,
	cooldownUntil: number,
	dodgeUntil: number,
	attackUsed: boolean,
	dodged: boolean,
	start: Vector3,
	direction: Vector3,
	token: number,
}

local PREFIX = "[OttiArena][Slide]"

local SlideService = {}

local states: { [Player]: State } = {}

local function get(player: Player): State
	local state = states[player]
	if not state then
		state = { slideUntil = 0, cooldownUntil = 0, dodgeUntil = 0, attackUsed = false, dodged = false, start = Vector3.zero, direction = Vector3.zero, token = 0 }
		states[player] = state
	end
	return state
end

-- Starts a slide. Returns the approved flat direction, or nil + reason.
function SlideService.tryStart(player: Player, airborne: boolean): (Vector3?, string?)
	local state = get(player)
	local now = os.clock()
	if now < state.cooldownUntil then
		return nil, "cooldown"
	end
	if airborne then
		return nil, "airborne"
	end
	local character, _, root = CombatUtil.getLivingCharacter(player)
	if not character or not root then
		return nil, "dead"
	end
	local velocity = CombatUtil.flat(root.AssemblyLinearVelocity)
	if velocity.Magnitude < SlideDefinitions.MinSpeed then
		return nil, "not moving" -- stationary players can't slide
	end
	local direction = velocity.Unit
	state.slideUntil = now + SlideDefinitions.Duration
	state.dodgeUntil = now + SlideDefinitions.DodgeWindow
	state.cooldownUntil = now + SlideDefinitions.Cooldown
	state.attackUsed = false
	state.dodged = false
	state.start = root.Position
	state.direction = direction
	state.token += 1
	local token = state.token
	character:SetAttribute("SlideStart", Workspace:GetServerTimeNow())
	character:SetAttribute("SlideLength", SlideDefinitions.Duration)
	task.delay(SlideDefinitions.Duration + 0.25, function()
		if state.token ~= token then
			return
		end
		local _, _, endRoot = CombatUtil.getLivingCharacter(player)
		if endRoot then
			local moved = CombatUtil.flatDistance(endRoot.Position, state.start)
			if moved > SlideDefinitions.Distance + SlideDefinitions.MaxDistanceTolerance + 6 then
				warn(PREFIX, ("%s slid %.1f studs (allowed %.1f)"):format(player.Name, moved, SlideDefinitions.Distance))
			end
		end
	end)
	return direction, nil
end

function SlideService.isSliding(player: Player): boolean
	return os.clock() < get(player).slideUntil
end

-- The one slide attack of this slide (true once per slide).
function SlideService.consumeAttack(player: Player): boolean
	local state = get(player)
	if os.clock() >= state.slideUntil + 0.1 or state.attackUsed then
		return false
	end
	state.attackUsed = true
	state.cooldownUntil = math.max(state.cooldownUntil, os.clock() + SlideDefinitions.SlideAttackRecovery + 0.6) -- no instant re-slide
	return true
end

-- Inside the dodge window? Returns (dodged, firstDodgeOfThisSlide).
function SlideService.tryDodge(player: Player): (boolean, boolean)
	local state = get(player)
	if os.clock() >= state.dodgeUntil then
		return false, false
	end
	local first = not state.dodged
	state.dodged = true
	return true, first
end

function SlideService.cancel(player: Player)
	local state = get(player)
	state.slideUntil = 0
	state.dodgeUntil = 0
	state.token += 1
end

function SlideService.forget(player: Player)
	states[player] = nil
end

return SlideService
