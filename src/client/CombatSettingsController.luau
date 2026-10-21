--!strict
-- Compact combat setting on the right edge (display only, saved as a preference):
--   CAMERA   camera shake Full / Reduced / Off (CombatEffectsConfig)
-- There is only one control mode (Classic, ControlModeDefinitions). The value comes from the
-- server-owned Pref_* attribute (the saved profile); changes go through the SavePreference remote
-- (whitelisted there).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))

export type Settings = {
	getCameraShake: () -> string,
	onChanged: (callback: () -> ()) -> (),
}

local CombatSettingsController = {}

local CAMERA_ORDER = { "Full", "Reduced", "Off" }

function CombatSettingsController.start(edge: Frame, preferenceRemote: RemoteEvent?, notify: (text: string) -> ()): Settings
	local player = Players.LocalPlayer
	local changeListeners: { () -> () } = {}
	local camera = "Full"

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(44, 26)
	button.BackgroundColor3 = UiConfig.Panel
	button.BackgroundTransparency = 0.3
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 9
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextWrapped = true
	button.Text = "CAM\nFULL"
	button.LayoutOrder = 3
	button.Parent = edge
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local function changed()
		button.Text = "CAM\n" .. camera:upper()
		for _, callback in changeListeners do
			callback()
		end
	end

	local function fromAttribute()
		local saved = player:GetAttribute(Config.PreferencePrefix .. "CameraShake")
		if typeof(saved) == "string" and table.find(CAMERA_ORDER, saved) then
			camera = saved
		end
		changed()
	end

	button.Activated:Connect(function()
		camera = CAMERA_ORDER[(table.find(CAMERA_ORDER, camera) or 1) % #CAMERA_ORDER + 1]
		if preferenceRemote and player:GetAttribute(Config.PreferencePrefix .. "CameraShake") ~= camera then
			preferenceRemote:FireServer("CameraShake", camera)
		end
		notify("CAMERA SHAKE: " .. camera:upper())
		changed()
	end)
	player:GetAttributeChangedSignal(Config.PreferencePrefix .. "CameraShake"):Connect(fromAttribute)
	fromAttribute()

	return {
		getCameraShake = function()
			return camera
		end,
		onChanged = function(callback: () -> ())
			table.insert(changeListeners, callback)
		end,
	}
end

return CombatSettingsController
