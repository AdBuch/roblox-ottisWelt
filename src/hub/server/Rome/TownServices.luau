--!strict
-- The two working counters of Rome's MVP, entirely server-decided:
--   FORGE  the smith offers the first improvement stage for an OWNED weapon (ForgeDefinitions).
--          The dialog shows the item, its real basic hit against zombies now and after the
--          improvement, and the price in Denarii. InventoryService.forgeUpgrade charges and
--          upgrades in one step.
--   ORACLE a priest offers a prophecy for OracleDefinitions.Price Denarii, charged exactly once
--          per confirmed offer; the text names the Aura still missing for the next title.
-- Flow: the player triggers the NPC's prompt -> the server checks the player and sends an OFFER
-- with a one-time token (Remotes.RomeEvent) -> the client shows it and confirms -> the client
-- invokes Remotes.RomeRequest(action, payload) -> the server checks everything again (token,
-- distance to the NPC, Hub lobby state, loaded data, item, ownership, stage, price, balance),
-- then answers. The client only confirms what the server answered.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local ForgeDefinitions = require(ReplicatedStorage.Shared.ForgeDefinitions)
local OracleDefinitions = require(ReplicatedStorage.Shared.OracleDefinitions)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local WeaponDefinitions = require(ReplicatedStorage.Shared.WeaponDefinitions)

export type Deps = {
	inventory: any, -- InventoryService
	isReady: (player: Player) -> boolean, -- PlayerDataService.isReady
	rootOf: (player: Player) -> BasePart?, -- living character's root
	fire: (player: Player, kind: string, payload: any) -> (), -- Remotes.RomeEvent:FireClient
	now: () -> number,
	token: () -> string,
}

type Offer = { kind: string, token: string, expires: number }

local TownServices = {}

local deps: Deps
local smithAt: () -> Vector3? = function()
	return nil
end
local oracleAt: () -> Vector3? = function()
	return nil
end
local offers: { [Player]: { [string]: Offer } } = {}
local lastRequest: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
local turns: { [Player]: number } = {}
local REQUEST_INTERVAL = 0.35

-- Why a player can't use a counter right now, or nil.
local function refusal(player: Player, at: Vector3?, distance: number): string?
	if not GameStates.isInLobby(player:GetAttribute(GameStates.StateAttribute)) then
		return "Das geht nur in der Stadt, nicht im Kampf."
	end
	if not deps.isReady(player) then
		return "Deine Daten werden noch geladen. Versuche es gleich noch einmal."
	end
	local root = deps.rootOf(player)
	if not root or not at or (root.Position - at).Magnitude > distance then
		return "Du bist zu weit weg."
	end
	return nil
end

local function forgeOffers(player: Player): { any }
	local list = {}
	for _, weapon in WeaponDefinitions.Ordered do
		if deps.inventory.owns(player, "Weapon", weapon.Id) then
			local offer = ForgeDefinitions.offer(weapon.Id, deps.inventory.forgeLevel(player, weapon.Id))
			if offer then
				table.insert(list, offer)
			end
		end
	end
	return list
end

local function newOffer(player: Player, kind: string): Offer
	local offer = { kind = kind, token = deps.token(), expires = deps.now() + OracleDefinitions.OfferSeconds }
	offers[player] = offers[player] or {}
	offers[player][kind] = offer
	return offer
end

local function validOffer(player: Player, kind: string, token: unknown): Offer?
	local offer = offers[player] and offers[player][kind]
	if offer and typeof(token) == "string" and offer.token == token and deps.now() <= offer.expires then
		return offer
	end
	return nil
end

-- The NPC prompts: open an offer (or explain why not).
function TownServices.openForge(player: Player)
	local why = refusal(player, smithAt(), ForgeDefinitions.UseDistance)
	if why then
		deps.fire(player, "Refused", { title = "SCHMIEDE", text = why })
		return
	end
	local offer = newOffer(player, "Forge")
	deps.fire(player, "ForgeOffer", {
		token = offer.token,
		items = forgeOffers(player),
		denarii = deps.inventory.getDenarii(player),
		bonus = ForgeDefinitions.PvEBonus,
		maxLevel = ForgeDefinitions.MaxLevel,
	})
end

function TownServices.openOracle(player: Player)
	local why = refusal(player, oracleAt(), OracleDefinitions.UseDistance)
	if why then
		deps.fire(player, "Refused", { title = "ORAKEL", text = why })
		return
	end
	local offer = newOffer(player, "Oracle")
	deps.fire(player, "OracleOffer", { token = offer.token, price = OracleDefinitions.Price, denarii = deps.inventory.getDenarii(player) })
end

-- RomeRequest handler. Always answers a table { ok, message, ... }.
function TownServices.request(player: Player, action: unknown, payload: unknown): { [string]: any }
	local now = deps.now()
	if now - (lastRequest[player] or -math.huge) < REQUEST_INTERVAL or busy[player] then
		return { ok = false, message = "Einen Moment ..." }
	end
	lastRequest[player] = now
	if typeof(payload) ~= "table" then
		return { ok = false, message = "Ungültige Anfrage." }
	end
	local data = payload :: { [string]: any }
	busy[player] = true
	local result: { [string]: any }
	if action == "ForgeUpgrade" then
		local weaponId, expected = data.weaponId, data.level
		if not validOffer(player, "Forge", data.token) then
			result = { ok = false, message = "Das Angebot ist abgelaufen. Sprich den Schmied noch einmal an." }
		elseif typeof(weaponId) ~= "string" or not ForgeDefinitions.isSupported(weaponId) or typeof(expected) ~= "number" then
			result = { ok = false, message = "Ungültige Anfrage." }
		else
			local why = refusal(player, smithAt(), ForgeDefinitions.UseDistance)
			if why then
				result = { ok = false, message = why }
			else
				local ok, message = deps.inventory.forgeUpgrade(player, weaponId, expected)
				result = { ok = ok, message = message, items = forgeOffers(player), denarii = deps.inventory.getDenarii(player) }
			end
		end
	elseif action == "Oracle" then
		local offer = validOffer(player, "Oracle", data.token)
		if not offer then
			result = { ok = false, message = "Das Angebot ist abgelaufen. Sprich den Priester noch einmal an." }
		else
			local why = refusal(player, oracleAt(), OracleDefinitions.UseDistance)
			if why then
				result = { ok = false, message = why }
			elseif not deps.inventory.spendDenarii(player, OracleDefinitions.Price) then
				result = { ok = false, message = ("Zu wenig Denarii: %d nötig, du hast %d."):format(OracleDefinitions.Price, deps.inventory.getDenarii(player)), denarii = deps.inventory.getDenarii(player) }
			else
				offers[player]["Oracle"] = nil -- one prophecy per paid offer
				turns[player] = (turns[player] or 0) + 1
				local prophecy = OracleDefinitions.prophecy(deps.inventory.getAura(player), turns[player])
				result = { ok = true, message = "Die Weissagung", saying = prophecy.saying, hint = prophecy.hint, isMax = prophecy.isMax, denarii = deps.inventory.getDenarii(player) }
			end
		end
	else
		result = { ok = false, message = "Ungültige Anfrage." }
	end
	busy[player] = nil
	return result
end

function TownServices.forget(player: Player)
	offers[player], lastRequest[player], busy[player], turns[player] = nil, nil, nil, nil
end

-- `smith` / `oracle`: where the NPCs stand now (they walk).
function TownServices.init(dependencies: Deps, smith: () -> Vector3?, oracle: () -> Vector3?)
	deps = dependencies
	smithAt, oracleAt = smith, oracle
end

-- The live wiring in the Hub: real services, remotes and NPC prompts.
function TownServices.start(request: RemoteFunction, event: RemoteEvent, smith: BasePart?, oracle: BasePart?)
	local Server = script.Parent.Parent.Parent
	local InventoryService = require(Server.InventoryService) :: any
	local PlayerDataService = require(Server.PlayerDataService) :: any
	local CombatUtil = require(Server.CombatUtil) :: any
	TownServices.init({
		inventory = InventoryService,
		isReady = PlayerDataService.isReady,
		rootOf = function(player: Player): BasePart?
			local _, _, root = CombatUtil.getLivingCharacter(player)
			return root
		end,
		fire = function(player: Player, kind: string, payload: any)
			event:FireClient(player, kind, payload)
		end,
		now = os.clock,
		token = function(): string
			return HttpService:GenerateGUID(false)
		end,
	}, function(): Vector3?
		return if smith then smith.Position else nil
	end, function(): Vector3?
		return if oracle then oracle.Position else nil
	end)
	request.OnServerInvoke = function(player: Player, action: unknown, payload: unknown)
		return TownServices.request(player, action, payload)
	end
	Players.PlayerRemoving:Connect(TownServices.forget)
end

return TownServices
