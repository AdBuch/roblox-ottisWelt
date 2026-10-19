--!strict
-- Normal attacks per weapon: the contextual basic CHAIN and the slots that movement (Classic) or
-- gestures (Wild) select. Move data lives in SpecialMoveDefinitions (<Prefix>_<Slot>, generated
-- from each weapon's basic attack), so hitboxes and animations come from the same entry.
--   Classic  Attack cycles the chain; movement modifies the NEXT attack:
--            forward -> Up slot (thrust), sideways -> the matching side slash, backward -> Retreat,
--            airborne -> aerial, sliding -> Slide, right after a parry -> Counter,
--            three or more nearby zombies -> Wide (if the weapon has it)
--   Wild     Swipe Left / Right / Up / Down / Circle pick the slot directly; airborne gestures
--            pick the Air slots; sliding -> Slide; after a parry -> Counter
-- The chain never plays the same move twice in a row and resets after ChainResetSeconds without an
-- attack, a weapon change, stun, knockdown, death or leaving combat (server: AttackSequenceService).

export type Slot =
	"SlashRL" | "SlashLR" | "Thrust" | "Overhead" | "Retreat" | "Counter" | "Wide" | "Spin" | "Slide"
	| "AirLeft" | "AirRight" | "AirUp" | "AirDown"
	| "Shot" | "QuickShot" | "PowerShot"

export type Gesture = "Left" | "Right" | "Up" | "Down" | "Circle"

export type WeaponAttacks = {
	Prefix: string,
	Chain: { Slot },
	Left: Slot, -- strike moving toward the left (also: moving left)
	Right: Slot,
	Up: Slot, -- thrust / rising (also: moving forward)
	Down: Slot, -- overhead / downward
	Circle: Slot,
	Back: Slot,
	Wide: Slot?, -- several zombies close by
}

local function attacks(a: WeaponAttacks): WeaponAttacks
	return table.freeze(a) :: any
end

local SWORD = { "SlashRL", "SlashLR", "Thrust", "Overhead" } :: { Slot }

local byPrefix: { [string]: WeaponAttacks } = {
	Gladius = attacks({ Prefix = "Gladius", Chain = SWORD, Left = "SlashRL", Right = "SlashLR", Up = "Thrust", Down = "Overhead", Circle = "Spin", Back = "Retreat", Wide = "Wide" }),
	Legion = attacks({ Prefix = "Legion", Chain = SWORD, Left = "SlashRL", Right = "SlashLR", Up = "Thrust", Down = "Overhead", Circle = "Spin", Back = "Retreat", Wide = "Wide" }),
	Daggers = attacks({ Prefix = "Daggers", Chain = { "SlashRL", "SlashLR", "Thrust", "Overhead" }, Left = "SlashRL", Right = "SlashLR", Up = "Thrust", Down = "Overhead", Circle = "Spin", Back = "Retreat", Wide = "Wide" }),
	MorningStar = attacks({ Prefix = "MorningStar", Chain = { "SlashRL", "SlashLR", "Overhead" }, Left = "SlashRL", Right = "SlashLR", Up = "Thrust", Down = "Overhead", Circle = "Spin", Back = "Retreat", Wide = "Wide" }),
	Axe = attacks({ Prefix = "Axe", Chain = { "SlashRL", "SlashLR", "Overhead" }, Left = "SlashRL", Right = "SlashLR", Up = "Thrust", Down = "Overhead", Circle = "Spin", Back = "Retreat", Wide = "Wide" }),
	Trident = attacks({ Prefix = "Trident", Chain = { "Thrust", "SlashRL", "SlashLR", "Overhead" }, Left = "SlashRL", Right = "SlashLR", Up = "Thrust", Down = "Overhead", Circle = "Spin", Back = "Retreat", Wide = "Wide" }),
	Hoplite = attacks({ Prefix = "Hoplite", Chain = { "Thrust", "SlashRL", "Thrust", "Overhead" }, Left = "SlashRL", Right = "SlashLR", Up = "Thrust", Down = "Overhead", Circle = "Spin", Back = "Retreat", Wide = "Wide" }),
	Bow = attacks({ Prefix = "Bow", Chain = { "Shot", "QuickShot", "Shot", "PowerShot" }, Left = "QuickShot", Right = "QuickShot", Up = "PowerShot", Down = "Shot", Circle = "Spin", Back = "Retreat", Wide = "Wide" }),
}

local WeaponAttackDefinitions = {
	ChainResetSeconds = 1.1,
	CrowdForWide = 3, -- zombies within reach that switch the next Classic attack to Wide
	MovementThreshold = 6, -- studs/s of horizontal movement before it modifies an attack
	ByPrefix = table.freeze(byPrefix),
}

-- "Gladius_Basic" -> "Gladius"
function WeaponAttackDefinitions.prefixOf(basicMoveId: string): string
	return (basicMoveId:gsub("_Basic$", ""))
end

function WeaponAttackDefinitions.forBasic(basicMoveId: string): WeaponAttacks?
	return byPrefix[WeaponAttackDefinitions.prefixOf(basicMoveId)]
end

function WeaponAttackDefinitions.moveId(prefix: string, slot: string): string
	return prefix .. "_" .. slot
end

return table.freeze(WeaponAttackDefinitions)
