--!strict
-- Server-side combo recognition. Only actions the server ACCEPTED are recorded (with server
-- times), so clients can't claim combos, and rejected/macro inputs never count.
-- A combo matches when the recorded inputs plus the new input equal one of the weapon's
-- sequences and every input arrived within ComboWindowSeconds after the previous one ended.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local ComboDefinitions = require(ReplicatedStorage.Shared.ComboDefinitions)

type ComboDefinition = ComboDefinitions.ComboDefinition
type ComboInput = ComboDefinitions.ComboInput

type Entry = { input: ComboInput, time: number, finish: number }

local ComboService = {}

local histories: { [Player]: { Entry } } = {}

local function getHistory(player: Player): { Entry }
	local history = histories[player]
	if not history then
		history = {}
		histories[player] = history
	end
	return history
end

-- Returns the combo completed by `input` (performed at `now`), or nil.
function ComboService.match(player: Player, weaponId: string, input: ComboInput, now: number): ComboDefinition?
	local combos = ComboDefinitions[weaponId]
	if not combos then
		return nil
	end
	local history = getHistory(player)
	local window = CombatConfig.ComboWindowSeconds
	for _, combo in combos do
		local sequence = combo.Sequence
		local length = #sequence
		if sequence[length] == input and #history >= length - 1 then
			local ok = true
			local nextTime = now
			for k = length - 1, 1, -1 do
				local entry = history[#history - (length - 1 - k)]
				if entry.input ~= sequence[k] or nextTime - entry.finish > window or nextTime < entry.time then
					ok = false
					break
				end
				nextTime = entry.time
			end
			if ok then
				return combo
			end
		end
	end
	return nil
end

-- Records an accepted input. `finish` is when its move ends (inputs are timed from there).
function ComboService.record(player: Player, input: ComboInput, now: number, finish: number)
	local history = getHistory(player)
	table.insert(history, { input = input, time = now, finish = finish })
	while #history > CombatConfig.ComboHistoryLength do
		table.remove(history, 1)
	end
end

-- Forgets the history (combo finished, death, stun, state change, blocking an offense, ...).
function ComboService.clear(player: Player)
	histories[player] = nil
end

return ComboService
