--!strict
-- Hero monuments reuse OttiModel / CompanionModel so the statues match their boss silhouettes,
-- then turns it into stone: no Humanoid, no lights, everything anchored, non-colliding and never
-- queried, fur and cloth in marble, armour and weapons in bronze, scaled up with Model:ScaleTo.
-- The pedestal (built by LobbyService) is the only collision.

local OttiModel = require(script.Parent.OttiModel)
local CompanionModel = require(script.Parent.CompanionModel)

local MARBLE = Color3.fromRGB(226, 218, 202)
local MARBLE_SHADE = Color3.fromRGB(196, 186, 168)
local BRONZE = Color3.fromRGB(184, 140, 70)

local LobbyStatue = {}

local METALS: { [Enum.Material]: boolean } = {
	[Enum.Material.Metal] = true,
	[Enum.Material.CorrodedMetal] = true,
}

-- Builds the statue standing on `base` (a CFrame on the pedestal top, -Z = where Otti looks).
function LobbyStatue.build(parent: Instance, base: CFrame, scale: number, bossId: string?): Model
	local id = bossId or "Otti"
	local rig = if CompanionModel.has(id) then CompanionModel.build(id) else OttiModel.build()
	local model = rig.model
	model.Name = id .. "Statue"
	model:SetAttribute("BossName", nil)
	rig.humanoid:Destroy()
	for _, part in rig.sheathedParts do
		part:Destroy() -- the statue holds the drawn gladius only
	end
	for _, item in model:GetDescendants() do
		if item:IsA("PointLight") or item:IsA("ParticleEmitter") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.CollisionGroup = "Default"
			if item.Transparency < 1 then
				local metal = METALS[item.Material] == true
				item.Material = if metal then Enum.Material.Metal else Enum.Material.Marble
				-- darker fur areas keep a slightly darker marble so the face stays readable
				local dark = item.Color.R + item.Color.G + item.Color.B < 0.75
				item.Color = if metal then BRONZE elseif dark then MARBLE_SHADE else MARBLE
			end
		end
	end
	model:ScaleTo(scale)
	-- Stand it on the pedestal: lowest point exactly on the base
	model:PivotTo(base)
	local box, size = model:GetBoundingBox()
	local bottom = box.Position.Y - size.Y / 2
	model:PivotTo(base + Vector3.new(0, base.Position.Y - bottom, 0))
	model.Parent = parent
	return model
end

return LobbyStatue
