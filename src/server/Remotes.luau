--!strict
-- Resolves the RemoteEvents that Rojo creates in ReplicatedStorage.Remotes.
-- If one is missing (Rojo not synced), it warns and creates it so the game still runs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PREFIX = "[OttiArena][Server]"

local function getFolder(): Instance
	local folder = ReplicatedStorage:FindFirstChild(Config.RemotesFolderName)
	if folder then
		return folder
	end
	warn(PREFIX, "ReplicatedStorage.Remotes is missing (should come from Rojo); creating it at runtime")
	local created = Instance.new("Folder")
	created.Name = Config.RemotesFolderName
	created.Parent = ReplicatedStorage
	return created
end

local folder = getFolder()

local function getRemote(name: string): RemoteEvent
	local remote = folder:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	warn(PREFIX, ("Remotes.%s is missing (should come from Rojo); creating it at runtime"):format(name))
	local created = Instance.new("RemoteEvent")
	created.Name = name
	created.Parent = folder
	return created
end

return table.freeze({
	CombatAction = getRemote(Config.CombatActionRemoteName),
	ShieldBlock = getRemote(Config.ShieldBlockRemoteName),
	CombatFeedback = getRemote(Config.CombatFeedbackRemoteName),
	SavePreference = getRemote(Config.PreferenceRemoteName),
})
