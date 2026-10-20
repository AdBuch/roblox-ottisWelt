--!strict
-- Routes server-validated hit events to the presentation controllers (display only):
--   DamageFx(position, kind, scale, direction, extra)   kind Zombie | Player | Boss | Block
--   extra { category, attackerId, victimId, heavy, perfect, projectile, killed, armored }
-- Child-friendly: no blood anywhere. Per weapon category (CombatEffectsConfig): sparks and dust
-- (DamageEffectsController), a bow arrow that sticks briefly into a shield (pooled), a short camera
-- impulse (only for the own character's hits and damage, scaled by the CameraShake preference) and
-- a perfect-block flash.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlockDefinitions = require(Shared:WaitForChild("BlockDefinitions"))
local CombatEffectsConfig = require(Shared:WaitForChild("CombatEffectsConfig"))

local DamageEffectsController = require(script.Parent.DamageEffectsController)

type Camera = {
	impulse: (strength: number) -> (),
}

export type Options = {
	gui: ScreenGui,
	camera: Camera,
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
		local me = options.userId()
		local mine = info.attackerId == me or info.victimId == me
		local impulse = if info.heavy == true then CombatEffectsConfig.Camera.HeavyImpulse else cat.Impulse

		if kind == "Block" then
			-- Shield sparks, the blocked arrow sticks briefly, perfect flash
			DamageEffectsController.burst(position, kind, scale * (cat.Spark / 6 + 0.4), direction)
			if info.projectile == true and direction then -- blocked projectiles are arrows
				stickArrow(position, direction.Unit)
			end
			if info.perfect == true then
				flashScreen()
			end
			if mine then
				options.camera.impulse(cat.Impulse)
			end
		else
			-- Zombies, players and Otti: sparks and dust only
			DamageEffectsController.burst(position, kind, scale, direction)
			if (kind == "Player" and info.victimId == me) or (kind ~= "Player" and mine) then
				options.camera.impulse(impulse)
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
