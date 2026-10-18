--!strict
-- Draws the per-player state of the equipment wall locally: plaque status (LOCKED / OWNED /
-- EQUIPPED), prompt text (BUY / EQUIP) and a highlight on equipped items. All decisions happen
-- on the server; this only reads the player's inventory attributes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local ShopController = {}

type Names = {
	tag: string,
	aura: string,
	equippedWeapon: string,
	equippedShield: string,
	ownedWeapons: string,
	ownedShields: string,
}

local function splitSet(value: unknown): { [string]: boolean }
	local set = {}
	if typeof(value) == "string" then
		for id in value:gmatch("[^,]+") do
			set[id] = true
		end
	end
	return set
end

function ShopController.start(names: Names)
	local player = Players.LocalPlayer

	local function refreshItem(item: Instance)
		local kind = item:GetAttribute("ItemKind")
		local id = item:GetAttribute("ItemId")
		local price = tonumber(item:GetAttribute("Price")) or 0
		if typeof(id) ~= "string" then
			return
		end
		local isWeapon = kind == "Weapon"
		local owned = splitSet(player:GetAttribute(if isWeapon then names.ownedWeapons else names.ownedShields))[id] == true
		local equipped = player:GetAttribute(if isWeapon then names.equippedWeapon else names.equippedShield) == id
		local aura = tonumber(player:GetAttribute(names.aura)) or 0

		local status = item:FindFirstChild("Status", true)
		if status and status:IsA("TextLabel") then
			if equipped then
				status.Text = "EQUIPPED"
				status.TextColor3 = Color3.fromRGB(120, 255, 140)
			elseif owned then
				status.Text = "OWNED"
				status.TextColor3 = Color3.fromRGB(200, 230, 255)
			else
				status.Text = if aura >= price then "LOCKED · affordable" else "LOCKED"
				status.TextColor3 = if aura >= price then Color3.fromRGB(255, 220, 120) else Color3.fromRGB(190, 190, 190)
			end
		end

		local prompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			if equipped then
				prompt.ActionText = "Equipped"
			elseif owned then
				prompt.ActionText = "EQUIP"
			else
				prompt.ActionText = ("BUY (%d AURA)"):format(price)
			end
		end

		local display = item:FindFirstChild("Display")
		if display then
			local highlight = display:FindFirstChild("EquippedHighlight")
			if equipped and not highlight then
				local h = Instance.new("Highlight")
				h.Name = "EquippedHighlight"
				h.FillTransparency = 1
				h.OutlineColor = Color3.fromRGB(120, 255, 140)
				h.DepthMode = Enum.HighlightDepthMode.Occluded
				h.Parent = display
			elseif not equipped and highlight then
				highlight:Destroy()
			end
		end
	end

	local function refreshAll()
		for _, item in CollectionService:GetTagged(names.tag) do
			refreshItem(item)
		end
	end

	CollectionService:GetInstanceAddedSignal(names.tag):Connect(function(item)
		task.defer(refreshItem, item) -- wait for descendants to replicate
	end)
	for _, attribute in { names.aura, names.equippedWeapon, names.equippedShield, names.ownedWeapons, names.ownedShields } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshAll)
	end
	refreshAll()
end

return ShopController
