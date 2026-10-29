--!strict
-- Included ONLY by build-boss-qa.ps1, never by a published place project.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio(), "Boss QA must run in Studio")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Moves = require(Shared.OttiMoveDefinitions)
local Profiles = require(Shared.HeroCombatDefinitions)
local Arena = require(Server.Arena)
local BossService = require(Server.OttiBossService)
local Combat = require(Server.PlayerCombatService)
local Rules = require(Server.CombatRules)
local Attack = require(Server.BossAttackService)
local Animation = require(Server.OttiAnimationService)
local AI = require(Server.OttiBossAI)
local Otti = require(Server.OttiModel)
local Companions = require(Server.CompanionModel)

local function check(condition: boolean, name: string)
	if not condition then error("[HeroQA] FAIL " .. name) end
	print("[HeroQA] PASS " .. name)
end

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local arena = workspace:WaitForChild(Config.ArenaFolderName)
local deadline = os.clock() + 90
repeat task.wait(0.2) until (tonumber(arena:GetAttribute(Config.BossHealthAttribute)) or 0) > 0 or os.clock() > deadline
check(Rules.canZombiesTarget(player), "real match admits fighter")
local liveModel, liveRoot = BossService.getHittable()
check(liveModel ~= nil and liveRoot ~= nil, "explicit Otti selection starts encounter")
check(liveRoot ~= nil and not liveRoot.Anchored, "Otti leaves the anchored spectator seat")
check(liveRoot ~= nil and Arena.isInside(liveRoot.Position), "Otti lands inside the arena")
BossService.stop() -- keep the real match and its damage rules; execute controlled attacks below
task.wait(3)
local character = player.Character :: Model
local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
humanoid.MaxHealth, humanoid.Health = 1000, 1000
root.Anchored = true
local rigs = {}
local function placeFighter(bossRoot: BasePart, distance: number)
	root.CFrame = CFrame.new(bossRoot.Position.X, Arena.Layout.FloorTop + humanoid.HipHeight + root.Size.Y / 2, bossRoot.Position.Z - distance)
	Combat.resetCombatState(player)
	task.wait(0.5)
end

for index, id in { "Otti", "Kroko", "Schili" } do
	local rig = if id == "Otti" then Otti.build() else Companions.build(id)
	rig.model.Parent = arena
	rig.root.Anchored = true
	rig.model:PivotTo(CFrame.new((index - 2) * 13, Arena.Layout.FloorTop + rig.humanoid.HipHeight + rig.root.Size.Y / 2, 0))
	CollectionService:AddTag(rig.model, Config.OttiTag)
	rig.model:SetAttribute("OttiState", "BOSS")
	local boss = Animation.new(rig)
	boss.stance, boss.fighting, boss.invulnerable = "Biped", true, false
	boss.companion = if id == "Otti" then nil else id
	rig.model:SetAttribute("Stance", "Biped")
	local enabled = true
	local ctx = {
		stillValid = function() return enabled end,
		fighters = function() return { player } end,
		hitPlayer = Combat.applyBossHit,
		warn = function() end, crowd = function() end,
		setControlLocked = function() end, grantImmunity = function() end, knockdown = function() end,
	}
	local move = if id == "Otti" then table.clone(Moves.GladiusSlash) else Profiles.move(id, "Strike", 1)
	assert(move)
	move.Knockback = 0
	local function strike()
		boss.cooldowns[move.Id] = 0
		return Attack.execute(boss, ctx, move, player)
	end
	placeFighter(rig.root, 5)
	local before = humanoid.Health
	local result = strike()
	check(humanoid.Health < before and result.damaged, id .. " removes real Humanoid HP")
	print("[HeroQA] DAMAGE", id, before - humanoid.Health)
	boss.interrupted = true
	Animation.react(boss, "STAGGER", 0.1)
	check(not boss.interrupted, id .. " clears interruption after recovery")
	placeFighter(rig.root, 5)
	before = humanoid.Health
	strike()
	check(humanoid.Health < before, id .. " attacks again after stagger")
	placeFighter(rig.root, 20)
	before = humanoid.Health
	strike()
	check(humanoid.Health == before, id .. " cannot hit outside reach")
	placeFighter(rig.root, 5)
	local wall = Instance.new("Part")
	wall.Size, wall.Anchored = Vector3.new(10, 12, 0.5), true
	wall.CFrame = CFrame.new(rig.root.Position + Vector3.new(0, 1, -2.5))
	wall.Parent = workspace
	before = humanoid.Health
	strike()
	check(humanoid.Health == before, id .. " cannot hit through solid cover")
	wall:Destroy()
	placeFighter(rig.root, 5)
	before = humanoid.Health
	task.delay(0.1, function() enabled = false end)
	strike()
	check(humanoid.Health == before, id .. " cancelled wind-up cannot damage")
	enabled = true
	local home = rig.root.CFrame
	for _, role in { "Charge", "Sweep", "Feint" } do
		rig.root.CFrame = home
		placeFighter(rig.root, if role == "Charge" then 10 else 5)
		local attack = if id == "Otti" then table.clone(Moves[({ Charge = "RiverDash", Sweep = "TailSweep", Feint = "GladiatorCombination" })[role]]) else Profiles.move(id, role, 2)
		assert(attack)
		attack.Knockback = 0
		boss.cooldowns[attack.Id] = 0
		before = humanoid.Health
		Attack.execute(boss, ctx, attack, player)
		check(humanoid.Health < before, id .. " " .. role .. " damages stationary fighter")
	end
	rig.root.CFrame = home
	if id ~= "Otti" then
		placeFighter(rig.root, 5)
		for _, forced in { "Guard", "Retreat" } do
			for _, role in { "Strike", "Charge", "Sweep", "Guard", "Feint", "Roar", "Retreat" } do boss.companionReadyAt[role] = math.huge end
			boss.companionReadyAt[forced] = 0
			AI.companionDecide(boss, ctx, player, root, 5, os.clock())
			check(boss.lockedUntil > os.clock(), id .. " holds " .. forced .. " state")
			if forced == "Guard" then check(boss.guardUntil > os.clock(), id .. " guard has real duration") end
			local goal = rig.humanoid.WalkToPoint
			AI.step(boss, ctx, 0.1)
			check(rig.humanoid.WalkToPoint == goal, id .. " does not overwrite " .. forced)
			task.wait(1.3)
		end
	end
	for _, joint in { "RightElbow", "LeftElbow", "RightKnee", "LeftKnee" } do
		check(rig.motors[joint] ~= nil, id .. " articulated " .. joint)
	end
	Animation.setPose(boss, "", 0.1)
	Animation.setLoco(boss, "BIPED_IDLE")
	table.insert(rigs, rig)
end

root.Anchored = false
character:PivotTo(Arena.getTribuneCFrame(0))
workspace:SetAttribute("HeroQAStage", "Lineup")
workspace:SetAttribute("HeroQACenter", Vector3.new(0, Arena.Layout.FloorTop + 4, 0))
print("[HeroQA] COMPLETE: damage, stagger recovery, range, cover, cancellation; lineup ready")
