--!strict
-- Combat inputs and their timing. A = Attack, B = Block tap, J = Jump, E = Execute combo.
-- Holding Block still defends normally; the moment Block is pressed also counts as a "B" input.

local InputDefinitions = {
	-- Combo buffer (server)
	MaxGap = 0.65, -- seconds between two inputs of one sequence
	BufferLifetime = 2.8, -- the whole sequence must fit in this time
	MaxLength = 6,
	ExecuteGrace = 0.35, -- Execute while a move is still finishing waits this long at most

	-- Aerial attacks (server)
	AerialWindow = 1.2, -- attack this long after leaving the ground at the latest
	AirborneHeight = 1.0, -- studs above standing height that count as airborne
	MaxAirSeconds = 1.4, -- an aerial move always ends by then (landing or not)
	LeapUpVelocity = 32, -- one controlled hop for combo aerials started on the ground
	DiveVelocity = 55, -- downward speed of a descending aerial strike

	-- Mappings (shown in the info panel and on the training board)
	Desktop = table.freeze({ Attack = "Left mouse", Block = "Right mouse (hold = guard)", Jump = "Space", Execute = "Enter" }),
	Gamepad = table.freeze({ Attack = "R2", Block = "L2", Jump = "A", Execute = "Y" }),
	Touch = table.freeze({ Attack = "ATK", Block = "BLOCK", Jump = "Jump button", Execute = "COMBO" }),
	ExecuteKey = Enum.KeyCode.Return,
	GamepadExecute = Enum.KeyCode.ButtonY,
}

return table.freeze(InputDefinitions)
