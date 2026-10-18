--!strict
-- Lobby group panel (right side): shows the CO-OP party with ready states while you are in it,
-- the RED / BLUE rosters and the start countdown while you are in a team, and the match
-- scoreboard (eliminations / deaths / assists) during a Team Battle. Display only.

local Players = game:GetService("Players")

local PartyController = {}

type Names = {
	lobbyFolder: Instance,
	arenaFolder: Instance?,
	coopRoster: string,
	redRoster: string,
	blueRoster: string,
	teamCountdown: string,
	inParty: string,
	team: string,
	eliminations: string,
	deaths: string,
	assists: string,
	matchMode: string,
}

local function parse(value: unknown): { { name: string, ready: boolean, leader: boolean } }
	local list = {}
	if typeof(value) == "string" and value ~= "" then
		for entry in value:gmatch("[^;]+") do
			local name, ready, leader = entry:match("^([^|]*)|([^|]*)|?(.*)$")
			if name then
				table.insert(list, { name = name, ready = ready == "ready", leader = leader == "leader" })
			end
		end
	end
	return list
end

function PartyController.start(gui: ScreenGui, names: Names)
	local player = Players.LocalPlayer
	local panel = Instance.new("Frame")
	panel.Name = "GroupPanel"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -16, 0.5, 0)
	panel.Size = UDim2.fromOffset(230, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(30, 24, 18)
	panel.BackgroundTransparency = 0.2
	panel.Visible = false
	panel.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 0, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamMedium
	text.TextSize = 14
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextWrapped = true
	text.RichText = true
	text.Parent = panel

	local function roster(title: string, value: unknown, color: string): string
		local lines = { ('<font color="%s"><b>%s</b></font>'):format(color, title) }
		local entries = parse(value)
		if #entries == 0 then
			table.insert(lines, "  (empty)")
		end
		for _, entry in entries do
			table.insert(lines, ("  %s%s  %s"):format(if entry.leader then "★ " else "", entry.name, if entry.ready then '<font color="#8CFF8C">READY</font>' else "…"))
		end
		return table.concat(lines, "\n")
	end

	local function refresh()
		local arena = names.arenaFolder
		local team = player:GetAttribute(names.team)
		if arena and arena:GetAttribute(names.matchMode) == "TeamBattle" and (team == "Red" or team == "Blue") then
			local lines = { "<b>TEAM BATTLE</b>" }
			for _, other in Players:GetPlayers() do
				local otherTeam = other:GetAttribute(names.team)
				if otherTeam == "Red" or otherTeam == "Blue" then
					table.insert(lines, ('<font color="%s">%s</font>  %d / %d / %d'):format(
						if otherTeam == "Red" then "#FF7070" else "#78AAFF",
						other.DisplayName,
						tonumber(other:GetAttribute(names.eliminations)) or 0,
						tonumber(other:GetAttribute(names.deaths)) or 0,
						tonumber(other:GetAttribute(names.assists)) or 0
					))
				end
			end
			table.insert(lines, '<font color="#BBBBBB">elims / deaths / assists</font>')
			text.Text = table.concat(lines, "\n")
			panel.Visible = true
		elseif player:GetAttribute(names.inParty) == true then
			text.Text = roster("CO-OP LEGIONS", names.lobbyFolder:GetAttribute(names.coopRoster), "#FFD278")
				.. "\n<font color=\"#BBBBBB\">Leader starts at START post</font>"
			panel.Visible = true
		elseif team == "Red" or team == "Blue" then
			local countdown = tonumber(names.lobbyFolder:GetAttribute(names.teamCountdown)) or 0
			text.Text = roster("RED GLADIATORS", names.lobbyFolder:GetAttribute(names.redRoster), "#FF7070")
				.. "\n"
				.. roster("BLUE GLADIATORS", names.lobbyFolder:GetAttribute(names.blueRoster), "#78AAFF")
				.. (if countdown > 0 then ("\n<b>Starting in %d</b>"):format(countdown) else "\n<font color=\"#BBBBBB\">Needs 1 ready player per team</font>")
			panel.Visible = true
		else
			panel.Visible = false
		end
	end

	for _, attribute in { names.coopRoster, names.redRoster, names.blueRoster, names.teamCountdown } do
		names.lobbyFolder:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	for _, attribute in { names.inParty, names.team } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	task.spawn(function()
		while true do
			task.wait(0.5) -- scoreboard stats of other players change often; poll lightly
			refresh()
		end
	end)
	refresh()
end

return PartyController
