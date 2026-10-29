--!strict
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MatchRequest") :: RemoteFunction
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn = "StudioBossTests", false
local panel = Instance.new("Frame")
panel.Size, panel.Position = UDim2.fromOffset(330, 66), UDim2.new(0.5, -165, 1, -76)
panel.BackgroundColor3, panel.BackgroundTransparency = Color3.fromRGB(30, 27, 24), 0.1
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local label = Instance.new("TextLabel")
label.Size, label.BackgroundTransparency = UDim2.new(1, 0, 0, 22), 1
label.Text, label.TextColor3, label.TextSize = "STUDIO · BOSSKAMPF TESTEN", Color3.fromRGB(235, 212, 160), 12
label.Parent = panel
for i, id in { "Otti", "Kroko", "Schili" } do
	local button = Instance.new("TextButton")
	button.Position, button.Size = UDim2.fromOffset(8 + (i - 1) * 108, 27), UDim2.fromOffset(98, 30)
	button.BackgroundColor3, button.TextColor3 = Color3.fromRGB(86, 65, 42), Color3.new(1, 1, 1)
	button.Text, button.TextSize, button.Parent = id, 16, panel
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
	button.Activated:Connect(function()
		local ok, response = pcall(function() return remote:InvokeServer("StudioBoss", id) end)
		label.Text = if ok and response.ok then id .. " · NEUSTART IN BIS ZU 14 SEK." else "BITTE KURZ WARTEN UND ERNEUT WÄHLEN"
	end)
end
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
