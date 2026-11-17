--!strict
-- Install once in each Place. Fulfillment depends only on the server catalog and the profile lease.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ForgeDefinitions = require(ReplicatedStorage.Shared.ForgeDefinitions)
local InventoryService = require(script.Parent.InventoryService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local PurchaseService = {}
local LOAD_WAIT_SECONDS = 20
local started = false
local pendingFeedback: { [Player]: { [string]: boolean } } = setmetatable({}, { __mode = "k" })

function PurchaseService.init(onGranted: ((Player, ForgeDefinitions.Product) -> ())?)
	if started then
		return
	end
	started = true
	MarketplaceService.ProcessReceipt = function(receipt: any): Enum.ProductPurchaseDecision
		local pending = Enum.ProductPurchaseDecision.NotProcessedYet
		if typeof(receipt) ~= "table" or typeof(receipt.PurchaseId) ~= "string" or receipt.PurchaseId == ""
			or typeof(receipt.PlayerId) ~= "number" or receipt.PlayerId <= 0 or receipt.PlayerId % 1 ~= 0
			or typeof(receipt.ProductId) ~= "number" or receipt.ProductId <= 0 or receipt.ProductId % 1 ~= 0 then
			return pending
		end
		local product = ForgeDefinitions.product(receipt.ProductId)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not product or not player then
			return pending
		end
		local deadline = os.clock() + LOAD_WAIT_SECONDS
		while player.Parent and PlayerDataService.getStatus(player) == "Loading" and os.clock() < deadline do
			task.wait(0.1)
		end
		if not player.Parent or not PlayerDataService.canPersist(player) then
			return pending
		end

		local ok, granted = pcall(function()
			local applied, isNew = InventoryService.applyPurchase(player, product, receipt.PurchaseId)
			if not applied then
				return false
			end
			if onGranted and isNew then
				local feedback = pendingFeedback[player] or {}
				feedback[receipt.PurchaseId] = true
				pendingFeedback[player] = feedback
			end
			-- A local duplicate may still be uncommitted. Only Task 2 can confirm this revision.
			return PlayerDataService.flush(player)
		end)
		if not ok then
			warn("[OttiArena][Purchase]", "Receipt processing failed; Roblox can redeliver it")
		end
		if not ok or granted ~= true then
			return pending
		end

		local feedback = pendingFeedback[player]
		if onGranted and feedback and feedback[receipt.PurchaseId] then
			feedback[receipt.PurchaseId] = nil
			if player.Parent then
				task.defer(onGranted, player, product)
			end
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

return PurchaseService
