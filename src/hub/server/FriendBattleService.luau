--!strict
-- Roblox friends of each Hub player, resolved on the SERVER (Players:GetFriendsAsync) and cached
-- for ExperienceConfig.Spectating.FriendCacheSeconds: one paged request per player per cache
-- period (prefetched on join), never per frame or per list refresh. Clients never claim
-- friendships. Studio adds ExperienceConfig.Studio.MockFriendIds (and the mock "Studio Friend").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)

local PREFIX = "[OttiArena][Friends]"
local MAX_FRIENDS = 200

export type FriendSet = { [number]: string } -- userId -> display name

type Cached = { friends: FriendSet, at: number, loading: boolean }

local FriendBattleService = {}

local cache: { [Player]: Cached } = {}

-- Fake participant id used by Studio mock battles (see LiveBattlesService).
FriendBattleService.MockFriendId = 1

local function fetch(player: Player): FriendSet
	local friends: FriendSet = {}
	local ok, err = pcall(function()
		local pages = Players:GetFriendsAsync(player.UserId)
		local count = 0
		while count < MAX_FRIENDS do
			for _, item in pages:GetCurrentPage() :: { any } do
				friends[item.Id] = if typeof(item.DisplayName) == "string" and item.DisplayName ~= "" then item.DisplayName else item.Username
				count += 1
			end
			if pages.IsFinished then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if not ok then
		warn(PREFIX, ("Friend list for %s unavailable: %s"):format(player.Name, tostring(err)))
	end
	if EnvironmentConfig.isStudio() then
		for i, userId in ExperienceConfig.Studio.MockFriendIds do
			friends[userId] = friends[userId] or ("MockFriend" .. i)
		end
		if ExperienceConfig.Studio.MockFriendSelf then
			friends[FriendBattleService.MockFriendId] = "Studio Friend"
		end
	end
	return friends
end

-- Friend set of a player (cached; refreshes in the background when old).
function FriendBattleService.friendsOf(player: Player): FriendSet
	local entry = cache[player]
	local now = os.clock()
	if entry and (now - entry.at < ExperienceConfig.Spectating.FriendCacheSeconds or entry.loading) then
		return entry.friends
	end
	if entry then
		entry.loading = true
		task.spawn(function()
			local friends = fetch(player)
			if cache[player] == entry then
				entry.friends, entry.at, entry.loading = friends, os.clock(), false
			end
		end)
		return entry.friends
	end
	local created: Cached = { friends = {}, at = now, loading = true }
	cache[player] = created
	created.friends = fetch(player)
	created.at, created.loading = os.clock(), false
	return created.friends
end

function FriendBattleService.init()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(FriendBattleService.friendsOf, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(FriendBattleService.friendsOf, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
	end)
end

return FriendBattleService
