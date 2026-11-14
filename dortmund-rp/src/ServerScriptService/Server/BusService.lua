--!strict
-- City buses (RealisticCars type "Bus"): passenger seats, two doors on the right
-- side, a line + destination display, the stop request ("Haltewunsch") and tickets.
--   * passengers can only get on while a door is open
--   * the ticket (Config.BusFare) goes from the passenger to the bus driver
--     (admin bus and riding your own bus: free)
--   * a passenger presses 🛑 -> every display in the bus shows "Wagen hält",
--     the next time a door opens the request is cleared

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(script.Parent.EconomyService)
local GameLog = require(script.Parent.GameLog)
local Remotes = require(script.Parent.Remotes)
local Roles = require(script.Parent.Roles)
local XPService = require(script.Parent.XPService)

local BusService = {}

local FARE = Config.BusFare or 5
local TICKET_XP = 10
local SEAT_GAP = 4.4 -- studs between seat rows
local MAX_ROWS = 10
local LED = Color3.fromRGB(255, 170, 30)

local function weld(part: BasePart, to: BasePart)
	local w = Instance.new("Weld")
	w.Part0 = to
	w.Part1 = part
	w.C0 = to.CFrame:ToObjectSpace(part.CFrame)
	w.Parent = part
end

local function part(
	model: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = model
	return p
end

-- the LED destination display (front, right side, rear)
local function display(p: BasePart, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LineDisplay"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = p
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.BackgroundTransparency = 1
	line.Size = UDim2.fromScale(0.22, 1)
	line.Font = Enum.Font.Arcade
	line.TextScaled = true
	line.TextColor3 = LED
	line.Parent = bg
	local dest = Instance.new("TextLabel")
	dest.Name = "Dest"
	dest.BackgroundTransparency = 1
	dest.Position = UDim2.fromScale(0.24, 0)
	dest.Size = UDim2.fromScale(0.76, 1)
	dest.Font = Enum.Font.Arcade
	dest.TextScaled = true
	dest.TextColor3 = LED
	dest.TextXAlignment = Enum.TextXAlignment.Left
	dest.Parent = bg
end

local function refreshDisplays(model: Model)
	local line = tostring(model:GetAttribute("BusLine") or "")
	local dest = tostring(model:GetAttribute("BusDest") or "")
	if model:GetAttribute("StopRequest") then
		dest = dest .. "  ·  WAGEN HÄLT"
	end
	for _, d in model:GetDescendants() do
		if d:IsA("SurfaceGui") and d.Name == "LineDisplay" then
			local bg = d:FindFirstChildOfClass("Frame")
			if bg then
				((bg :: any).Line :: TextLabel).Text = line;
				((bg :: any).Dest :: TextLabel).Text = dest
			end
		end
	end
end

local function playerIn(seat: Seat | VehicleSeat): Player?
	local hum = seat.Occupant
	return hum and Players:GetPlayerFromCharacter(hum.Parent)
end

local function driverOf(model: Model): Player?
	local seat = model:FindFirstChild("DriverSeat")
	return if seat and seat:IsA("VehicleSeat") then playerIn(seat) else nil
end

local function doorsOpen(model: Model): boolean
	return model:GetAttribute("Door1Open") == true or model:GetAttribute("Door2Open") == true
end

-- the bus this player drives (driver seat) / rides in (passenger seat)
local function busOf(player: Player): (Model?, boolean)
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local model = seat and seat.Parent
	if not seat or not model or not model:IsA("Model") or not model:GetAttribute("Bus") then
		return nil, false
	end
	return model, seat.Name == "DriverSeat"
end
BusService.BusOf = busOf

-- passengers pay the driver when they sit down
local function standUp(seat: Seat)
	local hum = seat.Occupant
	if hum then
		task.defer(function()
			hum.Sit = false
			hum.Jump = true
		end)
	end
end

-- Admin bus: only admins (any admin rank) may ride, and they ride free.
function BusService.MayBoard(model: Model, passenger: Player): boolean
	return not model:GetAttribute("AdminBus") or Roles.IsServerAdmin(passenger)
end

local function onBoard(model: Model, seat: Seat, passenger: Player, owner: Player)
	if not BusService.MayBoard(model, passenger) then
		standUp(seat)
		Remotes.Push(passenger, "Notify", { key = "bus_admin_only", error = true })
		return
	end
	if not doorsOpen(model) then
		-- (only possible through glitches: the prompts are off while the doors are shut)
		standUp(seat)
		Remotes.Push(passenger, "Notify", { key = "bus_doors_closed", error = true })
		return
	end
	local driver = driverOf(model)
	if model:GetAttribute("FreeRide") or not driver or driver == passenger or passenger == owner then
		Remotes.Push(passenger, "Notify", { key = "bus_free_ride" })
		return
	end
	if not Economy.TrySpend(passenger, FARE, "Busticket Linie " .. tostring(model:GetAttribute("BusLine") or "")) then
		local hum = seat.Occupant
		if hum then
			task.defer(function()
				hum.Sit = false
				hum.Jump = true
			end)
		end
		Remotes.Push(passenger, "Notify", { key = "bus_no_money", args = { FARE }, error = true })
		return
	end
	Economy.Add(driver, FARE, "Busticket: " .. passenger.Name)
	pcall(XPService.Earn, driver, "Bus", TICKET_XP, "Busticket")
	model:SetAttribute("TicketsSold", (tonumber(model:GetAttribute("TicketsSold")) or 0) + 1)
	model:SetAttribute("TicketIncome", (tonumber(model:GetAttribute("TicketIncome")) or 0) + FARE)
	Remotes.Push(passenger, "Notify", { key = "bus_ticket_bought", args = { FARE } })
	Remotes.Push(driver, "Notify", { key = "bus_ticket_sold", args = { passenger.DisplayName, FARE } })
	GameLog.Add("money", passenger, ("bus ticket %d € -> %s"):format(FARE, driver.Name))
end

-- Adds the bus parts (before the model is parented). Everything is welded to the
-- chassis, massless and non-colliding. Returns false for a model without a body.
function BusService.Build(model: Model, freeRide: boolean): boolean
	local chassis = model:FindFirstChild("Chassis") :: BasePart?
	local hb = model:FindFirstChild("Hitbox") :: BasePart?
	local driverSeat = model:FindFirstChild("DriverSeat") :: BasePart?
	if not chassis or not hb or not driverSeat then
		return false
	end
	model:SetAttribute("Bus", true)
	model:SetAttribute("Door1Open", false)
	model:SetAttribute("Door2Open", false)
	model:SetAttribute("StopRequest", false)
	model:SetAttribute("TicketsSold", 0)
	model:SetAttribute("TicketIncome", 0)
	model:SetAttribute("FreeRide", freeRide)
	model:SetAttribute("AdminBus", freeRide)
	model:SetAttribute("BusLine", if freeRide then "A" else "")
	model:SetAttribute("BusDest", if freeRide then "ADMIN SHUTTLE" else "Sonderfahrt")

	-- body frame: -Z = front, +X = right (door side)
	local frame = hb.CFrame
	local W, L = hb.Size.X, hb.Size.Z
	local driverLocal = frame:PointToObjectSpace(driverSeat.CFrame.Position)
	local floorY = -hb.Size.Y / 2
	local roofY = floorY + 10
	local body = model:FindFirstChild("Body")
	local roof = body and body:FindFirstChild("Roof", true) :: BasePart?
	if roof then
		roofY = frame:PointToObjectSpace(roof.CFrame.Position).Y
	end
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end

	-- doors (right side): front door next to the driver, middle door in the centre
	local doorH = roofY - floorY - 0.8
	local doorZ = { driverLocal.Z + 1, 0 }
	for i, z in doorZ do
		for leaf = -1, 1, 2 do
			local p = part(
				model,
				("Door%d_%d"):format(i, leaf),
				Vector3.new(0.25, doorH, 2.3),
				at(W / 2 + 0.12, floorY + doorH / 2 + 0.2, z + leaf * 1.15),
				Color3.fromRGB(70, 90, 100),
				Enum.Material.Glass
			)
			p.Transparency = 0.35
			p:SetAttribute("Leaf", leaf)
			p:SetAttribute("Door", i)
			weld(p, chassis)
		end
		local lamp = part(
			model,
			("DoorLamp%d"):format(i),
			Vector3.new(0.3, 0.3, 1.2),
			at(W / 2 + 0.15, floorY + doorH + 0.5, z),
			Color3.fromRGB(60, 20, 20),
			Enum.Material.Neon
		)
		weld(lamp, chassis)
	end

	-- passenger seats: rows of 2 + 2 behind the driver, none in front of the middle door
	local rows = 0
	local seatY = driverLocal.Y
	local z = driverLocal.Z + 7
	local n = 2
	while z < L / 2 - 2 and rows < MAX_ROWS do
		for _, x in { -W / 2 + 1.4, -W / 2 + 3.2, W / 2 - 3.2, W / 2 - 1.4 } do
			if x > 0 and math.abs(z - doorZ[2]) < 3 then
				continue -- standing room at the middle door
			end
			n += 1
			local cf = at(x, seatY, z)
			local cushion = part(
				model,
				"BusSeatCushion",
				Vector3.new(1.7, 0.35, 1.7),
				cf * CFrame.new(0, -0.25, 0),
				Color3.fromRGB(20, 70, 110)
			)
			weld(cushion, chassis)
			local back = part(
				model,
				"BusSeatBack",
				Vector3.new(1.7, 2.2, 0.3),
				cf * CFrame.new(0, 0.9, 0.95),
				Color3.fromRGB(20, 70, 110)
			)
			weld(back, chassis)
			local seat = Instance.new("Seat")
			seat.Name = "Seat" .. n
			seat.Size = Vector3.new(1.6, 0.2, 1.6)
			seat.CFrame = cf
			seat.Transparency = 1
			seat.CanCollide = false
			seat.CanTouch = false
			seat.Massless = true
			seat.Parent = model
			weld(seat, chassis)
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "EnterPrompt"
			prompt.ActionText = if freeRide then "Einsteigen (nur Admins)" else "Einsteigen (" .. FARE .. " €)"
			prompt.ObjectText = model.Name
			prompt.HoldDuration = 0.15
			prompt.MaxActivationDistance = 14
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.Q
			prompt.Enabled = false
			prompt.Parent = seat
		end
		rows += 1
		z += SEAT_GAP
	end

	-- destination displays
	local front =
		part(model, "LineFront", Vector3.new(W * 0.8, 1.4, 0.1), at(0, roofY - 1, -L / 2 - 0.08), Color3.new())
	display(front, Enum.NormalId.Front)
	weld(front, chassis)
	local side =
		part(model, "LineSide", Vector3.new(0.1, 1.1, 7), at(W / 2 + 0.08, roofY - 0.9, doorZ[1] + 5), Color3.new())
	display(side, Enum.NormalId.Right)
	weld(side, chassis)
	local rear = part(model, "LineRear", Vector3.new(W * 0.4, 1.1, 0.1), at(0, roofY - 0.9, L / 2 + 0.08), Color3.new())
	display(rear, Enum.NormalId.Back)
	weld(rear, chassis)
	refreshDisplays(model)
	-- doors start closed: nobody gets on yet (also the builder's front passenger seat)
	for _, s in model:GetChildren() do
		local prompt = s:IsA("Seat") and s:FindFirstChild("EnterPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = false
		end
	end
	return true
end

-- Called by VehicleService.spawnCar before the model is parented.
function BusService.Equip(model: Model, owner: Player, freeRide: boolean)
	if not BusService.Build(model, freeRide) then
		return
	end
	-- doors: slide the leaves open, lamp green, prompts on; opening clears the stop request
	local function applyDoors()
		local open = { model:GetAttribute("Door1Open") == true, model:GetAttribute("Door2Open") == true }
		for _, p in model:GetChildren() do
			local i = p:GetAttribute("Door")
			local leaf = p:GetAttribute("Leaf")
			if i and leaf and p:IsA("BasePart") then
				local w = p:FindFirstChildOfClass("Weld")
				local closedC0 = p:GetAttribute("ClosedC0") :: CFrame?
				if w then
					if not closedC0 then
						closedC0 = w.C0
						p:SetAttribute("ClosedC0", closedC0)
					end
					w.C0 = if open[i] then (closedC0 :: CFrame) * CFrame.new(0.3, 0, leaf * 2.1) else closedC0 :: CFrame
				end
			elseif p.Name:match("^DoorLamp") and p:IsA("BasePart") then
				local k = tonumber(p.Name:sub(9))
				p.Color = if k and open[k] then Color3.fromRGB(40, 220, 80) else Color3.fromRGB(60, 20, 20)
			end
		end
		local any = open[1] or open[2]
		for _, s in model:GetChildren() do
			if s:IsA("Seat") then
				local prompt = s:FindFirstChild("EnterPrompt") :: ProximityPrompt?
				if prompt then
					prompt.Enabled = any and s.Occupant == nil
				end
			end
		end
		if any and model:GetAttribute("StopRequest") then
			model:SetAttribute("StopRequest", false)
		end
	end
	model:GetAttributeChangedSignal("Door1Open"):Connect(applyDoors)
	model:GetAttributeChangedSignal("Door2Open"):Connect(applyDoors)
	for _, a in { "BusLine", "BusDest", "StopRequest" } do
		model:GetAttributeChangedSignal(a):Connect(function()
			refreshDisplays(model)
		end)
	end

	-- every passenger seat (incl. the builder's front seat): tickets + door rule
	for _, s in model:GetChildren() do
		if s:IsA("Seat") then
			local seat = s :: Seat
			seat:GetPropertyChangedSignal("Occupant"):Connect(function()
				-- CarServer turns the prompt back on when someone leaves: doors decide
				task.defer(function()
					local prompt = seat:FindFirstChild("EnterPrompt") :: ProximityPrompt?
					if prompt then
						prompt.Enabled = doorsOpen(model) and seat.Occupant == nil
					end
				end)
				local p = playerIn(seat)
				if p then
					onBoard(model, seat, p, owner)
				end
			end)
		end
	end
end

local function cleanText(player: Player, text: string): string?
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
			:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or typeof(result) ~= "string" then
		return nil
	end
	return result
end

function BusService.Start()
	-- driver: open / close door 1 or 2
	Remotes.Handle("Bus.Door", function(player, door: any)
		local model, isDriver = busOf(player)
		if not model or not isDriver then
			return Remotes.Fail("not_driving")
		end
		local i = Remotes.Check.Int(door, 1, 2)
		if not i then
			return Remotes.Fail("bad_request")
		end
		local attr = "Door" .. i .. "Open"
		model:SetAttribute(attr, not model:GetAttribute(attr))
		return Remotes.Ok()
	end, { rate = 10, needsData = false })

	-- driver: line number + destination (filtered, shown on the LED displays)
	Remotes.Handle("Bus.Line", function(player, line: any, dest: any)
		local model, isDriver = busOf(player)
		if not model or not isDriver then
			return Remotes.Fail("not_driving")
		end
		local l = Remotes.Check.String(line, 4)
		local d = Remotes.Check.String(dest, 24)
		if not l or not d or not l:match("^[%w]+$") then
			return Remotes.Fail("bus_bad_line")
		end
		local cleanLine = cleanText(player, l)
		local cleanDest = cleanText(player, d)
		if not cleanLine or not cleanDest then
			return Remotes.Fail("bus_bad_line")
		end
		model:SetAttribute("BusLine", cleanLine:upper())
		model:SetAttribute("BusDest", cleanDest)
		GameLog.Add("vehicle", player, ("bus line %s -> %s"):format(cleanLine, cleanDest))
		return Remotes.Ok()
	end, { rate = 4, needsData = false })

	-- passenger: stop request
	Remotes.Handle("Bus.Stop", function(player)
		local model, isDriver = busOf(player)
		if not model or isDriver then
			return Remotes.Fail("bad_request")
		end
		if not model:GetAttribute("StopRequest") then
			model:SetAttribute("StopRequest", true)
			local driver = driverOf(model)
			if driver then
				Remotes.Push(driver, "Notify", { key = "bus_stop_requested" })
			end
		end
		return Remotes.Ok()
	end, { rate = 4, needsData = false })
end

return BusService
