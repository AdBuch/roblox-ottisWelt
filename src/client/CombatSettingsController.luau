--!strict
-- Compact combat settings on the right edge (display / input only, saved as preferences):
--   CLASSIC ⇄ WILD   control mode (ControlModeDefinitions). A switch requested during an attack waits
--                    until the attack finished; switching cancels unfinished gestures and ends a block
--                    (InputController.onModeChanged).
--   BLOOD            Auto / Stylized / Reduced / Off (BloodConfig, never changes combat)
--   CAMERA           camera shake Full / Reduced / Off (CombatEffectsConfig)
-- Values come from the server-owned Pref_* attributes (the saved profile) and changes are sent
-- through the SavePreference remote (whitelisted there).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ControlModeDefinitions = require(Shared:WaitForChild("ControlModeDefinitions"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))

export type Settings = {
	getMode: () -> string,
	getBlood: () -> string,
	getCameraShake: () -> string,
	onModeChanged: (callback: (mode: string) -> ()) -> (),
	onChanged: (callback: () -> ()) -> (),
}

local CombatSettingsController = {}

local BLOOD_ORDER = { "Auto", "Stylized", "Reduced", "Off" }
local CAMERA_ORDER = { "Full", "Reduced", "Off" }

local function pill(parent: Instance, text: string, order: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(44, 26)
	b.BackgroundColor3 = UiConfig.Panel
	b.BackgroundTransparency = 0.3
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 9
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextWrapped = true
	b.Text = text
	b.LayoutOrder = order
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	return b
end

function CombatSettingsController.start(edge: Frame, preferenceRemote: RemoteEvent?, notify: (text: string) -> ()): Settings
	local player = Players.LocalPlayer
	local modeListeners: { (mode: string) -> () } = {}
	local changeListeners: { () -> () } = {}
	local mode = ControlModeDefinitions.Default :: string
	local pendingMode: string? = nil
	local blood = "Auto"
	local camera = "Full"

	local modeButton = pill(edge, "CLASSIC", 3)
	local bloodButton = pill(edge, "BLOOD\nAUTO", 4)
	local cameraButton = pill(edge, "CAM\nFULL", 5)

	local function refreshLabels()
		modeButton.Text = (if pendingMode then pendingMode else mode):upper()
		modeButton.TextColor3 = if mode == "Wild" then UiConfig.Gold else Color3.new(1, 1, 1)
		bloodButton.Text = "BLOOD\n" .. blood:upper()
		cameraButton.Text = "CAM\n" .. camera:upper()
	end

	local function save(key: string, value: string)
		if preferenceRemote and player:GetAttribute(Config.PreferencePrefix .. key) ~= value then
			preferenceRemote:FireServer(key, value)
		end
	end

	-- An attack in progress? (server-published attack timing on the own character)
	local function attacking(): boolean
		local character = player.Character
		if not character then
			return false
		end
		local start = tonumber(character:GetAttribute("AttackStart")) or 0
		local length = tonumber(character:GetAttribute("AttackLength")) or 0
		return Workspace:GetServerTimeNow() < start + length
	end

	local function applyMode(newMode: string, persist: boolean)
		if not ControlModeDefinitions.isMode(newMode) or newMode == mode then
			pendingMode = nil
			refreshLabels()
			return
		end
		if attacking() then
			-- Delayed until the current attack finished
			pendingMode = newMode
			refreshLabels()
			task.delay(0.15, function()
				if pendingMode == newMode then
					applyMode(newMode, persist)
				end
			end)
			return
		end
		pendingMode = nil
		mode = newMode
		refreshLabels()
		if persist then
			save("ControlMode", newMode)
			notify("CONTROLS: " .. newMode:upper())
		end
		for _, callback in modeListeners do
			callback(newMode)
		end
	end

	local function fromAttributes()
		local saved = player:GetAttribute(Config.PreferencePrefix .. "ControlMode")
		if typeof(saved) == "string" and saved ~= "" then
			applyMode(saved, false)
		end
		local savedBlood = player:GetAttribute(Config.PreferencePrefix .. "BloodFx")
		if typeof(savedBlood) == "string" and table.find(BLOOD_ORDER, savedBlood) then
			blood = savedBlood
		end
		local savedCamera = player:GetAttribute(Config.PreferencePrefix .. "CameraShake")
		if typeof(savedCamera) == "string" and table.find(CAMERA_ORDER, savedCamera) then
			camera = savedCamera
		end
		refreshLabels()
		for _, callback in changeListeners do
			callback()
		end
	end

	modeButton.Activated:Connect(function()
		applyMode(if (pendingMode or mode) == "Classic" then "Wild" else "Classic", true)
	end)
	bloodButton.Activated:Connect(function()
		blood = BLOOD_ORDER[(table.find(BLOOD_ORDER, blood) or 1) % #BLOOD_ORDER + 1]
		save("BloodFx", blood)
		refreshLabels()
		notify("BLOOD EFFECTS: " .. blood:upper())
		for _, callback in changeListeners do
			callback()
		end
	end)
	cameraButton.Activated:Connect(function()
		camera = CAMERA_ORDER[(table.find(CAMERA_ORDER, camera) or 1) % #CAMERA_ORDER + 1]
		save("CameraShake", camera)
		refreshLabels()
		notify("CAMERA SHAKE: " .. camera:upper())
		for _, callback in changeListeners do
			callback()
		end
	end)
	for _, key in { "ControlMode", "BloodFx", "CameraShake" } do
		player:GetAttributeChangedSignal(Config.PreferencePrefix .. key):Connect(fromAttributes)
	end
	fromAttributes()

	return {
		getMode = function()
			return mode
		end,
		getBlood = function()
			return blood
		end,
		getCameraShake = function()
			return camera
		end,
		onModeChanged = function(callback: (mode: string) -> ())
			table.insert(modeListeners, callback)
		end,
		onChanged = function(callback: () -> ())
			table.insert(changeListeners, callback)
		end,
	}
end

return CombatSettingsController
