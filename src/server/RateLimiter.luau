--!strict
-- Per-player, per-action cooldowns for remote requests (server only).
--   local limiter = RateLimiter.new({ Watch = 2, Refresh = 3 }, 0.5)
--   if not limiter:allow(player, "Watch") then return end

local Players = game:GetService("Players")

export type Limiter = {
	allow: (player: Player, action: string) -> boolean,
}

local RateLimiter = {}

function RateLimiter.new(cooldowns: { [string]: number }, default: number): Limiter
	local last: { [Player]: { [string]: number } } = {}
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
	end)
	return {
		allow = function(player: Player, action: string): boolean
			local now = os.clock()
			local perPlayer = last[player]
			if not perPlayer then
				perPlayer = {}
				last[player] = perPlayer
			end
			local cooldown = cooldowns[action] or default
			if now - (perPlayer[action] or -math.huge) < cooldown then
				return false
			end
			perPlayer[action] = now
			return true
		end,
	}
end

return RateLimiter
