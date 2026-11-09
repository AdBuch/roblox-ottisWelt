--!strict
-- Hub safety rules (server-side, height and region checks four times a second):
--   * EDGE   a player who went over the rim of the world disc (outside its radius and below the
--            sea) or fell deep below the island is placed ONCE at the forum fountain: progress,
--            items and Denarii stay as they are (no death). A short grace period follows, so a
--            single fall never triggers twice, and the fountain lies far from any edge.
--   * SAND   a lobby player who somehow gets onto the arena sand in the Hub returns to the lobby
--            respawn (the rule of the former lobby safety net).
-- Normal arena deaths, spawn choice, intro and returns are untouched: those happen in the Arena
-- place or through HubMatchService.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ColosseumLayout = require(ReplicatedStorage.Shared.ColosseumLayout)
local RomeLayout = require(script.Parent.RomeLayout)

local WorldEdgeService = {}

WorldEdgeService.DeepFall = -45 -- below any island ground and the harbour floor
WorldEdgeService.Grace = 3 -- seconds after a placement without another check

export type Verdict = "Edge" | "Sand" | nil

-- What happened to a player at `position` (pure, for tests).
function WorldEdgeService.classify(position: Vector3): Verdict
	local disc = RomeLayout.Disc
	local dx, dz = position.X - disc.x, position.Z - disc.z
	local outside = dx * dx + dz * dz > (disc.radius + disc.rim) ^ 2
	if position.Y < WorldEdgeService.DeepFall or (outside and position.Y < RomeLayout.Levels.Water - 3) then
		return "Edge"
	end
	local ex = position.X / (ColosseumLayout.SemiAxisX + ColosseumLayout.PodiumThickness - 0.5)
	local ez = position.Z / (ColosseumLayout.SemiAxisZ + ColosseumLayout.PodiumThickness - 0.5)
	if ex * ex + ez * ez <= 1 and position.Y >= ColosseumLayout.FloorTop - 10 and position.Y < ColosseumLayout.FloorTop + ColosseumLayout.PodiumHeight + 2 then
		return "Sand"
	end
	return nil
end

function WorldEdgeService.start(forumRespawn: () -> CFrame?, lobbyRespawn: CFrame, notify: (player: Player, kind: string) -> ())
	local graceUntil: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(player)
		graceUntil[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if character and root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and now >= (graceUntil[player] or 0) then
					local verdict = WorldEdgeService.classify(root.Position)
					local target: CFrame? = nil
					if verdict == "Edge" then
						target = forumRespawn() or lobbyRespawn
					elseif verdict == "Sand" then
						target = lobbyRespawn
					end
					if target then
						graceUntil[player] = now + WorldEdgeService.Grace
						root.AssemblyLinearVelocity = Vector3.zero
						root.AssemblyAngularVelocity = Vector3.zero
						character:PivotTo(target + Vector3.new(0, 3.5, 0))
						player:SetAttribute("EdgeRespawns", (player:GetAttribute("EdgeRespawns") or 0) + (if verdict == "Edge" then 1 else 0))
						notify(player, verdict :: string)
					end
				end
			end
		end
	end)
end

return WorldEdgeService
