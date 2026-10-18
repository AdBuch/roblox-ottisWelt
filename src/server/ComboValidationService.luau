--!strict
-- Server-validated combination input buffer (replaces the old Q/E combo history).
--   record(player, input)   an ACCEPTED input with server time (A = attack request, B = block press,
--                           J = jump request; a J only counts if JumpAttackService saw a real jump)
--   resolve(player, weapon) on Execute: the most recent inputs must equal one of the weapon's
--                           sequences, every gap <= MaxGap, the whole sequence <= BufferLifetime
-- Gaps that are too long start a new sequence; the buffer holds at most MaxLength inputs and is
-- cleared after Execute, on death, stun, leaving combat and weapon changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ComboDefinitions = require(ReplicatedStorage.Shared.ComboDefinitions)
local InputDefinitions = require(ReplicatedStorage.Shared.InputDefinitions)
local JumpAttackService = require(script.Parent.JumpAttackService)

type ComboDefinition = ComboDefinitions.ComboDefinition
type ComboInput = ComboDefinitions.ComboInput

type Entry = { input: ComboInput, time: number }

local ComboValidationService = {}

local buffers: { [Player]: { Entry } } = {}

function ComboValidationService.record(player: Player, input: ComboInput)
	local now = os.clock()
	local buffer = buffers[player]
	if not buffer then
		buffer = {}
		buffers[player] = buffer
	end
	local last = buffer[#buffer]
	if last and now - last.time > InputDefinitions.MaxGap then
		table.clear(buffer) -- too slow: a new sequence starts
	end
	table.insert(buffer, { input = input, time = now })
	while #buffer > InputDefinitions.MaxLength do
		table.remove(buffer, 1)
	end
end

-- The live inputs (for diagnostics / training feedback).
function ComboValidationService.peek(player: Player): { ComboInput }
	local list: { ComboInput } = {}
	local buffer: { Entry } = buffers[player] or {}
	for _, entry in buffer do
		table.insert(list, entry.input)
	end
	return list
end

-- Returns the combo the recent inputs complete (or nil and a reason), then clears the buffer.
function ComboValidationService.resolve(player: Player, weaponId: string): (ComboDefinition?, string?)
	local buffer = buffers[player]
	buffers[player] = nil
	local now = os.clock()
	if not buffer or #buffer == 0 then
		return nil, "empty"
	end
	if now - buffer[#buffer].time > InputDefinitions.MaxGap + InputDefinitions.ExecuteGrace then
		return nil, "expired"
	end
	local combos: { ComboDefinition } = ComboDefinitions.ByWeapon[weaponId] or {}
	for _, combo in combos do
		local sequence = combo.Sequence
		local length = #sequence
		if #buffer >= length then
			local first = #buffer - length + 1
			local ok = now - buffer[first].time <= InputDefinitions.BufferLifetime
			for k = 1, length do
				local entry = buffer[first + k - 1]
				if not ok or entry.input ~= sequence[k] then
					ok = false
					break
				end
				if k > 1 and entry.time - buffer[first + k - 2].time > InputDefinitions.MaxGap then
					ok = false
					break
				end
				-- A jump in the sequence must have been a real jump
				if entry.input == "J" and not JumpAttackService.jumpConfirmed(player, entry.time) then
					ok = false
					break
				end
			end
			if ok then
				return combo, nil
			end
		end
	end
	return nil, "no combo"
end

function ComboValidationService.clear(player: Player)
	buffers[player] = nil
end

return ComboValidationService
