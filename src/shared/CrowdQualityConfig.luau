--!strict
-- Crowd density (server) and presentation quality (client). Gameplay never depends on any of it.
--   Importance  Low (rounds 1-2) · Normal · High (final round, Otti, sudden death, match point):
--               multiplies every zone's density; groups above the current level stay unloaded
--               on the server (not replicated), so a quiet early round costs less.
--   Quality     clients animate at most MaxAnimated animals within AnimateDistance of the camera;
--               farther animals stay still (cheap anchored parts, no Humanoids at all).

export type Importance = "Low" | "Normal" | "High"
export type Quality = "Low" | "Medium" | "High"

local CrowdQualityConfig = {
	Importance = table.freeze({
		Low = 0.55,
		Normal = 1.0,
		High = 1.35,
	}) :: { [Importance]: number },
	MaxDensity = 0.9, -- never fill a zone completely (empty seats look natural)

	Quality = table.freeze({
		Low = table.freeze({ MaxAnimated = 35, AnimateDistance = 70, UpdateHz = 15 }),
		Medium = table.freeze({ MaxAnimated = 70, AnimateDistance = 100, UpdateHz = 24 }),
		High = table.freeze({ MaxAnimated = 140, AnimateDistance = 150, UpdateHz = 30 }),
	}) :: { [Quality]: { MaxAnimated: number, AnimateDistance: number, UpdateHz: number } },

	-- Crowd reaction cooldowns (seconds): no constant noise for normal hits
	MajorMoveCooldown = 8,
	UltimateCooldown = 4,
}

-- Device -> quality (client): phones Low, tablets Medium, desktop / console High.
function CrowdQualityConfig.qualityFor(device: string): Quality
	if device == "Phone" then
		return "Low"
	elseif device == "Tablet" then
		return "Medium"
	end
	return "High"
end

return table.freeze(CrowdQualityConfig)
