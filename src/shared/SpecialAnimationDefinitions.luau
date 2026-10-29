--!strict
-- The body choreography of every special move (PlayerAnimator plays it; display only).
-- One TRACK per "<Prefix>:<MoveId>" for every weapon/family assignment in WeaponSpecialDefinitions.
-- A track is a list of keys { t, p, s }: t = seconds from the special's start, p = a key pose,
-- s = whole-body spin in degrees (cumulative; a key without s keeps the previous spin, every track
-- ends on a whole turn). Key times are written against the server's timing (wind-up end, the n-th hit
-- = WindUp + Hits[n].Delay, duration) so a weapon's tempo never desynchronises them.
-- Aerial tracks: Keys run from the release (gather, jump, air pose: the last key is held until the
-- real landing), Land runs from SpecialLandingStart (impact, recovery).
-- Key pose fields (degrees; all optional): w waist, rs / ls shoulders, rh / lh hips (x = pitch,
-- y = twist, z = roll), c crouch (studs), re / le elbow bend, rw / lw wrists. Right hand = weapon (and
-- the bow), left hand = shield or the second dagger. The weapon stays in the hand: every line of the
-- blade comes from shoulder + elbow + wrist.

local Specials = require(script.Parent.WeaponSpecialDefinitions)
local Moves = require(script.Parent.SpecialMoveDefinitions)

export type KeyPose = {
	w: Vector3?, rs: Vector3?, ls: Vector3?, rh: Vector3?, lh: Vector3?,
	c: number?, re: number?, le: number?, rw: Vector3?, lw: Vector3?,
}
export type Key = { t: number, p: KeyPose, s: number? }
export type Track = {
	Style: string, -- "Sword" | "Heavy" | "Spear" | "Daggers" | "Bow"
	Keys: { Key },
	Land: { Key }?, -- aerial moves only
	Length: number, -- time of the last key
	Aerial: boolean,
	Bow: boolean,
	Hits: { number }, -- server hit times (seconds from the start), for tests and tuning
}

type Timing = { wind: number, dur: number, hit: (index: number) -> number }
type Choreo = (T: Timing, style: string) -> ({ Key }, { Key }?)

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function k(t: number, p: KeyPose, s: number?): Key
	return { t = t, p = p, s = s }
end

-- A copy of `base` with some fields replaced
local function with(base: KeyPose, o: KeyPose): KeyPose
	local p = table.clone(base)
	for key, value in o :: any do
		(p :: any)[key] = value
	end
	return p
end

-- Daggers: the left hand copies the right hand's line, mirrored
local function both(p: KeyPose): KeyPose
	local rs, rw = p.rs or v(0, 0, 0), p.rw or v(0, 0, 0)
	return with(p, { ls = v(rs.X, -rs.Y, -rs.Z), le = p.re, lw = v(rw.X, -rw.Y, -rw.Z) })
end

-- Heavier weapons: deeper knees, more hips in the turn
local function heavy(p: KeyPose): KeyPose
	local w = p.w or v(0, 0, 0)
	return with(p, { w = v(w.X, w.Y * 1.2, w.Z), c = (p.c or 0) + 0.15 })
end

------------------------------------------------------------------------------------------
-- Pose library (sword arm right, shield arm left)
------------------------------------------------------------------------------------------

local P = {
	READY = { w = v(-4, 6, 0), rs = v(30, 0, 18), re = 55, rw = v(-50, 0, 0), ls = v(55, -10, -15), le = 55, rh = v(-6, 0, 0), lh = v(12, 0, 0), c = 0.2 } :: KeyPose,
	COUNTER = { w = v(-10, 12, 0), rs = v(35, 0, 22), re = 70, rw = v(-45, 0, 0), ls = v(95, -12, -20), le = 40, rh = v(-8, 0, 0), lh = v(22, 0, 0), c = 0.5 } :: KeyPose,
	LOW_WIND = { w = v(-10, -32, 0), rs = v(65, 0, 50), re = 30, rw = v(-55, 0, 0), ls = v(60, 0, -15), le = 50, rh = v(-10, 0, 0), lh = v(25, 0, 0), c = 0.5 } :: KeyPose,
	LOW_CUT = { w = v(-22, 36, 0), rs = v(22, 0, -55), re = 10, rw = v(-75, 0, 0), ls = v(45, 0, -20), le = 45, rh = v(-12, 0, 0), lh = v(32, 0, 0), c = 0.6 } :: KeyPose,
	LR_WIND = { w = v(6, 34, 6), rs = v(150, 0, -40), re = 85, rw = v(-10, 0, 0), ls = v(30, 0, -30), le = 70, rh = v(16, 0, 0), lh = v(-10, 0, 0), c = 0.1 } :: KeyPose,
	LR_HIT = { w = v(-12, -34, -8), rs = v(50, 0, 50), re = 10, rw = v(-65, 0, 0), ls = v(35, 0, -15), le = 45, rh = v(-14, 0, 0), lh = v(24, 0, 0), c = 0.28 } :: KeyPose,
	RL_WIND = { w = v(6, -32, -6), rs = v(165, 0, 35), re = 70, rw = v(-10, 0, 0), ls = v(35, 0, -20), le = 50, rh = v(-12, 0, 0), lh = v(18, 0, 0), c = 0.1 } :: KeyPose,
	RL_HIT = { w = v(-14, 34, 8), rs = v(55, 0, -45), re = 10, rw = v(-70, 0, 0), ls = v(25, 0, -10), le = 40, rh = v(20, 0, 0), lh = v(-15, 0, 0), c = 0.28 } :: KeyPose,
	OVER_WIND = { w = v(12, 0, 0), rs = v(168, 0, 8), re = 78, rw = v(-10, 0, 0), ls = v(45, 0, -15), le = 60, rh = v(-12, 0, 0), lh = v(18, 0, 0), c = 0.05 } :: KeyPose,
	OVER_HIT = { w = v(-28, 0, 0), rs = v(45, 0, -4), re = 5, rw = v(-72, 0, 0), ls = v(25, 0, -20), le = 40, rh = v(-24, 0, 0), lh = v(36, 0, 0), c = 0.45 } :: KeyPose,
	SMASH = { w = v(-36, 0, 0), rs = v(28, 0, -4), re = 5, rw = v(-85, 0, 0), ls = v(20, 0, -25), le = 35, rh = v(-24, 0, 0), lh = v(48, 0, 0), c = 0.9 } :: KeyPose,
	THRUST_WIND = { w = v(6, -28, 0), rs = v(-25, 0, 12), re = 100, rw = v(-80, 0, 0), ls = v(45, 0, -15), le = 55, rh = v(-10, 0, 0), lh = v(20, 0, 0), c = 0.2 } :: KeyPose,
	LUNGE = { w = v(-20, 26, 0), rs = v(84, 0, 2), re = 0, rw = v(-92, 0, 0), ls = v(20, 0, -30), le = 45, rh = v(-40, 0, 0), lh = v(55, 0, 0), c = 0.55 } :: KeyPose,
	SPIN_ARM = { w = v(-6, 0, 0), rs = v(85, 0, 62), re = 8, rw = v(-72, 0, 0), ls = v(45, 0, 10), le = 95, rh = v(-8, 0, 0), lh = v(18, 0, 0), c = 0.35 } :: KeyPose,
	SHIELD_SLAM = { w = v(-12, -26, 0), rs = v(20, 0, 22), re = 60, rw = v(-50, 0, 0), ls = v(92, 8, -8), le = 8, rh = v(-22, 0, 0), lh = v(38, 0, 0), c = 0.35 } :: KeyPose,
	CLEAVE_WIND = { w = v(6, -55, -4), rs = v(85, 0, 80), re = 25, rw = v(-70, 0, 0), ls = v(40, 0, -22), le = 55, rh = v(12, 0, 0), lh = v(-6, 0, 0), c = 0.25 } :: KeyPose,
	CLEAVE_HIT = { w = v(-10, 50, 6), rs = v(80, 0, -60), re = 10, rw = v(-75, 0, 0), ls = v(30, 0, -15), le = 45, rh = v(16, 0, 0), lh = v(-12, 0, 0), c = 0.35 } :: KeyPose,
	CLEAVE_FOLLOW = { w = v(-12, 70, 8), rs = v(70, 0, -85), re = 15, rw = v(-78, 0, 0), ls = v(30, 0, -15), le = 45, rh = v(18, 0, 0), lh = v(-14, 0, 0), c = 0.38 } :: KeyPose,
	TOES = { w = v(16, 0, 0), rs = v(176, 0, 5), re = 82, rw = v(-10, 0, 0), ls = v(60, 0, -12), le = 55, rh = v(-4, 0, 0), lh = v(-4, 0, 0), c = 0 } :: KeyPose,
	SPEAR_WIND = { w = v(4, -30, 0), rs = v(-10, 0, 8), re = 95, rw = v(-85, 0, 0), ls = v(55, 0, -15), le = 55, rh = v(-12, 0, 0), lh = v(22, 0, 0), c = 0.3 } :: KeyPose,
	SPEAR_HIT = { w = v(-16, 24, 0), rs = v(72, 0, 0), re = 0, rw = v(-72, 0, 0), ls = v(35, 0, -25), le = 50, rh = v(-24, 0, 0), lh = v(36, 0, 0), c = 0.35 } :: KeyPose,
	SPEAR_LUNGE = { w = v(-24, 30, 0), rs = v(86, 0, 0), re = 0, rw = v(-72, 0, 0), ls = v(25, 0, -30), le = 45, rh = v(-45, 0, 0), lh = v(60, 0, 0), c = 0.62 } :: KeyPose,
	GATHER = { w = v(14, 0, 0), rs = v(40, 0, 25), re = 60, rw = v(-50, 0, 0), ls = v(40, 0, -18), le = 60, rh = v(32, 0, 0), lh = v(32, 0, 0), c = 0.75 } :: KeyPose,
	LIFTOFF = { w = v(-6, 0, 0), rs = v(150, 0, 15), re = 40, rw = v(-20, 0, 0), ls = v(80, 0, -20), le = 30, rh = v(-12, 0, 0), lh = v(14, 0, 0), c = 0 } :: KeyPose,
	TUCK = { w = v(10, 0, 0), rs = v(168, 0, 8), re = 78, rw = v(-10, 0, 0), ls = v(50, 0, -20), le = 55, rh = v(58, 0, 0), lh = v(48, 0, 0), c = 0.1 } :: KeyPose,
	LAND_GUARD = { w = v(-10, 8, 0), rs = v(35, 0, 20), re = 55, rw = v(-50, 0, 0), ls = v(85, -12, -18), le = 45, rh = v(-14, 0, 0), lh = v(34, 0, 0), c = 0.6 } :: KeyPose,
	-- Bow in the right hand: the right arm aims, the left hand draws to the cheek
	BOW_READY = { w = v(2, -20, 0), rs = v(70, 0, 12), re = 15, rw = v(0, 0, -12), ls = v(60, -30, -15), le = 70, rh = v(-8, 0, 0), lh = v(12, 0, 0), c = 0.1 } :: KeyPose,
	BOW_DRAW = { w = v(2, -26, 0), rs = v(84, 0, 12), re = 6, rw = v(0, 0, -12), ls = v(80, -40, -18), le = 115, lw = v(-15, 0, 0), rh = v(-8, 0, 0), lh = v(14, 0, 0), c = 0.15 } :: KeyPose,
	BOW_RELEASE = { w = v(-2, -18, 0), rs = v(84, 0, 10), re = 8, rw = v(-5, 0, -12), ls = v(55, -65, -38), le = 40, rh = v(-8, 0, 0), lh = v(14, 0, 0), c = 0.12 } :: KeyPose,
	BOW_SKY = { w = v(14, -20, 0), rs = v(140, 0, 8), re = 6, rw = v(0, 0, -10), ls = v(118, -30, -16), le = 112, rh = v(-6, 0, 0), lh = v(12, 0, 0), c = 0.15 } :: KeyPose,
	BOW_SKY_RELEASE = { w = v(10, -16, 0), rs = v(140, 0, 10), re = 8, rw = v(-5, 0, -10), ls = v(95, -50, -30), le = 40, rh = v(-6, 0, 0), lh = v(12, 0, 0), c = 0.12 } :: KeyPose,
}

-- The same idea for each weapon style
local function cleaveWind(style: string): KeyPose
	if style == "Spear" then return with(P.CLEAVE_WIND, { rs = v(40, 0, 75), re = 30, rw = v(-60, 0, 0), c = 0.4 }) end
	if style == "Daggers" then return both(with(P.CLEAVE_WIND, { w = v(-4, 0, 0), rs = v(80, 0, -40), re = 40 })) end
	if style == "Heavy" then return heavy(with(P.CLEAVE_WIND, { w = v(8, -70, -6) })) end
	return P.CLEAVE_WIND
end
local function cleaveHit(style: string): KeyPose
	if style == "Spear" then return with(P.CLEAVE_HIT, { rs = v(40, 0, -70), re = 15, rw = v(-60, 0, 0), c = 0.45 }) end
	if style == "Daggers" then return both(with(P.CLEAVE_HIT, { w = v(-10, 0, 0), rs = v(80, 0, 75), re = 5 })) end
	if style == "Heavy" then return heavy(P.CLEAVE_HIT) end
	return P.CLEAVE_HIT
end
local function spinArm(style: string): KeyPose
	if style == "Daggers" then return both(P.SPIN_ARM) end
	if style == "Spear" then return with(P.SPIN_ARM, { rs = v(78, 0, 48), rw = v(-60, 0, 0) }) end
	if style == "Heavy" then return heavy(with(P.SPIN_ARM, { rs = v(92, 0, 80) })) end
	return P.SPIN_ARM
end
local function raised(style: string): KeyPose
	if style == "Daggers" then return both(with(P.OVER_WIND, { re = 60, rs = v(160, 0, 15) })) end
	if style == "Spear" then return with(P.OVER_WIND, { rs = v(170, 0, 0), re = 100, rw = v(0, 0, 0) }) end -- point down, ready to drive
	if style == "Heavy" then return heavy(P.OVER_WIND) end
	return P.OVER_WIND
end
local function slam(style: string): KeyPose
	if style == "Daggers" then return both(with(P.SMASH, { rs = v(40, 0, -10), re = 0, rw = v(-90, 0, 0) })) end
	if style == "Spear" then return with(P.SMASH, { rs = v(30, 0, 0), re = 0, rw = v(-90, 0, 0) }) end -- point driven down
	if style == "Heavy" then return with(P.SMASH, { c = 1 }) end
	return P.SMASH
end

------------------------------------------------------------------------------------------
-- Choreographies (by move id, or by generated slot for shared moves)
------------------------------------------------------------------------------------------

local CHOREO: { [string]: Choreo } = {}

-- Rusty Gladius I: counter stance -> low cut -> rising cut from the upper left -> full shoulder turn -> lunge
CHOREO.RebellionCombo = function(T)
	return {
		k(T.wind, P.COUNTER, 0),
		k(T.hit(1) - 0.1, P.LOW_WIND),
		k(T.hit(1) + 0.03, P.LOW_CUT),
		k(T.hit(2) - 0.09, P.LR_WIND),
		k(T.hit(2) + 0.03, P.LR_HIT, 0),
		k(T.hit(3) + 0.12, P.SPIN_ARM, 360),
		k(T.hit(4) - 0.06, P.THRUST_WIND),
		k(T.hit(4) + 0.05, P.LUNGE),
		k(T.dur - 0.05, P.LUNGE),
	}
end

-- Legion Sword I: cut from the upper right -> shield slam -> spin cut -> lunge
CHOREO.LegionsFury = function(T)
	return {
		k(T.wind * 0.8, P.RL_WIND, 0),
		k(T.hit(1) + 0.04, P.RL_HIT),
		k(T.hit(2) - 0.05, P.SHIELD_SLAM),
		k(T.hit(2) + 0.08, P.SHIELD_SLAM, 0),
		k(T.hit(3) + 0.14, P.SPIN_ARM, 360),
		k(T.hit(4) - 0.08, P.THRUST_WIND),
		k(T.hit(4) + 0.05, P.LUNGE),
		k(T.dur - 0.05, P.LUNGE),
	}
end

-- Morning Star I: heavy right-to-left swing -> backhand -> shove with the mace head
CHOREO.SpecCombination = function(T, style)
	local shove = heavy(with(P.LUNGE, { rs = v(80, 0, 0), rw = v(-60, 0, 0), c = 0.4 }))
	return {
		k(0, heavy(P.RL_WIND)),
		k(T.hit(1) + 0.05, heavy(P.RL_HIT)),
		k(T.hit(2) - 0.12, heavy(P.LR_WIND)),
		k(T.hit(2) + 0.05, heavy(P.LR_HIT)),
		k(T.hit(3) - 0.14, heavy(P.THRUST_WIND)),
		k(T.hit(3) + 0.05, shove),
		k(T.dur - 0.08, shove),
	}
end

-- Trident I: low guard -> two quick thrusts -> low spinning sweep -> long lunge
CHOREO.RetiariusFury = function(T)
	local lowSweep = with(P.SPIN_ARM, { rs = v(55, 0, 60), rw = v(-65, 0, 0), c = 0.68, w = v(-14, 0, 0) })
	return {
		k(T.wind, P.SPEAR_WIND, 0),
		k(T.hit(1) - 0.07, P.SPEAR_WIND),
		k(T.hit(1) + 0.03, P.SPEAR_HIT),
		k(T.hit(2) - 0.08, P.SPEAR_WIND),
		k(T.hit(2) + 0.03, P.SPEAR_HIT, 0),
		k(T.hit(3) + 0.14, lowSweep, 360),
		k(T.hit(4) - 0.08, P.SPEAR_WIND),
		k(T.hit(4) + 0.04, P.SPEAR_LUNGE),
		k(T.dur - 0.05, P.SPEAR_LUNGE),
	}
end

-- Hoplite I: weight far back, spear drawn back at shoulder height -> explosive lunge
CHOREO.PhalanxBreaker = function(T)
	local gather = { w = v(6, -42, 0), rs = v(55, 0, 22), re = 112, rw = v(-60, 0, 0), ls = v(72, -10, -15), le = 55, rh = v(16, 0, 0), lh = v(-4, 0, 0), c = 0.38 } :: KeyPose
	return {
		k(T.wind * 0.85, gather),
		k(T.hit(1) + 0.05, with(P.SPEAR_LUNGE, { w = v(-26, 32, 0), c = 0.66 })),
		k(T.dur * 0.6, P.SPEAR_LUNGE),
	}
end

-- Twin Daggers I: cut -> evasive spin backwards -> right / left / right stabs -> spin with both blades out
CHOREO.ViperDance = function(T)
	local stabR = { w = v(-10, 22, 0), rs = v(85, 0, 5), re = 0, rw = v(-90, 0, 0), ls = v(40, 0, -10), le = 100, rh = v(-18, 0, 0), lh = v(28, 0, 0), c = 0.35 } :: KeyPose
	local stabL = { w = v(-10, -22, 0), ls = v(85, 0, -5), le = 0, lw = v(-90, 0, 0), rs = v(40, 0, 10), re = 100, rw = v(-60, 0, 0), rh = v(28, 0, 0), lh = v(-18, 0, 0), c = 0.35 } :: KeyPose
	return {
		k(0, both(with(P.READY, { ls = v(30, 0, -18) })), 0),
		k(T.hit(1) + 0.05, with(P.RL_HIT, { ls = v(40, 0, -10), le = 90 })),
		k(T.hit(2) - 0.06, both(P.READY), 0),
		k(T.hit(2) + 0.14, both(with(P.READY, { c = 0.55 })), 360),
		k(T.hit(3) - 0.04, stabR),
		k(T.hit(4) - 0.04, stabL),
		k(T.hit(5) - 0.04, stabR),
		k(T.hit(6) - 0.12, both(P.SPIN_ARM), 360),
		k(T.hit(6) + 0.12, both(P.SPIN_ARM), 720),
		k(T.dur - 0.02, both(P.READY)),
	}
end

-- Battle Axe I: guard -> hook from the left -> body spin -> overhead -> blow into the ground
CHOREO.ColosseumBreaker = function(T)
	return {
		k(T.wind, heavy(P.READY), 0),
		k(T.hit(1) - 0.1, heavy(with(P.LR_WIND, { rs = v(95, 0, -70), re = 50 }))),
		k(T.hit(1) + 0.04, heavy(P.LR_HIT), 0),
		k(T.hit(2) + 0.12, spinArm("Heavy"), 360),
		k(T.hit(3) - 0.12, heavy(P.OVER_WIND)),
		k(T.hit(3) + 0.04, heavy(P.OVER_HIT)),
		k(T.hit(4) - 0.14, heavy(with(P.OVER_WIND, { rs = v(130, 0, 6), re = 55 }))),
		k(T.hit(4) + 0.04, slam("Heavy")),
		k(T.dur - 0.05, slam("Heavy")),
	}
end

-- Morning Star II: swing -> backhand -> spin with the arm stretched -> overhead into the sand
CHOREO.ChainTempest = function(T)
	return {
		k(0, heavy(P.RL_WIND), 0),
		k(T.hit(1) + 0.05, heavy(P.RL_HIT)),
		k(T.hit(2) - 0.1, heavy(P.LR_WIND)),
		k(T.hit(2) + 0.05, heavy(P.LR_HIT), 0),
		k(T.hit(3) + 0.12, spinArm("Heavy"), 360),
		k(T.hit(4) - 0.13, heavy(P.OVER_WIND)),
		k(T.hit(4) + 0.04, slam("Heavy")),
		k(T.dur - 0.05, slam("Heavy")),
	}
end

-- GLADIATOR CLEAVE (tier II of six weapons): wide flat sweep right to left
CHOREO.SpecCleave = function(T, style)
	local follow = if style == "Daggers" then both(with(P.CLEAVE_FOLLOW, { rs = v(70, 0, 88), w = v(-12, 0, 0) })) else P.CLEAVE_FOLLOW
	return {
		k(T.wind * 0.85, cleaveWind(style)),
		k(T.hit(1) + 0.04, cleaveHit(style)),
		k(T.hit(1) + 0.2, follow),
		k(T.dur - 0.08, follow),
	}
end

-- HEAVY DESCENT (tier III of five weapons): up on the toes -> slam down into a deep crouch
CHOREO.SpecHeavy = function(T, style)
	return {
		k(T.wind * 0.55, raised(style)),
		k(T.wind - 0.02, with(raised(style), { w = v(16, 0, 0), c = 0, rh = v(-4, 0, 0), lh = v(-4, 0, 0) })),
		k(T.hit(1) + 0.06, slam(style)),
		k(T.hit(1) + 0.4, slam(style)),
		k(T.dur - 0.05, with(slam(style), { c = 0.4, w = v(-14, 0, 0) })),
	}
end

-- ARENA SPIN (Circle of every melee weapon): two full turns, weapon arm out, knees bent
CHOREO.U_ArenaSpin = function(T, style)
	local arm = spinArm(style)
	return {
		k(T.wind * 0.5, arm, 0),
		k(T.hit(2) - 0.06, arm, 360),
		k(T.hit(2) + 0.3, arm, 720),
		k(T.dur - 0.05, with(arm, { c = 0.2 })),
	}
end

------------------------------------------------------------------------------------------
-- Aerial choreographies (Keys from the release, Land from the real landing)
------------------------------------------------------------------------------------------

-- Ground release: gather, jump (the server hops 0.28 s after the wind-up), then the air pose
local function jumpKeys(T: Timing, gather: KeyPose, air: KeyPose, spin: boolean): { Key }
	local keys = {
		k(T.wind, gather, 0),
		k(T.wind + 0.12, P.LIFTOFF),
		k(T.wind + 0.26, air, 0),
	}
	if spin then
		table.insert(keys, k(T.wind + 0.56, air, 360))
	end
	return keys
end

local function landKeys(impact: KeyPose, after: KeyPose): { Key }
	return { k(0.06, impact), k(0.32, impact), k(0.62, after) }
end

-- RISING ATTACK (Up): cut from low left to high right in the air, land in a guard
CHOREO.U_Rising = function(T, style)
	local low = with(P.LOW_CUT, { rh = v(40, 0, 0), lh = v(30, 0, 0), c = 0.1 })
	local high = with(P.RL_WIND, { w = v(8, -30, 0), rs = v(165, 0, 30), re = 15, rw = v(-25, 0, 0), rh = v(40, 0, 0), lh = v(25, 0, 0), c = 0 })
	local keys = { k(0, low, 0), k(T.wind + 0.08, if style == "Heavy" then heavy(high) else high), k(T.wind + 0.28, with(P.LAND_GUARD, { rh = v(30, 0, 0), lh = v(20, 0, 0), c = 0 })) }
	return keys, landKeys(P.LAND_GUARD, P.READY)
end

-- Legion Up: arms spread like wings -> sword over the head -> land with a downward cut
CHOREO.EagleOfRome = function(T)
	local wings = { w = v(12, 0, 0), rs = v(90, 0, 85), re = 5, rw = v(-60, 0, 0), ls = v(90, 0, -85), le = 5, rh = v(35, 0, 0), lh = v(25, 0, 0), c = 0 } :: KeyPose
	return { k(0, wings, 0), k(T.wind + 0.12, wings), k(T.wind + 0.3, P.TUCK) }, landKeys(P.OVER_HIT, P.READY)
end

-- Trident Up: trident pulled back -> dive point first, body stretched -> land on a lunge
CHOREO.SeaEagleDive = function(T)
	local dive = { w = v(-30, 0, 0), rs = v(60, 0, 0), re = 0, rw = v(-90, 0, 0), ls = v(60, 0, -30), le = 40, rh = v(-20, 0, 0), lh = v(-8, 0, 0), c = 0 } :: KeyPose
	return { k(0, with(P.SPEAR_WIND, { rh = v(45, 0, 0), lh = v(40, 0, 0), c = 0 }), 0), k(T.wind + 0.15, dive) }, landKeys(P.SPEAR_LUNGE, P.READY)
end

-- Hoplite Up: legs swing up over the planted spear -> point straight down -> land on the thrust
CHOREO.SpartanVault = function(T)
	local vault = { w = v(-12, 0, 0), rs = v(20, 0, 8), re = 0, rw = v(-90, 0, 0), ls = v(60, 0, -20), le = 50, rh = v(72, 0, 0), lh = v(80, 0, 0), c = 0 } :: KeyPose
	local down = with(vault, { rs = v(18, 0, 0), rw = v(-95, 0, 0), rh = v(38, 0, 0), lh = v(40, 0, 0) })
	return { k(0, vault, 0), k(T.wind + 0.18, down) }, landKeys(P.SPEAR_LUNGE, P.READY)
end

-- Daggers Up: a full spin in the air, blades out -> land low, blades crossed
CHOREO.RiverShadow = function(T)
	local out = both(with(P.SPIN_ARM, { rh = v(45, 0, 0), lh = v(40, 0, 0), c = 0 }))
	local crossed = both(with(P.LOW_CUT, { rs = v(70, 0, -30), re = 30, rw = v(-60, 0, 0) }))
	return { k(0, out, 0), k(0.36, out, 360), k(T.wind + 0.45, with(crossed, { c = 0, rh = v(35, 0, 0), lh = v(30, 0, 0) })) }, landKeys(with(crossed, { c = 0.85 }), both(P.READY))
end

-- Morning Star III: jump, the mace whirls above the head -> two-handed-weight slam on landing
CHOREO.FallingMeteor = function(T)
	local whirlA = heavy(with(P.TUCK, { rs = v(170, 0, 40), re = 10, rw = v(-30, 0, 0) }))
	local whirlB = heavy(with(P.TUCK, { rs = v(165, 0, -30), re = 10, rw = v(-30, 0, 0) }))
	local keys = jumpKeys(T, heavy(P.GATHER), whirlA, false)
	table.insert(keys, k(T.wind + 0.38, whirlB))
	table.insert(keys, k(T.wind + 0.5, whirlA))
	table.insert(keys, k(T.wind + 0.62, heavy(P.TUCK)))
	return keys, landKeys(slam("Heavy"), heavy(P.READY))
end

-- Battle Axe III: jump, axe high behind the head, legs tucked -> massive blow on landing
CHOREO.ThunderOfMars = function(T)
	return jumpKeys(T, heavy(P.GATHER), heavy(P.TUCK), false), landKeys(with(slam("Heavy"), { c = 1.05 }), heavy(P.READY))
end

-- Melee ULTIMATE: deep gather, big jump, a full spin with the weapon high, all-out landing blow
CHOREO.Ultimate = function(T, style)
	local gather = with(P.GATHER, { rs = v(150, 0, 20), re = 60, rw = v(-20, 0, 0) })
	local air = with(raised(style), { rh = v(58, 0, 0), lh = v(48, 0, 0), c = 0.1 })
	if style == "Daggers" then
		gather = both(gather)
	end
	return jumpKeys(T, if style == "Heavy" then heavy(gather) else gather, air, true), landKeys(with(slam(style), { c = 1.05 }), if style == "Daggers" then both(P.READY) else P.READY)
end

------------------------------------------------------------------------------------------
-- Hunter Bow
------------------------------------------------------------------------------------------

-- I: short hop, aim from the air, full draw to the cheek, release
CHOREO.EagleShot = function(T)
	local airDraw = with(P.BOW_DRAW, { rh = v(40, 0, 0), lh = v(30, 0, 0), c = 0 })
	return {
		k(T.wind * 0.6, with(P.BOW_READY, { c = 0.45, rh = v(20, 0, 0), lh = v(20, 0, 0) })),
		k(T.wind + 0.18, airDraw),
		k(T.wind + 0.3, airDraw),
		k(T.wind + 0.36, with(P.BOW_RELEASE, { rh = v(25, 0, 0), lh = v(20, 0, 0) })),
		k(T.dur, P.BOW_RELEASE),
	}
end

-- II: aim left, draw, release while the bow sweeps from left to right
CHOREO.SpecFan = function(T)
	return {
		k(T.wind * 0.5, with(P.BOW_DRAW, { w = v(2, 28, 0) })),
		k(T.wind, with(P.BOW_DRAW, { w = v(2, 18, 0) })),
		k(T.wind + 0.08, with(P.BOW_RELEASE, { w = v(0, -10, 0) })),
		k(T.wind + 0.3, with(P.BOW_RELEASE, { w = v(0, -32, 0) })),
		k(T.dur, P.BOW_READY),
	}
end

-- III: step back, bow steeply to the sky, full draw, release, follow the arrows
CHOREO.ArrowRain = function(T)
	return {
		k(T.wind * 0.7, P.BOW_SKY),
		k(T.wind + 0.04, with(P.BOW_SKY_RELEASE, { rh = v(-16, 0, 0), lh = v(4, 0, 0) })),
		k(T.dur, with(P.BOW_SKY_RELEASE, { w = v(18, -10, 0) })),
	}
end

-- Up (in the air): long, slow full draw, release with a recoil
CHOREO.SpecPierce = function(T)
	local airDraw = with(P.BOW_DRAW, { le = 120, rh = v(40, 0, 0), lh = v(30, 0, 0), c = 0 })
	return {
		k(T.wind * 0.4, with(P.BOW_READY, { rh = v(40, 0, 0), lh = v(30, 0, 0), c = 0 })),
		k(T.wind, airDraw),
		k(T.wind + 0.06, with(P.BOW_RELEASE, { w = v(10, -22, 0), rh = v(30, 0, 0), lh = v(20, 0, 0) })),
		k(T.dur, P.BOW_RELEASE),
	}
end

-- Circle: one full turn with the bow drawn, arrows leave all around
CHOREO.SpecCircle = function(T)
	return {
		k(0.05, P.BOW_DRAW, 0),
		k(T.wind, P.BOW_DRAW),
		k(T.wind + 0.06, P.BOW_RELEASE),
		k(T.dur - 0.25, P.BOW_RELEASE, 360),
		k(T.dur, P.BOW_READY),
	}
end

-- ULTIMATE: kneel, two draws into the sky, rise and loose the last arrow
local KNEEL = { c = 0.85, rh = v(-10, 0, 0), lh = v(72, 0, 0) } :: KeyPose
CHOREO.BowUltimate = function(T)
	return {
		k(T.wind * 0.6, with(P.BOW_SKY, KNEEL)),
		k(T.wind, with(P.BOW_SKY_RELEASE, KNEEL)),
		k(T.wind + 0.25, with(P.BOW_SKY, KNEEL)),
		k(T.wind + 0.4, with(P.BOW_SKY_RELEASE, KNEEL)),
		k(T.wind + 0.7, P.BOW_SKY),
		k(T.wind + 0.85, P.BOW_SKY_RELEASE),
		k(T.dur, P.BOW_READY),
	}
end

------------------------------------------------------------------------------------------
-- Tracks for every weapon / family
------------------------------------------------------------------------------------------

local STYLE: { [string]: string } = {
	Gladius = "Sword", Legion = "Sword", MorningStar = "Heavy", Axe = "Heavy",
	Trident = "Spear", Hoplite = "Spear", Daggers = "Daggers", Bow = "Bow",
}

local function choreoFor(prefix: string, moveId: string): Choreo?
	local slot = moveId:match("^" .. prefix .. "_(.+)$")
	if slot == "Ultimate" and prefix == "Bow" then
		return CHOREO.BowUltimate
	end
	return CHOREO[slot or moveId]
end

local tracks: { [string]: Track } = {}
for prefix, families in Specials.ByPrefix do
	local style = STYLE[prefix] or "Sword"
	for _, moveId in families do
		local move = (Moves :: any)[moveId]
		local choreo = choreoFor(prefix, moveId)
		if not move or not choreo then
			continue
		end
		local hitTimes: { number } = {}
		for i, step in move.Hits or { { Delay = 0 } } do
			hitTimes[i] = move.WindUp + step.Delay
		end
		local timing: Timing = {
			wind = move.WindUp,
			dur = move.Duration,
			hit = function(index: number): number
				return hitTimes[index] or move.WindUp
			end,
		}
		local keys, land = choreo(timing, style)
		table.sort(keys, function(a, b) return a.t < b.t end)
		tracks[prefix .. ":" .. moveId] = table.freeze({
			Style = style,
			Keys = keys,
			Land = land,
			Length = keys[#keys].t,
			Aerial = move.Kind == "Aerial",
			Bow = style == "Bow",
			Hits = hitTimes,
		})
	end
end

return table.freeze(tracks)
