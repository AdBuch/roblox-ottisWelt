--!strict
-- The Hub's gateways (server-side, position checks five times a second):
--   * PORTALS  the closed gates of Kroko and Schili lead down to the gathering cellars under the
--              arena (team battles / co-op zombies), and each cellar's gate leads back up into
--              the hall. A player in the lobby state who walks into a gateway's box is placed at
--              its target; a short pause follows, so nobody bounces between two gateways.
--   * SAND     the arena is closed in the Hub. A player who got onto the sand anyway (a jump from
--              the podium) is put back into Otti's hall.
-- Nothing here starts a fight: the mosaics in the cellars do that (LobbyPadService), and the solo
-- mosaic in Otti's gateway.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameStates = require(ReplicatedStorage.Shared.GameStates)

export type Portal = { name: string, cframe: CFrame, size: Vector3, target: CFrame, text: string }

local CellarService = {}

CellarService.Interval = 0.2
CellarService.Pause = 1.5 -- seconds after a placement without another one

-- The portal a position lies in, or nil (pure, for tests).
function CellarService.portalAt(portals: { Portal }, position: Vector3): Portal?
	for _, portal in portals do
		local o = portal.cframe:PointToObjectSpace(position)
		if math.abs(o.X) <= portal.size.X / 2 and math.abs(o.Y) <= portal.size.Y / 2 and math.abs(o.Z) <= portal.size.Z / 2 then
			return portal
		end
	end
	return nil
end

-- `isOnSand`: the closed arena's floor; `hall`: where a player found there is put.
-- `notify`: a short line for the player (where they are now).
function CellarService.start(portals: { Portal }, isOnSand: (position: Vector3) -> boolean, hall: CFrame, notify: (player: Player, text: string) -> ())
	local pauseUntil: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(player)
		pauseUntil[player] = nil
	end)
	local function place(player: Player, character: Model, root: BasePart, target: CFrame, text: string)
		pauseUntil[player] = os.clock() + CellarService.Pause
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(target + Vector3.new(0, 3.5, 0))
		notify(player, text)
	end
	task.spawn(function()
		while true do
			task.wait(CellarService.Interval)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if character and root and root:IsA("BasePart") and humanoid and humanoid.Health > 0
					and now >= (pauseUntil[player] or 0)
					and GameStates.isInLobby(player:GetAttribute(GameStates.StateAttribute)) then
					local portal = CellarService.portalAt(portals, root.Position)
					if portal then
						place(player, character, root, portal.target, portal.text)
					elseif isOnSand(root.Position) then
						place(player, character, root, hall, "The arena is closed · your fight starts at the gate")
					end
				end
			end
		end
	end)
end

return CellarService
