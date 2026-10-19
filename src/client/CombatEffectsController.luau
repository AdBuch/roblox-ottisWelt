--!strict
-- Routes server-validated hit events to the presentation controllers (display only):
--   DamageFx(position, kind, scale, direction, extra)   kind Zombie | Player | Boss | Block
--   extra { category, attackerId, victimId, heavy, perfect, projectile, killed, armored }
-- Per weapon category (CombatEffectsConfig): sparks and dust (DamageEffectsController), zombie blood
-- and sand stains (BloodEffectsController, by the player's BloodFx preference), a bow arrow that
-- sticks briefly into a shield (pooled), a short camera impulse (only for the own character's hits
-- and damage, scaled by the CameraShake preference) and a perfect-block flash.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlockDefinitions = require(Shared:WaitForChild("BlockDefinitions"))
local BloodConfig = require(Shared:WaitForChild("BloodConfig"))
local CombatEffectsConfig = require(Shared:WaitForChild("CombatEffectsConfig"))

local DamageEffectsController = require(script.Parent.DamageEffectsController)

type Blood = {
	zombieHit: (position: Vector3, scale: number, direction: Vector3?, mode: string) -> (),
}
type Camera = {
	impulse: (strength: number) -> (),
}

export type Options = {
	gui: ScreenGui,
	blood: Blood,
	camera: Camera,
	bloodPreference: () -> string?,
	device: () -> string,
	userId: () -> number,
}

export type CombatEffects = {
	damageFx: (position: Vector3, kind: string, scale: number, direction: Vector3?, extra: any) -> (),
	perfectBlock: () -> (),
}

local CombatEffectsController = {}

local ARROW_LENGTH = 2.2
local ARROW_THICKNESS = 0.12

function CombatEffectsController.start(options: Options): CombatEffects
	local categories = CombatEffectsConfig.Categories
	local camera = CombatEffectsConfig.Camera

	-- Pooled embedded arrows: the same few parts are reused round robin, never created per hit
	local arrowFolder = Instance.new("Folder")
	arrowFolder.Name = "LocalArrows"
	arrowFolder.Parent = Workspace
	local arrows: { Part } = {}
	local arrowGeneration: { number } = {}
	local nextArrow = 1

	local function createArrow(): Part
		local arrow = Instance.new("Part")
		arrow.Name = "EmbeddedArrow"
		arrow.Shape = Enum.PartType.Block
		arrow.Size = Vector3.new(ARROW_THICKNESS, ARROW_THICKNESS, ARROW_LENGTH)
		arrow.Anchored = true
		arrow.CanCollide = false
		arrow.CanQuery = false
		arrow.CanTouch = false
		arrow.CastShadow = false
		arrow.Material = Enum.Material.Wood
		arrow.Color = Color3.fromRGB(122, 84, 50)
		arrow.Transparency = 1
		arrow.Parent = arrowFolder
		return arrow
	end

	local function stickArrow(position: Vector3, direction: Vector3)
		local slot = nextArrow
		nextArrow = nextArrow % CombatEffectsConfig.MaxEmbeddedArrows + 1
		local arrow: Part = arrows[slot] or createArrow()
		arrows[slot] = arrow
		local generation = (arrowGeneration[slot] or 0) + 1
		arrowGeneration[slot] = generation
		-- the shaft sits in the shield, tip toward the attacker's side
		arrow.CFrame = CFrame.lookAt(position - direction * (ARROW_LENGTH * 0.4), position + direction)
		arrow.Transparency = 0
		task.delay(BlockDefinitions.ArrowEmbedSeconds, function()
			if arrowGeneration[slot] == generation then
				arrow.Transparency = 1
			end
		end)
	end

	-- Perfect block: a short white flash over the screen (no text here, the banner is in Main)
	local flash = Instance.new("Frame")
	flash.Name = "PerfectFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 50
	flash.Parent = options.gui
	local flashTween: Tween? = nil
	local function flashScreen()
		if flashTween then
			flashTween:Cancel()
		end
		flash.BackgroundTransparency = 0.7
		local tween = TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
		flashTween = tween
		tween:Play()
	end

	local api = {} :: CombatEffects
	function api.damageFx(position: Vector3, kind: string, scale: number, direction: Vector3?, extra: any)
		local info = if typeof(extra) == "table" then extra else {}
		local category = if typeof(info.category) == "string" and categories[info.category] then info.category else "Blade"
		local cat = categories[category]
		local mine = info.attackerId == options.userId() or info.victimId == options.userId()
		local heavy = info.heavy == true
		local bloodPreference = options.bloodPreference()
		local mode = BloodConfig.resolve(bloodPreference, options.device())

		if kind == "Block" then
			-- Shield sparks (sparks style for blocks), the bow arrow sticks briefly, perfect flash
			DamageEffectsController.burst(position, "Boss", scale * (cat.Spark / 6 + 0.4), direction)
			if info.projectile == true and direction then -- blocked projectiles are arrows
				stickArrow(position, direction.Unit)
			end
			if info.perfect == true then
				flashScreen()
			end
			if mine then
				options.camera.impulse(cat.Impulse)
			end
		elseif kind == "Zombie" then
			-- Blood for zombies only, by preference; without blood the dust / sparks remain
			if mode == "Off" then
				DamageEffectsController.burst(position, "Boss", scale, direction)
			else
				options.blood.zombieHit(position, scale, direction, mode)
				if cat.Dust > 0 then
					DamageEffectsController.burst(position, "Boss", scale, direction)
				end
			end
			if mine then
				options.camera.impulse(if heavy then CombatEffectsConfig.Camera.HeavyImpulse else cat.Impulse)
			end
		elseif kind == "Player" then
			-- Players bleed only when PlayerBlood is on (DamageEffectsController decides by style)
			DamageEffectsController.burst(position, "Player", scale, direction)
			if info.victimId == options.userId() then
				options.camera.impulse(if heavy then CombatEffectsConfig.Camera.HeavyImpulse else cat.Impulse)
			end
		elseif kind == "Boss" then
			DamageEffectsController.burst(position, "Boss", scale, direction)
			if mine then
				options.camera.impulse(if heavy then CombatEffectsConfig.Camera.HeavyImpulse else cat.Impulse)
			end
		end
	end

	function api.perfectBlock()
		options.camera.impulse(CombatEffectsConfig.Camera.PerfectBlock)
		flashScreen()
	end

	return api
end

return CombatEffectsController
