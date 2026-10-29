--!strict
-- One attack executor and skeleton, small species-specific combat profiles.
local Moves = require(script.Parent.OttiMoveDefinitions)
local Personalities = require(script.Parent.CompanionBossDefinitions)
type Move = Moves.OttiMove

local HeroCombatDefinitions = {}
HeroCombatDefinitions.Movement = table.freeze({
	Otti = table.freeze({ Ring = 6.5, Walk = 10, Strafe = 9, Quad = true }),
	Kroko = table.freeze({ Ring = 4.8, Walk = 13, Strafe = 10, Quad = false }),
	Schili = table.freeze({ Ring = 5.2, Walk = 8, Strafe = 6, Quad = false }),
})

function HeroCombatDefinitions.move(hero: string, role: string, phase: number): Move?
	local personality = Personalities.get(hero)
	local def = personality and personality.Roles[role :: any]
	if not def then return nil end
	local baseId = ({ Strike = "GladiusSlash", Charge = "RiverDash", Sweep = "TailSweep", Feint = "GladiatorCombination", Roar = "BattleCry" })[role]
	if not baseId then return nil end
	local move: Move = table.clone(Moves[baseId])
	move.Id = hero .. role
	move.Name = hero .. " · " .. role
	move.WindUp, move.Recovery, move.Cooldown = def.Telegraph, def.Recovery, def.Cooldown
	move.StartRange, move.MinRange = def.MaxRange, def.MinRange
	move.Damage = math.floor((if role == "Charge" then 16 else 15) * def.Damage)
	move.Stance = "Biped"
	move.FollowUp, move.Steps = nil, nil
	local kroko = hero == "Kroko"
	if role == "Strike" then
		move.Pose = if kroko then "Club" else "Staff"
		move.Range = if kroko then 7 else 8
		move.Active = 0.22
		if phase >= 2 and kroko then
			move.Steps = {
				{ Pose = "Club", WindUp = def.Telegraph, Active = 0.2, Damage = 13, Range = 7, ArcDot = 0.3 },
				{ Pose = "Bash", WindUp = 0.55, Active = 0.2, Damage = 11, Range = 6, ArcDot = 0.5 },
			}
		end
	elseif role == "Charge" then
		move.StraightDash = true
		move.Active = if kroko then 0.8 else 1.1
		move.Radius = 3.8
		move.Warning = if kroko then "KROKO STÜRMT — SEITLICH AUSWEICHEN!" else "SCHILI RÜCKT VOR!"
		move.MissRecovery = 0.6
	elseif role == "Sweep" and not kroko then
		-- A tortoise has a short tail. Schili sweeps the staff, never an invisible otter tail.
		move.Kind, move.Pose = "Melee", "StaffSweep"
		move.Range, move.ArcDot, move.Active = 7.5, -0.5, 0.25
		move.MultiTarget, move.Jumpable = true, false
		move.Warning = "STABBOGEN — ABSTAND HALTEN!"
	elseif role == "Sweep" then
		move.Radius, move.SweepDegrees = 10, 300
	elseif role == "Feint" then
		move.Warning = if kroko then "KROKOS DOPPELSCHLAG!" else "SCHILI TÄUSCHT AN — WARTE AUF DEN STAB!"
		move.Steps = {
			{ Pose = "Feint", WindUp = 0.45, Active = 0, Damage = 0, Range = 0, ArcDot = 1 },
			{ Pose = if kroko then "Club" else "Staff", WindUp = 0.4, Active = 0.22, Damage = 16, Range = 8, ArcDot = 0.55 },
		}
	end
	return move
end

return table.freeze(HeroCombatDefinitions)
