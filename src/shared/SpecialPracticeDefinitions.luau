--!strict
-- Special practice: every weapon/move pair has its own mastery progress (steps), shared moves
-- train independently per weapon. Every execution rolls the outcome with the current odds
-- (Fail, Perfect, Normal) and then counts one step, as long as the daily allowance of the place
-- lasts: 5 points a day in the training yard, 15 points a day in the arena (1 point = 1 %).
--   Fail     starts at 25 % and falls 0.15 points per step down to 5 %
--   Perfect  starts at 1 % and rises 0.25 points per step up to 75 %
-- Perfect executions deal more damage and impact (PerfectDamage / PerfectImpact).
-- Six mastery stages follow the Perfect chance. A weapon's stage is the highest stage reached by
-- any of its moves; each stage unlocks attacks for that weapon (Stages.Unlocks).
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
}

-- Steps until the Perfect chance reaches its ceiling (also the cap of stored progress).
Practice.MaxSteps = math.floor((Practice.MaxPerfect - Practice.StartPerfect) / Practice.PerfectStep + 1e-9)

-- Mastery stages by Perfect chance (the first one starts at 1 %). Unlocks: the attack families
-- (or the parry counter) that a weapon gains when it reaches the stage. Left and Right are always
-- available.
Practice.Stages = table.freeze({
	{ Name = "Ungeübt", Perfect = 0.01, Unlocks = table.freeze({}) :: { string } },
	{ Name = "Geübt", Perfect = 0.15, Unlocks = table.freeze({ "Up" }) :: { string } },
	{ Name = "Erfahren", Perfect = 0.30, Unlocks = table.freeze({ "Down" }) :: { string } },
	{ Name = "Sicher", Perfect = 0.45, Unlocks = table.freeze({ "Circle" }) :: { string } },
	{ Name = "Virtuos", Perfect = 0.60, Unlocks = table.freeze({ "Counter" }) :: { string } },
	{ Name = "Meister", Perfect = 0.75, Unlocks = table.freeze({ "Ultimate" }) :: { string } },
})

-- Saved progress is keyed by weapon AND move.
function Practice.key(weaponId: string, moveId: string): string
	return weaponId .. ":" .. moveId
end

-- Player attribute holding a key's steps (attribute names allow only letters, digits and _).
function Practice.attribute(key: string): string
	return "SpecialAttempts_" .. (key:gsub(":", "_"))
end

-- Prefix of the attributes of every move of one weapon.
function Practice.attributePrefix(weaponId: string): string
	return "SpecialAttempts_" .. weaponId .. "_"
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

-- Stage of a weapon: the highest stage reached by any of its moves (given their steps).
function Practice.weaponStage(stepsOfMoves: { number }): number
	local index = 1
	for _, steps in stepsOfMoves do
		index = math.max(index, Practice.stage(steps))
	end
	return index
end

-- Whether a weapon at this stage has the attack family (or "Counter") unlocked.
function Practice.unlocked(stage: number, family: string): boolean
	if family == "Left" or family == "Right" then return true end
	for i = 1, math.min(stage, #Practice.Stages) do
		if table.find(Practice.Stages[i].Unlocks, family) then return true end
	end
	return false
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

-- The attack family for a charge at this weapon stage. Ultimate takes priority, then the air
-- and block variants. A locked family falls back to the charge tier's own family, and a locked
-- Down falls back to Left.
function Practice.family(base: string, ultimate: boolean, airborne: boolean, blocking: boolean, stage: number): string
	if ultimate and Practice.unlocked(stage, "Ultimate") then return "Ultimate" end
	if airborne and Practice.unlocked(stage, "Up") then return "Up" end
	if blocking and Practice.unlocked(stage, "Circle") then return "Circle" end
	if Practice.unlocked(stage, base) then return base end
	return "Left"
end

return table.freeze(Practice)
