--!strict
-- Zombie attacks and attack SEQUENCES per zombie type (server: ZombieAttackSequenceService picks,
-- ZombieService executes; clients only see the replicated poses and effects).
-- A step:
--   Kind  "Hit" (a validated blow), "Block" (raise the guard), "Counter" (only if the guard just
--         stopped a player attack), "Move" (short step: Forward > 0, back < 0, Side), "Roar"
--         (telegraph), "Stomp" (ring around the zombie), "Net" (Retiarius throw)
--   Anim  pose family (SlashR, SlashL, Thrust, Bash, Overhead, Wide, Low, Rise, Charge, Shove, ...)
--   Arc   full hit arc in degrees: the target must be inside it at the impact moment (the pose
--         and the validated volume point the same way)
-- Multipliers are relative to the zombie's ZombieDefinitions values (Damage, WindUpSeconds).
-- Selection (ZombieAttackSequenceService): distance window, health condition, the target's block,
-- per-sequence cooldown, never the same sequence more than twice in a row, weights; heavy steps
-- of different zombies on the same target are spaced (HeavySpacing) so they never sync up.

export type StepKind = "Hit" | "Block" | "Counter" | "Move" | "Roar" | "Stomp" | "Net"
export type Condition = "Any" | "Healthy" | "Wounded" | "Critical" | "NotCritical"

export type Step = {
	Kind: StepKind,
	Anim: string,
	WindUp: number, -- x WindUpSeconds
	Damage: number, -- x Damage
	ReachAdd: number?,
	Arc: number?, -- degrees (default 110)
	Height: string?, -- Low | Mid | High
	Heavy: boolean?,
	Pierce: number?, -- block pierce override
	Knockback: number?,
	Forward: number?, -- Move: studs (negative = back)
	Side: number?, -- Move: sideways studs
	Recovery: number?, -- seconds after the step
	Radius: number?, -- Stomp
}

export type Sequence = {
	Id: string,
	Name: string,
	Steps: { Step },
	Weight: number,
	MinDistance: number?,
	MaxDistance: number?, -- default: the zombie's attack range
	Cooldown: number,
	Condition: Condition,
	PreferVsBlock: boolean?, -- extra weight when the target is blocking
	NeedsShield: boolean?, -- needs the shield arm
	Recovery: number?, -- extra recovery at the end
}

local function hit(anim: string, windUp: number, damage: number, extra: { [string]: any }?): Step
	local step: { [string]: any } = { Kind = "Hit", Anim = anim, WindUp = windUp, Damage = damage }
	for k, v in (extra or {}) :: { [string]: any } do
		step[k] = v
	end
	return table.freeze(step) :: any
end

local function step(kind: StepKind, anim: string, windUp: number, extra: { [string]: any }?): Step
	local s: { [string]: any } = { Kind = kind, Anim = anim, WindUp = windUp, Damage = 0 }
	for k, v in (extra or {}) :: { [string]: any } do
		s[k] = v
	end
	return table.freeze(s) :: any
end

local function seq(id: string, name: string, weight: number, cooldown: number, condition: Condition, steps: { Step }, extra: { [string]: any }?): Sequence
	local s: { [string]: any } = { Id = id, Name = name, Weight = weight, Cooldown = cooldown, Condition = condition, Steps = table.freeze(steps) }
	for k, v in (extra or {}) :: { [string]: any } do
		s[k] = v
	end
	return table.freeze(s) :: any
end

local ByZombie: { [string]: { Sequence } } = {
	LegionRemnant = {
		seq("RightSlash", "RIGHT SLASH", 2, 0, "Any", { hit("SlashR", 1, 1) }),
		seq("LeftSlash", "LEFT SLASH", 2, 0, "Any", { hit("SlashL", 1, 1) }),
		seq("Thrust", "FORWARD THRUST", 1.5, 0, "Any", { hit("Thrust", 1, 1, { Arc = 50, ReachAdd = 1 }) }),
		seq("ShieldBash", "SHIELD BASH", 1, 2, "NotCritical", { hit("Bash", 0.8, 0.6, { Pierce = 0.8, Knockback = 22 }) }, { NeedsShield = true, PreferVsBlock = true }),
		seq("GuardedStep", "GUARDED STEP", 1, 2, "NotCritical", { step("Move", "Guard", 0.4, { Forward = 2 }), hit("Thrust", 0.7, 0.9, { Arc = 60 }) }, { NeedsShield = true }),
		seq("LegionCombination", "LEGION COMBINATION", 2.5, 5, "NotCritical", {
			step("Block", "Guard", 0.4), hit("SlashR", 0.9, 0.8), hit("SlashL", 0.6, 0.8), hit("Thrust", 0.6, 0.9, { Arc = 50, ReachAdd = 1 }),
		}, { NeedsShield = true, Recovery = 0.4 }),
		seq("ShieldPressure", "SHIELD PRESSURE", 2, 6, "NotCritical", {
			hit("Bash", 0.8, 0.6, { Pierce = 0.8, Knockback = 18 }), step("Move", "Guard", 0.3, { Forward = 3 }), hit("Overhead", 1, 1.1, { Height = "High", Arc = 70 }),
		}, { NeedsShield = true, PreferVsBlock = true, Recovery = 0.4 }),
		seq("DefensiveCounter", "DEFENSIVE COUNTER", 1.5, 7, "NotCritical", {
			step("Block", "Guard", 0.2, { Recovery = 0.9 }), step("Counter", "SlashR", 0.35, { Damage = 1.1 }),
		}, { NeedsShield = true }),
		seq("Desperate", "DESPERATE ATTACKS", 3, 3, "Critical", {
			hit("SlashR", 0.7, 0.9, { ReachAdd = -0.5 }), hit("SlashL", 0.6, 0.9, { ReachAdd = -0.5 }),
		}, { Recovery = 1.0 }),
	},
	RottenVelite = {
		seq("SideSlash", "FAST SIDE SLASH", 2, 0, "Any", { hit("SlashR", 0.8, 1) }),
		seq("LowCut", "LOW CUT", 1.5, 0, "Any", { hit("Low", 0.8, 0.9, { Height = "Low" }) }),
		seq("LungingStab", "LUNGING STAB", 1.5, 2, "Any", { step("Move", "Thrust", 0.3, { Forward = 3 }), hit("Thrust", 0.6, 1.1, { Arc = 45, ReachAdd = 1 }) }),
		seq("RetreatingCut", "RETREATING CUT", 1, 2, "Any", { hit("SlashL", 0.7, 0.8), step("Move", "Guard", 0.1, { Forward = -4 }) }),
		seq("SkirmisherStrike", "SKIRMISHER STRIKE", 2.5, 5, "NotCritical", {
			step("Move", "Thrust", 0.2, { Forward = 3 }), hit("SlashR", 0.7, 0.9), hit("SlashL", 0.6, 0.8), step("Move", "Guard", 0.1, { Forward = -5 }),
		}, { MinDistance = 3 }),
		seq("LowHigh", "LOW-HIGH COMBINATION", 2, 5, "Any", {
			hit("Low", 0.8, 0.8, { Height = "Low" }), hit("Rise", 0.6, 0.9, { Height = "High", Arc = 80 }), step("Move", "Guard", 0.1, { Side = 4 }),
		}),
		seq("DesperateFlurry", "DESPERATE FLURRY", 3, 6, "Critical", {
			hit("SlashR", 0.5, 0.5), hit("SlashL", 0.4, 0.5), hit("SlashR", 0.4, 0.5), hit("Thrust", 0.4, 0.6, { Arc = 50 }),
		}, { Recovery = 1.4 }),
	},
	ArenaBrute = {
		seq("HeavyOverhead", "HEAVY OVERHEAD", 2, 0, "Any", { hit("Overhead", 1.2, 1.3, { Height = "High", Heavy = true, Arc = 70, Knockback = 18 }) }, { Recovery = 0.4 }),
		seq("WideStrike", "WIDE STRIKE", 1.5, 2, "Any", { hit("Wide", 1.1, 1, { Arc = 170, Heavy = true, Knockback = 14 }) }, { Recovery = 0.4 }),
		seq("Shove", "WEAPON SHOVE", 1, 2, "Any", { hit("Shove", 0.7, 0.6, { Arc = 70, Knockback = 26, Pierce = 0.6 }) }, { PreferVsBlock = true }),
		seq("Stomp", "STOMP", 1, 4, "Any", { step("Stomp", "Stomp", 1, { Damage = 0.7, Radius = 7, Heavy = true, Height = "Low" }) }, { MaxDistance = 7 }),
		seq("BruteCrush", "BRUTE CRUSH", 2, 7, "NotCritical", {
			step("Roar", "Roar", 0.9), hit("Overhead", 1.4, 1.5, { Height = "High", Heavy = true, Arc = 70, Knockback = 20 }), step("Stomp", "Stomp", 0.3, { Damage = 0.4, Radius = 6, Height = "Low" }),
		}, { Recovery = 0.8 }),
		seq("WallOfForce", "WALL OF FORCE", 2, 8, "Any", {
			step("Move", "Charge", 0.6, { Forward = 6 }), hit("Shove", 0.3, 0.7, { Arc = 80, Knockback = 28, Heavy = true }), hit("Wide", 0.9, 1, { Arc = 170, Heavy = true }),
		}, { MinDistance = 4, MaxDistance = 12, Recovery = 0.8 }),
		seq("Enraged", "ENRAGED COMBINATION", 3, 7, "Wounded", {
			hit("SlashL", 1, 1.1, { Heavy = true, Arc = 120 }), hit("SlashR", 0.9, 1.1, { Heavy = true, Arc = 120 }), hit("Overhead", 1.1, 1.3, { Height = "High", Heavy = true, Arc = 70 }),
		}, { Recovery = 1.6 }),
	},
	NetFighter = {
		seq("Thrust", "TRIDENT THRUST", 2, 0, "Any", { hit("Thrust", 1, 1, { Arc = 40, ReachAdd = 1.5 }) }),
		seq("Sweep", "TRIDENT SWEEP", 1.5, 2, "Any", { hit("Low", 0.9, 0.8, { Height = "Low", Arc = 140 }) }),
		seq("BackThrust", "DEFENSIVE THRUST", 1, 3, "Any", { step("Move", "Guard", 0.1, { Forward = -3 }), hit("Thrust", 0.7, 0.9, { Arc = 40, ReachAdd = 2 }) }),
		seq("NetAndStrike", "NET AND STRIKE", 2.5, 9, "NotCritical", {
			step("Net", "Net", 1), step("Move", "Thrust", 0.2, { Forward = 4 }), hit("Thrust", 0.6, 1.2, { Arc = 40, ReachAdd = 1.5 }),
		}, { NeedsShield = true, MinDistance = 5, MaxDistance = 13 }),
		seq("RetiariusRetreat", "RETIARIUS RETREAT", 2, 5, "Any", {
			hit("Low", 0.8, 0.8, { Height = "Low", Arc = 140 }), step("Move", "Guard", 0.1, { Forward = -4 }), hit("Thrust", 0.6, 0.9, { Arc = 40, ReachAdd = 2 }),
		}),
		seq("CornerEscape", "CORNER ESCAPE", 1.5, 6, "Any", {
			hit("Low", 0.7, 0.7, { Height = "Low", Arc = 150 }), step("Move", "Guard", 0.1, { Side = 5 }), step("Move", "Guard", 0.1, { Forward = -5 }),
		}, { MaxDistance = 5 }),
	},
	ArenaChampion = {
		seq("GuardedThrust", "GUARDED THRUST", 2, 0, "Any", { hit("Thrust", 1, 1, { Arc = 50, ReachAdd = 1 }) }),
		seq("HeavyBash", "HEAVY SHIELD BASH", 1.5, 3, "NotCritical", { hit("Bash", 0.9, 0.7, { Pierce = 0.8, Knockback = 26, Heavy = true }) }, { NeedsShield = true, PreferVsBlock = true }),
		seq("Slash", "SWORD SLASH", 2, 0, "Any", { hit("SlashR", 1, 1) }),
		seq("Overhead", "OVERHEAD STRIKE", 1, 2, "Any", { hit("Overhead", 1.2, 1.3, { Height = "High", Arc = 70 }) }, { Recovery = 0.3 }),
		seq("Judgement", "CHAMPION'S JUDGEMENT", 2.5, 7, "NotCritical", {
			step("Move", "Guard", 0.4, { Forward = 2 }), hit("Bash", 0.7, 0.6, { Pierce = 0.8, Knockback = 16 }), hit("SlashR", 0.6, 0.9), hit("Overhead", 0.9, 1.2, { Height = "High", Arc = 70 }),
		}, { NeedsShield = true, Recovery = 0.5 }),
		seq("BronzeCounter", "BRONZE COUNTER", 2, 8, "NotCritical", {
			step("Block", "Guard", 0.2, { Recovery = 1.0 }), step("Counter", "Bash", 0.25, { Damage = 0.5, Knockback = 18 }), hit("SlashL", 0.5, 0.9), hit("Thrust", 0.5, 1, { Arc = 50 }),
		}, { NeedsShield = true }),
		seq("FinalFury", "FINAL FURY", 3, 7, "Critical", {
			hit("SlashL", 0.9, 1.1, { Heavy = true }), hit("SlashR", 0.8, 1.1, { Heavy = true }), hit("Bash", 0.6, 0.7, { Knockback = 18 }), hit("Overhead", 0.9, 1.3, { Height = "High", Arc = 70, Heavy = true }),
		}, { Recovery = 1.5 }),
	},
	UndeadSagittarius = {
		-- melee only when cornered (bow shove / weak stab); its arrows: see Archer below
		seq("BowShove", "BOW SHOVE", 2, 0, "Any", { hit("Shove", 0.6, 0.6, { Arc = 80, Knockback = 20 }) }),
		seq("Stab", "ARROW STAB", 1, 0, "Any", { hit("Thrust", 0.8, 1, { Arc = 45 }) }),
	},
}

local ZombieAttackDefinitions = {
	ByZombie = ByZombie,
	MaxRepeats = 2, -- never the same sequence more than twice in a row
	HeavySpacing = 1.1, -- seconds between heavy steps of different zombies on one player
	StepGap = 0.12, -- seconds between steps
	OutOfReachAbort = 4, -- a sequence stops when the target is this far beyond the reach
	-- Undead Sagittarius shots and sequences (ZombieArcherAI)
	Archer = table.freeze({
		Shots = table.freeze({
			Normal = table.freeze({ Draw = 1, Damage = 1, Error = 1 }),
			Quick = table.freeze({ Draw = 0.55, Damage = 0.75, Error = 1.8 }),
			Aimed = table.freeze({ Draw = 1.9, Damage = 1.7, Error = 0.35 }),
		}),
		Sequences = table.freeze({
			table.freeze({ Id = "Single", Shots = { "Normal" }, Weight = 3 }),
			table.freeze({ Id = "DoubleShot", Shots = { "Normal", "Quick" }, Weight = 2, Reposition = 1.2 }),
			table.freeze({ Id = "AimedShot", Shots = { "Aimed" }, Weight = 1.2, Recovery = 1.0, MinDistance = 45 }),
		}),
		MaxAimedPerTarget = 1, -- never several archers aiming an Aimed Shot at one player at once
	}),
}

function ZombieAttackDefinitions.forZombie(id: string): { Sequence }
	return ByZombie[id] or ByZombie.LegionRemnant
end

return table.freeze(ZombieAttackDefinitions)
