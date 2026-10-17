--!strict
-- Safety net: any player found outside the arena (or fallen through the floor) is
-- teleported back to the spawn. Checked twice per second, not every frame.

local Players = game:GetService("Players")

local Arena = require(script.Parent.Arena)

local PREFIX = "[OttiArena][Server]"
local CHECK_INTERVAL = 0.5
local MAX_HEIGHT_ABOVE_WALL = 20

local ArenaSafetyService = {}

local function check()
	local maxY = Arena.Layout.FloorTop + Arena.Layout.WallHeight + MAX_HEIGHT_ABOVE_WALL
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") then
			local position = root.Position
			if not Arena.isInside(position, 1) or position.Y > maxY then
				root.AssemblyLinearVelocity = Vector3.zero
				character:PivotTo(Arena.getSpawnCFrame())
				print(PREFIX, player.Name, "was outside the arena and was returned to the spawn")
			end
		end
	end
end

function ArenaSafetyService.init()
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			check()
		end
	end)
end

return ArenaSafetyService
