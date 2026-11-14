--!strict
-- "Choose your plate" pop-up. The server sends PlateRequired when a car would go out
-- without a plate (own car: its plate; job / admin car: your personal plate). After
-- choosing, the original spawn request is repeated, so the car comes right away.

local Players = game:GetService("Players")

local Make = require(script.Parent.Make)
local Notify = require(script.Parent.Notify)
local Net = require(script.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme

local PlatePrompt = {}

local gui = New("ScreenGui", {
	Name = "PlatePrompt",
	ResetOnSpawn = false,
	DisplayOrder = 40,
	Enabled = false,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})
New("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	Parent = gui,
})
local box = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.fromOffset(320, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = T.bg,
	Parent = gui,
}, { Make.Corner(14), Make.Padding(14), Make.List(10), Make.Stroke(Color3.fromRGB(0, 50, 153), 2) })

local title = Make.Label("", 17, T.text, T.black, { LayoutOrder = 1, Parent = box })
local sub = Make.Label("", 12, T.sub, T.font, { LayoutOrder = 2, Parent = box })
-- the plate itself: blue EU strip with D, fixed "DO-", then your letters + digits
local plate = New("Frame", {
	LayoutOrder = 3,
	Size = UDim2.new(1, 0, 0, 52),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Parent = box,
}, { Make.Corner(6), Make.Stroke(Color3.new(0, 0, 0), 2) })
New("Frame", {
	Size = UDim2.new(0, 30, 1, 0),
	BackgroundColor3 = Color3.fromRGB(0, 50, 153),
	Parent = plate,
}, { Make.Corner(6) })
Make.Label("D", 14, Color3.new(1, 1, 1), T.bold, {
	Position = UDim2.fromOffset(0, 26),
	Size = UDim2.fromOffset(30, 22),
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = plate,
})
Make.Label("DO-", 30, Color3.new(0, 0, 0), T.black, {
	Position = UDim2.fromOffset(38, 0),
	Size = UDim2.fromOffset(70, 52),
	Parent = plate,
})
local input = Make.TextBox("AB 123", {
	Position = UDim2.fromOffset(106, 6),
	Size = UDim2.new(1, -112, 1, -12),
	TextSize = 26,
	Font = T.black,
	BackgroundColor3 = Color3.fromRGB(240, 240, 240),
	TextColor3 = Color3.new(0, 0, 0),
	PlaceholderColor3 = Color3.fromRGB(150, 150, 150),
	Parent = plate,
})
local pending: { [string]: any }? = nil

local function close()
	gui.Enabled = false
	pending = nil
end

local confirm = Make.Button("✅ " .. Store.T("plate_set_go"), T.good, function()
	local p = pending
	if not p then
		return
	end
	local text = "DO-" .. input.Text
	local r = if p.uid
		then Net.Request("Vehicle.SetPlate", p.uid, text)
		else Net.Request("Vehicle.SetPersonalPlate", text)
	if not r.ok then
		Notify.Error(r.err)
		return
	end
	close()
	-- now take the car out (the request that asked for the plate)
	local retry = p.retry
	if typeof(retry) == "table" and typeof(retry[1]) == "string" then
		local again = Net.Request(retry[1], table.unpack(retry, 2))
		if not again.ok then
			Notify.Error(again.err)
		end
	end
end, { LayoutOrder = 4, Parent = box })
local _ = confirm
Make.Button(Store.T("cancel"), T.panel, close, { LayoutOrder = 5, Parent = box })

Net.On("PlateRequired", function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	pending = payload
	input.Text = ""
	title.Text = "🔢 " .. Store.T("plate_choose")
	sub.Text = if payload.uid then Store.T("plate_for_car", tostring(payload.name or "")) else Store.T("plate_personal")
	gui.Enabled = true
end)

return PlatePrompt
