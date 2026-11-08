--!strict
-- Item texts and REAL game values for weapons, shields and armor, read only from the existing
-- definitions (WeaponDefinitions + SpecialMoveDefinitions, WeaponBalanceConfig, ShieldDefinitions,
-- ArmorDefinitions, DamageConfig). Used by the Gladiator Armory card (ShopController) and the lobby
-- inventory (LobbyMenuController), so both always show the same numbers. Nothing here is invented:
-- a value that the game does not use is not shown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmorDefinitions = require(Shared:WaitForChild("ArmorDefinitions"))
local DamageConfig = require(Shared:WaitForChild("DamageConfig"))
local ShieldDefinitions = require(Shared:WaitForChild("ShieldDefinitions"))
local Practice = require(Shared:WaitForChild("SpecialPracticeDefinitions"))
local SpecialMoveDefinitions = require(Shared:WaitForChild("SpecialMoveDefinitions"))
local WeaponAttackDefinitions = require(Shared:WaitForChild("WeaponAttackDefinitions"))
local WeaponBalanceConfig = require(Shared:WaitForChild("WeaponBalanceConfig"))
local WeaponDefinitions = require(Shared:WaitForChild("WeaponDefinitions"))
local WeaponSpecialDefinitions = require(Shared:WaitForChild("WeaponSpecialDefinitions"))

export type Kind = "Weapon" | "Shield" | "Armor"

-- One comparable value. `better`: +1 higher is better, -1 lower is better, 0 neutral.
export type Value = { key: string, label: string, value: number, text: string, better: number }

export type Card = {
	title: string,
	section: string,
	description: string,
	values: { Value },
	notes: { string }, -- facts without a number (two-handed, projectile, specials)
	levelRequired: number,
	price: number,
}

export type Difference = { label: string, from: string, to: string, change: string, verdict: number } -- verdict: 1 better, -1 worse, 0 same / neutral

local ItemInfo = {}

local ROW_NAMES: { [string]: string } = { Blades = "KLINGEN", Heavy = "SCHWER & REICHWEITE", Ranged = "FERNKAMPF & SPEZIAL" }
local CLASS_NAMES: { [string]: string } = { Light = "LEICHTER SCHILD", Balanced = "AUSGEWOGENER SCHILD", Heavy = "SCHWERER SCHILD" }

local function pct(value: number): string
	return ("%d %%"):format(math.round(value * 100))
end

local function speedWord(cooldown: number): string
	return if cooldown <= 0.45 then "schnell" elseif cooldown <= 0.75 then "mittel" else "langsam"
end

local function value(key: string, label: string, v: number, text: string, better: number): Value
	return { key = key, label = label, value = v, text = text, better = better }
end

function ItemInfo.describe(kind: string, id: string): Card?
	if kind == "Weapon" then
		local weapon = WeaponDefinitions.ById[id]
		if not weapon then
			return nil
		end
		local pve = WeaponBalanceConfig.pveFactor(weapon.Id)
		local values = {
			value("damage", "Schaden (Grundangriff)", weapon.Damage, tostring(weapon.Damage), 1),
			value("pve", "Gegen Zombies & Bosse", pve, ("× %.2f"):format(pve), 1),
			value("cooldown", if weapon.Kind == "Bow" then "Schussintervall" else "Angriffstempo", weapon.Cooldown, ("%.2f s (%s)"):format(weapon.Cooldown, speedWord(weapon.Cooldown)), -1),
			value("range", if weapon.Kind == "Bow" then "Reichweite" elseif weapon.Row == "Heavy" then "Reichweite (lang)" else "Reichweite", weapon.Range, ("%g Studs"):format(weapon.Range), 1),
		}
		local notes = {}
		if weapon.TwoHanded then
			table.insert(notes, "Zweihändig: kein Schild, eingebaute Parade beim Blocken")
		end
		if weapon.Kind == "Bow" then
			table.insert(notes, "Geschoss: fliegt zum Zielpunkt, Wände und erhobene Schilde stoppen es")
		end
		local aerial = (SpecialMoveDefinitions :: any)[weapon.Aerial]
		if aerial then
			table.insert(notes, "Sprungangriff: " .. aerial.Name)
		end
		local specials = {}
		local families = WeaponSpecialDefinitions.forPrefix(WeaponAttackDefinitions.prefixOf(weapon.Basic))
		for _, family in { "Left", "Right", "Up", "Down", "Circle", "Ultimate" } do
			local moveId = families and (families :: any)[family]
			local move = moveId and (SpecialMoveDefinitions :: any)[moveId]
			if move and moveId then
				local unlock = if family == "Up" then " · Luft ab Lv5" elseif family == "Circle" then " · Block ab Lv9" else ""
				table.insert(specials, move.Name .. " (" .. Practice.label(Players.LocalPlayer, weapon.Id, moveId) .. unlock .. ")")
			end
		end
		if #specials > 0 then
			-- one short line per special: wraps cleanly on narrow phone screens
			table.insert(notes, "Spezialangriffe:")
			for _, special in specials do
				table.insert(notes, "  · " .. special)
			end
		end
		return {
			title = weapon.DisplayName,
			section = ROW_NAMES[weapon.Row] or "WAFFE",
			description = weapon.Description,
			values = values,
			notes = notes,
			levelRequired = weapon.LevelRequired,
			price = weapon.Price,
		}
	elseif kind == "Shield" then
		local shield = ShieldDefinitions.ById[id]
		if not shield then
			return nil
		end
		local angle = math.round(math.deg(math.acos(math.clamp(shield.FacingDot, -1, 1))) * 2)
		return {
			title = shield.DisplayName,
			section = CLASS_NAMES[ShieldDefinitions.classOf(shield)] or "SCHILD",
			description = shield.Description,
			values = {
				value("reduction", "Blockschutz vorne", shield.Reduction, pct(shield.Reduction), 1),
				value("arrows", "Schutz gegen Pfeile", shield.ProjectileReduction, pct(shield.ProjectileReduction), 1),
				value("angle", "Blockwinkel", angle, ("%d°"):format(angle), 1),
				value("speed", "Tempo beim Blocken", shield.BlockSpeedMultiplier, pct(shield.BlockSpeedMultiplier), 1),
				value("raise", "Zeit zum Anheben", shield.RaiseSeconds, ("%.2f s"):format(shield.RaiseSeconds), -1),
			},
			notes = { "Ein Schild zur Zeit · mit Zweihandwaffen unbenutzt" },
			levelRequired = shield.LevelRequired,
			price = shield.Price,
		}
	elseif kind == "Armor" then
		local armor = ArmorDefinitions.ById[id]
		if not armor then
			return nil
		end
		local pvp = armor.Reduction * DamageConfig.PvPArmorEffectiveness
		return {
			title = armor.DisplayName,
			section = "RÜSTUNG",
			description = armor.Description,
			values = {
				value("reduction", "Schadensminderung", armor.Reduction, pct(armor.Reduction), 1),
				value("pvp", "Schadensminderung PvP", pvp, pct(pvp), 1),
				value("move", "Tempoverlust", armor.MovePenalty, if armor.MovePenalty > 0 then "−" .. pct(armor.MovePenalty) else "keiner", -1),
			},
			notes = { "Eine Rüstung zur Zeit · Wechsel nur in der Lobby" },
			levelRequired = armor.LevelRequired,
			price = armor.Price,
		}
	end
	return nil
end

-- Selected item vs. the equipped one of the same kind: only values the game really uses.
function ItemInfo.compare(kind: string, selectedId: string, equippedId: string): { Difference }
	local selected = ItemInfo.describe(kind, selectedId)
	local equipped = ItemInfo.describe(kind, equippedId)
	local result: { Difference } = {}
	if not selected or not equipped then
		return result
	end
	local byKey: { [string]: Value } = {}
	for _, v in equipped.values do
		byKey[v.key] = v
	end
	for _, v in selected.values do
		local old = byKey[v.key]
		if old then
			local delta = v.value - old.value
			local verdict = if math.abs(delta) < 1e-6 or v.better == 0 then 0 elseif (delta > 0) == (v.better > 0) then 1 else -1
			local change = if math.abs(delta) < 1e-6 then "gleich" elseif verdict > 0 then "besser" else "schwächer"
			table.insert(result, { label = v.label, from = old.text, to = v.text, change = change, verdict = verdict })
		end
	end
	return result
end

-- The two-handed rule as a short hint for the inventory (nil when nothing special applies).
function ItemInfo.handRule(kind: string, id: string, equippedWeaponId: string): string?
	local weapon = WeaponDefinitions.ById[equippedWeaponId]
	if kind == "Shield" and weapon and weapon.TwoHanded then
		return ("Wird gespeichert, aber erst mit einer Einhandwaffe benutzt (%s ist zweihändig)"):format(weapon.DisplayName)
	end
	local selected = WeaponDefinitions.ById[id]
	if kind == "Weapon" and selected and selected.TwoHanded then
		return "Zweihändig: dein Schild bleibt gespeichert, wird aber nicht getragen"
	end
	return nil
end

return ItemInfo
