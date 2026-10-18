--!strict
-- Optional audio. Put only Roblox-owned, project-owned or properly licensed sound IDs here
-- (e.g. "rbxassetid://123" for audio your group owns). Empty strings are fine: the game then
-- uses visual crowd animation and HUD feedback instead, and warns once in Studio.
-- Built-in Studio sounds (rbxasset://sounds/...) ship with Roblox and need no upload.

local AudioConfig = {
	-- Crowd (no built-in crowd sounds exist; leave empty until you own suitable audio)
	CrowdMurmur = "", -- quiet anticipation before the boss
	CrowdCheer = "", -- Otti enters, normal cheers
	CrowdRoar = "", -- after a successful throw
	CrowdGasp = "", -- heavy player hit
	CrowdCelebrate = "", -- Otti defeated

	-- Otti (optional; the encounter works without them)
	OttiBattleCry = "",
	ShieldStrike = "rbxasset://sounds/unsheath.wav", -- built-in placeholder
	SandImpact = "rbxasset://sounds/swordslash.wav", -- built-in placeholder

	Volume = 0.8,
}

return table.freeze(AudioConfig)
