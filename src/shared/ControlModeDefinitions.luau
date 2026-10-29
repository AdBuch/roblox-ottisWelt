--!strict
-- Classic controls (the only control mode). Same combat on every device and in PvE, PvP and boss fights:
--   Desktop  move WASD · LMB attack (tap again for combos) · hold RMB block · hold Q special,
--            release to fire · Space jump · F interact
--   Gamepad  left stick move · R2 attack · hold L2 block · hold X special · A jump
--   Touch    Roblox thumbstick (left) · ATTACK, SPECIAL (hold), BLOCK (hold) around Roblox's own
--            jump button (right) · drag on free screen space turns the camera
-- Movement is camera-relative (Roblox's character controller) and turns the character; Soft
-- Targeting nudges an attack toward the enemy in front (visible line of sight only), the server
-- validates every target.

local ControlModeDefinitions = {
	SpecialKey = Enum.KeyCode.Q,
	GamepadSpecial = Enum.KeyCode.ButtonX,
	GamepadAttack = Enum.KeyCode.ButtonR2,
	GamepadBlock = Enum.KeyCode.ButtonL2,
	-- Soft Targeting
	SoftTargetCone = 75, -- full cone in degrees in front of the character
	SoftTargetExtraRange = 4, -- studs beyond the weapon's range
	MaxTurnDegrees = 40, -- an attack turns the character at most this much toward the target...
	TurnSeconds = 0.1, -- ...smoothly over this time (no snapping)
}

return table.freeze(ControlModeDefinitions)
