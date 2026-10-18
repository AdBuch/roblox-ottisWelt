--!strict
-- Otti's entrance for Round 7, entirely server-controlled and deterministic:
--   stand up from the throne -> draw gladius, raise shield -> climb onto the railing -> the crowd
--   falls quiet -> a controlled bezier arc over the railing onto the sand (anchored root, no
--   falling physics, the landing point is fixed inside the arena) -> sand ring, warm light pulse,
--   crowd cheer -> landing recovery -> bipedal gladiator stance.
-- During all of it Otti can't be hit (the fight hasn't started) and can't hurt anyone. Clients
-- may move the camera to the imperial box (OttiEntranceController); skipping that camera never
-- skips any of this. Publishes the stage on the arena folder (BossIntro: Rise | Leap | "").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local OttiEntranceConfig = require(ReplicatedStorage.Shared.OttiEntranceConfig)
local Arena = require(script.Parent.Arena)
local CombatEffects = require(script.Parent.CombatEffects)
local CrowdReactionService = require(script.Parent.CrowdReactionService)
local OttiAnimationService = require(script.Parent.OttiAnimationService)

type Boss = OttiAnimationService.Boss

local PREFIX = "[OttiArena][Server]"

local OttiEntranceService = {}

local landingCount = 0

-- Moves an anchored root along a CFrame curve for `seconds` (false if cancelled).
local function follow(boss: Boss, seconds: number, curve: (t: number) -> CFrame, valid: () -> boolean): boolean
	local elapsed = 0
	while elapsed < seconds do
		elapsed = math.min(seconds, elapsed + RunService.Heartbeat:Wait())
		if not valid() then
			return false
		end
		boss.root.CFrame = curve(elapsed / seconds)
	end
	return true
end

local function waitFor(seconds: number, valid: () -> boolean): boolean
	local elapsed = 0
	while elapsed < seconds do
		elapsed += task.wait(0.05)
		if not valid() then
			return false
		end
	end
	return true
end

-- Plays the entrance on the boss (yields ~6 s). Returns false if the encounter was stopped.
function OttiEntranceService.play(boss: Boss, arena: Instance, valid: () -> boolean): boolean
	local root = boss.root
	root.Anchored = true
	local standing = boss.humanoid.HipHeight + root.Size.Y / 2

	-- 1. Stands up from the seat, draws gladius, raises shield
	arena:SetAttribute(Config.BossIntroAttribute, "Rise")
	OttiAnimationService.setLoco(boss, "BIPED_IDLE")
	OttiAnimationService.setPose(boss, "StandUp", 0.4)
	if not waitFor(OttiEntranceConfig.StandSeconds, valid) then
		return false
	end
	OttiAnimationService.setPose(boss, "DrawSword", 0.25)
	task.delay(0.3, function()
		if valid() then
			OttiAnimationService.setSwordDrawn(boss, true)
		end
	end)
	if not waitFor(OttiEntranceConfig.DrawSeconds, valid) then
		return false
	end

	-- 2. Climbs onto the railing; the crowd falls quiet
	local start = root.CFrame
	local rail = Arena.Layout.ImperialRail + Vector3.new(0, standing, 0)
	local railCFrame = CFrame.new(rail.Position) * start.Rotation
	OttiAnimationService.setPose(boss, "ClimbRail", 0.2)
	CrowdReactionService.react("Silent")
	if not follow(boss, OttiEntranceConfig.ClimbSeconds, function(t: number): CFrame
		local lift = math.sin(t * math.pi) * 1.2
		return start:Lerp(railCFrame, t) + Vector3.new(0, lift, 0)
	end, valid) then
		return false
	end
	if not waitFor(OttiEntranceConfig.PauseOnRailSeconds, valid) then
		return false
	end

	-- 3. The leap: a quadratic bezier from the railing to the fixed boss start (inside the arena)
	arena:SetAttribute(Config.BossIntroAttribute, "Leap")
	local landing = Arena.Layout.BossStart + Vector3.new(0, standing, 0)
	if not Arena.isInside(landing.Position, -8) then
		landing = CFrame.new(Arena.getSafePoint(landing.Position) + Vector3.new(0, standing, 0)) * landing.Rotation
	end
	local p0, p2 = railCFrame.Position, landing.Position
	local p1 = (p0 + p2) / 2 + Vector3.new(0, OttiEntranceConfig.LeapHeight, 0)
	local facing = landing.Rotation
	OttiAnimationService.setPose(boss, "Leap", 0.15)
	if not follow(boss, OttiEntranceConfig.LeapSeconds, function(t: number): CFrame
		local eased = t * t * (3 - 2 * t) * 0.35 + t * 0.65 -- slight hang time at the apex
		local a = p0:Lerp(p1, eased)
		local b = p1:Lerp(p2, eased)
		return CFrame.new(a:Lerp(b, eased)) * facing
	end, valid) then
		return false
	end
	root.CFrame = landing

	-- 4. Landing: sand ring, warm light, cheer, a short shake for nearby cameras. No damage.
	landingCount += 1
	arena:SetAttribute(Config.BossLandingAttribute, landingCount)
	arena:SetAttribute("BossLandPosition", landing.Position)
	CombatEffects.sandBurst(Vector3.new(landing.X, Arena.Layout.FloorTop, landing.Z), OttiEntranceConfig.LandingRingRadius, 1.8)
	CombatEffects.ring(Vector3.new(landing.X, Arena.Layout.FloorTop + 0.1, landing.Z), OttiEntranceConfig.LandingRingRadius + 4, Color3.fromRGB(255, 200, 120))
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 190, 110)
	glow.Range = 40
	glow.Brightness = 6
	glow.Parent = root
	TweenService:Create(glow, TweenInfo.new(1.2), { Brightness = 0 }):Play()
	task.delay(1.3, function()
		glow:Destroy()
	end)
	CrowdReactionService.react("Enter")
	OttiAnimationService.setPose(boss, "Land", 0.05)
	print(PREFIX, "Otti landed in the arena")
	if not waitFor(OttiEntranceConfig.LandingRecoverySeconds, valid) then
		return false
	end

	-- 5. Rises into the bipedal gladiator stance; the model becomes a physical fighter again
	OttiAnimationService.setPose(boss, "", 0.3)
	OttiAnimationService.setLoco(boss, "BIPED_IDLE")
	for _, part in boss.rig.bodyParts do
		part.CanQuery = part.Name == "Pelvis" or part.Name == "Chest" or part.Name == "Head"
			or part.Name == "RightArm" or part.Name == "LeftArm" or part.Name == "RightLeg" or part.Name == "LeftLeg"
	end
	root.CanCollide = true
	root.CanQuery = true
	root.Anchored = false
	root:SetNetworkOwner(nil)
	arena:SetAttribute(Config.BossIntroAttribute, "")
	return true
end

return OttiEntranceService
