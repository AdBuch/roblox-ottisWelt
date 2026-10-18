--!strict
-- Server-side jump knowledge for aerial attacks and Jump (J) combo inputs. The client never tells
-- the server it is airborne: the server looks at the character itself (ground ray below the root
-- plus the humanoid state) about ten times per second for players who may fight, and on demand.
--   * an aerial attack needs a real jump, starts within AerialWindow after leaving the ground and
--     happens at most once per jump (reset only when the server sees the player on the ground)
--   * a J input only counts if the server saw the player airborne shortly after it
--   * waitForLanding yields until the player is on the ground again (or MaxAirSeconds)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local InputDefinitions = require(ReplicatedStorage.Shared.InputDefinitions)
local CombatUtil = require(script.Parent.CombatUtil)

type JumpState = {
	airborne: boolean,
	airborneSince: number,
	lastAirborneSeen: number,
	aerialUsed: boolean,
}

local JumpAttackService = {}

local states: { [Player]: JumpState } = {}

local function getState(player: Player): JumpState
	local state = states[player]
	if not state then
		state = { airborne = false, airborneSince = 0, lastAirborneSeen = -100, aerialUsed = false }
		states[player] = state
	end
	return state
end

-- Measures right now whether the character is clearly off the ground.
local function measure(player: Player): boolean
	local character, humanoid, root = CombatUtil.getLivingCharacter(player)
	if not character or not humanoid or not root then
		return false
	end
	local humanoidState = humanoid:GetState()
	if humanoidState == Enum.HumanoidStateType.Freefall or humanoidState == Enum.HumanoidStateType.Jumping then
		return true
	end
	local standing = humanoid.HipHeight + root.Size.Y / 2
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local result = Workspace:Raycast(root.Position, Vector3.new(0, -(standing + InputDefinitions.AirborneHeight + 0.4), 0), params)
	return result == nil
end

local function update(player: Player): JumpState
	local state = getState(player)
	local now = os.clock()
	local airborne = measure(player)
	if airborne then
		if not state.airborne then
			state.airborneSince = now
		end
		state.lastAirborneSeen = now
	else
		state.aerialUsed = false -- landing ends the aerial state; the next jump allows a new one
	end
	state.airborne = airborne
	return state
end

-- True if the player may start an aerial attack now (also marks the jump as used).
function JumpAttackService.tryAerial(player: Player): boolean
	local state = update(player)
	local now = os.clock()
	if state.airborne and not state.aerialUsed and now - state.airborneSince <= InputDefinitions.AerialWindow then
		state.aerialUsed = true
		return true
	end
	return false
end

function JumpAttackService.isAirborne(player: Player): boolean
	return update(player).airborne
end

-- Was a jump pressed at `time` real? (the server saw the player airborne shortly after)
function JumpAttackService.jumpConfirmed(player: Player, time: number): boolean
	local state = update(player)
	return state.lastAirborneSeen >= time - 0.1 and state.lastAirborneSeen <= time + 1.0
end

-- Marks the current jump as used by a combo aerial (no extra aerial basic attack in the same jump).
function JumpAttackService.consume(player: Player)
	getState(player).aerialUsed = true
end

-- Yields until the player lands (true) or maxSeconds pass / the character is gone (false).
function JumpAttackService.waitForLanding(player: Player, maxSeconds: number): boolean
	local started = os.clock()
	-- give a fresh leap a moment to leave the ground before checking for the landing
	local leftGround = measure(player)
	while os.clock() - started < maxSeconds do
		RunService.Heartbeat:Wait()
		if not CombatUtil.getLivingCharacter(player) then
			return false
		end
		local airborne = measure(player)
		if airborne then
			leftGround = true
		elseif leftGround or os.clock() - started > 0.35 then
			update(player)
			return true
		end
	end
	update(player)
	return false
end

function JumpAttackService.init(isWatched: (Player) -> boolean)
	-- Light polling (10 Hz) for players who may fight: keeps jump times accurate for J inputs
	task.spawn(function()
		while true do
			task.wait(0.1)
			for _, player in Players:GetPlayers() do
				if isWatched(player) then
					update(player)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return JumpAttackService
