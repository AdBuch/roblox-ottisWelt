--!strict
-- Compact travel / queue status (both places), top centre below the score capsule:
--   * "Travelling to the Colosseum…", "Returning to the Hub…", failures (from MatchEvent "Teleport")
--   * the matchmaking chip: SEARCHING · TIME BATTLE · 0:23  [LEAVE]  (+ START WITH CURRENT PARTY
--     for co-op after a short wait) — from MatchEvent "Queue"
--   * Arena: the emergency RETURN TO HUB button when a return teleport failed or was rejected
-- Display and requests only; the server decides everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiConfig = require(Shared:WaitForChild("UiConfig"))

export type TeleportStatus = {
	flash: (text: string, seconds: number?) -> (),
}

local TeleportStatusController = {}

local function pillButton(parent: Instance, text: string, color: Color3, width: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, 30)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = b
	return b
end

function TeleportStatusController.start(gui: ScreenGui, request: RemoteFunction?, events: RemoteEvent?, isArena: boolean): TeleportStatus
	local holder = Instance.new("Frame")
	holder.Name = "TravelStatus"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 40)
	holder.Size = UDim2.fromOffset(0, 32)
	holder.AutomaticSize = Enum.AutomaticSize.X
	holder.BackgroundColor3 = UiConfig.Panel
	holder.BackgroundTransparency = 0.2
	holder.Visible = false
	holder.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = holder
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 4)
	padding.Parent = holder
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 6)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = holder
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromOffset(0, 32)
	text.AutomaticSize = Enum.AutomaticSize.X
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 13
	text.TextColor3 = Color3.new(1, 1, 1)
	text.LayoutOrder = 1
	text.Parent = holder
	local startButton = pillButton(holder, "START WITH CURRENT PARTY", Color3.fromRGB(150, 40, 34), 200)
	startButton.LayoutOrder = 2
	startButton.Visible = false
	local leaveButton = pillButton(holder, "LEAVE", Color3.fromRGB(80, 70, 60), 64)
	leaveButton.LayoutOrder = 3
	leaveButton.Visible = false
	local hubButton = pillButton(holder, "RETURN TO HUB", Color3.fromRGB(150, 110, 30), 130)
	hubButton.LayoutOrder = 4
	hubButton.Visible = false

	local queue: { mode: string, since: number, offerStartAfter: number }? = nil
	local flashUntil = 0
	local flashText = ""

	local function invoke(action: string)
		if not request then
			return
		end
		task.spawn(function()
			pcall(function()
				request:InvokeServer(action)
			end)
		end)
	end

	local function refresh()
		local now = os.clock()
		local current = queue
		if now < flashUntil then
			text.Text = flashText
			startButton.Visible = false
			leaveButton.Visible = false
			holder.Visible = true
		elseif current and current.mode ~= "" then
			local waited = math.max(0, os.time() - current.since)
			text.Text = ("SEARCHING · %s · %d:%02d"):format((current.mode:gsub("_", " ")), waited // 60, waited % 60)
			leaveButton.Visible = true
			startButton.Visible = current.mode == "COOP_ZOMBIES" and waited >= current.offerStartAfter
			holder.Visible = true
		else
			startButton.Visible = false
			leaveButton.Visible = false
			holder.Visible = hubButton.Visible
			if hubButton.Visible then
				text.Text = "Return failed"
			end
		end
	end

	local function flash(message: string, seconds: number?)
		flashText = message
		flashUntil = os.clock() + (seconds or 4)
		refresh()
	end

	leaveButton.Activated:Connect(function()
		invoke("LeaveQueue")
	end)
	startButton.Activated:Connect(function()
		invoke("StartCoop")
	end)
	hubButton.Activated:Connect(function()
		hubButton.Visible = false
		flash("Returning to the Hub…", 6)
		invoke("ReturnToHub")
	end)

	if events then
		events.OnClientEvent:Connect(function(kind: string, a: any, b: any)
			if kind == "Queue" and typeof(a) == "table" then
				queue = { mode = tostring(a.mode or ""), since = tonumber(a.since) or os.time(), offerStartAfter = tonumber(a.offerStartAfter) or 20 }
				refresh()
			elseif kind == "Teleport" then
				if a == "Travelling" then
					flash(("TRAVELLING · %s"):format((tostring(b or ""):gsub("_", " "))), 25)
				elseif a == "Returning" then
					flash("RETURNING TO THE HUB…", 25)
				elseif a == "Mock" then
					flash("STUDIO MOCK · no teleport", 5)
				elseif a == "Failed" then
					flashUntil = 0
					refresh()
				end
			elseif kind == "ReturnFailed" or kind == "Rejected" then
				flashUntil = 0
				hubButton.Visible = isArena
				if typeof(a) == "string" then
					flash(a, 4)
				end
				refresh()
			end
		end)
	end
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)
	return { flash = flash }
end

return TeleportStatusController
