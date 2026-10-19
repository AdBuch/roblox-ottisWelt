--!strict
-- The combat slide (server: SlideService inside PlayerCombatService; client: SlideController moves
-- the own character because it owns its physics).
--   * only while moving, on the ground, not stunned / knocked down / held / in a committed special
--     or a heavy block reaction; a block ends when sliding
--   * ~12 studs in 0.55 s, slight steering only, stops at walls, barriers, gates and solid enemies
--     (raycasts every frame), never upward (no launching from slopes), no BodyVelocity objects
--   * a short DODGE window at the start: an appropriate attack landing inside it misses
--     (no invulnerability for the rest of the slide)
--   * one weapon-specific slide attack per slide (Attack / any gesture while sliding)

local SlideDefinitions = {
	Duration = 0.55,
	Cooldown = 1.3,
	Distance = 12,
	MinSpeed = 6, -- studs/s of horizontal movement needed to start
	Steering = 0.2, -- share of the movement input that may bend the path
	DodgeWindow = 0.15,
	SlideAttackRecovery = 0.35, -- extra cooldown after a slide attack before the next slide
	MaxDistanceTolerance = 5, -- server sanity check (studs beyond Distance)
	CameraLower = 1.2, -- client camera offset while sliding
}

return table.freeze(SlideDefinitions)
