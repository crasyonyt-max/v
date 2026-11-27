--!strict
-- Bus HUD. Driver: a panel above the dashboard (line + destination, doors,
-- stop request, tickets sold) and the line pop-up; keys J / K = door 1 / 2.
-- Passenger: line + destination and a big 🛑 HALT button (key H).
-- Config.BusLines (testing server first): 🚏 opens a list of the real lines, "Leerfahrt"
-- and "display off"; on a line, a checkpoint (like the Maps app) shows the next stop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BusLineData = require(ReplicatedStorage.Shared.BusLineData) :: any
local BusStopData = require(ReplicatedStorage.Shared.BusStopData)
local Config = require(ReplicatedStorage.Shared.Config)
local Make = require(script.Parent.Parent.UI.Make)
local Waypoint = require(script.Parent.Parent.UI.Waypoint)
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
	Size = UDim2.fromOffset(340, 80),
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

local stopLabel = Make.Label("", 12, Color3.fromRGB(120, 220, 140), T.bold, {
	Position = UDim2.fromOffset(10, 56),
	Size = UDim2.new(1, -20, 0, 18),
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

-- driver (bus lines): choose a line / Leerfahrt / display off
local linesOn = Config.On(Config.BusLines)
local chooser = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.fromOffset(340, 420),
	BackgroundColor3 = T.bg,
	Visible = false,
	Parent = gui,
}, { Make.Corner(14), Make.Stroke(Color3.fromRGB(11, 110, 138), 2) })
Make.Label(Store.T("bus_line_title"), 17, T.text, T.black, {
	Position = UDim2.fromOffset(14, 10),
	Size = UDim2.new(1, -28, 0, 24),
	Parent = chooser,
})
local chooserList = Make.Scroll({
	Position = UDim2.fromOffset(10, 40),
	Size = UDim2.new(1, -20, 1, -90),
	Parent = chooser,
})
Make.Button(Store.T("cancel"), T.panel, function()
	chooser.Visible = false
end, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.new(1, -20, 0, 36),
	Parent = chooser,
})
local function choose(mode: string, id: number?)
	chooser.Visible = false
	task.spawn(function()
		local r = Net.Request("Bus.Route", mode, id)
		if not r.ok then
			Notify.Error(r.err)
		end
	end)
end
do
	local order = 0
	local function add(text: string, color: Color3, fn: () -> ())
		order += 1
		Make.Button(text, color, fn, {
			LayoutOrder = order,
			Size = UDim2.new(1, -6, 0, 38),
			TextSize = 14,
			Parent = chooserList,
		})
	end
	add(Store.T("bus_route_off"), Color3.fromRGB(20, 20, 22), function()
		choose("off")
	end)
	add(Store.T("bus_route_empty"), Color3.fromRGB(90, 90, 96), function()
		choose("empty")
	end)
	for i, line in BusLineData do
		add(
			(if tostring(line.ref):sub(1, 1) == "N" then "🌙 " else "")
				.. ("%s → %s  ·  %s"):format(line.ref, line.to, Store.T("bus_route_stops", #line.stops)),
			if tostring(line.ref):sub(1, 1) == "N" then Color3.fromRGB(30, 40, 90) else Color3.fromRGB(11, 110, 138),
			function()
				choose("line", i)
			end
		)
	end
end

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

-- the next stop of the line (BusStopData entry) or nil
local checkpoint: number? = nil
local function nextStop(m: Model): ({ any }?, number?)
	local line = BusLineData[tonumber(m:GetAttribute("BusRoute")) or 0]
	local k = tonumber(m:GetAttribute("BusNext")) or 0
	local idx = line and line.stops[k]
	return (if idx then BusStopData[idx] :: any else nil), idx
end

local function leave()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	bus = nil
	gui.Enabled = false
	popup.Visible = false
	chooser.Visible = false
	stopButton.Visible = false
	if checkpoint then
		checkpoint = nil
		Waypoint.Clear()
	end
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
	-- next stop: on a line the checkpoint, otherwise the nearest stop (twice a second)
	task.spawn(function()
		while bus == model and model.Parent do
			local pos = model:GetPivot().Position
			local st, idx = nil, nil
			if linesOn then
				st, idx = nextStop(model)
			end
			if st then
				local d = math.sqrt((st[2] - pos.X) ^ 2 + (st[3] - pos.Z) ^ 2)
				stopLabel.Text = Store.T("bus_next_checkpoint", st[1], math.floor(d * 0.28))
				if isDriver and checkpoint ~= idx then
					checkpoint = idx
					Waypoint.Set(Vector3.new(st[2], pos.Y, st[3]), "🚏 " .. st[1], Color3.fromRGB(0, 130, 70))
				end
			else
				if checkpoint then
					checkpoint = nil
					Waypoint.Clear()
				end
				if
					linesOn
					and isDriver
					and tostring(model:GetAttribute("BusDest") or "") == ""
					and model:GetAttribute("BusRoute") == nil
					and not model:GetAttribute("FreeRide")
				then
					stopLabel.Text = Store.T("bus_no_line")
				else
					local best, bestD = nil, 700
					for _, s2 in BusStopData do
						local d = math.sqrt((s2[2] - pos.X) ^ 2 + (s2[3] - pos.Z) ^ 2)
						if d < bestD then
							best, bestD = s2, d
						end
					end
					stopLabel.Text = if best then Store.T("bus_next_stop", best[1], math.floor(bestD * 0.28)) else ""
				end
			end
			task.wait(0.5)
		end
	end)
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
	if linesOn then
		chooser.Visible = not chooser.Visible
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
