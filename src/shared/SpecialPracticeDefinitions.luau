--!strict
-- Special practice: every weapon/move pair has its own mastery progress (steps), shared moves
-- train independently per weapon. Every execution rolls the outcome with the current odds
-- (Fail, Perfect, Normal) and then counts one step, as long as the daily allowance of the place
-- lasts: 5 points a day in the training yard, 15 points a day in the arena (1 point = 1 %).
--   Fail     starts at 25 % and falls 0.15 points per step down to 5 %
--   Perfect  starts at 1 % and rises 0.25 points per step up to 75 %
-- Perfect executions deal more damage and impact (PerfectDamage / PerfectImpact).
-- Six mastery stages follow the Perfect chance; each stage unlocks its attacks (Stages.Unlocks).
local Practice = {
	StartFail = 0.25,
	MinFail = 0.05,
	FailStep = 0.0015,
	StartPerfect = 0.01,
	MaxPerfect = 0.75,
	PerfectStep = 0.0025,
	DailyAllowance = { Training = 0.05, Arena = 0.15 },
	PerfectDamage = 1.25,
	PerfectImpact = 1.25,
	FallSeconds = 1.1,
	UpLevel = 5,
	CircleLevel = 9,
}

-- Steps until the Perfect chance reaches its ceiling (also the cap of stored progress).
Practice.MaxSteps = math.floor((Practice.MaxPerfect - Practice.StartPerfect) / Practice.PerfectStep + 1e-9)

-- Mastery stages by Perfect chance (the first one starts at 1 %). Unlocks: attack ids that a
-- stage makes available for this weapon; empty until the attacks are designed.
Practice.Stages = table.freeze({
	{ Name = "Ungeübt", Perfect = 0.01, Unlocks = table.freeze({}) :: { string } },
	{ Name = "Geübt", Perfect = 0.15, Unlocks = table.freeze({}) :: { string } },
	{ Name = "Erfahren", Perfect = 0.30, Unlocks = table.freeze({}) :: { string } },
	{ Name = "Sicher", Perfect = 0.45, Unlocks = table.freeze({}) :: { string } },
	{ Name = "Virtuos", Perfect = 0.60, Unlocks = table.freeze({}) :: { string } },
	{ Name = "Meister", Perfect = 0.75, Unlocks = table.freeze({}) :: { string } },
})

-- Saved progress is keyed by weapon AND move.
function Practice.key(weaponId: string, moveId: string): string
	return weaponId .. ":" .. moveId
end

-- Player attribute holding a key's steps (attribute names allow only letters, digits and _).
function Practice.attribute(key: string): string
	return "SpecialAttempts_" .. (key:gsub(":", "_"))
end

-- Clamps saved progress to the valid step range.
function Practice.clampSteps(steps: number): number
	return math.clamp(math.floor(steps), 0, Practice.MaxSteps)
end

function Practice.failure(steps: number): number
	return math.max(Practice.MinFail, Practice.StartFail - Practice.clampSteps(steps) * Practice.FailStep)
end

function Practice.perfect(steps: number): number
	return math.min(Practice.MaxPerfect, Practice.StartPerfect + Practice.clampSteps(steps) * Practice.PerfectStep)
end

-- Index (1..6) of the mastery stage reached with these steps.
function Practice.stage(steps: number): number
	local perfect = Practice.perfect(steps)
	local index = 1
	for i, stage in Practice.Stages do
		if perfect + 1e-9 >= stage.Perfect then
			index = i
		end
	end
	return index
end

-- Outcome of one execution for a roll in [0, 1): Fail, Perfect or Normal.
function Practice.outcome(failure: number, perfect: number, roll: number): string
	if roll < failure then return "Fail" end
	if roll < failure + perfect then return "Perfect" end
	return "Normal"
end

-- Text for menus and the HUD: stage, Fail and Perfect chances of the saved progress.
function Practice.describe(steps: number): string
	local index = Practice.stage(steps)
	return ("%s %d/%d · Fehl %.1f%% · Perfekt %.2f%%"):format(Practice.Stages[index].Name, index, #Practice.Stages, Practice.failure(steps) * 100, Practice.perfect(steps) * 100)
end

function Practice.label(player: Player, weaponId: string, moveId: string): string
	local steps = tonumber(player:GetAttribute(Practice.attribute(Practice.key(weaponId, moveId)))) or 0
	return Practice.describe(steps)
end

-- Ultimate takes priority. Locked context variants fall back to the ordinary charge tier.
function Practice.family(base: string, ultimate: boolean, airborne: boolean, blocking: boolean, level: number): string
	if ultimate then return "Ultimate" end
	if airborne and level >= Practice.UpLevel then return "Up" end
	if blocking and level >= Practice.CircleLevel then return "Circle" end
	return base
end

return table.freeze(Practice)
