--!strict
-- Subtle combat camera impulses (presentation only). They offset the rendered camera for a moment
-- and decay quickly; aim, hit detection and the server never read the camera. The strength follows
-- the player's CameraShake preference: Full = 1, Reduced = CombatEffectsConfig.Camera.ReducedScale,
-- Off = no shake at all. Impulses are only triggered for the own character's hits / damage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatEffectsConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CombatEffectsConfig"))

export type CombatCamera = {
	impulse: (strength: number) -> (),
	setShake: (mode: string) -> (),
}

local CombatCameraController = {}

local BIND_NAME = "OttiCombatCamera"

function CombatCameraController.start(): CombatCamera
	local settings = CombatEffectsConfig.Camera
	local magnitude = 0
	local multiplier = 1

	local api = {} :: CombatCamera
	function api.impulse(strength: number)
		if multiplier <= 0 then
			return
		end
		magnitude = math.min(settings.MaxOffset, math.max(magnitude, strength * multiplier))
	end
	function api.setShake(mode: string)
		multiplier = if mode == "Off" then 0 elseif mode == "Reduced" then settings.ReducedScale else 1
		if multiplier <= 0 then
			magnitude = 0
		end
	end

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		magnitude *= math.exp(-settings.Decay * dt)
		if magnitude < 0.005 then
			magnitude = 0
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local offset = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, 0) * magnitude
		camera.CFrame = camera.CFrame * CFrame.new(offset)
	end)

	return api
end

return CombatCameraController
