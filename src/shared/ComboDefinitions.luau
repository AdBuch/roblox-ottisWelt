--!strict
-- Weapon combos: input sequences that end in a normal action and boost it.
-- Inputs: "Basic" | "Special1" (Q) | "Special2" (E) | "Block" (raising the shield/parry).
-- Each input must arrive within CombatConfig.ComboWindowSeconds after the previous move ended.
-- The server records only accepted actions, so a client can't claim a combo it didn't perform.
-- A late or wrong sequence simply plays the last action normally.

export type ComboInput = "Basic" | "Special1" | "Special2" | "Block"

export type ComboDefinition = {
	Name: string,
	Sequence: { ComboInput },
	DamageMultiplier: number,
	BonusStagger: number?,
}

local function combo(name: string, sequence: { ComboInput }, multiplier: number, stagger: number?): ComboDefinition
	return table.freeze({ Name = name, Sequence = table.freeze(sequence), DamageMultiplier = multiplier, BonusStagger = stagger }) :: any
end

local ComboDefinitions: { [string]: { ComboDefinition } } = {
	RustyGladius = {
		combo("GLADIATOR'S POINT", { "Basic", "Basic", "Special1" }, 1.4),
		combo("IRON REPLY", { "Block", "Special2" }, 1.5, 0.4),
		combo("SAND STEP", { "Special1", "Basic" }, 1.25),
	},
	LegionSword = {
		combo("TESTUDO BREAKER", { "Basic", "Basic", "Special2" }, 1.4, 0.3),
		combo("CENTURION'S ORDER", { "Special1", "Basic", "Special2" }, 1.6),
	},
	HunterBow = {
		combo("VOLLEY", { "Basic", "Basic", "Special1" }, 1.3),
		combo("STEADY AIM", { "Block", "Special2" }, 1.4),
	},
	MorningStar = {
		combo("MACE AND THUNDER", { "Basic", "Special1" }, 1.3, 0.3),
		combo("IRON STORM", { "Basic", "Special2" }, 1.3),
	},
	Trident = {
		combo("SEA STORM", { "Basic", "Basic", "Special1" }, 1.3),
		combo("CAUGHT IN THE NET", { "Special2", "Basic" }, 1.5),
	},
	HopliteSpear = {
		combo("SHIELD WALL", { "Block", "Special1" }, 1.4, 0.3),
		combo("HOPLITE CIRCLE", { "Basic", "Basic", "Special2" }, 1.3),
	},
	TwinDaggers = {
		combo("VIPER'S NEST", { "Basic", "Basic", "Special1" }, 1.2),
		combo("SHADOW COUNTER", { "Block", "Special2" }, 1.5),
		combo("TWIN FANGS", { "Special2", "Basic", "Basic" }, 1.3),
	},
	BattleAxe = {
		combo("HEADSMAN", { "Basic", "Special1" }, 1.3),
		combo("ARENA STORM", { "Basic", "Basic", "Special2" }, 1.3),
	},
}

for id, list in ComboDefinitions do
	ComboDefinitions[id] = table.freeze(list) :: any
end

return table.freeze(ComboDefinitions)
