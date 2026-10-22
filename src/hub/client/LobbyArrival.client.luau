--!strict
-- Align the camera once on a direct Hub arrival. The server publishes the placement as an
-- attribute so it is still available if this script starts after the character was positioned.
-- Later respawns and Arena returns keep the normal Roblox camera behavior.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local ATTRIBUTE = "HubArrivalCFrame"
local applied = false
local pending = false

local function alignArrival()
	local target = player:GetAttribute(ATTRIBUTE)
	if applied or pending or typeof(target) ~= "CFrame" then
		return
	end
	pending = true
	task.spawn(function()
		local deadline = os.clock() + 10
		while player.Parent and os.clock() < deadline do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local camera = Workspace.CurrentCamera
			if root and root:IsA("BasePart") and camera and (root.Position - target.Position).Magnitude < 8 then
				-- Apply after Roblox's camera update, then immediately release camera control.
				RunService:BindToRenderStep("OttiHubArrival", Enum.RenderPriority.Camera.Value + 1, function()
					RunService:UnbindFromRenderStep("OttiHubArrival")
					if player.Character == character and root.Parent and Workspace.CurrentCamera == camera then
						local focus = root.Position + Vector3.new(0, 2, 0)
						camera.CFrame = CFrame.lookAt(root.Position - target.LookVector * 8 + Vector3.new(0, 5, 0), focus)
						camera.Focus = CFrame.new(focus)
					end
				end)
				applied = true
				pending = false
				return
			end
			task.wait(0.05)
		end
		pending = false
	end)
end

player:GetAttributeChangedSignal(ATTRIBUTE):Connect(alignArrival)
alignArrival()
