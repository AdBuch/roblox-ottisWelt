--!strict
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
controls:Disable()
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
