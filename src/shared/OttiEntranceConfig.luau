--!strict
-- Otti in the imperial box during zombie rounds (OTTI_SPECTATING) and his jump into the arena
-- before Round 7. All movement is server-controlled and deterministic (no falling physics).

local OttiEntranceConfig = {
	-- Spectating
	ReactionCooldown = 4, -- seconds between visible reactions (no reaction for every basic hit)
	IdleLookInterval = 1, -- head follows the fighting
	ImpatientFromRound = 5,

	-- Entrance (after the last Round 6 zombie and the silent pause)
	StandSeconds = 1.0, -- stands up from the seat
	DrawSeconds = 0.7, -- picks up / draws gladius and shield
	ClimbSeconds = 0.8, -- onto the railing
	PauseOnRailSeconds = 0.6, -- the crowd falls quiet
	LeapSeconds = 1.35, -- the controlled arc into the arena
	LeapHeight = 14, -- arc apex above the straight line
	LandingRecoverySeconds = 0.9, -- no damage either way until this is over
	LandingRingRadius = 12,
	CameraSeconds = 4.6, -- local camera focus (skippable once seen this session)
}

return table.freeze(OttiEntranceConfig)
