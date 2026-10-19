--!strict
-- Cross-place protocol version. Bump Version when Hub and Arena must change together (ticket
-- format, match definitions, teleport payload, mode rules). The Hub writes its version into every
-- admission ticket and match record; the Arena rejects tickets outside [MinCompatible, Version]
-- with GAME UPDATE IN PROGRESS. Saved player data is NOT tied to this number (PlayerDataSchema).

local GameProtocol = {
	Version = 1,
	MinCompatible = 1,
}

function GameProtocol.isCompatible(version: unknown): boolean
	return typeof(version) == "number" and version >= GameProtocol.MinCompatible and version <= GameProtocol.Version
end

return table.freeze(GameProtocol)
