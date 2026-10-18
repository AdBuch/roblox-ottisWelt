--!strict
-- Boss HUD for Round 7: a large centred health bar under the AURA display (never covering it)
-- with "OTTI" / "CHAMPION OF THE COLOSSEUM", the current phase (accent color per phase), the
-- active damage-effect mode, and a SKIP INTRO button once you have seen the intro this session.
-- Everything is read from server attributes on the arena folder; the client never decides.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BossPhaseDefinitions = require(Shared:WaitForChild("BossPhaseDefinitions"))
local Config = require(Shared:WaitForChild("Config"))
local OttiBossConfig = require(Shared:WaitForChild("OttiBossConfig"))

local BossHudController = {}

local PANEL = Color3.fromRGB(30, 24, 18)

function BossHudController.start(gui: ScreenGui, arena: Instance, skipRemote: RemoteEvent?)
	local player = Players.LocalPlayer

	local frame = Instance.new("Frame")
	frame.Name = "BossBar"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 100)
	frame.Size = UDim2.fromOffset(560, 74)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.2
	frame.Visible = false
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = BossPhaseDefinitions.Phases[1].Accent
	stroke.Parent = frame

	local function text(name: string, value: string, size: UDim2, position: UDim2, textSize: number, font: Enum.Font, align: Enum.TextXAlignment?): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Text = value
		label.Size = size
		label.Position = position
		label.BackgroundTransparency = 1
		label.Font = font
		label.TextSize = textSize
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.5
		label.TextXAlignment = align or Enum.TextXAlignment.Center
		label.Parent = frame
		return label
	end
	local name = text("Name", OttiBossConfig.DisplayName, UDim2.new(0, 120, 0, 28), UDim2.fromOffset(14, 4), 26, Enum.Font.GothamBlack, Enum.TextXAlignment.Left)
	name.TextColor3 = Color3.fromRGB(255, 215, 90)
	text("Title", OttiBossConfig.Title, UDim2.new(0, 300, 0, 16), UDim2.fromOffset(100, 12), 14, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
	local phaseLabel = text("Phase", "PHASE 1", UDim2.new(0, 200, 0, 16), UDim2.new(1, -214, 0, 12), 13, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(14, 36)
	back.Size = UDim2.new(1, -28, 0, 16)
	back.BackgroundColor3 = Color3.fromRGB(45, 25, 20)
	back.BorderSizePixel = 0
	back.Parent = frame
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 5)
	backCorner.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = BossPhaseDefinitions.Phases[1].Accent
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill
	local healthText = text("Health", "", UDim2.new(1, -28, 0, 16), UDim2.fromOffset(14, 36), 12, Enum.Font.GothamBold)
	local fxLabel = text("Fx", "", UDim2.new(1, -28, 0, 14), UDim2.fromOffset(14, 55), 11, Enum.Font.Gotham, Enum.TextXAlignment.Right)
	fxLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	local roundLabel = text("Round", OttiBossConfig.RoundTitle, UDim2.new(1, -28, 0, 14), UDim2.fromOffset(14, 55), 11, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
	roundLabel.TextColor3 = Color3.fromRGB(255, 205, 70)

	local skip = Instance.new("TextButton")
	skip.Name = "SkipIntro"
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -16, 1, -110)
	skip.Size = UDim2.fromOffset(150, 40)
	skip.BackgroundColor3 = PANEL
	skip.BackgroundTransparency = 0.15
	skip.Font = Enum.Font.GothamBold
	skip.TextSize = 16
	skip.TextColor3 = Color3.fromRGB(255, 215, 90)
	skip.Text = "SKIP INTRO ▶"
	skip.Visible = false
	skip.Parent = gui
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 8)
	skipCorner.Parent = skip
	skip.Activated:Connect(function()
		if skipRemote then
			skipRemote:FireServer("SkipIntro")
		end
		skip.Visible = false
	end)

	local lastPhase = 1
	local function refresh()
		local active = arena:GetAttribute(Config.BossActiveAttribute) == true
		local intro = tostring(arena:GetAttribute(Config.BossIntroAttribute) or "")
		local maxHealth = tonumber(arena:GetAttribute(Config.BossMaxHealthAttribute)) or 0
		local health = tonumber(arena:GetAttribute(Config.BossHealthAttribute)) or 0
		local phase = math.clamp(tonumber(arena:GetAttribute(Config.BossPhaseAttribute)) or 1, 1, #BossPhaseDefinitions.Phases)
		local def = BossPhaseDefinitions.Phases[phase]
		local location = player:GetAttribute("Location")
		local watching = location == "Arena" or location == "Tribune"
		frame.Visible = active and watching and maxHealth > 0
		skip.Visible = active and intro ~= "" and arena:GetAttribute("BossIntroSkippable") == true and player:GetAttribute(Config.IntroSeenAttribute) == true and location == "Arena"
		if not frame.Visible then
			return
		end
		local share = math.clamp(health / math.max(1, maxHealth), 0, 1)
		TweenService:Create(fill, TweenInfo.new(0.2), { Size = UDim2.fromScale(share, 1) }):Play()
		healthText.Text = if arena:GetAttribute(Config.BossDefeatedAttribute) then "DEFEATED" else ("%d / %d"):format(health, maxHealth)
		phaseLabel.Text = ("PHASE %d · %s"):format(phase, def.Name)
		phaseLabel.TextColor3 = def.Accent
		fxLabel.Text = "EFFECTS: " .. tostring(arena:GetAttribute(Config.DamageFxModeAttribute) or "STYLIZED")
		if phase ~= lastPhase then
			lastPhase = phase
			-- Phase change: the bar changes its accent color with a short pulse
			TweenService:Create(fill, TweenInfo.new(0.4), { BackgroundColor3 = def.Accent }):Play()
			TweenService:Create(stroke, TweenInfo.new(0.4), { Color = def.Accent, Thickness = 4 }):Play()
			task.delay(0.6, function()
				TweenService:Create(stroke, TweenInfo.new(0.4), { Thickness = 2 }):Play()
			end)
		elseif phase == 1 then
			fill.BackgroundColor3 = def.Accent
			stroke.Color = def.Accent
		end
	end
	for _, attribute in {
		Config.BossActiveAttribute, Config.BossIntroAttribute, Config.BossHealthAttribute, Config.BossMaxHealthAttribute,
		Config.BossPhaseAttribute, Config.BossDefeatedAttribute, Config.DamageFxModeAttribute, "BossIntroSkippable",
	} do
		arena:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	player:GetAttributeChangedSignal("Location"):Connect(refresh)
	player:GetAttributeChangedSignal(Config.IntroSeenAttribute):Connect(refresh)
	refresh()
end

return BossHudController
