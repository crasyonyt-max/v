--!strict
-- Vote panel: shows the running vote on this server with live percentages.
-- Tap an answer to vote (once). The ▾ button folds it up.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Make = require(script.Parent.Make)
local Notify = require(script.Parent.Notify)
local Net = require(script.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme

local Vote = {}

local gui = New("ScreenGui", {
	Name = "Vote",
	ResetOnSpawn = false,
	DisplayOrder = 7,
	Enabled = false,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})
local panel = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(300, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = T.bg,
	BackgroundTransparency = 0.08,
	Parent = gui,
}, { Make.Corner(12), Make.Padding(10), Make.List(6), Make.Stroke(T.accent, 2) })

local current: { [string]: any }? = nil
local mine: number? = nil
local folded = false
local timerLabel: TextLabel? = nil

local function timeLeft(): string
	local v = current
	if not v then
		return ""
	end
	if v.done then
		return Store.T("vote_over")
	end
	local left = math.max(0, math.floor(v.ends - Workspace:GetServerTimeNow()))
	return string.format("⏱ %d:%02d", left // 60, left % 60)
end

local function render()
	Make.Clear(panel)
	timerLabel = nil
	local v = current
	gui.Enabled = v ~= nil
	if not v then
		return
	end
	local head =
		New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 0, Parent = panel })
	Make.Label("🗳️ " .. Store.T("vote"), 14, T.text, T.black, { Size = UDim2.new(1, -110, 1, 0), Parent = head })
	timerLabel = Make.Label(timeLeft(), 12, T.sub, T.bold, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -32, 0, 0),
		Size = UDim2.fromOffset(80, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = head,
	})
	Make.Button(if folded then "▸" else "▾", T.card, function()
		folded = not folded
		render()
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(26, 22),
		TextSize = 12,
		Parent = head,
	})
	Make.Label(tostring(v.question), 15, T.text, T.bold, { LayoutOrder = 1, Parent = panel })
	if folded then
		return
	end
	local total = math.max(0, tonumber(v.total) or 0)
	local showResults = mine ~= nil or v.done
	local best = 0
	for _, c in v.counts do
		best = math.max(best, c)
	end
	for i, option in v.options do
		local count = v.counts[i] or 0
		local pct = if total > 0 then count / total else 0
		local button = New("TextButton", {
			LayoutOrder = 1 + i,
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = T.card,
			AutoButtonColor = not showResults,
			Text = "",
			Parent = panel,
		}, { Make.Corner(8) })
		if showResults then
			local winner = v.done and count == best and count > 0
			New("Frame", {
				Size = UDim2.fromScale(pct, 1),
				BackgroundColor3 = if winner then T.good elseif mine == i then T.accent else Color3.fromRGB(80, 85, 95),
				BackgroundTransparency = 0.25,
				Parent = button,
			}, { Make.Corner(8) })
		end
		Make.Label((if mine == i then "✓ " else "") .. tostring(option), 13, T.text, T.bold, {
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -70, 1, 0),
			Parent = button,
		})
		if showResults then
			Make.Label(string.format("%d %%", math.floor(pct * 100 + 0.5)), 13, T.text, T.black, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 0),
				Size = UDim2.fromOffset(56, 34),
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = button,
			})
		end
		button.Activated:Connect(function()
			if mine or v.done then
				return
			end
			local r = Net.Request("Vote.Cast", i)
			if not r.ok then
				Notify.Error(r.err)
			end
		end)
	end
	Make.Label(Store.T("vote_count", total) .. "  ·  " .. tostring(v.by), 11, T.sub, T.font, {
		LayoutOrder = 10,
		Parent = panel,
	})
end

local function set(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local before = current and current.id
	current = if typeof(payload.vote) == "table" then payload.vote else nil
	mine = if typeof(payload.mine) == "number" then payload.mine else nil
	if current and current.id ~= before and not current.done then
		folded = false
		Notify.Show("🗳️ " .. tostring(current.question), false, 5)
	end
	render()
end

Net.On("Vote", set)
task.spawn(function()
	local r = Net.Request("Vote.Get")
	if r.ok then
		set(r)
	end
end)
task.spawn(function()
	while true do
		task.wait(1)
		if timerLabel then
			timerLabel.Text = timeLeft()
		end
	end
end)

return Vote
