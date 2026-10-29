--!strict
-- Otti's own boss AI (not the zombie AI). One decision loop per encounter:
--   target    scored per living arena fighter: recent damage to Otti (threat), distance, healing
--             or reviving nearby, attacking from range, minus a penalty for having been attacked
--             by Otti just now and for being focused too long (no endless focus on one player)
--   movement  two legs: measured shield-forward circling at sword range; four legs: fast low
--             runs, sharp direction changes, circling wide (harder to surround)
--   attacks   weighted by phase (BossPhaseDefinitions), filtered by range and cooldowns; grapples
--             never pick the same player twice in a row when someone else is available; when
--             surrounded Otti prefers a tail sweep or a River Dash out; follow-ups chain moves
--             (Phase 3 shield bash -> tail sweep, bite -> throw, dash -> tail trip)
--   pacing    pauses between sequences (shorter in later phases), a short "study" on new targets

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossPhaseDefinitions = require(ReplicatedStorage.Shared.BossPhaseDefinitions)
local OttiBossConfig = require(ReplicatedStorage.Shared.OttiBossConfig)
local OttiMoveDefinitions = require(ReplicatedStorage.Shared.OttiMoveDefinitions)
local Arena = require(script.Parent.Arena)
local BossAttackService = require(script.Parent.BossAttackService)
local CombatUtil = require(script.Parent.CombatUtil)
local OttiAnimationService = require(script.Parent.OttiAnimationService)
local HeroCombatDefinitions = require(ReplicatedStorage.Shared.HeroCombatDefinitions)
local Workspace = game:GetService("Workspace")
local CompanionBossAI = require(script.Parent.CompanionBossAI)
local CompanionBossDefinitions = require(ReplicatedStorage.Shared.CompanionBossDefinitions)

type Boss = OttiAnimationService.Boss
type BossContext = OttiAnimationService.BossContext
type OttiMove = OttiMoveDefinitions.OttiMove

local OttiBossAI = {}

type MoveState = { drift: number, nextDriftFlip: number, studyUntil: number }
local motion: { [Boss]: MoveState } = setmetatable({}, { __mode = "k" }) :: any

local function decayThreat(boss: Boss, now: number)
	local elapsed = now - boss.threatTime
	boss.threatTime = now
	local factor = math.max(0, 1 - OttiBossConfig.ThreatDecayPerSecond * elapsed)
	for player, value in boss.threat do
		local decayed: number = value * factor
		if decayed < 0.5 then
			boss.threat[player] = nil
		else
			boss.threat[player] = decayed
		end
	end
end

function OttiBossAI.selectTarget(boss: Boss, ctx: BossContext, now: number): (Player?, BasePart?)
	local fighters = ctx.fighters()
	local current = boss.target
	if current and now < boss.nextRetarget and table.find(fighters, current) and boss.grabbed ~= current then
		local _, _, root = CombatUtil.getLivingCharacter(current)
		if root then
			return current, root
		end
	end
	boss.nextRetarget = now + OttiBossConfig.RetargetInterval * (0.8 + boss.rng:NextNumber() * 0.4)
	decayThreat(boss, now)
	local best: Player?, bestRoot: BasePart?, bestScore = nil, nil, -math.huge
	for _, player in fighters do
		local _, _, root = CombatUtil.getLivingCharacter(player)
		if root and player ~= boss.grabbed then
			local distance = CombatUtil.flatDistance(root.Position, boss.root.Position)
			local score = math.min((boss.threat[player] or 0) / 100, 1.5) * 1.2
				+ (1 - math.clamp(distance / 60, 0, 1))
			if now - (boss.healedAt[player] or -100) < 4 then
				score += 0.6 -- healing / reviving draws attention
			end
			if now - (boss.rangedAt[player] or -100) < 5 then
				score += 0.5 -- repeatedly attacking from range
			end
			if now - (boss.lastAttacked[player] or -100) < OttiBossConfig.RecentAttackPenaltySeconds then
				score -= 0.4 -- give the others a turn
			end
			if player == current then
				score += if now - boss.targetSince > OttiBossConfig.MaxFocusSeconds then -1.0 else 0.4
			end
			if score > bestScore then
				best, bestRoot, bestScore = player, root, score
			end
		end
	end
	if best ~= current then
		boss.target = best
		boss.targetSince = now
		local state = motion[boss]
		if state then
			state.studyUntil = now + BossPhaseDefinitions.Phases[boss.phase].StudySeconds
		end
	end
	return best, bestRoot
end

local function fightersNear(ctx: BossContext, position: Vector3, radius: number): number
	local count = 0
	for _, player in ctx.fighters() do
		local _, _, root = CombatUtil.getLivingCharacter(player)
		if root and CombatUtil.flatDistance(root.Position, position) <= radius then
			count += 1
		end
	end
	return count
end

local function ready(boss: Boss, moveId: string, now: number): boolean
	return now >= (boss.cooldowns[moveId] or 0)
end

-- Weighted choice among moves that fit the situation right now.
local function chooseMove(boss: Boss, ctx: BossContext, target: Player, distance: number, now: number): OttiMove?
	local phase = BossPhaseDefinitions.Phases[boss.phase]
	local surrounded = fightersNear(ctx, boss.root.Position, 9) >= 2
	local fighters = ctx.fighters()
	local options: { { move: OttiMove, weight: number } } = {}
	local total = 0
	for moveId, weight in phase.MoveWeights do
		local move = OttiMoveDefinitions[moveId]
		if move and weight > 0 and ready(boss, moveId, now) and distance <= move.StartRange and distance >= (move.MinRange or 0) then
			local w = weight
			if move.Kind == "Grapple" then
				if boss.lastGrappled == target and #fighters > 1 then
					w = 0 -- never the same player twice in a row when others are available
				end
			end
			if surrounded and (move.Id == "TailSweep" or move.Id == "RiverDash") then
				w *= 3 -- break free when surrounded
			end
			if w > 0 then
				table.insert(options, { move = move, weight = w })
				total += w
			end
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = boss.rng:NextNumber() * total
	for _, option in options do
		roll -= option.weight
		if roll <= 0 then
			return option.move
		end
	end
	return options[#options].move
end

local function clampInside(position: Vector3): Vector3
	if Arena.isInside(position, -6) then
		return position
	end
	return Vector3.new(0, position.Y, 0):Lerp(position, 0.8)
end

-- Movement between attacks: stance choice, approach and circling.
local function move(boss: Boss, ctx: BossContext, targetRoot: BasePart, distance: number, now: number, dt: number)
	local state = motion[boss]
	local phase = BossPhaseDefinitions.Phases[boss.phase]
	local profile = HeroCombatDefinitions.Movement[boss.companion or "Otti"]
	if now >= state.nextDriftFlip then
		state.drift = -state.drift
		local quick = boss.stance == "Quad"
		state.nextDriftFlip = now + (if quick then 0.8 + boss.rng:NextNumber() * 0.9 else 2.5 + boss.rng:NextNumber() * 2)
	end
	-- Stance: four legs to cover distance (later phases also to reposition), two legs to duel
	local wantQuad = boss.stance == "Quad"
	if distance > 30 then
		wantQuad = true
	elseif distance > 16 and boss.rng:NextNumber() < phase.QuadChance * dt * 2 then
		wantQuad = true
	elseif distance < 11 and boss.stance == "Quad" and (phase.QuadChance == 0 or boss.rng:NextNumber() < dt * 1.2) then
		wantQuad = false
	end
	if not profile.Quad then wantQuad = false end
	if wantQuad ~= (boss.stance == "Quad") then
		OttiAnimationService.setStance(boss, if wantQuad then "Quad" else "Biped")
		return
	end

	local position = boss.root.Position
	local away = CombatUtil.flat(position - targetRoot.Position)
	local direction = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
	local goal: Vector3
	if boss.stance == "Biped" then
		-- Shield forward, circle at sword range, never rigidly still
		boss.humanoid.AutoRotate = false
		OttiAnimationService.faceTowards(boss, targetRoot.Position, dt)
		local studying = now < state.studyUntil
		local ring = if studying then 8 else profile.Ring
		boss.humanoid.WalkSpeed = if distance > 14 then profile.Walk else profile.Strafe
		goal = targetRoot.Position + CFrame.fromAxisAngle(Vector3.yAxis, state.drift * 0.45):VectorToWorldSpace(direction) * ring
	else
		-- Low otter run: approach in curves and circle wide
		boss.humanoid.AutoRotate = true
		boss.humanoid.WalkSpeed = OttiBossConfig.RunSpeedQuad
		local ring = if distance > 16 then 4 else 8
		goal = targetRoot.Position + CFrame.fromAxisAngle(Vector3.yAxis, state.drift * 0.9):VectorToWorldSpace(direction) * ring
	end
	-- Surrounded: reposition away from the crowd
	if fightersNear(ctx, position, 8) >= 3 then
		goal = position + direction * 10
	end
	boss.humanoid:MoveTo(clampInside(Vector3.new(goal.X, position.Y, goal.Z)))
end

-- One AI step. Yields while an attack runs.
-- Companion bosses: the personality AI picks a ROLE, the role runs a real, validated move (or a
-- non-damaging stance / step). Otti's own choice (chooseMove) is not used for companions.


function OttiBossAI.companionDecide(boss: Boss, ctx: BossContext, target: Player, targetRoot: BasePart, distance: number, now: number)
	local personality = CompanionBossDefinitions.get(boss.companion :: string)
	if not personality then
		return
	end
	local readyAt: { [string]: number } = {}
	for name in personality.Roles do
		readyAt[name] = boss.companionReadyAt[name] or 0
	end
	local near = 0
	for _, fighter in ctx.fighters() do
		local _, _, root = CombatUtil.getLivingCharacter(fighter)
		if root and CombatUtil.flatDistance(boss.root.Position, root.Position) < 9 then
			near += 1
		end
	end
	local health = boss.health / math.max(1, boss.maxHealth)
	local character = target.Character
	local attackStart = if character then tonumber(character:GetAttribute("AttackStart")) or 0 else 0
	local attackLength = if character then tonumber(character:GetAttribute("AttackLength")) or 0 else 0
	local targetAttacking = Workspace:GetServerTimeNow() < attackStart + attackLength
	local choice = CompanionBossAI.choose(personality, {
		now = now,
		distance = distance,
		bossHealth = health,
		lastRole = boss.companionLastRole :: any,
		readyAt = readyAt :: any,
		targetAttacking = targetAttacking,
		recentlyBlocked = now < (tonumber(boss.model:GetAttribute("BlockedUntil")) or 0),
		surrounded = near >= 3,
	}, boss.rng)
	local role: any = choice.role
	if not role then
		boss.nextDecisionAt = now + 0.4
		return
	end
	boss.companionLastRole = role
	boss.companionReadyAt[role] = CompanionBossAI.cooldownEnds(personality, role, now)
	local def = personality.Roles[role :: any]
	local attack = HeroCombatDefinitions.move(boss.companion :: string, role, boss.phase)
	if attack then
		BossAttackService.execute(boss, ctx, attack, target)
		boss.companionReadyAt[role] = boss.cooldowns[attack.Id] or os.clock() + def.Cooldown
	elseif role == "Guard" then
		boss.guardUntil = now + def.Recovery + 0.6
		boss.lockedUntil = boss.guardUntil
		OttiAnimationService.setGuard(boss, true)
		OttiAnimationService.setPose(boss, if boss.companion == "Schili" then "ShellGuard" else "RaiseShield", 0.18)
		boss.humanoid:MoveTo(boss.root.Position)
		task.delay(def.Recovery + 0.6, function()
			if boss.model.Parent and not boss.defeated and os.clock() >= boss.guardUntil then
				OttiAnimationService.setGuard(boss, false)
				if not boss.busy then OttiAnimationService.setPose(boss, "", 0.2) end
			end
		end)
	elseif role == "Retreat" then
		local away = CombatUtil.flat(boss.root.Position - targetRoot.Position)
		if away.Magnitude > 0.1 then
			boss.lockedUntil = now + 0.8
			boss.humanoid:MoveTo(clampInside(boss.root.Position + away.Unit * 7))
		end
	end
	boss.nextDecisionAt = os.clock() + CompanionBossAI.pause(personality, health, boss.rng)
end

function OttiBossAI.step(boss: Boss, ctx: BossContext, dt: number)
	local now = os.clock()
	if not motion[boss] then
		motion[boss] = { drift = if boss.rng:NextNumber() < 0.5 then 1 else -1, nextDriftFlip = now + 2, studyUntil = now + 1 }
	end
	OttiAnimationService.update(boss, dt)
	if boss.busy or now < boss.lockedUntil then
		return
	end
	local target, targetRoot = OttiBossAI.selectTarget(boss, ctx, now)
	if not target or not targetRoot then
		boss.humanoid:MoveTo(boss.root.Position)
		return
	end
	local distance = CombatUtil.flatDistance(boss.root.Position, targetRoot.Position)
	local state = motion[boss]

	-- Companion bosses (Kroko, Schili) decide with their own personality AI; movement stays shared
	if boss.companion then
		if now >= boss.nextDecisionAt and now >= state.studyUntil then
			OttiBossAI.companionDecide(boss, ctx, target, targetRoot, distance, now)
			return -- preserve guard/retreat and do not overwrite a completed attack with stale movement
		end
		move(boss, ctx, targetRoot, distance, now, dt)
		return
	end

	if now >= boss.nextDecisionAt and now >= state.studyUntil then
		local choice = chooseMove(boss, ctx, target, distance, now)
		if choice then
			local result = BossAttackService.execute(boss, ctx, choice, target)
			-- Follow-up combinations
			local followUp = choice.FollowUp
			if followUp and ctx.stillValid() and boss.phase >= followUp.MinPhase and boss.rng:NextNumber() < followUp.Chance
				and (not followUp.OnlyIfHit or result.damaged) and ready(boss, followUp.Move, os.clock()) then
				local nextMove = OttiMoveDefinitions[followUp.Move]
				if nextMove and not (nextMove.Kind == "Grapple" and boss.lastGrappled == target and #ctx.fighters() > 1) then
					BossAttackService.execute(boss, ctx, nextMove, target)
				end
			end
			local phase = BossPhaseDefinitions.Phases[boss.phase]
			boss.nextDecisionAt = os.clock() + phase.PauseMin + boss.rng:NextNumber() * (phase.PauseMax - phase.PauseMin)
			return
		end
	end
	move(boss, ctx, targetRoot, distance, now, dt)
end

-- Runs a specific move right away (phase-change roar, Phase 3 shield-and-tail counter).
function OttiBossAI.perform(boss: Boss, ctx: BossContext, moveId: string)
	local move = OttiMoveDefinitions[moveId]
	local target = boss.target
	if move and target and not boss.busy then
		BossAttackService.execute(boss, ctx, move, target)
	end
end

return OttiBossAI
