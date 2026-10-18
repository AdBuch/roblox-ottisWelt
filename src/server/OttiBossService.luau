--!strict
-- Round 7: OTTI — CHAMPION OF THE COLOSSEUM. Owns the boss encounter from the silent pause after
-- Round 6 to Otti's surrender:
--   pre-intro  ~6 s pause: arena darkens slightly, every gate's portcullis drops, the crowd falls
--              silent ("THE CROWD FALLS SILENT...")
--   intro      the main gladiator gate opens, Otti walks in on all fours, pauses, rises onto his
--              hind legs, draws his sword, raises his shield, sweeps his tail across the sand
--              (skippable once every participant has seen it this session)
--   fight      health scales with players (damage never does); three phases with a short
--              phase-change show; the AI runs in OttiBossAI; attacks in BossAttackService
--   defeat     at zero health Otti is DEFEATED, not killed: attacks stop, a grappled player is
--              released, he drops his sword, kneels and raises a paw in surrender
-- Otti is never a zombie: he uses his own tag (Config.OttiTag) and none of the zombie systems.
-- Every async step re-checks an encounter token, so a stopped match leaves no stale boss state.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioConfig = require(ReplicatedStorage.Shared.AudioConfig)
local BossPhaseDefinitions = require(ReplicatedStorage.Shared.BossPhaseDefinitions)
local Config = require(ReplicatedStorage.Shared.Config)
local OttiBossConfig = require(ReplicatedStorage.Shared.OttiBossConfig)
local OttiMoveDefinitions = require(ReplicatedStorage.Shared.OttiMoveDefinitions)
local Arena = require(script.Parent.Arena)
local BossGrappleService = require(script.Parent.BossGrappleService)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatUtil = require(script.Parent.CombatUtil)
local CrowdReactionService = require(script.Parent.CrowdReactionService)
local DamageEffectsService = require(script.Parent.DamageEffectsService)
local OttiAnimationService = require(script.Parent.OttiAnimationService)
local OttiBossAI = require(script.Parent.OttiBossAI)
local OttiModel = require(script.Parent.OttiModel)
local Remotes = require(script.Parent.Remotes)

type Boss = OttiAnimationService.Boss
type BossContext = OttiAnimationService.BossContext
type BossHit = OttiAnimationService.BossHit

export type Handlers = {
	hitPlayer: (player: Player, hit: BossHit) -> (number, boolean),
	setControlLocked: (player: Player, locked: boolean) -> (),
	grantImmunity: (player: Player, seconds: number) -> (),
	knockdown: (player: Player, seconds: number) -> (),
}

export type EncounterOptions = {
	playerCount: number, -- participants at the start (health scaling)
	participants: () -> { Player }, -- everyone in the match (for "intro seen")
	fighters: () -> { Player }, -- living arena fighters Otti may target
	onFightStarted: () -> (),
	onDefeated: (damageBy: { [Player]: number }) -> (),
}

local PREFIX = "[OttiArena][Server]"

local OttiBossService = {}

local arenaFolder: Instance? = nil
local handlers: Handlers? = nil
local token = 0
local boss: Boss? = nil
local options: EncounterOptions? = nil
local skipRequested = false
local warningId = 0
local pendingPhaseShow = false
local phaseChanging = false

local function setAttr(name: string, value: any)
	if arenaFolder then
		arenaFolder:SetAttribute(name, value)
	end
end

local function publishHealth()
	local current = boss
	if current then
		setAttr(Config.BossHealthAttribute, math.max(0, math.ceil(current.health)))
		setAttr(Config.BossMaxHealthAttribute, current.maxHealth)
		setAttr(Config.BossPhaseAttribute, current.phase)
	end
end

local function resetAttributes()
	setAttr(Config.BossActiveAttribute, false)
	setAttr(Config.BossIntroAttribute, "")
	setAttr(Config.BossHealthAttribute, 0)
	setAttr(Config.BossMaxHealthAttribute, 0)
	setAttr(Config.BossPhaseAttribute, 1)
	setAttr(Config.BossWarningAttribute, "")
	setAttr(Config.BossDefeatedAttribute, false)
	setAttr("BossIntroSkippable", false)
end

local function warnPlayers(text: string, seconds: number)
	warningId += 1
	local myId = warningId
	setAttr(Config.BossWarningAttribute, text)
	setAttr(Config.BossWarningIdAttribute, myId)
	task.delay(seconds + 0.3, function()
		if warningId == myId then
			setAttr(Config.BossWarningAttribute, "")
		end
	end)
end

local function playSound(id: string, at: BasePart)
	if id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = AudioConfig.Volume
	sound.RollOffMaxDistance = 300
	sound.PlayOnRemove = true
	sound.Parent = at
	sound:Destroy()
end

local function makeContext(myToken: number): BossContext
	local h = handlers :: Handlers
	return {
		hitPlayer = h.hitPlayer,
		setControlLocked = h.setControlLocked,
		grantImmunity = h.grantImmunity,
		knockdown = h.knockdown,
		fighters = function(): { Player }
			local current = options
			if not current or token ~= myToken then
				return {}
			end
			local list = {}
			for _, player in current.fighters() do
				local _, _, root = CombatUtil.getLivingCharacter(player)
				if root and Arena.isInside(root.Position) then
					table.insert(list, player)
				end
			end
			return list
		end,
		warn = warnPlayers,
		crowd = CrowdReactionService.react,
		stillValid = function(): boolean
			local current = boss
			return token == myToken and current ~= nil and current.fighting and not current.defeated
		end,
	}
end

------------------------------------------------------------------------------------------
-- Intro
------------------------------------------------------------------------------------------

-- Waits unless the intro was skipped; false if the encounter was stopped meanwhile.
local function introWait(myToken: number, seconds: number): boolean
	local elapsed = 0
	while elapsed < seconds do
		if token ~= myToken then
			return false
		end
		if skipRequested then
			return true
		end
		elapsed += task.wait(0.05)
	end
	return token == myToken
end

local function allSeenIntro(): boolean
	local current = options
	if not current then
		return false
	end
	for _, player in current.participants() do
		if player.Parent and not player:GetAttribute(Config.IntroSeenAttribute) then
			return false
		end
	end
	return true
end

local function gateFrame(offset: number): CFrame
	return Arena.frameAt(Arena.Layout.MainGateAngle, offset, Arena.Layout.FloorTop)
end

local function spawnOtti(): Boss
	local rig = OttiModel.build()
	local start = gateFrame(-3)
	local height = rig.humanoid.HipHeight + rig.root.Size.Y / 2
	rig.model:PivotTo(start + Vector3.new(0, height, 0))
	rig.model.Parent = arenaFolder
	rig.root:SetNetworkOwner(nil) -- the server moves Otti; clients only animate him
	CollectionService:AddTag(rig.model, Config.OttiTag)
	local created = OttiAnimationService.new(rig)
	OttiAnimationService.setSwordDrawn(created, false)
	created.lastYaw = OttiAnimationService.getYaw(created)
	return created
end

-- Final intro pose (also used when the intro is skipped).
local function finishIntroPose(current: Boss)
	local stop = gateFrame(-OttiBossConfig.WalkInDistance)
	local height = current.humanoid.HipHeight + current.root.Size.Y / 2
	current.model:PivotTo(stop + Vector3.new(0, height, 0))
	current.stance = "Biped"
	current.model:SetAttribute("Stance", "Biped")
	OttiAnimationService.setLoco(current, "BIPED_IDLE")
	OttiAnimationService.setSwordDrawn(current, true)
	OttiAnimationService.setPose(current, "", 0.2)
	current.humanoid.WalkSpeed = OttiBossConfig.WalkSpeedBiped
end

local function runIntro(myToken: number): boolean
	-- Quiet anticipation: darker arena, gates close, the crowd falls silent
	CrowdReactionService.react("Silent")
	CrowdReactionService.setBaseLight(-0.45)
	task.delay(0.8, function()
		if token == myToken then
			Arena.setGates(true)
		end
	end)
	if not introWait(myToken, OttiBossConfig.SilenceTextAt) then
		return false
	end
	setAttr(Config.BossIntroAttribute, "Silence")
	skipRequested = false -- skipping only applies to the walk-in itself
	setAttr("BossIntroSkippable", allSeenIntro())
	if not introWait(myToken, OttiBossConfig.PreIntroSeconds - OttiBossConfig.SilenceTextAt) then
		return false
	end

	-- The main gladiator gate opens and Otti enters
	Arena.setGates(false, true)
	local current = spawnOtti()
	boss = current
	setAttr(Config.BossIntroAttribute, "Reveal")
	CrowdReactionService.react("Enter")
	local current_options = options
	if current_options then
		for _, player in current_options.participants() do
			player:SetAttribute(Config.IntroSeenAttribute, true) -- may skip it next time
		end
	end
	local walkTo = gateFrame(-OttiBossConfig.WalkInDistance).Position
	current.humanoid.WalkSpeed = OttiBossConfig.WalkInDistance / OttiBossConfig.WalkInSeconds
	current.humanoid:MoveTo(Vector3.new(walkTo.X, current.root.Position.Y, walkTo.Z))
	OttiAnimationService.setLoco(current, "QUADRUPED_WALK")
	local steps: { { pose: string, seconds: number, loco: string?, action: (() -> ())? } } = {
		{ pose = "", seconds = OttiBossConfig.WalkInSeconds },
		{ pose = "", seconds = 0.6, loco = "QUADRUPED_IDLE" }, -- pauses, sniffs the air
		{ pose = "", seconds = 0.55, loco = "RISE_TO_BIPED", action = function()
			current.stance = "Biped"
			current.model:SetAttribute("Stance", "Biped")
		end },
		{ pose = "DrawSword", seconds = 0.7, loco = "BIPED_IDLE", action = function()
			task.delay(0.3, function()
				if token == myToken then
					OttiAnimationService.setSwordDrawn(current, true)
				end
			end)
		end },
		{ pose = "RaiseShield", seconds = 0.6 },
		{ pose = "IntroSweep", seconds = 1.0, action = function()
			local back = current.root.Position - CombatUtil.flat(current.root.CFrame.LookVector) * 4
			CombatEffects.sandBurst(Vector3.new(back.X, Arena.Layout.FloorTop, back.Z), 7, 1)
		end },
		{ pose = "Roar", seconds = 0.8, action = function()
			CrowdReactionService.react("Cheer")
			playSound(AudioConfig.OttiBattleCry, current.root)
		end },
	}
	for _, step in steps do
		if skipRequested then
			break
		end
		if step.loco then
			OttiAnimationService.setLoco(current, step.loco :: any)
		end
		OttiAnimationService.setPose(current, step.pose, 0.2)
		if step.action then
			step.action()
		end
		if not introWait(myToken, step.seconds) then
			return false
		end
	end
	if token ~= myToken then
		return false
	end
	finishIntroPose(current)
	Arena.setGates(true, true) -- the main gate closes behind him
	setAttr(Config.BossIntroAttribute, "")
	setAttr("BossIntroSkippable", false)
	return true
end

------------------------------------------------------------------------------------------
-- Fight
------------------------------------------------------------------------------------------

local function phaseShow(current: Boss, ctx: BossContext)
	-- Otti strikes his shield, sand bursts outward, the crowd reacts, the bar changes color
	phaseChanging = true
	current.lockedUntil = os.clock() + OttiBossConfig.PhaseChangeSeconds
	current.humanoid:MoveTo(current.root.Position)
	if current.stance ~= "Biped" then
		OttiAnimationService.setStance(current, "Biped")
	end
	OttiAnimationService.setLoco(current, "BIPED_IDLE")
	OttiAnimationService.setPose(current, "ShieldStrike", 0.15)
	task.wait(0.45)
	if not ctx.stillValid() then
		phaseChanging = false
		return
	end
	playSound(AudioConfig.ShieldStrike, current.root)
	CombatEffects.sandBurst(Vector3.new(current.root.Position.X, Arena.Layout.FloorTop, current.root.Position.Z), 14, 1.6)
	CrowdReactionService.react(if current.phase >= 3 then "Cheer" else "Gasp")
	warnPlayers(("PHASE %d"):format(current.phase), 1.8)
	task.wait(OttiBossConfig.PhaseChangeSeconds - 0.45)
	OttiAnimationService.setPose(current, "", 0.2)
	phaseChanging = false
	if current.phase >= 3 and ctx.stillValid() then
		OttiBossAI.perform(current, ctx, "BattleCry") -- champion unleashed
	end
end

local function fightLoop(myToken: number, current: Boss, ctx: BossContext)
	local last = os.clock()
	while token == myToken and current.fighting and not current.defeated do
		local dt = task.wait(0.1)
		local now = os.clock()
		-- Poise recovers over time
		current.poise = math.max(0, current.poise - OttiBossConfig.PoiseDecayPerSecond * (now - last))
		last = now
		if current.model:GetAttribute("Guard") and now >= current.guardUntil then
			OttiAnimationService.setGuard(current, false)
		end
		if pendingPhaseShow and not current.busy then
			pendingPhaseShow = false
			phaseShow(current, ctx)
		else
			OttiBossAI.step(current, ctx, dt)
		end
	end
end

local function defeat(current: Boss)
	if current.defeated then
		return
	end
	current.defeated = true
	current.fighting = false
	current.interrupted = true
	current.health = 0
	BossGrappleService.releaseAll() -- a grappled player is always released safely
	warningId += 1
	setAttr(Config.BossWarningAttribute, "")
	setAttr(Config.BossDefeatedAttribute, true)
	publishHealth()
	print(PREFIX, "OTTI DEFEATED — the Colosseum has a new champion")

	-- Surrender: drops his sword, kneels back on his tail, raises a paw. No injuries, no gore.
	current.humanoid:MoveTo(current.root.Position)
	current.humanoid.WalkSpeed = 0
	OttiAnimationService.setGuard(current, false)
	OttiAnimationService.setLoco(current, "DEFEATED")
	OttiAnimationService.setPose(current, "Surrender", 0.6)
	local blade = current.rig.swordParts
	local dropped = Instance.new("Model")
	dropped.Name = "DroppedGladius"
	for _, part in blade do
		local copy = part:Clone()
		for _, child in copy:GetChildren() do
			if not child:IsA("SpecialMesh") then
				child:Destroy()
			end
		end
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.Parent = dropped
		part.Transparency = 1
	end
	dropped.Parent = current.model
	local front = current.root.Position + CombatUtil.flat(current.root.CFrame.LookVector) * 3.5
	dropped:PivotTo(CFrame.new(front.X, Arena.Layout.FloorTop + 0.2, front.Z) * CFrame.Angles(0, math.rad(30), math.rad(90)))
	CombatEffects.sandBurst(Vector3.new(front.X, Arena.Layout.FloorTop, front.Z), 3, 0.5)
	CrowdReactionService.react("Celebrate")

	local current_options = options
	if current_options then
		task.spawn(current_options.onDefeated, table.clone(current.damageBy))
	end
end

------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------

function OttiBossService.init(folder: Instance, newHandlers: Handlers)
	arenaFolder = folder
	handlers = newHandlers
	resetAttributes()
	setAttr(Config.BossWarningIdAttribute, 0)
	-- Skipping the intro (only once every participant has already seen it this session)
	Remotes.CombatAction.OnServerEvent:Connect(function(player: Player, action: unknown)
		if action ~= "SkipIntro" or not player:GetAttribute(Config.IntroSeenAttribute) then
			return
		end
		local current = options
		if current and table.find(current.participants(), player) and allSeenIntro() then
			skipRequested = true
		end
	end)
	Players.PlayerRemoving:Connect(BossGrappleService.releasePlayer)
end

-- Starts Round 7 (yields through the intro, then returns while the fight runs).
function OttiBossService.startEncounter(newOptions: EncounterOptions)
	OttiBossService.stop()
	token += 1
	local myToken = token
	options = newOptions
	skipRequested = false
	pendingPhaseShow = false
	phaseChanging = false
	resetAttributes()
	setAttr(Config.BossActiveAttribute, true)
	print(PREFIX, "Round 7: OTTI — CHAMPION OF THE COLOSSEUM")

	if not runIntro(myToken) then
		return
	end
	local current = boss
	if not current or token ~= myToken then
		return
	end
	local count = math.clamp(newOptions.playerCount, 1, #OttiBossConfig.HealthByPlayers)
	current.maxHealth = OttiBossConfig.HealthByPlayers[count]
	current.health = current.maxHealth
	current.phase = 1
	current.fighting = true
	current.invulnerable = false
	current.nextDecisionAt = os.clock() + 1.2
	publishHealth()
	CrowdReactionService.setBaseLight(-0.2)
	newOptions.onFightStarted()
	local ctx = makeContext(myToken)
	task.spawn(fightLoop, myToken, current, ctx)
end

-- Ends the encounter immediately and removes every trace of it (cleanup, aborted match).
function OttiBossService.stop()
	token += 1
	BossGrappleService.releaseAll()
	local current = boss
	boss = nil
	options = nil
	skipRequested = false
	pendingPhaseShow = false
	phaseChanging = false
	warningId += 1
	if current then
		current.fighting = false
		current.defeated = true
		current.model:Destroy()
	end
	for _, leftover in CollectionService:GetTagged(Config.OttiTag) do
		leftover:Destroy()
	end
	resetAttributes()
	CrowdReactionService.reset()
	Arena.setGates(false) -- every portcullis back up (hidden)
end

-- The boss model/root while Otti can be hit (fight running, not defeated).
function OttiBossService.getHittable(): (Model?, BasePart?)
	local current = boss
	if current and current.fighting and not current.defeated and current.model.Parent then
		return current.model, current.root
	end
	return nil, nil
end

function OttiBossService.isActive(): boolean
	return boss ~= nil
end

-- A validated player hit on Otti. Returns damage dealt and whether his shield blocked it.
function OttiBossService.applyPlayerHit(attacker: Player, damage: number, fromPosition: Vector3, isProjectile: boolean, stagger: number, hitPosition: Vector3?): (number, boolean)
	local current = boss
	if not current or not current.fighting or current.defeated or current.invulnerable then
		return 0, false
	end
	local now = os.clock()
	local phase = BossPhaseDefinitions.Phases[current.phase]
	local frontal = CombatUtil.isFacing(current.root.CFrame, fromPosition, OttiBossConfig.GuardFacingDot)
	local blocked = false
	local amount = damage

	-- Raised shield: frontal hits are mostly stopped
	if frontal and now < current.guardUntil then
		blocked = true
		amount *= 1 - OttiBossConfig.GuardReduction
		CombatEffects.burst(current.rig.shieldFace.Position, Color3.fromRGB(255, 220, 120), 0.8)
		-- Phase 3: shield-and-tail counter (limited cooldown, never on every block)
		local counter = OttiMoveDefinitions.ShieldTailCounter
		if phase.CounterEnabled and now >= current.counterReadyAt and not current.busy then
			current.counterReadyAt = now + counter.Cooldown
			local ctx = makeContext(token)
			task.spawn(OttiBossAI.perform, current, ctx, counter.Id)
		end
	elseif frontal and not current.busy and now >= current.guardReadyAt then
		-- Predictable frontal attacks from one player make him raise his shield
		local list = current.frontalHits[attacker] or {}
		table.insert(list, now)
		while #list > 0 and now - list[1] > OttiBossConfig.PredictableWindow do
			table.remove(list, 1)
		end
		current.frontalHits[attacker] = list
		if #list >= OttiBossConfig.PredictableHits and current.rng:NextNumber() < phase.GuardChance then
			table.clear(list)
			current.guardUntil = now + OttiBossConfig.GuardSeconds
			current.guardReadyAt = now + OttiBossConfig.GuardSeconds + 3
			OttiAnimationService.setGuard(current, true)
			OttiAnimationService.faceTowards(current, fromPosition, 0)
		end
	end
	if phaseChanging then
		amount *= 0.5
	end
	local dealt = math.max(0, math.floor(amount + 0.5))
	if dealt <= 0 and not blocked then
		return 0, false
	end

	current.health -= dealt
	current.damageBy[attacker] = (current.damageBy[attacker] or 0) + dealt
	current.threat[attacker] = (current.threat[attacker] or 0) + dealt
	local _, _, attackerRoot = CombatUtil.getLivingCharacter(attacker)
	if isProjectile or (attackerRoot and CombatUtil.flatDistance(attackerRoot.Position, current.root.Position) > OttiBossConfig.RangedAttackerDistance) then
		current.rangedAt[attacker] = now
	end
	DamageEffectsService.hit("Boss", hitPosition or current.root.Position + Vector3.new(0, 2, 0), math.clamp(dealt / 25, 0.4, 1.4), CombatUtil.flat(current.root.Position - fromPosition))
	publishHealth()

	if current.health <= 0 then
		defeat(current)
		return dealt, blocked
	end

	-- Poise: heavy or repeated hits stagger him (never during an active hit window or a grapple)
	current.poise += dealt * 0.6 + stagger * 40
	if current.poise >= OttiBossConfig.PoiseMax and not current.inActive and current.grabbed == nil and not phaseChanging then
		current.poise = 0
		table.insert(current.breaks, now)
		while #current.breaks > 0 and now - current.breaks[1] > OttiBossConfig.KnockdownWindow do
			table.remove(current.breaks, 1)
		end
		current.interrupted = true
		local knocked = #current.breaks >= 3
		if knocked then
			table.clear(current.breaks)
		end
		local reaction: OttiAnimationService.Loco = if knocked then "KNOCKDOWN" else "STAGGER"
		task.spawn(OttiAnimationService.react, current, reaction, if knocked then OttiBossConfig.KnockdownSeconds else OttiBossConfig.StaggerSeconds)
	end

	-- Phase thresholds
	local newPhase = BossPhaseDefinitions.forShare(current.health / current.maxHealth).Index
	if newPhase > current.phase then
		current.phase = newPhase
		publishHealth()
		pendingPhaseShow = true
		print(PREFIX, ("Otti enters phase %d: %s"):format(newPhase, BossPhaseDefinitions.Phases[newPhase].Name))
	end
	return dealt, blocked
end

-- Healing near the fight draws Otti's attention.
function OttiBossService.onPlayerHealed(player: Player)
	local current = boss
	if current and current.fighting then
		current.healedAt[player] = os.clock()
	end
end

return OttiBossService
