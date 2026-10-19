--!strict
-- The two control modes. Both have IDENTICAL combat capabilities and damage; only the input differs.
--   CLASSIC  direct buttons. Desktop: LMB attack (contextual chain), RMB block, Space jump,
--            Left Shift (or C) slide, Q Special Mode (then drag the mouse = gesture).
--            Gamepad: R2 attack, L2 block, A jump, B slide, X Special Mode (right stick = gesture).
--            Touch: ATK, BLOCK, SLIDE, SPECIAL around Roblox's jump button.
--   WILD     the gesture pad (lower right): swipe Left / Right / Up / Down, Circle, hold the centre
--            = block, a short tap = parry attempt; separate jump (Roblox), SLIDE and SPECIAL
--            buttons; Soft Targeting picks the enemy in front.
-- The mode is a saved preference (PlayerDataSchema "ControlMode"). Switching waits until the
-- current attack finished, cancels unfinished gestures and ends an active block.

export type Mode = "Classic" | "Wild"

local ControlModeDefinitions = {
	Default = "Classic" :: Mode,
	Modes = table.freeze({ "Classic", "Wild" } :: { Mode }),
	SlideKeys = table.freeze({ Enum.KeyCode.LeftShift, Enum.KeyCode.C }),
	SpecialKey = Enum.KeyCode.Q,
	GamepadSlide = Enum.KeyCode.ButtonB,
	GamepadSpecial = Enum.KeyCode.ButtonX,
	GamepadStickDeadzone = 0.55,
	-- Wild pad (fractions of the shortest screen side)
	PadRadiusPhone = 0.2,
	PadRadiusTablet = 0.16,
	PadRadiusDesktop = 0.12,
	PadCenterHold = 0.35, -- touch within this share of the radius and hold = block
	HoldBlockSeconds = 0.16, -- holding the centre this long starts a block
	-- Soft Targeting
	SoftTargetCone = 75, -- full cone in degrees
	SoftTargetExtraRange = 4, -- studs beyond the weapon's range
	MaxTurnDegrees = 40, -- the player is rotated at most this much toward the target per attack
}

function ControlModeDefinitions.isMode(value: unknown): boolean
	return value == "Classic" or value == "Wild"
end

return table.freeze(ControlModeDefinitions)
