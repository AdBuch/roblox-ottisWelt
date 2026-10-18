--!strict
-- Compact group information (replaces the old right-side roster/scoreboard panel):
--   Team Battle  one capsule at the top: RED 8 — 6 BLUE · 04:12 (SUDDEN DEATH when tied)
--   Co-op        a collapsible teammate strip on the left edge: initial, tiny health bar,
--                downed marker, red pulse below 25 %, exact health only when critical
--   Lobby        the CO-OP party / RED and BLUE rosters with ready states and the team countdown
--                (only while you are in a party or team, and only in the lobby)
-- Full rosters during combat live in the info panel (rosterText).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameStates = require(Shared:WaitForChild("GameStates"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))

export type TeamStatus = {
	rosterText: () -> string,
}

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}

local TeamStatusController = {}

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

local function hex(color: Color3): string
	return ("#%02X%02X%02X"):format(math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

function TeamStatusController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, arena: Instance, lobby: Instance, isPhone: () -> boolean, notify: (string, string) -> ()): TeamStatus
	local player = Players.LocalPlayer

	------------------------------------------------------------------ Team Battle score capsule
	local scoreFrame = group("TeamScore", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 6), UDim2.fromOffset(260, 26))
	local score = Instance.new("TextLabel")
	score.Size = UDim2.fromScale(1, 1)
	score.BackgroundColor3 = Color3.new(0, 0, 0)
	score.BackgroundTransparency = 0.55
	score.Font = Enum.Font.GothamBlack
	score.TextSize = 16
	score.RichText = true
	score.TextColor3 = Color3.new(1, 1, 1)
	score.TextStrokeTransparency = 0.6
	score.Parent = scoreFrame
	local scoreCorner = Instance.new("UICorner")
	scoreCorner.CornerRadius = UDim.new(1, 0)
	scoreCorner.Parent = score
	local function refreshScore()
		local red = tonumber(arena:GetAttribute(Config.RedScoreAttribute)) or 0
		local blue = tonumber(arena:GetAttribute(Config.BlueScoreAttribute)) or 0
		local timeLeft = tonumber(arena:GetAttribute(Config.TimeLeftAttribute)) or 0
		local time = if arena:GetAttribute(Config.SuddenDeathAttribute) == true then "SUDDEN DEATH" else ("%02d:%02d"):format(timeLeft // 60, timeLeft % 60)
		score.Text = ('<font color="%s">RED %d</font>  —  <font color="%s">%d BLUE</font>   <font color="#DDDDDD">%s</font>'):format(hex(UiConfig.Red), red, hex(UiConfig.Blue), blue, time)
	end
	for _, attribute in { Config.RedScoreAttribute, Config.BlueScoreAttribute, Config.TimeLeftAttribute, Config.SuddenDeathAttribute } do
		arena:GetAttributeChangedSignal(attribute):Connect(refreshScore)
	end
	refreshScore()
	visibility.register("TeamScore", scoreFrame, function()
		return arena:GetAttribute(Config.MatchModeAttribute) == "TeamBattle"
	end)

	------------------------------------------------------------------ Co-op teammate strip
	local stripFrame = group("Teammates", Vector2.new(0, 0.5), UDim2.new(0, 8, 0.45, 0), UDim2.fromOffset(84, 180))
	local toggle = Instance.new("TextButton")
	toggle.Name = "Collapse"
	toggle.Size = UDim2.fromOffset(44, 26)
	toggle.BackgroundColor3 = UiConfig.Panel
	toggle.BackgroundTransparency = 0.4
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 16
	toggle.TextColor3 = Color3.new(1, 1, 1)
	toggle.Text = "‹"
	toggle.Parent = stripFrame
	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 8)
	toggleCorner.Parent = toggle
	local entriesFrame = Instance.new("Frame")
	entriesFrame.Position = UDim2.fromOffset(0, 30)
	entriesFrame.Size = UDim2.new(1, 0, 1, -30)
	entriesFrame.BackgroundTransparency = 1
	entriesFrame.Parent = stripFrame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = entriesFrame
	local expanded = UiConfig.TeammateStripVisible
	toggle.Activated:Connect(function()
		expanded = not expanded
		entriesFrame.Visible = expanded
		toggle.Text = if expanded then "‹" else "›"
	end)
	entriesFrame.Visible = expanded
	toggle.Text = if expanded then "‹" else "›"

	type Indicator = { frame: Frame, initial: TextLabel, fill: Frame, value: TextLabel, pulse: UIStroke }
	local indicators: { Indicator } = {}
	for i = 1, 4 do
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromOffset(84, 28)
		frame.BackgroundTransparency = 1
		frame.LayoutOrder = i
		frame.Visible = false
		frame.Parent = entriesFrame
		local initial = Instance.new("TextLabel")
		initial.Size = UDim2.fromOffset(26, 26)
		initial.BackgroundColor3 = UiConfig.Panel
		initial.BackgroundTransparency = 0.2
		initial.Font = Enum.Font.GothamBlack
		initial.TextSize = 14
		initial.TextColor3 = UiConfig.Gold
		initial.Parent = frame
		local initialCorner = Instance.new("UICorner")
		initialCorner.CornerRadius = UDim.new(1, 0)
		initialCorner.Parent = initial
		local pulse = Instance.new("UIStroke")
		pulse.Color = UiConfig.HealthLow
		pulse.Thickness = 2
		pulse.Transparency = 1
		pulse.Parent = initial
		local back = Instance.new("Frame")
		back.Position = UDim2.fromOffset(30, 10)
		back.Size = UDim2.fromOffset(48, 6)
		back.BackgroundColor3 = Color3.fromRGB(35, 22, 18)
		back.BorderSizePixel = 0
		back.Parent = frame
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BorderSizePixel = 0
		fill.Parent = back
		local value = Instance.new("TextLabel")
		value.Position = UDim2.fromOffset(30, 16)
		value.Size = UDim2.fromOffset(48, 12)
		value.BackgroundTransparency = 1
		value.Font = Enum.Font.GothamBold
		value.TextSize = 10
		value.TextColor3 = UiConfig.HealthLow
		value.TextXAlignment = Enum.TextXAlignment.Left
		value.Parent = frame
		table.insert(indicators, { frame = frame, initial = initial, fill = fill, value = value, pulse = pulse })
	end

	local function teammates(): { Player }
		local list = {}
		for _, other in Players:GetPlayers() do
			local state = other:GetAttribute(GameStates.StateAttribute)
			local location = other:GetAttribute(GameStates.LocationAttribute)
			local inMatch = GameStates.isFighter(state) or state == GameStates.Countdown or (state == GameStates.PlayerDefeated and location ~= "Lobby")
			if other ~= player and inMatch then
				table.insert(list, other)
			end
		end
		return list
	end

	local downed: { [Player]: boolean } = {}
	local function refreshStrip()
		local others = teammates()
		local maxShown = if isPhone() then 3 else 4
		for i, indicator in indicators do
			local other: Player? = others[i]
			indicator.frame.Visible = other ~= nil and i <= maxShown
			if other and i <= maxShown then
				local character = other.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local isDown = other:GetAttribute(GameStates.StateAttribute) == GameStates.PlayerDefeated or not humanoid or humanoid.Health <= 0
				local share = if humanoid and not isDown then math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1) else 0
				indicator.initial.Text = if isDown then "✕" else other.DisplayName:sub(1, 1):upper()
				indicator.initial.TextColor3 = if isDown then Color3.fromRGB(150, 150, 150) else UiConfig.Gold
				indicator.fill.Size = UDim2.fromScale(share, 1)
				indicator.fill.BackgroundColor3 = if share > 0.5 then UiConfig.HealthHigh elseif share > UiConfig.LowHealthShare then UiConfig.HealthMid else UiConfig.HealthLow
				local critical = not isDown and share <= UiConfig.LowHealthShare
				indicator.value.Text = if critical and humanoid then ("%d"):format(math.ceil(humanoid.Health)) else ""
				if critical then
					indicator.pulse.Transparency = 0
					TweenService:Create(indicator.pulse, TweenInfo.new(0.45), { Transparency = 1 }):Play()
				end
				if isDown and not downed[other] then
					notify("Info", "TEAMMATE DOWN")
				end
				downed[other] = isDown
			end
		end
	end
	visibility.register("Teammates", stripFrame, function()
		return arena:GetAttribute(Config.MatchModeAttribute) == "Coop" and #teammates() > 0
	end)

	------------------------------------------------------------------ lobby rosters (lobby only)
	local rosterFrame = group("Roster", Vector2.new(1, 0.5), UDim2.new(1, -8, 0.5, 0), UDim2.fromOffset(190, 0))
	rosterFrame.AutomaticSize = Enum.AutomaticSize.Y
	local roster = Instance.new("TextLabel")
	roster.Size = UDim2.fromOffset(190, 0)
	roster.AutomaticSize = Enum.AutomaticSize.Y
	roster.BackgroundColor3 = UiConfig.Panel
	roster.BackgroundTransparency = 0.3
	roster.Font = Enum.Font.GothamMedium
	roster.TextSize = 12
	roster.TextColor3 = Color3.new(1, 1, 1)
	roster.TextXAlignment = Enum.TextXAlignment.Left
	roster.TextWrapped = true
	roster.RichText = true
	roster.Parent = rosterFrame
	local rosterPadding = Instance.new("UIPadding")
	rosterPadding.PaddingTop = UDim.new(0, 6)
	rosterPadding.PaddingBottom = UDim.new(0, 6)
	rosterPadding.PaddingLeft = UDim.new(0, 8)
	rosterPadding.PaddingRight = UDim.new(0, 8)
	rosterPadding.Parent = roster
	local rosterCorner = Instance.new("UICorner")
	rosterCorner.CornerRadius = UDim.new(0, 8)
	rosterCorner.Parent = roster

	local function list(title: string, value: unknown, color: string): string
		local lines = { ('<font color="%s"><b>%s</b></font>'):format(color, title) }
		local entries = parse(value)
		if #entries == 0 then
			table.insert(lines, "  –")
		end
		for _, entry in entries do
			table.insert(lines, ("  %s%s %s"):format(if entry.leader then "★ " else "", entry.name, if entry.ready then '<font color="#8CFF8C">✓</font>' else "…"))
		end
		return table.concat(lines, "\n")
	end

	local function lobbyRoster(): string?
		local team = player:GetAttribute(Config.TeamAttribute)
		if player:GetAttribute(Config.InPartyAttribute) == true then
			return list("CO-OP PARTY", lobby:GetAttribute(Config.CoopRosterAttribute), "#FFD278")
		elseif team == "Red" or team == "Blue" then
			local countdown = tonumber(lobby:GetAttribute(Config.TeamCountdownAttribute)) or 0
			return list("RED", lobby:GetAttribute(Config.RedRosterAttribute), hex(UiConfig.Red))
				.. "\n" .. list("BLUE", lobby:GetAttribute(Config.BlueRosterAttribute), hex(UiConfig.Blue))
				.. (if countdown > 0 then ("\n<b>Starting in %d</b>"):format(countdown) else "")
		end
		return nil
	end
	local function refreshRoster()
		roster.Text = lobbyRoster() or ""
	end
	for _, attribute in { Config.CoopRosterAttribute, Config.RedRosterAttribute, Config.BlueRosterAttribute, Config.TeamCountdownAttribute } do
		lobby:GetAttributeChangedSignal(attribute):Connect(refreshRoster)
	end
	for _, attribute in { Config.InPartyAttribute, Config.TeamAttribute } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshRoster)
	end
	refreshRoster()
	visibility.register("Roster", rosterFrame, function()
		return roster.Text ~= ""
	end)

	-- Teammate health changes often: refresh the strip twice per second (no per-frame work)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if stripFrame.Visible then
				refreshStrip()
			end
		end
	end)

	return {
		-- Full rosters for the info panel (also during combat)
		rosterText = function(): string
			local mode = arena:GetAttribute(Config.MatchModeAttribute)
			if mode == "TeamBattle" then
				local lines = { "<b>TEAM BATTLE</b>  (elims / deaths / assists)" }
				for _, other in Players:GetPlayers() do
					local otherTeam = other:GetAttribute(Config.TeamAttribute)
					if otherTeam == "Red" or otherTeam == "Blue" then
						table.insert(lines, ('<font color="%s">%s</font>  %d / %d / %d'):format(
							hex(if otherTeam == "Red" then UiConfig.Red else UiConfig.Blue),
							other.DisplayName,
							tonumber(other:GetAttribute(Config.EliminationsAttribute)) or 0,
							tonumber(other:GetAttribute(Config.DeathsAttribute)) or 0,
							tonumber(other:GetAttribute(Config.AssistsAttribute)) or 0
						))
					end
				end
				return table.concat(lines, "\n")
			elseif mode == "Coop" then
				local names = { player.DisplayName }
				for _, other in teammates() do
					table.insert(names, other.DisplayName)
				end
				return "<b>CO-OP LEGION</b>\n  " .. table.concat(names, "\n  ")
			end
			return lobbyRoster() or "Not in a party or team."
		end,
	}
end

return TeamStatusController
