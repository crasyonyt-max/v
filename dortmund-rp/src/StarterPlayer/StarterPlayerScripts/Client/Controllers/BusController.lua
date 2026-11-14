--!strict
-- Bus HUD. Driver: a panel above the dashboard (line + destination, doors,
-- stop request, tickets sold) and the line pop-up; keys J / K = door 1 / 2.
-- Passenger: line + destination and a big 🛑 HALT button (key H).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Make = require(script.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.UI.Notify)
local Net = require(script.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme

local player = Players.LocalPlayer
local BusController = {}

local LED = Color3.fromRGB(255, 170, 30)
local RED = Color3.fromRGB(220, 40, 40)

local gui = New("ScreenGui", {
	Name = "BusHUD",
	ResetOnSpawn = false,
	DisplayOrder = 9,
	Enabled = false,
	Parent = player:WaitForChild("PlayerGui"),
})

-- shared: the LED line display
local panel = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -136),
	Size = UDim2.fromOffset(340, 62),
	BackgroundColor3 = Color3.fromRGB(8, 8, 10),
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { Make.Corner(12), Make.Stroke(Color3.fromRGB(60, 60, 70), 1) })
local led = New("TextLabel", {
	Position = UDim2.fromOffset(8, 6),
	Size = UDim2.new(1, -16, 0, 26),
	BackgroundColor3 = Color3.fromRGB(14, 14, 14),
	Font = Enum.Font.Arcade,
	TextScaled = true,
	TextColor3 = LED,
	Text = "",
	Parent = panel,
}, { Make.Corner(6) })
local info = Make.Label("", 12, T.sub, T.bold, {
	Position = UDim2.fromOffset(10, 36),
	Size = UDim2.new(1, -20, 0, 20),
	RichText = true,
	Parent = panel,
})

-- passenger: stop button
local stopButton = Make.Button(Store.T("bus_stop_button"), RED, function()
	BusController.RequestStop()
end, {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -150),
	Size = UDim2.fromOffset(120, 64),
	TextSize = 20,
	Visible = false,
	Parent = gui,
})

-- driver: line pop-up
local popup = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.fromOffset(300, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = T.bg,
	Visible = false,
	Parent = gui,
}, { Make.Corner(14), Make.Padding(14), Make.List(8), Make.Stroke(Color3.fromRGB(11, 110, 138), 2) })
Make.Label(Store.T("bus_line_title"), 17, T.text, T.black, { LayoutOrder = 1, Parent = popup })
local lineBox =
	Make.TextBox(Store.T("bus_line") .. " (440)", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 36), Parent = popup })
local destBox = Make.TextBox(
	Store.T("bus_dest") .. " (Hauptbahnhof)",
	{ LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 36), Parent = popup }
)
Make.Button("✅ " .. Store.T("bus_save"), T.good, function()
	local line, dest = lineBox.Text, destBox.Text
	task.spawn(function()
		local r = Net.Request("Bus.Line", line, dest)
		if r.ok then
			popup.Visible = false
		else
			Notify.Error(r.err)
		end
	end)
end, { LayoutOrder = 4, Parent = popup })
Make.Button(Store.T("cancel"), T.panel, function()
	popup.Visible = false
end, { LayoutOrder = 5, Parent = popup })

-- state ------------------------------------------------------------------------------
local bus: Model? = nil
local isDriver = false
local conns: { RBXScriptConnection } = {}
local ding = Instance.new("Sound")
ding.SoundId = "rbxasset://sounds/electronicpingshort.wav"
ding.Volume = 0.8
ding.Parent = gui

local function refresh()
	local m = bus
	if not m then
		return
	end
	local line = tostring(m:GetAttribute("BusLine") or "")
	local dest = tostring(m:GetAttribute("BusDest") or "")
	led.Text = (if line ~= "" then line .. "  " else "") .. dest
	local stopping = m:GetAttribute("StopRequest") == true
	if isDriver then
		local function door(i: number): string
			local open = m:GetAttribute("Door" .. i .. "Open") == true
			return ('🚪%d <font color="#%s">%s</font>'):format(
				i,
				if open then "40DC50" else "AAAAAA",
				Store.T(if open then "bus_open" else "bus_shut")
			)
		end
		local parts = { door(1), door(2) }
		if stopping then
			table.insert(parts, '<font color="#FF4040">' .. Store.T("bus_stopping") .. "</font>")
		elseif not m:GetAttribute("FreeRide") then
			table.insert(
				parts,
				Store.T("bus_tickets", m:GetAttribute("TicketsSold") or 0, m:GetAttribute("TicketIncome") or 0)
			)
		end
		info.Text = table.concat(parts, "   ")
	else
		info.Text = if stopping then '<font color="#FF4040">' .. Store.T("bus_stopping") .. "</font>" else ""
		stopButton.BackgroundColor3 = if stopping then Color3.fromRGB(120, 30, 30) else RED
		stopButton.Text = Store.T(if stopping then "bus_stopping" else "bus_stop_button")
	end
end

local function leave()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	bus = nil
	gui.Enabled = false
	popup.Visible = false
	stopButton.Visible = false
end

local function enter(model: Model, driver: boolean)
	leave()
	bus = model
	isDriver = driver
	gui.Enabled = true
	stopButton.Visible = not driver
	-- passengers: panel sits lower (no dashboard below it)
	panel.Position = if driver then UDim2.new(0.5, 0, 1, -136) else UDim2.new(0.5, 0, 1, -10)
	for _, a in { "BusLine", "BusDest", "Door1Open", "Door2Open", "TicketsSold", "TicketIncome" } do
		table.insert(conns, model:GetAttributeChangedSignal(a):Connect(refresh))
	end
	table.insert(
		conns,
		model:GetAttributeChangedSignal("StopRequest"):Connect(function()
			if model:GetAttribute("StopRequest") then
				ding:Play()
			end
			refresh()
		end)
	)
	refresh()
end

function BusController.RequestStop()
	if not bus or isDriver or bus:GetAttribute("StopRequest") then
		return
	end
	task.spawn(function()
		local r = Net.Request("Bus.Stop")
		if not r.ok then
			Notify.Error(r.err)
		end
	end)
end

function BusController.Door(i: number)
	if not bus or not isDriver then
		return
	end
	task.spawn(function()
		local r = Net.Request("Bus.Door", i)
		if not r.ok and r.err ~= "too_fast" then
			Notify.Error(r.err)
		end
	end)
end

function BusController.OpenLine()
	if not bus or not isDriver then
		return
	end
	lineBox.Text = tostring(bus:GetAttribute("BusLine") or "")
	destBox.Text = ""
	popup.Visible = true
end

local function watch(character: Model)
	leave()
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		local seat = hum.SeatPart
		local model = seat and seat.Parent
		if seat and model and model:IsA("Model") and model:GetAttribute("Bus") then
			enter(model, seat.Name == "DriverSeat")
		elseif bus then
			leave()
		end
	end)
end
player.CharacterAdded:Connect(watch)
if player.Character then
	task.spawn(watch, player.Character)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not bus then
		return
	end
	local k = input.KeyCode
	if isDriver and k == Enum.KeyCode.J then
		BusController.Door(1)
	elseif isDriver and k == Enum.KeyCode.K then
		BusController.Door(2)
	elseif not isDriver and k == Enum.KeyCode.H then
		BusController.RequestStop()
	end
end)

return BusController
