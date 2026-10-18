--!strict
-- Combination moves: Attack (A), Block tap (B) and Jump (J) inputs, resolved with Execute (Enter /
-- COMBO button / gamepad Y). The server records only inputs it accepted and validated (a J needs
-- a real jump), checks the timing (InputDefinitions) and matches the most recent inputs against
-- the equipped weapon's sequences. Basic attacks never need a combo.
--
-- Shared patterns work with every weapon (universal moves scale with the weapon's basic attack);
-- each weapon replaces some of them with its own named, more spectacular move.

export type ComboInput = "A" | "B" | "J"

export type ComboDefinition = {
	Name: string,
	Sequence: { ComboInput },
	Move: string, -- SpecialMoveDefinitions id
	Advanced: boolean, -- a named weapon combo (otherwise a universal pattern)
}

local function combo(name: string, sequence: { ComboInput }, moveId: string, advanced: boolean): ComboDefinition
	return table.freeze({ Name = name, Sequence = table.freeze(sequence), Move = moveId, Advanced = advanced }) :: any
end

-- The five shared patterns.
local Universal: { [string]: ComboDefinition } = table.freeze({
	Counter = combo("COUNTER COMBINATION", { "B", "A", "B", "A" }, "U_Counter", false),
	JumpFinisher = combo("JUMP FINISHER", { "A", "A", "J", "A" }, "U_JumpFinisher", false),
	GuardBreak = combo("GUARD BREAK", { "B", "B", "A" }, "U_GuardBreak", false),
	ArenaSpin = combo("ARENA SPIN", { "A", "B", "A", "A" }, "U_ArenaSpin", false),
	Rising = combo("RISING ATTACK", { "B", "J", "A" }, "U_Rising", false),
}) :: any

-- Weapon-specific moves (same sequence as a shared pattern replaces it).
local Named: { [string]: { ComboDefinition } } = {
	RustyGladius = {
		combo("REBELLION COMBO", { "B", "A", "B", "A" }, "RebellionCombo", true),
		combo("SAND VIPER", { "A", "A", "J", "A" }, "SandViper", true),
	},
	LegionSword = {
		combo("LEGION'S FURY", { "A", "B", "A", "A" }, "LegionsFury", true),
		combo("EAGLE OF ROME", { "B", "J", "A" }, "EagleOfRome", true),
	},
	HunterBow = {
		combo("ARROW RAIN", { "B", "A", "A" }, "ArrowRain", true),
		combo("EAGLE SHOT", { "A", "J", "A" }, "EagleShot", true),
	},
	MorningStar = {
		combo("CHAIN TEMPEST", { "A", "B", "A", "A" }, "ChainTempest", true),
		combo("FALLING METEOR", { "B", "J", "A" }, "FallingMeteor", true),
	},
	Trident = {
		combo("RETIARIUS FURY", { "B", "A", "B", "A" }, "RetiariusFury", true),
		combo("SEA EAGLE DIVE", { "A", "A", "J", "A" }, "SeaEagleDive", true),
	},
	HopliteSpear = {
		combo("PHALANX BREAKER", { "B", "B", "A" }, "PhalanxBreaker", true),
		combo("SPARTAN VAULT", { "A", "J", "A" }, "SpartanVault", true),
	},
	TwinDaggers = {
		combo("VIPER DANCE", { "A", "B", "A", "A" }, "ViperDance", true),
		combo("RIVER SHADOW", { "B", "J", "A" }, "RiverShadow", true),
	},
	BattleAxe = {
		combo("COLOSSEUM BREAKER", { "B", "A", "B", "A" }, "ColosseumBreaker", true),
		combo("THUNDER OF MARS", { "A", "A", "J", "A" }, "ThunderOfMars", true),
	},
}

local function key(sequence: { ComboInput }): string
	return table.concat(sequence, "")
end

local byWeapon: { [string]: { ComboDefinition } } = {}
for weaponId, named in Named do
	local list: { ComboDefinition } = {}
	local taken: { [string]: boolean } = {}
	for _, entry in named do
		table.insert(list, entry)
		taken[key(entry.Sequence)] = true
	end
	for _, entry in Universal do
		if not taken[key(entry.Sequence)] then
			table.insert(list, entry)
		end
	end
	-- Longest sequences first, so a longer combo wins over a shorter one ending the same way
	table.sort(list, function(a, b)
		if #a.Sequence ~= #b.Sequence then
			return #a.Sequence > #b.Sequence
		end
		return a.Advanced and not b.Advanced
	end)
	byWeapon[weaponId] = table.freeze(list) :: any
end

local ComboDefinitions = {
	Universal = Universal,
	ByWeapon = table.freeze(byWeapon) :: { [string]: { ComboDefinition } },
}

-- "B → A → B → A" style text for boards and the info panel.
function ComboDefinitions.describe(sequence: { ComboInput }): string
	return table.concat(sequence, " → ") .. " → ENTER"
end

return table.freeze(ComboDefinitions)
