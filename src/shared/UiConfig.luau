--!strict
-- All HUD sizes, breakpoints, limits and timings in one place (client presentation only).
-- Sizes are base pixels at scale 1; the HUD multiplies them by the device scale below.

export type HudMode = "Full" | "Minimal" | "Hidden"
export type DeviceClass = "Phone" | "Tablet" | "Desktop" | "Console"

local UiConfig = {
	-- Breakpoints (shortest viewport side, in pixels)
	MobileBreakpoint = 500, -- below: phone layout
	TabletBreakpoint = 900, -- touch devices below this (and above the phone breakpoint) use the tablet layout

	-- Device scale (UIScale on every HUD group)
	MobilePortraitScale = 0.8,
	MobileLandscapeScale = 0.85,
	TabletScale = 1,
	DesktopScale = 1,
	ConsoleScale = 1.15, -- TV distance

	-- Player health bar (bottom-left)
	HealthBarWidthPhone = 0.25, -- share of the screen width
	HealthBarWidthDesktop = 260, -- pixels
	HealthBarHeight = 20,
	HealthBarBottomPhone = 150, -- above Roblox's thumbstick area
	HealthBarBottomTablet = 250,
	HealthBarBottomDesktop = 24,
	HideHealthNumberBelowWidth = 400, -- the "82 / 120" text is dropped on very narrow screens
	LowHealthShare = 0.25,

	-- Contextual world-space health bars
	MaxEnemyBarsPhone = 4,
	MaxEnemyBarsDesktop = 8,
	ContextBarTimeout = 3, -- seconds after the last interaction
	ContextNearDistance = 14, -- zombies/dummies this close always show a bar
	ContextMaxDistance = 90, -- never beyond this distance
	TeammateBarDistance = 70,
	ContextUpdateInterval = 0.2, -- distance / line-of-sight checks (not every frame)

	-- Notifications
	MaxNotifications = 3,
	NotificationSeconds = 1.6,
	AuraNotificationSeconds = 1.5,
	AuraCombineWindow = 0.8, -- rewards within this window are merged into one "+n"
	BannerSeconds = 1.8,
	RoundIndicatorSeconds = 5, -- the compact round line hides after this long without changes

	-- Teammates / HUD modes
	TeammateStripVisible = true, -- co-op strip starts expanded
	DefaultHudMode = "Full" :: HudMode,
	HudToggleKey = Enum.KeyCode.H,
	InfoPanelOpenInLobbyOnDesktop = false,

	-- Touch controls: FOUR equal buttons as an exact rhombus around one centre C with distance R:
	--   BLOCK C+(0,-R) · ATTACK C+(R,0) · JUMP C+(0,R) · SPECIAL C+(-R,0)
	-- (UiConfig.rhombusOffsets). Size = width = height of every button (base pixels; the HUD's UIScale
	-- scales all four identically). Margin = distance of the rhombus box to the bottom-right screen
	-- edge (the ScreenGui already keeps out of notches / safe areas). JUMP replaces Roblox's own
	-- touch jump button, which is hidden (MobileControlsController), so there is never a fifth button.
	-- Neighbouring centres are R*sqrt(2) apart: R >= (Size + Gap) / sqrt(2) keeps them apart.
	TouchRhombus = table.freeze({
		Phone = table.freeze({ Size = 66, Radius = 60, Margin = 14 }),
		Tablet = table.freeze({ Size = 84, Radius = 76, Margin = 26 }),
	}),
	TouchButtonGap = 12, -- minimum free space between two neighbouring touch buttons

	-- Menus (MenuSystem): warm stone, dark surfaces, discreet bronze / gold accents
	Menu = table.freeze({
		Backdrop = Color3.fromRGB(8, 6, 4),
		BackdropTransparency = 0.45,
		Panel = Color3.fromRGB(27, 22, 18), -- dark surface
		Surface = Color3.fromRGB(44, 37, 30), -- cards, rows
		SurfaceRaised = Color3.fromRGB(62, 52, 42), -- tabs, secondary buttons
		Stone = Color3.fromRGB(148, 131, 108), -- warm stone band
		StoneDark = Color3.fromRGB(96, 84, 70),
		Bronze = Color3.fromRGB(176, 125, 60),
		Gold = Color3.fromRGB(238, 196, 96),
		Text = Color3.fromRGB(246, 238, 224),
		TextMuted = Color3.fromRGB(198, 186, 168),
		Primary = Color3.fromRGB(150, 48, 34), -- Roman red: the main action
		Equipped = Color3.fromRGB(86, 150, 86),
		Locked = Color3.fromRGB(86, 80, 74),
		Positive = Color3.fromRGB(130, 220, 130),
		Negative = Color3.fromRGB(240, 130, 120),
		TitleFont = Enum.Font.GothamBlack,
		LabelFont = Enum.Font.GothamBold,
		BodyFont = Enum.Font.Gotham,
		TouchTarget = 44, -- minimum height / width of every interactive element (px)
		Padding = 12,
		Gap = 8,
		Corner = 10,
		MaxSize = Vector2.new(820, 600),
		ToggleKey = Enum.KeyCode.M,
		GamepadToggle = Enum.KeyCode.ButtonY,
	}),

	-- Colors
	Gold = Color3.fromRGB(255, 205, 70),
	Panel = Color3.fromRGB(30, 24, 18),
	HealthHigh = Color3.fromRGB(90, 205, 90),
	HealthMid = Color3.fromRGB(240, 180, 50),
	HealthLow = Color3.fromRGB(230, 60, 50),
	Red = Color3.fromRGB(255, 110, 110),
	Blue = Color3.fromRGB(120, 170, 255),
	-- Special charge phases I · II · III and the ULTIMATE (touch button, charge bar)
	SpecialPhaseColors = table.freeze({ Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 140, 40), Color3.fromRGB(235, 55, 50) }),
	UltimateColor = Color3.fromRGB(190, 95, 255),
	-- Block stages I · II · III (touch button ring)
	BlockStageColors = table.freeze({ Color3.fromRGB(120, 170, 235), Color3.fromRGB(70, 215, 200), Color3.fromRGB(255, 205, 70) }),
}

-- The four rhombus offsets from the common centre C (pixels, y grows downwards). Computed ONCE
-- from the radius, never four independent guesses.
function UiConfig.rhombusOffsets(radius: number): { [string]: Vector2 }
	return {
		Block = Vector2.new(0, -radius), -- top
		Attack = Vector2.new(radius, 0), -- right
		Jump = Vector2.new(0, radius), -- bottom
		Special = Vector2.new(-radius, 0), -- left
	}
end

-- Side length of the square box that holds the whole rhombus (button size + 2 radius).
function UiConfig.rhombusBox(size: number, radius: number): number
	return size + 2 * radius
end

return table.freeze(UiConfig)
