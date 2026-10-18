--!strict
-- Maps the server-owned player/match attributes to one explicit UI state:
--   Lobby | Solo | Coop | TeamBattle | Boss | Spectator | Results
-- (UiStateDefinitions lists what each state shows.) Display only; it never changes game state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameStates = require(Shared:WaitForChild("GameStates"))

local HudStateController = {}

function HudStateController.compute(arena: Instance?): string
	local player = Players.LocalPlayer
	local state = player:GetAttribute(GameStates.StateAttribute)
	local location = player:GetAttribute(GameStates.LocationAttribute)
	local mode = if arena then arena:GetAttribute(Config.MatchModeAttribute) else nil
	local phase = if arena then arena:GetAttribute(Config.WavePhaseAttribute) else nil
	if state == GameStates.Victory or state == GameStates.MatchComplete then
		return "Results"
	elseif state == GameStates.Spectating or (state == GameStates.PlayerDefeated and location == "Tribune") then
		return "Spectator"
	elseif GameStates.isInLobby(state) or location == "Lobby" then
		return "Lobby"
	elseif mode == "TeamBattle" then
		return "TeamBattle"
	elseif phase == "BossIntro" or phase == "Boss" then
		return "Boss"
	elseif mode == "Coop" then
		return "Coop"
	end
	return "Solo"
end

-- Calls `callback(state)` whenever the UI state may have changed.
function HudStateController.watch(arena: Instance, callback: (string) -> ())
	local player = Players.LocalPlayer
	local last = ""
	local function check()
		local state = HudStateController.compute(arena)
		if state ~= last then
			last = state
			callback(state)
		end
	end
	for _, attribute in { GameStates.StateAttribute, GameStates.LocationAttribute } do
		player:GetAttributeChangedSignal(attribute):Connect(check)
	end
	for _, attribute in { Config.MatchModeAttribute, Config.WavePhaseAttribute } do
		arena:GetAttributeChangedSignal(attribute):Connect(check)
	end
	check()
end

return HudStateController
