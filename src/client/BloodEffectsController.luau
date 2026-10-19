--!strict
-- Stylized ZOMBIE blood (visual only, from server-confirmed hits). Players never see it unless
-- BloodConfig.PlayerBlood is on; the Hub never shows it (ArenaOnly). Mode comes from the player's
-- BloodFx preference (Auto / Stylized / Reduced / Off), resolved with BloodConfig.resolve:
--   Stylized  short dark-red particle burst plus a sand stain
--   Reduced   faint dark-red dust and a very faint stain, never limb blood
--   Off       nothing here: DamageEffectsController shows dust and sparks instead
-- Bursts are budgeted per second and scaled by the device quality (BloodConfig.Quality).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BloodConfig = require(Shared:WaitForChild("BloodConfig"))

export type Blood = {
	zombieHit: (position: Vector3, scale: number, direction: Vector3?, mode: string) -> (),
	setQuality: (quality: string) -> (),
}

-- The sand stains module (SandStainController.start); structural so no require is needed here
type Stains = {
	stain: (position: Vector3, faint: boolean) -> (),
	setQuality: (quality: string) -> (),
}

local BloodEffectsController = {}

local BURSTS_PER_SECOND = 10
local LIFETIME = 0.35

function BloodEffectsController.start(stains: Stains): Blood
	local quality = "High" :: any
	local budget = BURSTS_PER_SECOND
	local lastRefill = os.clock()

	local function allow(): boolean
		local now = os.clock()
		budget = math.min(BURSTS_PER_SECOND, budget + (now - lastRefill) * BURSTS_PER_SECOND)
		lastRefill = now
		if budget < 1 then
			return false
		end
		budget -= 1
		return true
	end

	local api = {} :: Blood
	function api.zombieHit(position: Vector3, scale: number, direction: Vector3?, mode: string)
		if mode == "Off" or not BloodConfig.EnableParticles and not BloodConfig.EnableSandStains then
			return
		end
		local faint = mode == "Reduced"
		if BloodConfig.EnableSandStains then
			stains.stain(position, faint)
		end
		if not BloodConfig.EnableParticles or not allow() then
			return
		end
		local settings = BloodConfig.Quality[quality :: any]
		local count = math.clamp(math.floor(6 * scale * settings.ParticleScale + 0.5), 2, BloodConfig.MaxParticlesPerHit)
		local facing = if direction and direction.Magnitude > 0.01 then direction.Unit else Vector3.yAxis

		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.CastShadow = false
		holder.Transparency = 1
		holder.Size = Vector3.one * 0.2
		holder.CFrame = CFrame.lookAt(position, position + facing + Vector3.new(0, 0.6, 0))
		holder.Parent = Workspace

		local emitter = Instance.new("ParticleEmitter")
		local color = if faint then BloodConfig.ReducedColor else BloodConfig.Color
		emitter.Color = ColorSequence.new(color, BloodConfig.ColorDark)
		emitter.Size = NumberSequence.new(0.3 * scale * settings.ParticleScale, 0.05)
		emitter.Speed = NumberRange.new(6, 12)
		emitter.Lifetime = NumberRange.new(LIFETIME * 0.7, LIFETIME)
		emitter.Acceleration = Vector3.new(0, -35, 0)
		emitter.SpreadAngle = Vector2.new(35, 35)
		emitter.LightEmission = 0
		emitter.Transparency = NumberSequence.new(0, 1)
		emitter.Rate = 0
		emitter.EmissionDirection = Enum.NormalId.Front
		emitter.Parent = holder
		emitter:Emit(if faint then math.ceil(count / 2) else count)

		task.delay(LIFETIME * 2 + 0.2, function()
			holder:Destroy()
		end)
	end
	function api.setQuality(newQuality: string)
		if BloodConfig.Quality[newQuality :: any] then
			quality = newQuality
			stains.setQuality(newQuality)
		end
	end
	return api
end

return BloodEffectsController
