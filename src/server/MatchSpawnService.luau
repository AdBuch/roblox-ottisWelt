--!strict
-- Places every (re)spawning character according to PlayerMatchStateService.ExpectedSpawnZone:
--   LOBBY         Roblox's lobby SpawnLocation (nothing to do)
--   RED_TEAM /    the player's team spawn in the arena, visible spawn protection, equipment is
--   BLUE_TEAM     rebuilt by PlayerCombatService, match membership untouched
--   ZOMBIE_ARENA  the arena start line
--   SPECTATOR     a spot on the lower or middle tribune walkway (never the imperial box)
--   ELIMINATED    the closed waiting box below the arena (Elimination: out for the round)
-- Characters are positioned as soon as their root exists (event-driven, no fixed delays). The
-- returned boolean tells MatchService that the match owns this character.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local Arena = require(script.Parent.Arena)
local PlayerCombatService = require(script.Parent.PlayerCombatService)
local PlayerMatchStateService = require(script.Parent.PlayerMatchStateService)

local PREFIX = "[OttiArena][Match]"

export type Hooks = {
	-- Team Battle: is the match already active (false during the arena countdown)?
	teamMatchActive: (matchId: number) -> boolean,
	-- Team Battle: listen for this character's death (eliminations, respawn)
	onTeamCharacter: (player: Player, character: Model) -> (),
}

local MatchSpawnService = {}

local hooks: Hooks? = nil

function MatchSpawnService.init(newHooks: Hooks)
	hooks = newHooks
end

-- Team spawn slot: spread the team over four lateral positions.
local function teamSlot(player: Player): number
	return (player.UserId % 4) + 1
end

function MatchSpawnService.cframeFor(player: Player, zone: PlayerMatchStateService.SpawnZone, index: number?): CFrame?
	if zone == "RED_TEAM" then
		return Arena.getTeamSpawnCFrame("Red", index or teamSlot(player))
	elseif zone == "BLUE_TEAM" then
		return Arena.getTeamSpawnCFrame("Blue", index or teamSlot(player))
	elseif zone == "ZOMBIE_ARENA" then
		return Arena.getStartCFrame(index)
	elseif zone == "SPECTATOR" then
		return Arena.getTribuneCFrame(player.UserId)
	elseif zone == "ELIMINATED" then
		return Arena.getEliminationCFrame(player.UserId)
	end
	return nil
end

-- Moves a living character to its zone right now (match start, revive).
function MatchSpawnService.place(player: Player, index: number?): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local cframe = MatchSpawnService.cframeFor(player, PlayerMatchStateService.getZone(player), index)
	if not character or not root or not root:IsA("BasePart") or not cframe then
		return false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(cframe)
	return true
end

-- CharacterAdded: returns true if the character belongs to a match zone (handled here).
function MatchSpawnService.onCharacterAdded(player: Player, character: Model): boolean
	local zone = PlayerMatchStateService.getZone(player)
	if zone == "LOBBY" then
		return false
	end
	local matchId = PlayerMatchStateService.getMatchId(player)
	-- Position as soon as the root exists (no arbitrary waits)
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	if not root or player.Character ~= character or PlayerMatchStateService.getZone(player) ~= zone then
		return true
	end
	local cframe = MatchSpawnService.cframeFor(player, zone, nil)
	if cframe then
		character:PivotTo(cframe)
	end
	if zone == "RED_TEAM" or zone == "BLUE_TEAM" then
		local currentHooks = hooks
		local active = currentHooks ~= nil and currentHooks.teamMatchActive(matchId)
		PlayerCombatService.setSpawnProtection(player, CombatConfig.SpawnProtectionSeconds)
		player:SetAttribute(GameStates.StateAttribute, if active then GameStates.MatchActive else GameStates.Countdown)
		player:SetAttribute(GameStates.LocationAttribute, "Arena")
		if currentHooks then
			currentHooks.onTeamCharacter(player, character)
		end
		print(PREFIX, ("Match %d: %s respawned at the %s spawn"):format(matchId, player.Name, if zone == "RED_TEAM" then "Red" else "Blue"))
	elseif zone == "SPECTATOR" then
		player:SetAttribute(GameStates.LocationAttribute, "Tribune")
	elseif zone == "ELIMINATED" then
		-- Elimination: out for this round, closed waiting box, camera follows teammates only
		player:SetAttribute(GameStates.StateAttribute, GameStates.PlayerDefeated)
		player:SetAttribute(GameStates.LocationAttribute, "Tribune")
	elseif zone == "ZOMBIE_ARENA" then
		player:SetAttribute(GameStates.LocationAttribute, "Arena")
	end
	return true
end

return MatchSpawnService
