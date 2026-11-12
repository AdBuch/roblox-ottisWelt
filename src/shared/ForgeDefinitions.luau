--!strict
-- THE FORGE OF ROME (Hub · Schmiede an der Handwerksgasse). Every owned weapon exists as one or
-- more COPIES (Exemplare). A copy has its own hardening stage, wear, design and possibly a job at
-- the smith. Saved in the profile (PlayerDataSchema v10, `weaponCopies`, `activeCopy`) and read by
-- the server in every fight, in the Hub and in the Arena place.
--
-- PvE ONLY: hardening (+10 % per stage) and wear (weaker in steps) form the copy's PvE factor.
-- SpecialMoveService divides the whole PvE factor out again before the PvP normalization, and wear
-- grows only from hits on zombies and bosses. A duel is never decided by forge work or wear.
--
-- JOBS take real time (os.time, so they keep running through teleports and rejoins). While a copy
-- is at the smith the player can't use it: another free copy of the same weapon, or the starter
-- gladius, takes its place. A Robux purchase (ForgeSkip) finishes a job at once.
--   Harden   +1 stage (max MaxLevel)               price: 50 % of the weapon price, min 40
--   Sharpen  wear -35                                price: 10 + 4 % of the weapon price
--   Repair   wear 0                                  price: 15 + 20 % of the weapon price x wear share
--   Design   a cosmetic option (paid with Robux: DesignToken), no effect on combat
--   Copy     a further copy of the same weapon       price: base x 2^(copies owned), base min 40
-- Missing Denarii can be bought with Robux (Denarii packs). All Robux products are configured
-- here; productId 0 = not created yet (Studio test purchases only).

local SpecialMoveDefinitions = require(script.Parent.SpecialMoveDefinitions)
local WeaponBalanceConfig = require(script.Parent.WeaponBalanceConfig)
local WeaponDefinitions = require(script.Parent.WeaponDefinitions)

export type Offer = {
	weaponId: string,
	name: string,
	level: number, -- current forge stage (0 = not improved)
	maxLevel: number,
	price: number, -- Denarii for the next stage (0 at the top)
	basicNow: number, -- basic hit against zombies today (rounded)
	basicNext: number, -- basic hit against zombies after the next stage (rounded)
	factorNow: number, -- whole PvE damage factor today
	factorNext: number,
}

export type JobKind = "Harden" | "Sharpen" | "Repair" | "Design" | "Copy"
export type Job = { kind: JobKind, untilTime: number, slot: string?, option: string? }
export type Copy = {
	uid: string,
	forge: number, -- hardening stage
	wear: number, -- 0 (new) .. MaxWear (worn out)
	design: { [string]: string }, -- slot -> option (missing = standard)
	job: Job?,
}

export type DesignOption = { id: string, label: string, color: Color3?, material: Enum.Material? }
export type DesignSlot = { id: string, label: string, parts: { string }, options: { DesignOption } }
export type Product = { key: string, productId: number, robux: number, label: string, denarii: number?, credits: { [string]: number }? }

local GOLD = Color3.fromRGB(232, 186, 82)
local SILVER = Color3.fromRGB(206, 210, 216)
local BRONZE = Color3.fromRGB(176, 125, 60)

local ForgeDefinitions = {
	MaxLevel = 1,
	PvEBonus = 0.1, -- +10 % PvE damage per stage
	PriceShare = 0.5,
	MinPrice = 40,
	UseDistance = 16, -- the smith must be this close (server check, studs)
	Attribute = "ForgeLevels", -- display: "WeaponId:stage" of the active copies
	CopiesAttribute = "WeaponCopies", -- display: JSON of the player's copies (client dialog)
	ValueNote = "Angezeigt: Grundschlag (Basisangriff) gegen Zombies mit dem PvE-Faktor dieses Exemplars (Härtung und Zustand). Kombo- und Spezialfaktoren und der Bonus gegen Zombies mit gebrochener Rüstung wirken erst beim Treffer und folgen demselben Faktor. Gegen Spieler gelten Härtung und Verschleiss nicht.",

	-- WEAR (PvE only): every landed hit on a zombie or boss
	MaxWear = 100,
	WearPerHit = 0.25,
	-- damage steps: below 60 full, from 60 reduced, from 90 worn out (still usable)
	WearSteps = table.freeze({
		table.freeze({ from = 0, factor = 1, label = "Gut" }),
		table.freeze({ from = 60, factor = 0.85, label = "Abgenutzt" }),
		table.freeze({ from = 90, factor = 0.7, label = "Stumpf" }),
	}),
	SharpenAmount = 35,

	-- JOB durations (seconds)
	JobSeconds = table.freeze({ Harden = 15 * 60, Sharpen = 2 * 60, Repair = 5 * 60, Design = 10 * 60, Copy = 20 * 60 }),
	JobLabels = table.freeze({ Harden = "Härten", Sharpen = "Schleifen", Repair = "Reparieren", Design = "Neues Design", Copy = "Neues Exemplar" }),
	MaxCopies = 6, -- per weapon type
	MinCopyPrice = 40,

	-- COSMETIC designs (no effect on combat): slot -> options; the parts each slot recolours
	DesignSlots = table.freeze({
		table.freeze({ id = "Grip", label = "Griff", parts = table.freeze({ "Grip", "Handle", "Haft", "Shaft", "Wrap" }), options = table.freeze({
			table.freeze({ id = "Gold", label = "Goldener Griff", color = GOLD, material = Enum.Material.Metal }),
			table.freeze({ id = "Silver", label = "Silbergriff", color = SILVER, material = Enum.Material.Metal }),
			table.freeze({ id = "Purple", label = "Purpurleder", color = Color3.fromRGB(96, 40, 92), material = Enum.Material.Leather }),
		}) }),
		table.freeze({ id = "Blade", label = "Klinge", parts = table.freeze({ "Blade", "Tip", "Edge", "Head", "HeadTip", "Spike", "Prong", "Barb", "Ball" }), options = table.freeze({
			table.freeze({ id = "Polished", label = "Poliert", color = Color3.fromRGB(226, 230, 236), material = Enum.Material.Metal }),
			table.freeze({ id = "Blackened", label = "Geschwärzt", color = Color3.fromRGB(46, 46, 52), material = Enum.Material.Metal }),
			table.freeze({ id = "Bronze", label = "Bronzeklinge", color = BRONZE, material = Enum.Material.Metal }),
		}) }),
		table.freeze({ id = "Fittings", label = "Beschläge", parts = table.freeze({ "Guard", "Pommel", "Collar", "Cap", "Band", "Socket", "Butt", "Sauroter", "Link" }), options = table.freeze({
			table.freeze({ id = "Gold", label = "Goldbeschläge", color = GOLD, material = Enum.Material.Metal }),
			table.freeze({ id = "Silver", label = "Silberbeschläge", color = SILVER, material = Enum.Material.Metal }),
			table.freeze({ id = "Bronze", label = "Bronzebeschläge", color = BRONZE, material = Enum.Material.Metal }),
		}) }),
	}) :: { DesignSlot },
	-- Shield paint (per shield type, cosmetic)
	ShieldSlot = table.freeze({ id = "Paint", label = "Schildbemalung", parts = table.freeze({ "Face", "Body" }), options = table.freeze({
		table.freeze({ id = "LegionRed", label = "Legionsrot", color = Color3.fromRGB(150, 36, 34), material = Enum.Material.SmoothPlastic }),
		table.freeze({ id = "ImperialBlue", label = "Kaiserblau", color = Color3.fromRGB(40, 66, 130), material = Enum.Material.SmoothPlastic }),
		table.freeze({ id = "Gold", label = "Goldschild", color = GOLD, material = Enum.Material.Metal }),
	}) }) :: DesignSlot,

	-- ROBUX developer products (create them in the Creator Hub, then enter the ids)
	Products = (table.freeze({
		table.freeze({ key = "DenariiSmall", productId = 0, robux = 25, label = "250 Denarii", denarii = 250 } :: Product),
		table.freeze({ key = "DenariiMedium", productId = 0, robux = 99, label = "1200 Denarii", denarii = 1200 } :: Product),
		table.freeze({ key = "DenariiLarge", productId = 0, robux = 199, label = "3000 Denarii", denarii = 3000 } :: Product),
		table.freeze({ key = "ForgeSkip", productId = 0, robux = 15, label = "Auftrag sofort fertig", credits = table.freeze({ Skip = 1 }) } :: Product),
		table.freeze({ key = "DesignToken", productId = 0, robux = 49, label = "Design anfertigen", credits = table.freeze({ Design = 1 }) } :: Product),
		-- SALE bundles: cheaper than buying the parts one by one
		table.freeze({ key = "SkipPack", productId = 0, robux = 39, label = "3× Vorspulen · SALE (statt 45 R$)", credits = table.freeze({ Skip = 3 }) } :: Product),
		table.freeze({ key = "DesignPack", productId = 0, robux = 129, label = "3× Design · SALE (statt 147 R$)", credits = table.freeze({ Design = 3 }) } :: Product),
		table.freeze({ key = "RomeStarter", productId = 0, robux = 149, label = "Starterpaket: 1200 Denarii + Vorspulen + Design · SALE (statt 163 R$)", denarii = 1200, credits = table.freeze({ Skip = 1, Design = 1 }) } :: Product),
	}) :: any) :: { Product },
	MaxReceipts = 50, -- processed purchase ids kept per profile (no double grant)
}

-- Clamp a saved stage.
function ForgeDefinitions.clampLevel(value: unknown): number
	local n = tonumber(value) or 0
	if n ~= n then
		return 0
	end
	return math.clamp(math.floor(n), 0, ForgeDefinitions.MaxLevel)
end

function ForgeDefinitions.clampWear(value: unknown): number
	local n = tonumber(value) or 0
	if n ~= n then
		return 0
	end
	return math.clamp(n, 0, ForgeDefinitions.MaxWear)
end

-- Weapons the forge can work on (every weapon definition).
function ForgeDefinitions.isSupported(weaponId: unknown): boolean
	return typeof(weaponId) == "string" and WeaponDefinitions.ById[weaponId] ~= nil
end

-- Price of the hardening stage after `level` (0 when the weapon is at the top).
function ForgeDefinitions.price(weaponId: string, level: number): number
	local weapon = WeaponDefinitions.ById[weaponId]
	if not weapon or level >= ForgeDefinitions.MaxLevel then
		return 0
	end
	local raw = weapon.Price * ForgeDefinitions.PriceShare * (level + 1)
	return math.max(ForgeDefinitions.MinPrice, math.floor(raw / 5 + 0.5) * 5)
end

local function round5(x: number): number
	return math.floor(x / 5 + 0.5) * 5
end

function ForgeDefinitions.sharpenPrice(weaponId: string): number
	local weapon = WeaponDefinitions.ById[weaponId]
	return round5(10 + 0.04 * (if weapon then weapon.Price else 0))
end

function ForgeDefinitions.repairPrice(weaponId: string, wear: number): number
	local weapon = WeaponDefinitions.ById[weaponId]
	local share = ForgeDefinitions.clampWear(wear) / ForgeDefinitions.MaxWear
	return round5(15 + 0.2 * (if weapon then weapon.Price else 0) * share)
end

-- Price of a further copy when the player already owns `owned` copies of the weapon.
function ForgeDefinitions.copyPrice(weaponId: string, owned: number): number
	local weapon = WeaponDefinitions.ById[weaponId]
	local base = math.max(ForgeDefinitions.MinCopyPrice, if weapon then weapon.Price else 0)
	return base * 2 ^ math.max(1, owned)
end

-- Extra PvE factor of a hardening stage (1 = none).
function ForgeDefinitions.pveFactor(level: number): number
	return 1 + ForgeDefinitions.clampLevel(level) * ForgeDefinitions.PvEBonus
end

-- The wear step a copy is in.
function ForgeDefinitions.wearStep(wear: number): { from: number, factor: number, label: string }
	local value = ForgeDefinitions.clampWear(wear)
	local step = ForgeDefinitions.WearSteps[1]
	for _, s in ForgeDefinitions.WearSteps do
		if value >= s.from then
			step = s
		end
	end
	return step
end

function ForgeDefinitions.wearFactor(wear: number): number
	return ForgeDefinitions.wearStep(wear).factor
end

-- The whole PvE factor a copy adds (hardening x wear).
function ForgeDefinitions.copyFactor(level: number, wear: number): number
	return ForgeDefinitions.pveFactor(level) * ForgeDefinitions.wearFactor(wear)
end

-- The weapon's basic hit against zombies with a copy factor (whole factor, rounded).
function ForgeDefinitions.basicAgainstZombies(weaponId: string, copyFactor: number): (number, number)
	local weapon = WeaponDefinitions.ById[weaponId]
	local basic = weapon and (SpecialMoveDefinitions :: any)[weapon.Basic]
	local damage = if basic then basic.Damage else (if weapon then weapon.Damage else 0)
	local factor = WeaponBalanceConfig.pveFactor(weaponId) * copyFactor
	return math.floor(damage * factor + 0.5), factor
end

-- Everything the hardening offer shows for one weapon at the given stage (wear ignored).
function ForgeDefinitions.offer(weaponId: string, level: number): Offer?
	local weapon = WeaponDefinitions.ById[weaponId]
	if not weapon then
		return nil
	end
	local current = ForgeDefinitions.clampLevel(level)
	local nextLevel = math.min(current + 1, ForgeDefinitions.MaxLevel)
	local now, factorNow = ForgeDefinitions.basicAgainstZombies(weaponId, ForgeDefinitions.pveFactor(current))
	local after, factorNext = ForgeDefinitions.basicAgainstZombies(weaponId, ForgeDefinitions.pveFactor(nextLevel))
	return {
		weaponId = weaponId,
		name = weapon.DisplayName,
		level = current,
		maxLevel = ForgeDefinitions.MaxLevel,
		price = ForgeDefinitions.price(weaponId, current),
		basicNow = now,
		basicNext = after,
		factorNow = factorNow,
		factorNext = factorNext,
	}
end

function ForgeDefinitions.designSlot(slotId: unknown, shield: boolean?): DesignSlot?
	if shield then
		return if slotId == ForgeDefinitions.ShieldSlot.id then ForgeDefinitions.ShieldSlot else nil
	end
	for _, slot in ForgeDefinitions.DesignSlots do
		if slot.id == slotId then
			return slot
		end
	end
	return nil
end

function ForgeDefinitions.designOption(slot: DesignSlot, optionId: unknown): DesignOption?
	for _, option in slot.options do
		if option.id == optionId then
			return option
		end
	end
	return nil
end

function ForgeDefinitions.product(key: unknown): Product?
	for _, p in ForgeDefinitions.Products do
		if p.key == key or (typeof(key) == "number" and key ~= 0 and p.productId == key) then
			return p
		end
	end
	return nil
end

-- Recolours a built weapon / shield model by its design (cosmetic only).
function ForgeDefinitions.applyDesign(model: Instance, design: { [string]: string }, shield: boolean?)
	local slots: { DesignSlot } = if shield then { ForgeDefinitions.ShieldSlot } else ForgeDefinitions.DesignSlots
	for _, slot in slots do
		local option = ForgeDefinitions.designOption(slot, design[slot.id])
		if option then
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and table.find(slot.parts, part.Name) then
					if option.color then
						part.Color = option.color
					end
					if option.material then
						part.Material = option.material
					end
				end
			end
		end
	end
end

-- "Id:1,Id:1" for the display attribute (sorted, only improved weapons).
function ForgeDefinitions.encode(levels: { [string]: number }): string
	local parts = {}
	for id, level in levels do
		if level > 0 then
			table.insert(parts, ("%s:%d"):format(id, level))
		end
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

function ForgeDefinitions.decode(value: unknown): { [string]: number }
	local levels: { [string]: number } = {}
	if typeof(value) == "string" then
		for id, level in value:gmatch("([%w_]+):(%d+)") do
			if ForgeDefinitions.isSupported(id) then
				levels[id] = ForgeDefinitions.clampLevel(tonumber(level))
			end
		end
	end
	return levels
end

return table.freeze(ForgeDefinitions)
