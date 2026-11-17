--!strict
export type Claim = {
	id: string,
	matchId: string?,
	aura: number,
	denarii: number,
	stats: { [string]: number },
	campaign: string?,
	stage: number?,
}
local RewardTypes = {}
function RewardTypes.id(matchId: string, outcome: string, userId: number): string
	return matchId .. "/" .. outcome .. "/p" .. tostring(userId)
end
return table.freeze(RewardTypes)
