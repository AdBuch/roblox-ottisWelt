--!strict
-- The Hub's first steps. A new player sees only the way to the arena; after every finished fight
-- one more part of the lobby appears, with a short hint and a floor arrow (LobbyIntroController):
--   0 the arena gate · 1 the shops · 2 group fights in the Schili / Kroko halls ·
--   3 the hypogeum (meeting point, team queues, training) · 4 boss fights and live battles
-- Progress: fights = zombieRuns + teamMatches (saved by the Arena); introSeen (saved) = the last
-- stage shown, so each return reveals exactly one new stage. Players who already fought more
-- often than there are stages skip the intro. The IntroStage attribute tells the client which
-- of the start hall's signs to show.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local Server = script.Parent.Parent
local InventoryService = require(Server.InventoryService)
local LobbyService = require(Server.LobbyService)
local Remotes = require(Server.Remotes)

local LAST_STAGE = 4
local ATTRIBUTE = "IntroStage"
local HINTS: { [number]: { title: string, text: string } } = {
	[0] = { title = "THE ARENA", text = "Walk through the gate ahead · your first fight starts there" },
	[1] = { title = "THE SHOPS", text = "Spend your denarii on weapons, shields and armor · through the side door" },
	[2] = { title = "GROUP FIGHTS", text = "Co-op groups and team battles gather in the Schili and Kroko halls" },
	[3] = { title = "THE HYPOGEUM", text = "Down the stairs: the meeting point, team battle queues and the training yard" },
	[4] = { title = "BOSSES & LIVE BATTLES", text = "Challenge Otti, Schili or Krokero · or watch other fights live" },
}

local LobbyIntroService = {}

local targets: { Vector3 } = {}

function LobbyIntroService.init(lobby: LobbyService.LobbyLayout)
	targets = lobby.introTargets
end

-- After the profile loaded: decide the stage, save it and show its hint once the player stands
-- in the hall.
function LobbyIntroService.onLoaded(player: Player)
	local fights = InventoryService.getStat(player, "zombieRuns") + InventoryService.getStat(player, "teamMatches")
	local seen = InventoryService.getStat(player, "introSeen")
	local forced = ExperienceConfig.Studio.IntroStage
	local stage, hint = math.min(seen, LAST_STAGE), nil :: number?
	if EnvironmentConfig.isStudio() and forced >= 0 then
		stage, hint = math.min(forced, LAST_STAGE), math.min(forced, LAST_STAGE)
	elseif seen == 0 and fights > LAST_STAGE then
		InventoryService.addStat(player, "introSeen", LAST_STAGE)
		stage = LAST_STAGE
	elseif fights == 0 then
		hint = 0
	elseif fights > seen and seen < LAST_STAGE then
		InventoryService.addStat(player, "introSeen", 1)
		stage, hint = seen + 1, seen + 1
	end
	player:SetAttribute(ATTRIBUTE, stage)
	local shown = hint
	if shown then
		task.delay(2.5, function()
			local text = HINTS[shown]
			if player.Parent and text then
				Remotes.MatchEvent:FireClient(player, "IntroHint", { stage = shown, title = text.title, text = text.text, target = targets[shown + 1] })
			end
		end)
	end
end

return LobbyIntroService
