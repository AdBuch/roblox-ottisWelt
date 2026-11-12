--!strict
-- Equip an OWNED item from the lobby menu (LoadoutRequest RemoteFunction). The client only ASKS;
-- this service decides and answers, and the menu shows a change only after { ok = true }.
-- Checks, in this order:
--   * rate limit, request shape (kind + id strings), the id exists for that kind
--   * Hub place only (the Arena never changes gear), saved data loaded and not mid-teleport
--   * lobby state + lobby location, no match being prepared (MatchTransition) -> no changes during a
--     fight or the transition into one
--   * the player OWNS the item (buying stays in the Gladiator Armory; equipping never costs Denarii)
-- Then InventoryService.equip (two-handed rule: a shield choice is kept but unused while a
-- two-handed weapon is equipped) and PlayerCombatService.refreshEquipment rebuilds weapon, shield
-- and armor models (attack chain, walk speed and animations follow the new weapon). The profile is
-- saved by PlayerDataService (debounced, flushed before every teleport), so the choice survives
-- rejoining and travels to the Arena.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local InventoryService = require(script.Parent.InventoryService)
local PlayerCombatService = require(script.Parent.PlayerCombatService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = require(script.Parent.Remotes)

export type Response = { ok: boolean, message: string, code: string, data: { [string]: string }? }

local LoadoutRequestService = {}

local limiter = RateLimiter.new({ Equip = 0.35 }, 0.35)

local function loadout(player: Player): { [string]: string }
	return {
		Weapon = InventoryService.getEquippedWeapon(player).Id,
		Shield = tostring(player:GetAttribute(Config.EquippedShieldAttribute) or ""),
		Armor = InventoryService.getEquippedArmor(player).Id,
		Helmet = InventoryService.getEquippedHelmet(player).Id,
	}
end

local function refuse(code: string, message: string): Response
	return { ok = false, code = code, message = message }
end

-- Why `player` may not change gear right now (code, German message), or nil when it may.
function LoadoutRequestService.lockReason(player: Player): (string?, string?)
	if EnvironmentConfig.role() ~= "Hub" then
		return "NOT_LOBBY", "Ausrüstung wechselst du in der Lobby"
	end
	if not PlayerDataService.isReady(player) then
		return "LOADING", "Deine Ausrüstung wird noch geladen oder gespeichert"
	end
	local state = player:GetAttribute(GameStates.StateAttribute)
	local location = player:GetAttribute(GameStates.LocationAttribute)
	if not GameStates.canChangeEquipment(state) or (location ~= nil and location ~= "Lobby") then
		return "IN_BATTLE", "Während eines Kampfes ist kein Wechsel möglich"
	end
	if player:GetAttribute(Config.MatchTransitionAttribute) == true then
		return "TRANSITION", "Der Kampf wird vorbereitet · kein Wechsel möglich"
	end
	return nil, nil
end

function LoadoutRequestService.handle(player: Player, action: unknown, kind: unknown, id: unknown): Response
	if typeof(action) ~= "string" or not limiter.allow(player, action) then
		return refuse("RATE", "Einen Moment …")
	end
	if action ~= "Equip" then
		return refuse("INVALID", "Unbekannte Anfrage")
	end
	if not InventoryService.isItem(kind, id) then
		return refuse("INVALID", "Unbekannter Gegenstand")
	end
	local itemKind: InventoryService.ItemKind = if kind == "Weapon" then "Weapon" elseif kind == "Shield" then "Shield" elseif kind == "Helmet" then "Helmet" else "Armor"
	local itemId = id :: string
	local code, message = LoadoutRequestService.lockReason(player)
	if code then
		return refuse(code, message :: string)
	end
	if not InventoryService.owns(player, itemKind, itemId) then
		return refuse("NOT_OWNED", "Nicht in deinem Besitz · erhältlich in der Gladiatorenwaffenkammer")
	end
	if InventoryService.isEquipped(player, itemKind, itemId) then
		return { ok = true, code = "ALREADY", message = "Bereits ausgerüstet", data = loadout(player) }
	end
	local ok, result = InventoryService.equip(player, itemKind, itemId)
	if not ok then
		return refuse("REFUSED", result)
	end
	PlayerCombatService.refreshEquipment(player)
	return { ok = true, code = "EQUIPPED", message = result, data = loadout(player) }
end

function LoadoutRequestService.init()
	Remotes.LoadoutRequest.OnServerInvoke = function(player: Player, action: unknown, kind: unknown, id: unknown): Response
		local ok, response = pcall(LoadoutRequestService.handle, player, action, kind, id)
		if ok then
			return response
		end
		warn("[OttiArena][Loadout]", player.Name, tostring(response))
		return refuse("ERROR", "Wechsel fehlgeschlagen · bitte erneut versuchen")
	end
end

return LoadoutRequestService
