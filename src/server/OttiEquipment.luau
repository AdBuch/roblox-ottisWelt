--!strict
-- All weapons stay bound to their authored hand bones; only visibility changes.
local Equipment={}
function Equipment.refresh(model: Model)
	if model:GetAttribute("HeroId")~="Otti" or not model:GetAttribute("SkinnedRig") then return end
	local drawn=model:GetAttribute("SwordDrawn")==true
	local retiarius=model:GetAttribute("WeaponMode")=="Retiarius"
	local visible={Otti_Sword=drawn and not retiarius,Otti_Shield=drawn and not retiarius,
		Otti_Trident=drawn and retiarius,Otti_NetHeld=drawn and retiarius and model:GetAttribute("NetReleased")~=true,
		Otti_Sheathed=not drawn}
	for name,show in visible do
		local part=model:FindFirstChild(name)
		if part and part:IsA("BasePart") then part.Transparency=if show then 0 else 1 end
	end
end
function Equipment.select(model: Model,mode: string)
	model:SetAttribute("WeaponMode",mode)
	Equipment.refresh(model)
end
return Equipment
