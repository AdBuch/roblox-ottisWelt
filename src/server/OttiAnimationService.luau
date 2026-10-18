--!strict
-- Otti's locomotion/animation state machine (server side) and the shared boss types.
-- The server owns WHAT Otti does: locomotion state, stance (four legs / two legs), attack pose
-- and its timing. It publishes them as model attributes:
--   Loco       QUADRUPED_IDLE | QUADRUPED_WALK | QUADRUPED_RUN | QUADRUPED_TURN | RISE_TO_BIPED |
--              BIPED_IDLE | BIPED_STRAFE | BIPED_ATTACK | DROP_TO_QUADRUPED | STAGGER | KNOCKDOWN |
--              RECOVERY | DEFEATED
--   Stance     Biped | Quad
--   Pose       attack/intro pose key ("" = none), PoseStart = server time, PoseBlend = seconds
--   Guard, SwordDrawn
-- The client (OttiAnimator) turns these into joint motion procedurally (Motor6D.Transform), so
-- authored animations can replace the procedural poses later (OttiBossConfig.AnimationIds)
-- without touching the server. Hit validation uses the same timings (OttiMoveDefinitions).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local OttiBossConfig = require(ReplicatedStorage.Shared.OttiBossConfig)
local CombatUtil = require(script.Parent.CombatUtil)
local OttiModel = require(script.Parent.OttiModel)

export type Stance = "Biped" | "Quad"

export type Loco =
	"QUADRUPED_IDLE"
	| "QUADRUPED_WALK"
	| "QUADRUPED_RUN"
	| "QUADRUPED_TURN"
	| "RISE_TO_BIPED"
	| "BIPED_IDLE"
	| "BIPED_STRAFE"
	| "BIPED_ATTACK"
	| "DROP_TO_QUADRUPED"
	| "STAGGER"
	| "KNOCKDOWN"
	| "RECOVERY"
	| "DEFEATED"

export type BossHit = {
	fromPosition: Vector3,
	damage: number,
	blockable: boolean,
	blockStops: boolean?,
	blockPierce: number?,
	knockback: number,
	knockbackIfBlocked: boolean?,
	knockdownSeconds: number?,
	slowSeconds: number?,
}

-- Everything the boss modules may do to players, injected by OttiBossService (no require cycles).
export type BossContext = {
	hitPlayer: (player: Player, hit: BossHit) -> (number, boolean),
	fighters: () -> { Player }, -- living arena fighters Otti may target
	setControlLocked: (player: Player, locked: boolean) -> (),
	grantImmunity: (player: Player, seconds: number) -> (),
	knockdown: (player: Player, seconds: number) -> (),
	warn: (text: string, seconds: number) -> (),
	crowd: (mood: string) -> (),
	stillValid: () -> boolean, -- same encounter, Otti not defeated
}

export type Boss = {
	rig: OttiModel.OttiRig,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	rng: Random,
	-- encounter
	fighting: boolean,
	defeated: boolean,
	health: number,
	maxHealth: number,
	phase: number,
	-- motion
	stance: Stance,
	loco: Loco,
	lockedUntil: number, -- transitions/stagger: the AI waits
	lastYaw: number,
	yawRate: number,
	-- combat
	busy: boolean,
	attackId: string?,
	inActive: boolean, -- inside an attack's active hit window (poise breaks wait)
	interrupted: boolean, -- staggered during a wind-up: the attack is cancelled
	attackHitThisStep: { [Player]: boolean },
	invulnerable: boolean,
	guardUntil: number,
	guardReadyAt: number,
	counterReadyAt: number,
	poise: number,
	poiseTime: number,
	breaks: { number },
	cooldowns: { [string]: number },
	nextDecisionAt: number,
	-- targeting
	target: Player?,
	targetSince: number,
	nextRetarget: number,
	threat: { [Player]: number },
	threatTime: number,
	damageBy: { [Player]: number },
	lastAttacked: { [Player]: number },
	rangedAt: { [Player]: number },
	healedAt: { [Player]: number },
	frontalHits: { [Player]: { number } },
	lastGrappled: Player?,
	grabbed: Player?,
	vulnerableUntil: number, -- takes more damage while recovering from a missed big move
	comboHistory: { [Player]: { { name: string, time: number } } },
}

local OttiAnimationService = {}

local QUAD_SPEED_RUN = 18

function OttiAnimationService.new(rig: OttiModel.OttiRig): Boss
	local now = os.clock()
	local boss: Boss = {
		rig = rig,
		model = rig.model,
		humanoid = rig.humanoid,
		root = rig.root,
		rng = Random.new(),
		fighting = false,
		defeated = false,
		health = 1,
		maxHealth = 1,
		phase = 1,
		stance = "Quad",
		loco = "QUADRUPED_IDLE",
		lockedUntil = 0,
		lastYaw = 0,
		yawRate = 0,
		busy = false,
		attackId = nil,
		inActive = false,
		interrupted = false,
		attackHitThisStep = {},
		invulnerable = true,
		guardUntil = 0,
		guardReadyAt = now,
		counterReadyAt = now,
		poise = 0,
		poiseTime = now,
		breaks = {},
		cooldowns = {},
		nextDecisionAt = now,
		target = nil,
		targetSince = now,
		nextRetarget = 0,
		threat = {},
		threatTime = now,
		damageBy = {},
		lastAttacked = {},
		rangedAt = {},
		healedAt = {},
		frontalHits = {},
		lastGrappled = nil,
		grabbed = nil,
		vulnerableUntil = 0,
		comboHistory = {},
	}
	OttiAnimationService.setLoco(boss, "QUADRUPED_IDLE")
	OttiAnimationService.setPose(boss, "", 0.2)
	boss.model:SetAttribute("Stance", "Quad")
	boss.model:SetAttribute("Guard", false)
	boss.model:SetAttribute("SwordDrawn", false)
	return boss
end

function OttiAnimationService.setLoco(boss: Boss, loco: Loco)
	if boss.loco == loco and boss.model:GetAttribute("Loco") == loco then
		return
	end
	boss.loco = loco
	boss.model:SetAttribute("Loco", loco)
end

-- An attack/intro pose. The client blends into it over `blend` seconds from PoseStart.
function OttiAnimationService.setPose(boss: Boss, pose: string, blend: number?)
	boss.model:SetAttribute("Pose", pose)
	boss.model:SetAttribute("PoseBlend", blend or 0.15)
	boss.model:SetAttribute("PoseStart", Workspace:GetServerTimeNow())
end

function OttiAnimationService.setGuard(boss: Boss, guarding: boolean)
	boss.model:SetAttribute("Guard", guarding)
	boss.rig.guardLight.Enabled = guarding
end

function OttiAnimationService.setSwordDrawn(boss: Boss, drawn: boolean)
	boss.model:SetAttribute("SwordDrawn", drawn)
	for _, part in boss.rig.swordParts do
		part.Transparency = if drawn then 0 else 1
	end
	for _, part in boss.rig.sheathedParts do
		part.Transparency = if drawn then 1 else 0
	end
end

-- Changes stance with a visible transition (yields for its duration).
function OttiAnimationService.setStance(boss: Boss, stance: Stance)
	if boss.stance == stance then
		return
	end
	boss.stance = stance
	boss.model:SetAttribute("Stance", stance)
	local seconds = if stance == "Biped" then 0.5 else 0.4
	OttiAnimationService.setLoco(boss, if stance == "Biped" then "RISE_TO_BIPED" else "DROP_TO_QUADRUPED")
	boss.lockedUntil = math.max(boss.lockedUntil, os.clock() + seconds)
	boss.humanoid.WalkSpeed = if stance == "Biped" then OttiBossConfig.WalkSpeedBiped else OttiBossConfig.RunSpeedQuad
	task.wait(seconds)
	if not boss.defeated then
		OttiAnimationService.setLoco(boss, if stance == "Biped" then "BIPED_IDLE" else "QUADRUPED_IDLE")
	end
end

-- Turns the body toward a point, limited by the stance's turn rate (dt = 0: instantly).
function OttiAnimationService.faceTowards(boss: Boss, position: Vector3, dt: number)
	local root = boss.root
	local flat = CombatUtil.flat(position - root.Position)
	if flat.Magnitude < 0.1 then
		return
	end
	local goal = math.atan2(-flat.X, -flat.Z)
	local look = root.CFrame.LookVector
	local current = math.atan2(-look.X, -look.Z)
	local delta = (goal - current + math.pi) % (2 * math.pi) - math.pi
	if dt > 0 then
		local rate = if boss.stance == "Quad" then OttiBossConfig.TurnRateQuad else OttiBossConfig.TurnRateBiped
		delta = math.clamp(delta, -rate * dt, rate * dt)
	end
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, current + delta, 0)
end

-- Sets the body yaw directly (sweeps rotate Otti around himself).
function OttiAnimationService.setYaw(boss: Boss, yaw: number)
	boss.root.CFrame = CFrame.new(boss.root.Position) * CFrame.Angles(0, yaw, 0)
end

function OttiAnimationService.getYaw(boss: Boss): number
	local look = boss.root.CFrame.LookVector
	return math.atan2(-look.X, -look.Z)
end

-- Locomotion from movement while no attack/transition owns the body (called every AI step).
function OttiAnimationService.update(boss: Boss, dt: number)
	local yaw = OttiAnimationService.getYaw(boss)
	local deltaYaw = (yaw - boss.lastYaw + math.pi) % (2 * math.pi) - math.pi
	boss.yawRate = if dt > 0 then deltaYaw / dt else 0
	boss.lastYaw = yaw
	if boss.busy or boss.defeated or os.clock() < boss.lockedUntil then
		return
	end
	local velocity = boss.root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if boss.stance == "Quad" then
		if math.abs(boss.yawRate) > 3 and speed > 4 then
			OttiAnimationService.setLoco(boss, "QUADRUPED_TURN")
		elseif speed > QUAD_SPEED_RUN then
			OttiAnimationService.setLoco(boss, "QUADRUPED_RUN")
		elseif speed > 1 then
			OttiAnimationService.setLoco(boss, "QUADRUPED_WALK")
		else
			OttiAnimationService.setLoco(boss, "QUADRUPED_IDLE")
		end
	else
		OttiAnimationService.setLoco(boss, if speed > 1 then "BIPED_STRAFE" else "BIPED_IDLE")
	end
end

-- Stagger / knockdown / recovery: the body is locked for `seconds` (yields).
function OttiAnimationService.react(boss: Boss, loco: Loco, seconds: number)
	OttiAnimationService.setLoco(boss, loco)
	OttiAnimationService.setPose(boss, "", 0.1)
	boss.lockedUntil = math.max(boss.lockedUntil, os.clock() + seconds + 0.5)
	boss.humanoid:MoveTo(boss.root.Position)
	task.wait(seconds)
	if boss.defeated then
		return
	end
	OttiAnimationService.setLoco(boss, "RECOVERY")
	task.wait(0.5)
	if not boss.defeated then
		OttiAnimationService.setLoco(boss, if boss.stance == "Biped" then "BIPED_IDLE" else "QUADRUPED_IDLE")
	end
end

return OttiAnimationService
