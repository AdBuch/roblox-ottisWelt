--!strict
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
controls:Disable()
workspace:GetAttributeChangedSignal("HeroQAStage"):Connect(function()
	if workspace:GetAttribute("HeroQAStage")=="NetPreview" then
		local model=workspace:FindFirstChild(tostring(workspace:GetAttribute("HeroQANetBoss")),true)
		if model and model:IsA("Model") and model.PrimaryPart then
			local p=model.PrimaryPart.Position
			workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
			workspace.CurrentCamera.CFrame=CFrame.lookAt(p+Vector3.new(14,8,-20),p+Vector3.new(0,0,-6))
		end
	end
end)
repeat task.wait(0.2) until workspace:GetAttribute("HeroQAStage") == "Lineup"
local camera = workspace.CurrentCamera :: Camera
local center = workspace:GetAttribute("HeroQACenter") :: Vector3
camera.CameraType = Enum.CameraType.Scriptable
camera.CFrame = CFrame.lookAt(center + Vector3.new(18, 9, -35), center)
print("[HeroQA] CLIENT lineup camera ready")
task.wait(1)
for _,model in workspace:GetDescendants() do
	if model:IsA("Model") and model:GetAttribute("SkinnedRig") then
		local total,animated=0,0
		for _,bone in model:GetDescendants() do
			if bone:IsA("Bone") then
				total+=1
				if bone.Transform~=CFrame.identity then animated+=1 end
			end
		end
		assert(animated>0,"[HeroQA] No client bone animation: "..model.Name)
		print("[HeroQA] CLIENT SKIN",model.Name,total,animated)
	end
end
