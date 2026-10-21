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

	-- Touch controls (button centres measured from the bottom-right corner, base pixels). They sit
	-- around Roblox's own jump button (= JUMP), never on it: on phones Roblox draws it 70 px at about
	-- (60, 55) from the corner, on tablets 120 px at about (110, 150).
	TouchButtonSize = 56,
	TouchAttackSize = 66, -- ATTACK is the largest, most-used button
	TouchLayoutPhone = table.freeze({
		Attack = Vector2.new(145, 60), -- left of JUMP
		Special = Vector2.new(60, 160), -- above JUMP
		Block = Vector2.new(150, 150), -- diagonal
	}),
	TouchLayoutTablet = table.freeze({
		Attack = Vector2.new(245, 150),
		Special = Vector2.new(110, 290),
		Block = Vector2.new(250, 275),
	}),

	-- Colors
	Gold = Color3.fromRGB(255, 205, 70),
	Panel = Color3.fromRGB(30, 24, 18),
	HealthHigh = Color3.fromRGB(90, 205, 90),
	HealthMid = Color3.fromRGB(240, 180, 50),
	HealthLow = Color3.fromRGB(230, 60, 50),
	Red = Color3.fromRGB(255, 110, 110),
	Blue = Color3.fromRGB(120, 170, 255),
}

return table.freeze(UiConfig)
