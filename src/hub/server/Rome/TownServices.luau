--!strict
-- The two working counters of Rome, entirely server-decided:
--   SMITH  every owned weapon as copies (ForgeDefinitions): harden (+10 % PvE), sharpen and repair
--          (wear from PvE fights), a new design (Robux), a further copy (price doubles), choose the
--          copy to fight with, and paint a shield (Robux). Jobs take real time; a copy at the smith
--          can't be used. A Robux purchase finishes a job at once. Missing Denarii can be bought.
--   ORACLE a priest offers a prophecy for OracleDefinitions.Price Denarii, charged exactly once
--          per confirmed offer; the text names the Aura still missing for the next title.
-- Flow: the player triggers the NPC's prompt -> the server checks the player and sends an OFFER
-- with a one-time token (Remotes.RomeEvent) -> the client shows it and confirms -> the client
-- invokes Remotes.RomeRequest(action, payload) -> the server checks everything again (token,
-- distance to the NPC, Hub lobby state, loaded data, item, ownership, copy, price, balance), then
-- answers. The client only shows what the server answered.
--
-- ROBUX: the client asks to buy a product ("Buy"); the server remembers what the purchase is for
-- (pending: finish this job / this design / this paint) and returns the product id to prompt.
-- MarketplaceService.ProcessReceipt grants each receipt once (saved receipt ids), turns the
-- product into Denarii or a credit, uses a credit for the pending action, saves, then answers
-- PurchaseGranted. Products with id 0 are not created yet: in Studio the same grant runs as a test
-- purchase, anywhere else they are refused.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local ForgeDefinitions = require(ReplicatedStorage.Shared.ForgeDefinitions)
local OracleDefinitions = require(ReplicatedStorage.Shared.OracleDefinitions)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local WeaponDefinitions = require(ReplicatedStorage.Shared.WeaponDefinitions)
local ShieldDefinitions = require(ReplicatedStorage.Shared.ShieldDefinitions)

export type Deps = {
	inventory: any, -- InventoryService
	isReady: (player: Player) -> boolean, -- PlayerDataService.isReady
	rootOf: (player: Player) -> BasePart?, -- living character's root
	fire: (player: Player, kind: string, payload: any) -> (), -- Remotes.RomeEvent:FireClient
	now: () -> number,
	token: () -> string,
	refresh: ((player: Player) -> ())?, -- re-attach the weapon in hand (PlayerCombatService)
	save: ((player: Player) -> boolean)?, -- PlayerDataService.flush
	isStudio: (() -> boolean)?, -- test purchases for products without an id
}

type Offer = { kind: string, token: string, expires: number }
type Pending = { action: string, weaponId: string?, uid: string?, slot: string?, option: string?, shieldId: string? }

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
local pending: { [Player]: Pending } = {}
local studioReceipts = 0
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

local function designText(design: { [string]: string }): string
	local parts = {}
	for _, slot in ForgeDefinitions.DesignSlots do
		local option = ForgeDefinitions.designOption(slot, design[slot.id])
		if option then
			table.insert(parts, option.label)
		end
	end
	return if #parts > 0 then table.concat(parts, ", ") else "Standard"
end

local function productReady(product: ForgeDefinitions.Product): boolean
	return product.productId ~= 0 or (deps.isStudio ~= nil and deps.isStudio())
end

-- Everything the smith's dialog shows (all values from the server's definitions).
local function smithState(player: Player, token: string?): { [string]: any }
	local inv = deps.inventory
	local now = os.time()
	local weapons = {}
	for _, weapon in WeaponDefinitions.Ordered do
		if inv.owns(player, "Weapon", weapon.Id) then
			local copies = inv.copies(player, weapon.Id)
			local inUse = inv.copyInUse(player, weapon.Id)
			local active = inv.activeCopyId(player, weapon.Id)
			local rows = {}
			for index, c in copies do
				local factor = ForgeDefinitions.copyFactor(c.forge, c.wear)
				local basic = ForgeDefinitions.basicAgainstZombies(weapon.Id, factor)
				local hardened = ForgeDefinitions.basicAgainstZombies(weapon.Id, ForgeDefinitions.copyFactor(math.min(c.forge + 1, ForgeDefinitions.MaxLevel), c.wear))
				local job = c.job
				table.insert(rows, {
					uid = c.uid,
					index = index,
					active = c.uid == active,
					inHand = inUse ~= nil and inUse.uid == c.uid,
					forge = c.forge,
					wear = math.floor(c.wear + 0.5),
					wearLabel = ForgeDefinitions.wearStep(c.wear).label,
					basic = basic,
					basicHardened = hardened,
					design = table.clone(c.design),
					designText = designText(c.design),
					job = if job then { kind = job.kind, label = (ForgeDefinitions.JobLabels :: any)[job.kind], remaining = math.max(0, job.untilTime - now) } else nil,
					prices = {
						Harden = if c.forge < ForgeDefinitions.MaxLevel then ForgeDefinitions.price(weapon.Id, c.forge) else nil,
						Sharpen = if c.wear > 0 then ForgeDefinitions.sharpenPrice(weapon.Id) else nil,
						Repair = if c.wear > 0 then ForgeDefinitions.repairPrice(weapon.Id, c.wear) else nil,
					},
				})
			end
			table.insert(weapons, {
				weaponId = weapon.Id,
				name = weapon.DisplayName,
				copies = rows,
				copyPrice = if #copies < ForgeDefinitions.MaxCopies then ForgeDefinitions.copyPrice(weapon.Id, #copies) else nil,
			})
		end
	end
	local shields = {}
	for _, shield in ShieldDefinitions.Ordered do
		if inv.owns(player, "Shield", shield.Id) then
			local paint = inv.shieldDesign(player, shield.Id)
			local option = if paint then ForgeDefinitions.designOption(ForgeDefinitions.ShieldSlot, paint) else nil
			table.insert(shields, { shieldId = shield.Id, name = shield.DisplayName, paint = paint, paintText = if option then option.label else "Standard" })
		end
	end
	local slots = {}
	for _, slot in ForgeDefinitions.DesignSlots do
		local options = {}
		for _, o in slot.options do
			table.insert(options, { id = o.id, label = o.label })
		end
		table.insert(slots, { id = slot.id, label = slot.label, options = options })
	end
	local paints = {}
	for _, o in ForgeDefinitions.ShieldSlot.options do
		table.insert(paints, { id = o.id, label = o.label })
	end
	local products = {}
	for _, p in ForgeDefinitions.Products do
		table.insert(products, { key = p.key, label = p.label, robux = p.robux, denarii = p.denarii, ready = productReady(p) })
	end
	return {
		token = token,
		denarii = inv.getDenarii(player),
		credits = { Skip = inv.credits(player, "Skip"), Design = inv.credits(player, "Design") },
		weapons = weapons,
		shields = shields,
		slots = slots,
		paints = paints,
		products = products,
		note = ForgeDefinitions.ValueNote,
		bonus = ForgeDefinitions.PvEBonus,
		maxLevel = ForgeDefinitions.MaxLevel,
	}
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

local function refresh(player: Player)
	if deps.refresh then
		deps.refresh(player)
	end
end

-- Runs a pending Robux action if its credit is there. Returns (done, message).
local function applyPending(player: Player): (boolean, string?)
	local p = pending[player]
	if not p then
		return false, nil
	end
	local inv = deps.inventory
	if p.action == "Skip" and p.weaponId and p.uid then
		if inv.credits(player, "Skip") < 1 then
			return false, nil
		end
		local ok, message = inv.finishJobNow(player, p.weaponId, p.uid)
		if ok then
			inv.useCredit(player, "Skip") -- nothing to finish: the credit stays for later
		end
		pending[player] = nil
		refresh(player)
		return ok, message
	elseif p.action == "Design" and p.weaponId and p.uid then
		if inv.credits(player, "Design") < 1 then
			return false, nil
		end
		local ok, message = inv.startJob(player, p.weaponId, p.uid, "Design", p.slot, p.option)
		if ok then
			inv.useCredit(player, "Design")
		end
		pending[player] = nil
		refresh(player)
		return ok, message
	elseif p.action == "Paint" and p.shieldId and p.option then
		if inv.credits(player, "Design") < 1 then
			return false, nil
		end
		local ok, message = inv.setShieldDesign(player, p.shieldId, p.option)
		if ok then
			inv.useCredit(player, "Design")
		end
		pending[player] = nil
		refresh(player)
		return ok, message
	end
	pending[player] = nil
	return false, nil
end

-- Grants one Robux receipt exactly once. Returns true when it is (now or already) granted.
function TownServices.grant(player: Player, product: ForgeDefinitions.Product, purchaseId: string): boolean
	local inv = deps.inventory
	if inv.hasReceipt(player, purchaseId) then
		return true
	end
	if product.denarii then
		inv.addDenarii(player, product.denarii)
	end
	for key, count in product.credits or {} do
		inv.addCredit(player, key, count)
	end
	inv.recordReceipt(player, purchaseId)
	local _, message = applyPending(player)
	if deps.save and not deps.save(player) then
		return false -- not saved: Roblox asks again later, the receipt id prevents a double grant
	end
	deps.fire(player, "ForgeUpdate", { state = smithState(player, nil), message = message or ("Gekauft: " .. product.label), ok = true })
	return true
end

-- The NPC prompts: open an offer (or explain why not).
function TownServices.openForge(player: Player)
	local why = refusal(player, smithAt(), ForgeDefinitions.UseDistance)
	if why then
		deps.fire(player, "Refused", { title = "SCHMIEDE", text = why })
		return
	end
	local offer = newOffer(player, "Forge")
	deps.fire(player, "ForgeOffer", smithState(player, offer.token))
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

local JOBS: { [string]: boolean } = { Harden = true, Sharpen = true, Repair = true, Copy = true, Design = true }

local function smithRequest(player: Player, action: string, data: { [string]: any }): { [string]: any }
	local inv = deps.inventory
	local weaponId, uid = data.weaponId, data.uid
	local function answer(ok: boolean, message: string, extra: { [string]: any }?): { [string]: any }
		local result: { [string]: any } = extra or {}
		result.ok, result.message, result.state = ok, message, smithState(player, data.token)
		return result
	end
	if action == "ForgeJob" then
		local kind = data.kind
		if typeof(kind) ~= "string" or not JOBS[kind] or typeof(weaponId) ~= "string" or not ForgeDefinitions.isSupported(weaponId) or (kind ~= "Copy" and typeof(uid) ~= "string") then
			return { ok = false, message = "Ungültige Anfrage." }
		end
		if kind == "Design" then
			local slot = ForgeDefinitions.designSlot(data.slot)
			if not slot or not ForgeDefinitions.designOption(slot, data.option) then
				return { ok = false, message = "Dieses Design gibt es nicht." }
			end
			if inv.credits(player, "Design") < 1 then
				pending[player] = { action = "Design", weaponId = weaponId, uid = uid, slot = data.slot, option = data.option }
				return answer(false, "Ein Design kostet Robux.", { needProduct = "DesignToken" })
			end
			local ok, message = inv.startJob(player, weaponId, uid, "Design", data.slot, data.option)
			if ok then
				inv.useCredit(player, "Design")
			end
			refresh(player)
			return answer(ok, message)
		end
		local ok, message, price = inv.startJob(player, weaponId, if typeof(uid) == "string" then uid else nil, kind :: any, nil, nil)
		refresh(player)
		if not ok and price > inv.getDenarii(player) then
			return answer(false, message, { needDenarii = price - inv.getDenarii(player) })
		end
		return answer(ok, message)
	elseif action == "Skip" then
		if typeof(weaponId) ~= "string" or typeof(uid) ~= "string" or not ForgeDefinitions.isSupported(weaponId) then
			return { ok = false, message = "Ungültige Anfrage." }
		end
		pending[player] = { action = "Skip", weaponId = weaponId, uid = uid }
		if inv.credits(player, "Skip") < 1 then
			return answer(false, "Vorspulen kostet Robux.", { needProduct = "ForgeSkip" })
		end
		local ok, message = applyPending(player)
		return answer(ok, message or "Für dieses Exemplar läuft keine Arbeit.")
	elseif action == "SetActive" then
		if typeof(weaponId) ~= "string" or typeof(uid) ~= "string" or not ForgeDefinitions.isSupported(weaponId) then
			return { ok = false, message = "Ungültige Anfrage." }
		end
		local ok, message = inv.setActiveCopy(player, weaponId, uid)
		refresh(player)
		return answer(ok, message)
	elseif action == "Paint" then
		local shieldId, option = data.shieldId, data.option
		if typeof(shieldId) ~= "string" or not ShieldDefinitions.ById[shieldId] or not ForgeDefinitions.designOption(ForgeDefinitions.ShieldSlot, option) then
			return { ok = false, message = "Ungültige Anfrage." }
		end
		pending[player] = { action = "Paint", shieldId = shieldId, option = option }
		if inv.credits(player, "Design") < 1 then
			return answer(false, "Eine Bemalung kostet Robux.", { needProduct = "DesignToken" })
		end
		local ok, message = applyPending(player)
		return answer(ok, message or "Ungültige Anfrage.")
	elseif action == "Buy" then
		local product = ForgeDefinitions.product(data.key)
		if not product or typeof(data.key) ~= "string" then
			return { ok = false, message = "Ungültige Anfrage." }
		end
		if not product.denarii and not pending[player] then
			return { ok = false, message = "Wofür soll gekauft werden? Wähle zuerst eine Arbeit." }
		end
		if product.productId ~= 0 then
			return { ok = true, message = "Kauf wird geöffnet ...", productId = product.productId }
		end
		if deps.isStudio and deps.isStudio() then
			studioReceipts += 1
			TownServices.grant(player, product, ("STUDIO-%d-%d"):format(player.UserId, studioReceipts))
			return answer(true, "Studio-Testkauf: " .. product.label, { studio = true })
		end
		return { ok = false, message = "Dieses Robux-Produkt ist noch nicht eingerichtet." }
	end
	return { ok = false, message = "Ungültige Anfrage." }
end

-- RomeRequest handler. Always answers a table { ok, message, ... }.
function TownServices.request(player: Player, action: unknown, payload: unknown): { [string]: any }
	local now = deps.now()
	if now - (lastRequest[player] or -math.huge) < REQUEST_INTERVAL or busy[player] then
		return { ok = false, message = "Einen Moment ..." }
	end
	lastRequest[player] = now
	if typeof(payload) ~= "table" or typeof(action) ~= "string" then
		return { ok = false, message = "Ungültige Anfrage." }
	end
	local data = payload :: { [string]: any }
	busy[player] = true
	local result: { [string]: any }
	if action == "ForgeJob" or action == "Skip" or action == "SetActive" or action == "Paint" or action == "Buy" then
		if not validOffer(player, "Forge", data.token) then
			result = { ok = false, message = "Das Angebot ist abgelaufen. Sprich den Schmied noch einmal an." }
		else
			local why = refusal(player, smithAt(), ForgeDefinitions.UseDistance)
			if why then
				result = { ok = false, message = why }
			else
				result = smithRequest(player, action, data)
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

-- Due jobs end by themselves; the weapon in hand follows.
function TownServices.tick(player: Player)
	if deps.inventory.settleJobs(player) then
		refresh(player)
		deps.fire(player, "ForgeUpdate", { state = smithState(player, nil), message = "Der Schmied hat eine Arbeit beendet.", ok = true })
	end
end

function TownServices.forget(player: Player)
	offers[player], lastRequest[player], busy[player], turns[player], pending[player] = nil, nil, nil, nil, nil
end

-- `smith` / `oracle`: where the NPCs stand now (they walk).
function TownServices.init(dependencies: Deps, smith: () -> Vector3?, oracle: () -> Vector3?)
	deps = dependencies
	smithAt, oracleAt = smith, oracle
end

-- The live wiring in the Hub: real services, remotes, NPC prompts and Robux receipts.
function TownServices.start(request: RemoteFunction, event: RemoteEvent, smith: BasePart?, oracle: BasePart?)
	local Server = script.Parent.Parent.Parent
	local InventoryService = require(Server.InventoryService) :: any
	local PlayerDataService = require(Server.PlayerDataService) :: any
	local PlayerCombatService = require(Server.PlayerCombatService) :: any
	local CombatUtil = require(Server.CombatUtil) :: any
	local MarketplaceService = game:GetService("MarketplaceService")
	local RunService = game:GetService("RunService")
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
		refresh = PlayerCombatService.refreshEquipment,
		save = PlayerDataService.flush,
		isStudio = function(): boolean
			return RunService:IsStudio()
		end,
	}, function(): Vector3?
		return if smith then smith.Position else nil
	end, function(): Vector3?
		return if oracle then oracle.Position else nil
	end)
	request.OnServerInvoke = function(player: Player, action: unknown, payload: unknown)
		return TownServices.request(player, action, payload)
	end
	MarketplaceService.ProcessReceipt = function(receipt: any): Enum.ProductPurchaseDecision
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		local product = ForgeDefinitions.product(receipt.ProductId)
		if not player or not product or not PlayerDataService.isReady(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local ok = TownServices.grant(player, product, tostring(receipt.PurchaseId))
		return if ok then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Players.PlayerRemoving:Connect(TownServices.forget)
	task.spawn(function()
		while true do
			task.wait(5)
			for _, player in Players:GetPlayers() do
				if PlayerDataService.isReady(player) then
					TownServices.tick(player)
				end
			end
		end
	end)
end

return TownServices
