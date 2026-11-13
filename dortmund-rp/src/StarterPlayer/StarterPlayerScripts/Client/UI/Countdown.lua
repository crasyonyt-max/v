--!strict
-- AA countdown banner (set in the Admin app's AA tab, the same on every server):
-- "⏳ AA: 2h:10min:7s", then "🎉 AA – jetzt!" for a few minutes.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Make = require(script.Parent.Make)
local Net = require(script.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme

local Countdown = {}

local gui = New("ScreenGui", {
	Name = "Countdown",
	ResetOnSpawn = false,
	DisplayOrder = 7,
	Enabled = false,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})
local label = Make.Label("", 18, Color3.new(1, 1, 1), T.black, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(0, 40),
	AutomaticSize = Enum.AutomaticSize.X,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextWrapped = false,
	BackgroundColor3 = Color3.fromRGB(150, 30, 160),
	BackgroundTransparency = 0.1,
	Parent = gui,
})
New("UICorner", { CornerRadius = UDim.new(0, 12), Parent = label })
New("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = label })
New("UIStroke", {
	Color = Color3.fromRGB(255, 200, 60),
	Thickness = 2,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	Parent = label,
})

local current: { [string]: any }? = nil

function Countdown.Format(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	local text = string.format("%dh:%02dmin:%02ds", h, m, s)
	return if d > 0 then string.format("%dd %s", d, text) else text
end

local function tick()
	local c = current
	if not c then
		gui.Enabled = false
		return
	end
	local left = (tonumber(c.at) or 0) - Workspace:GetServerTimeNow()
	gui.Enabled = true
	if left > 0 then
		label.Text = "⏳ " .. tostring(c.title) .. ": " .. Countdown.Format(left)
	else
		label.Text = "🎉 " .. tostring(c.title) .. " – " .. Store.T("countdown_now")
	end
end

local function onEvents(e: any)
	if typeof(e) == "table" then
		current = if typeof(e.countdown) == "table" then e.countdown else nil
		tick()
	end
end

Net.On("Events", onEvents)
task.spawn(function()
	local r = Net.Request("Events.Get")
	if r.ok then
		onEvents(r)
	end
end)
task.spawn(function()
	while true do
		task.wait(1)
		if current and (tonumber(current.at) or 0) + 300 < Workspace:GetServerTimeNow() then
			current = nil
		end
		tick()
	end
end)

return Countdown
