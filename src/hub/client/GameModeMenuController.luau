--!strict
-- The compact Hub mode menu (PLAY button on the right edge, also reachable at the basement posts):
--   ZOMBIE BATTLES   SOLO · START CO-OP (current party or alone) · FIND PLAYERS (matchmaking)
--                    party: create / leave / ready / invite players in this server / accept
--                    invites / INVITE FRIENDS (Roblox game invite)
--   TEAM BATTLES     TIME BATTLE · FIRST TO 20 · ELIMINATION (queue, the party queues together)
--                    · LEAVE QUEUE
--   WATCH LIVE       opens LIVE IN THE COLOSSEUM
-- Requests only (MatchRequest); every answer comes from the server. Closed = invisible and inert.
-- Styled and coordinated by MenuSystem (same theme as the lobby menu; only one big menu at a time).

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

local MenuSystem = require(script.Parent.Parent:WaitForChild("MenuSystem"))

export type ModeMenu = {
	open: (tab: string?) -> (),
	close: () -> (),
}

local GameModeMenuController = {}

local THEME = MenuSystem.Theme
local RED = THEME.Primary
local DARK = THEME.SurfaceRaised

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function button(parent: Instance, text: string, color: Color3, order: number, height: number?): TextButton
	local b = make("TextButton", {
		Size = UDim2.new(1, 0, 0, math.max(THEME.TouchTarget, height or THEME.TouchTarget)),
		BackgroundColor3 = color,
		Font = THEME.LabelFont,
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = THEME.Text,
		Text = text,
		AutoButtonColor = true,
		LayoutOrder = order,
		ZIndex = 32,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	return b
end

local function note(parent: Instance, text: string, order: number): TextLabel
	return make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = THEME.BodyFont,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.TextMuted,
		Text = text,
		LayoutOrder = order,
		ZIndex = 32,
		RichText = true,
	}, parent)
end

function GameModeMenuController.start(gui: ScreenGui, edge: Frame, request: RemoteFunction?, events: RemoteEvent?, openLive: () -> (), notify: (string) -> ()): ModeMenu
	local player = Players.LocalPlayer
	local playButton = make("TextButton", {
		Name = "Play",
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = RED,
		BackgroundTransparency = 0.1,
		Font = Enum.Font.GothamBlack,
		TextSize = 11,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "PLAY",
		LayoutOrder = 0,
	}, edge)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, playButton)

	local backdrop = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = THEME.Backdrop, BackgroundTransparency = THEME.BackdropTransparency, Text = "", AutoButtonColor = false, Selectable = false, Visible = false, ZIndex = 30 }, gui)
	local panel = make("Frame", {
		Name = "ModeMenu",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 1, -24),
		BackgroundColor3 = THEME.Panel,
		Visible = false,
		ZIndex = 31,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
	make("UISizeConstraint", { MaxSize = Vector2.new(460, 620) }, panel)
	MenuSystem.stroke(panel, THEME.Bronze, 0.25, 2)
	make("TextButton", { Name = "ModalCatcher", Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Text = "", Modal = true, Selectable = false }, panel)

	-- the shared header: warm stone band, title, 44 px close button
	local header = make("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = THEME.Stone, ZIndex = 32 }, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, header)
	make("Frame", { Position = UDim2.new(0, 0, 1, -12), Size = UDim2.new(1, 0, 0, 12), BackgroundColor3 = THEME.Stone, BorderSizePixel = 0, ZIndex = 32 }, header)
	make("Frame", { Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = THEME.Bronze, BorderSizePixel = 0, ZIndex = 33 }, header)
	make("TextLabel", { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -76, 1, 0), BackgroundTransparency = 1, Font = THEME.TitleFont, TextSize = 19, TextColor3 = Color3.fromRGB(40, 28, 18), TextXAlignment = Enum.TextXAlignment.Left, Text = "SPIELMODI", ZIndex = 33 }, header)
	local closeButton = make("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), Size = UDim2.fromOffset(THEME.TouchTarget, THEME.TouchTarget), BackgroundColor3 = THEME.Panel, Font = THEME.TitleFont, TextSize = 18, TextColor3 = THEME.Gold, Text = "✕", ZIndex = 33 }, header)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, closeButton)

	local tabs = make("Frame", { Position = UDim2.fromOffset(12, 62), Size = UDim2.new(1, -24, 0, THEME.TouchTarget), BackgroundTransparency = 1, ZIndex = 32 }, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)

	local bodyTop = 62 + THEME.TouchTarget + 10
	local body = make("ScrollingFrame", {
		Position = UDim2.fromOffset(12, bodyTop),
		Size = UDim2.new(1, -24, 1, -(bodyTop + 12)),
		BackgroundTransparency = 1,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = THEME.Bronze,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 32,
	}, panel)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, body)

	local currentTab = "ZOMBIES"
	local partyState: any = { inParty = false, invites = {} }
	local isOpen = false

	local function invoke(action: string, arg: any?): any
		if not request then
			return nil
		end
		local ok, result = pcall(function()
			return request:InvokeServer(action, arg)
		end)
		local response = if ok then result else nil
		if response and response.message then
			notify(response.message)
		end
		if response and typeof(response.data) == "table" and response.data.inParty ~= nil then
			partyState = response.data
		end
		return response
	end

	local render: () -> ()

	local function act(action: string, arg: any?, rerender: boolean?)
		task.spawn(function()
			invoke(action, arg)
			if rerender and isOpen then
				render()
			end
		end)
	end

	local function clear()
		for _, child in body:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function partySection(order: number): number
		local state = partyState
		if state.invites and #state.invites > 0 then
			for _, invite in state.invites do
				order += 1
				button(body, ("ACCEPT INVITE · %s"):format(invite.leader), Color3.fromRGB(46, 96, 150), order).Activated:Connect(function()
					act("PartyAccept", invite.partyId, true)
				end)
			end
		end
		order += 1
		if not state.inParty then
			note(body, "<b>PARTY</b>  play alone, or create a party and invite players", order)
			order += 1
			button(body, "CREATE PARTY", DARK, order, 36).Activated:Connect(function()
				act("PartyCreate", nil, true)
			end)
		else
			local names = {}
			for _, member in state.members or {} do
				table.insert(names, ("%s%s%s"):format(if member.leader then "★ " else "", member.name, if member.ready then " ✓" else ""))
			end
			note(body, ("<b>PARTY</b> %s  %s"):format(if state.locked then "(queued)" else "", table.concat(names, " · ")), order)
			order += 1
			button(body, "READY / NOT READY", DARK, order, 36).Activated:Connect(function()
				act("PartyReady", nil, true)
			end)
			order += 1
			button(body, "LEAVE PARTY", DARK, order, 36).Activated:Connect(function()
				act("PartyLeave", nil, true)
			end)
			if state.leader then
				order += 1
				button(body, "INVITE PLAYERS HERE…", DARK, order, 36).Activated:Connect(function()
					task.spawn(function()
						local response = invoke("ServerPlayers")
						if not response or not response.ok then
							return
						end
						clear()
						local o = 0
						for _, entry in response.data do
							o += 1
							button(body, ("INVITE %s%s"):format(entry.name, if entry.inParty then " (in a party)" else ""), DARK, o, 36).Activated:Connect(function()
								act("PartyInvite", entry.userId, false)
							end)
						end
						if o == 0 then
							note(body, "Nobody else is in this Hub server right now. Use INVITE FRIENDS.", 1)
						end
						button(body, "BACK", RED, o + 2, 36).Activated:Connect(function()
							render()
						end)
					end)
				end)
			end
		end
		order += 1
		button(body, "INVITE FRIENDS (Roblox)", DARK, order, 36).Activated:Connect(function()
			pcall(function()
				SocialService:PromptGameInvite(player)
			end)
		end)
		return order
	end

	render = function()
		clear()
		local order = 0
		if currentTab == "ZOMBIES" then
			order += 1
			note(body, "<b>ZOMBIE BATTLES</b>  six rounds, then Otti in Round 7", order)
			order += 1
			button(body, "SOLO", RED, order).Activated:Connect(function()
				act("PlaySolo")
			end)
			order += 1
			button(body, "CO-OP · START WITH CURRENT PARTY", RED, order).Activated:Connect(function()
				act("StartCoop")
			end)
			order += 1
			button(body, "CO-OP · FIND PLAYERS (1-4)", DARK, order).Activated:Connect(function()
				act("Queue", "COOP_ZOMBIES")
			end)
			order = partySection(order)
		elseif currentTab == "BOSS" then
			order += 1
			note(body, "<b>BOSS FIGHT</b>  solo: you face one of Otti's companions alone. Choose your opponent.", order)
			for _, entry in {
				{ "Otti", "OTTI", "the Champion of the Colosseum" },
				{ "Kroko", "KROKERO", "the fearless protector · bold and reckless when hurt" },
				{ "Schili", "SCHILI", "the calm strategist · patient, cunning, persistent" },
			} do
				order += 1
				button(body, entry[2], RED, order).Activated:Connect(function()
					act("StartBoss", entry[1])
				end)
				order += 1
				note(body, entry[3], order)
			end
		elseif currentTab == "TEAMS" then
			order += 1
			note(body, "<b>TEAM BATTLES</b>  1v1 to 4v4, equal teams, your party stays together", order)
			for _, entry in {
				{ "TIME_BATTLE", "TIME BATTLE", "8 minutes · most eliminations" },
				{ "FIRST_TO", "FIRST TO 20", "first team to the target (10 / 15 / 20)" },
				{ "ELIMINATION", "ELIMINATION", "one life per round · Best of 5" },
			} do
				order += 1
				button(body, entry[2], RED, order).Activated:Connect(function()
					act("Queue", entry[1])
				end)
				order += 1
				note(body, entry[3], order)
			end
			order += 1
			button(body, "LEAVE QUEUE", DARK, order, 36).Activated:Connect(function()
				act("LeaveQueue")
			end)
			order = partySection(order)
		end
	end

	local function close()
		if not isOpen then
			return
		end
		isOpen = false
		panel.Visible = false
		backdrop.Visible = false
		MenuSystem.closed("ModeMenu")
	end
	MenuSystem.register("ModeMenu", close)

	local tabButtons: { [string]: TextButton } = {}
	local function selectTab(tab: string)
		if tab == "LIVE" then
			close()
			openLive() -- LIVE IN THE COLOSSEUM is its own big menu
			return
		end
		currentTab = tab
		for name, b in tabButtons do
			MenuSystem.setState(b, if name == currentTab then "Selected" else "Normal")
		end
		render()
	end
	for i, entry in { { "ZOMBIES", "ZOMBIE BATTLES" }, { "TEAMS", "TEAM BATTLES" }, { "BOSS", "BOSS FIGHT" }, { "LIVE", "WATCH LIVE" } } do
		local b = make("TextButton", { Size = UDim2.new(1 / 4, -3, 1, 0), BackgroundColor3 = DARK, Font = THEME.LabelFont, TextSize = 11, TextWrapped = true, TextColor3 = THEME.Text, Text = entry[2], LayoutOrder = i, ZIndex = 32 }, tabs)
		b:SetAttribute("MenuStyle", "Tab")
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
		tabButtons[entry[1]] = b
		b.Activated:Connect(function()
			selectTab(entry[1])
		end)
	end

	local function open(tab: string?)
		if tab == "LIVE" then
			openLive()
			return
		end
		MenuSystem.opening("ModeMenu") -- closes the lobby menu / live overlay first
		isOpen = true
		panel.Visible = true
		backdrop.Visible = true
		local target = tab or currentTab
		currentTab = target
		MenuSystem.focus(tabButtons[target])
		task.spawn(function()
			invoke("Party")
			if isOpen then
				selectTab(target)
			end
		end)
	end
	playButton.Activated:Connect(function()
		if isOpen then
			close()
		else
			open(nil)
		end
	end)
	closeButton.Activated:Connect(close)
	backdrop.Activated:Connect(close)
	if events then
		events.OnClientEvent:Connect(function(kind: string, data: any)
			if kind == "Party" and typeof(data) == "table" then
				partyState = data
				if isOpen and currentTab ~= "LIVE" then
					render()
				end
			elseif kind == "Teleport" and data == "Travelling" then
				close()
			elseif kind == "OpenMenu" then
				-- the arena portcullis in the lobby (server prompt)
				open(if typeof(data) == "string" then data else nil)
			end
		end)
	end

	return { open = open, close = close }
end

return GameModeMenuController
