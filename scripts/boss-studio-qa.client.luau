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
