--!strict
-- OTTI_SPECTATING: during every Solo/Co-op zombie match Otti sits in the imperial box and watches.
-- He is a decoration with opinions, not an enemy: anchored, no collisions, invisible to raycasts
-- (never blocks projectiles), not tagged as boss or zombie, no AI, no damage either way.
--   * sits like an otter (client OttiAnimator "SITTING"), tail beside the throne, head follows
--     the fighting, leans forward now and then, gets impatient in the late rounds
--   * reacts to meaningful moments only, with a cooldown: combos (lean / railing strike / paw),
--     big aerial finishers (stands up briefly), players knocked down (surprised), round complete
--     (claps), player defeat (sits back slowly)
-- handOff() gives the very same model to OttiBossService for the entrance: there is never a second
-- Otti, the spectator is transformed into the boss.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local OttiEntranceConfig = require(ReplicatedStorage.Shared.OttiEntranceConfig)
local Arena = require(script.Parent.Arena)
local OttiModel = require(script.Parent.OttiModel)

local PREFIX = "[OttiArena][Server]"

local OttiSpectatorService = {}

local rig: OttiModel.OttiRig? = nil
local token = 0
local lastReaction = 0
local poseToken = 0

local function setPose(pose: string, seconds: number?)
	local current = rig
	if not current then
		return
	end
	poseToken += 1
	local myToken = poseToken
	current.model:SetAttribute("Pose", pose)
	current.model:SetAttribute("PoseBlend", 0.25)
	current.model:SetAttribute("PoseStart", Workspace:GetServerTimeNow())
	if seconds then
		task.delay(seconds, function()
			if poseToken == myToken and rig == current then
				current.model:SetAttribute("Pose", "")
			end
		end)
	end
end

-- Seats Otti in the imperial box (idempotent).
function OttiSpectatorService.begin()
	if rig then
		return
	end
	token += 1
	local myToken = token
	local built = OttiModel.build()
	for _, descendant in built.model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false -- never blocks projectiles or aim
			descendant.CanTouch = false
		end
	end
	built.root.Anchored = true
	local height = built.humanoid.HipHeight + built.root.Size.Y / 2
	built.model:PivotTo(Arena.Layout.ImperialSeat + Vector3.new(0, height, 0))
	built.model:SetAttribute("Loco", "SITTING")
	built.model:SetAttribute("Stance", "Biped")
	built.model:SetAttribute("Pose", "")
	built.model:SetAttribute("OttiState", "OTTI_SPECTATING")
	for _, part in built.swordParts do
		part.Transparency = 1 -- gladius rests in its scabbard
	end
	for _, part in built.sheathedParts do
		part.Transparency = 0
	end
	local arena = Workspace:FindFirstChild(Config.ArenaFolderName)
	built.model.Parent = arena or Workspace
	CollectionService:AddTag(built.model, Config.OttiSpectatorTag)
	rig = built
	lastReaction = 0
	print(PREFIX, "Otti takes his seat in the imperial box (OTTI_SPECTATING)")

	-- Head follows the fighting; leans in now and then; impatient in the late rounds
	task.spawn(function()
		while token == myToken and rig == built do
			task.wait(OttiEntranceConfig.IdleLookInterval)
			local sum, count = Vector3.zero, 0
			for _, player in Players:GetPlayers() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and player:GetAttribute(GameStates.LocationAttribute) == "Arena" then
					sum += root.Position
					count += 1
				end
			end
			built.model:SetAttribute("LookAt", if count > 0 then sum / count else Arena.Layout.Center)
			local round = tonumber(arena and arena:GetAttribute(Config.RoundAttribute)) or 0
			local now = os.clock()
			if now - lastReaction > 6 and built.model:GetAttribute("Pose") == "" then
				local roll = math.random()
				if round >= OttiEntranceConfig.ImpatientFromRound and roll < 0.25 then
					setPose("SitImpatient", 2.5)
					lastReaction = now
				elseif roll < 0.12 then
					setPose("SitLean", 2)
					lastReaction = now
				end
			end
		end
	end)
end

-- A meaningful arena event. kind: Combo | AdvancedCombo | BigAerial | PlayerHurt | RoundComplete | PlayerDefeated
function OttiSpectatorService.react(kind: string)
	if not rig then
		return
	end
	local now = os.clock()
	local important = kind == "RoundComplete" or kind == "PlayerDefeated"
	if not important and now - lastReaction < OttiEntranceConfig.ReactionCooldown then
		return
	end
	lastReaction = now
	if kind == "Combo" then
		setPose("SitLean", 1.8)
	elseif kind == "AdvancedCombo" then
		setPose(if math.random() < 0.5 then "RailStrike" else "PawRaise", 1.6)
	elseif kind == "BigAerial" then
		setPose("StandBrief", 1.8)
	elseif kind == "PlayerHurt" then
		setPose("Surprised", 1.4)
	elseif kind == "RoundComplete" then
		setPose("Clap", 2.2)
	elseif kind == "PlayerDefeated" then
		setPose("SitBack", 2.5)
	end
end

function OttiSpectatorService.isSpectating(): boolean
	return rig ~= nil
end

-- Gives the spectator model to the boss encounter (same model, no duplicate Otti). nil if none.
function OttiSpectatorService.handOff(): OttiModel.OttiRig?
	local current = rig
	if not current then
		return nil
	end
	rig = nil
	token += 1
	CollectionService:RemoveTag(current.model, Config.OttiSpectatorTag)
	current.model:SetAttribute("OttiState", "BOSS_ENTRANCE")
	return current
end

-- Match over (or aborted): the spectator leaves.
function OttiSpectatorService.stop()
	token += 1
	local current = rig
	rig = nil
	if current then
		current.model:Destroy()
	end
	for _, leftover in CollectionService:GetTagged(Config.OttiSpectatorTag) do
		leftover:Destroy()
	end
end

return OttiSpectatorService
