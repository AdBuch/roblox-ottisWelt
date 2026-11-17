--!strict
-- Protocol 2 requires the profile/lease contract shipped with Tasks 2-6.
local PlayerDataSchema = require(script.Parent.PlayerDataSchema)

export type Capabilities = {
	protocol: number,
	minProtocol: number,
	maxProtocol: number,
	minRead: number,
	maxRead: number,
	write: number,
}

local GameProtocol = {
	Version = 2,
	MinCompatible = 2,
	MaxCompatible = 2,
}

function GameProtocol.isCompatible(version: unknown): boolean
	return typeof(version) == "number" and version % 1 == 0
		and version >= GameProtocol.MinCompatible and version <= GameProtocol.MaxCompatible
end

function GameProtocol.describe(): Capabilities
	return {
		protocol = GameProtocol.Version,
		minProtocol = GameProtocol.MinCompatible, maxProtocol = GameProtocol.MaxCompatible,
		minRead = PlayerDataSchema.MinReadVersion, maxRead = PlayerDataSchema.MaxReadVersion,
		write = PlayerDataSchema.WriteVersion,
	}
end

local function whole(value: any): boolean
	return typeof(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
end

function GameProtocol.canExchange(peer: any): boolean
	if typeof(peer) ~= "table" then return false end
	for _, name in { "protocol", "minProtocol", "maxProtocol", "minRead", "maxRead", "write" } do
		if not whole(peer[name]) then return false end
	end
	return GameProtocol.isCompatible(peer.protocol)
		and peer.minProtocol <= GameProtocol.Version and peer.maxProtocol >= GameProtocol.Version
		and peer.minProtocol <= peer.protocol and peer.protocol <= peer.maxProtocol
		and peer.minRead <= peer.write and peer.write <= peer.maxRead
		and peer.minRead <= PlayerDataSchema.WriteVersion and PlayerDataSchema.WriteVersion <= peer.maxRead
		and PlayerDataSchema.canRead(peer.write)
		and peer.write == PlayerDataSchema.WriteVersion
end

function GameProtocol.isRecordCompatible(record: any): boolean
	return typeof(record) == "table" and typeof(record.compatibility) == "table"
		and record.protocol == record.compatibility.protocol and GameProtocol.canExchange(record.compatibility)
end

return table.freeze(GameProtocol)
