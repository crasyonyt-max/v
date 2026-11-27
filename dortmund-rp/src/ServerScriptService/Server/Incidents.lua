--!strict
-- Update 2 (Config.Update2, testing server first): things happen in the city by
-- themselves, so the jobs always have work. Each one also opens a call in the Calls app.
--   🔥 Feuerwehr: building or car fires that spread until they are put out
--      (hold "Löschen" at every flame); paid when the last flame is out
--   🤕 Rettungsdienst / Notarzt: injured people: first aid (bonus), load them in, bring
--      them to the Klinikum (paid by distance)
--   🔧 ADMC: broken-down cars: repair on the spot, or tow them to the ADMC base
--   🚕 Taxi: customers wave at the roadside: pick them up, drive them to their address;
--      real players call 22456 ("TAXI") and pay by the taxi meter

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Locations = require(ReplicatedStorage.Shared.Locations)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local VehicleConfig = require(ReplicatedStorage.VehicleConfig)
local CareerService = require(script.Parent.CareerService)
local Economy = require(script.Parent.EconomyService)
local Emergency = require(script.Parent.EmergencyService)
local GameLog = require(script.Parent.GameLog)
local JobService = require(script.Parent.JobService)
local Remotes = require(script.Parent.Remotes)
local ThanksgivingService = require(script.Parent.ThanksgivingService)
local XPService = require(script.Parent.XPService)

local Incidents = {}

local rng = Random.new()
local folder: Folder? = nil

local function root(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "Incidents"
		f.Parent = Workspace
		folder = f
	end
	return folder :: Folder
end

local function onDuty(job: string): { Player }
	local out = {}
	for _, p in Players:GetPlayers() do
		if JobService.Get(p) == job then
			table.insert(out, p)
		end
	end
	return out
end

local function notify(p: Player, key: string, args: { any }?, err: boolean?)
	Remotes.Push(p, "Notify", { key = key, args = args, error = err })
end

local function waypoint(p: Player, pos: Vector3?, title: string?)
	Remotes.Push(p, "Waypoint", { pos = pos, title = title })
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function prompt(parent: Instance, action: string, object: string, hold: number, dist: number?): ProximityPrompt
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = action
	pr.ObjectText = object
	pr.HoldDuration = hold
	pr.MaxActivationDistance = dist or 12
	pr.RequiresLineOfSight = false
	pr.Parent = parent
	return pr
end

local function label(parent: BasePart, text: string, color: Color3)
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromOffset(170, 34)
	g.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	g.AlwaysOnTop = true
	g.MaxDistance = 250
	g.Parent = parent
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	l.BackgroundTransparency = 0.2
	l.TextColor3 = color
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.Text = text
	l.Parent = g
	local c = Instance.new("UICorner")
	c.Parent = l
end

-- a simple person (blocks); lying down or standing (waving)
local function person(pos: Vector3, lying: boolean, shirt: Color3): Model
	local m = Instance.new("Model")
	m.Name = if lying then "Patient" else "Customer"
	local skin = Color3.fromRGB(230, 190, 160)
	local base = if lying
		then CFrame.new(pos + Vector3.new(0, 0.6, 0)) * CFrame.Angles(math.rad(90), rng:NextNumber(0, math.pi * 2), 0)
		else CFrame.new(pos + Vector3.new(0, 3, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local torso = part(m, "Torso", Vector3.new(2, 2, 1), base, shirt)
	part(m, "Head", Vector3.new(1.2, 1.2, 1.2), base * CFrame.new(0, 1.6, 0), skin)
	for _, s in { -1, 1 } do
		part(m, "Leg", Vector3.new(0.9, 2, 0.9), base * CFrame.new(s * 0.5, -2, 0), Color3.fromRGB(40, 50, 80))
		local arm = part(m, "Arm", Vector3.new(0.8, 2, 0.8), base * CFrame.new(s * 1.4, 0, 0), shirt)
		if not lying and s == 1 then
			arm.CFrame = base * CFrame.new(1.5, 1.4, 0) * CFrame.Angles(0, 0, math.rad(-20)) -- waving
		end
	end
	m.PrimaryPart = torso
	m.Parent = root()
	return m
end

-- somewhere on a street, preferably `minD`..`maxD` studs from `near`
local function streetSpot(near: Vector3?, minD: number?, maxD: number?): Vector3?
	local best: Vector3? = nil
	for _ = 1, 20 do
		local p = ThanksgivingService.RandomSpot()
		if p then
			if not near then
				return p
			end
			local d = ((p - near) * Vector3.new(1, 0, 1)).Magnitude
			if d >= (minD or 0) and d <= (maxD or math.huge) then
				return p
			end
			best = best or p
		end
	end
	return best
end

local function hospital(): Vector3?
	local h = (Locations.Shops :: any).Hospital
	return h and Vector3.new(h.marker[1], 0, h.marker[2])
end

local function admcBase(): Vector3?
	local a = (Locations.Jobs :: any).ADMC
	return a and Vector3.new(a.marker[1], 0, a.marker[2])
end

local function isDriving(p: Player): Model?
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if seat and seat:IsA("VehicleSeat") and seat.Parent and seat.Parent:IsA("Model") then
		return seat.Parent :: Model
	end
	return nil
end

local function near(p: Player, pos: Vector3, dist: number): boolean
	local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return r ~= nil and ((r.Position - pos) * Vector3.new(1, 0, 1)).Magnitude <= dist
end

-- 🔥 Fires ------------------------------------------------------------------------------

Incidents.FIRE_MAX_FLAMES = 8
Incidents.FIRE_LIFETIME = 10 * 60

local fires: { [string]: { flames: { BasePart }, helpers: { [Player]: number }, call: string, model: Model, ends: number } } =
	{}

-- fire pay for one firefighter (`n` flames put out by them)
function Incidents.FirePay(n: number): (number, number)
	return 150 + 40 * n, 60 + 15 * n
end

local function addFlame(id: string, pos: Vector3)
	local f = fires[id]
	if not f or #f.flames >= Incidents.FIRE_MAX_FLAMES then
		return
	end
	local flame = part(f.model, "Flame", Vector3.new(4, 4, 4), CFrame.new(pos), Color3.new(1, 0.4, 0))
	flame.Transparency = 1
	local fire = Instance.new("Fire")
	fire.Size = rng:NextNumber(8, 12)
	fire.Heat = 18
	fire.Parent = flame
	local smoke = Instance.new("Smoke")
	smoke.RiseVelocity = 9
	smoke.Size = 8
	smoke.Opacity = 0.25
	smoke.Color = Color3.fromRGB(60, 60, 60)
	smoke.Parent = flame
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 40)
	light.Range = 22
	light.Brightness = 3
	light.Parent = flame
	local pr = prompt(flame, "🧯 Löschen", "Feuer", 2.5, 16)
	pr.Triggered:Connect(function(p)
		if JobService.Get(p) ~= "Fire" then
			notify(p, "fire_only_firefighters", nil, true)
			return
		end
		local i = table.find(f.flames, flame)
		if not i then
			return
		end
		table.remove(f.flames, i)
		flame:Destroy()
		f.helpers[p] = (f.helpers[p] or 0) + 1
		if #f.flames == 0 then
			for helper, n in f.helpers do
				if helper.Parent then
					local cash, xp = Incidents.FirePay(n)
					local paid = Economy.Earn(helper, cash, "Brand gelöscht")
					XPService.Earn(helper, "Fire", xp, "Brand gelöscht")
					CareerService.Progress(helper, "fire")
					notify(helper, "fire_out", { paid })
				end
			end
			Emergency.Close(f.call)
			f.model:Destroy()
			fires[id] = nil
		end
	end)
	table.insert(f.flames, flame)
end

function Incidents.StartFire(): string?
	local pos = streetSpot()
	if not pos then
		return nil
	end
	-- a building next to that street spot, else a car fire on the street
	local kind = "fire_car"
	local base = pos
	local city = Workspace:FindFirstChild("City")
	local buildings = city and city:FindFirstChild("Buildings")
	if buildings then
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { buildings }
		local best, bestD = nil, math.huge
		for _, b in Workspace:GetPartBoundsInRadius(pos, 70, params) do
			local d = (b.Position - pos).Magnitude
			if d < bestD and b.Size.Y > 8 then
				best, bestD = b, d
			end
		end
		if best then
			-- the point of the building's wall closest to the street
			local l = best.CFrame:PointToObjectSpace(pos)
			local h = best.Size / 2
			local c =
				best.CFrame:PointToWorldSpace(Vector3.new(math.clamp(l.X, -h.X, h.X), 0, math.clamp(l.Z, -h.Z, h.Z)))
			base = Vector3.new(c.X, pos.Y, c.Z)
			kind = "fire_building"
		end
	end
	local id = tostring(os.clock()) .. rng:NextInteger(1, 9999)
	local m = Instance.new("Model")
	m.Name = "Fire"
	m.Parent = root()
	fires[id] = {
		flames = {},
		helpers = {},
		model = m,
		ends = os.clock() + Incidents.FIRE_LIFETIME,
		call = Emergency.System(
			"112",
			{ "Fire" },
			if kind == "fire_building" then "🔥 Gebäudebrand" else "🔥 Fahrzeugbrand",
			base,
			"Leitstelle Feuerwehr"
		),
	}
	if kind == "fire_car" then
		-- a burnt-out car under the flames
		part(
			m,
			"BurningCar",
			Vector3.new(6, 3, 12),
			CFrame.new(base + Vector3.new(0, 1.5, 0)),
			Color3.fromRGB(35, 30, 28),
			Enum.Material.CorrodedMetal
		).CanCollide =
			true
	end
	for i = 1, 3 do
		addFlame(
			id,
			base
				+ Vector3.new(
					rng:NextNumber(-4, 4),
					2 + (if kind == "fire_building" then i * 3 else 1),
					rng:NextNumber(-4, 4)
				)
		)
	end
	return id
end

local function fireTick()
	for id, f in fires do
		if os.clock() > f.ends then
			-- burnt out on its own: nobody gets paid
			Emergency.Close(f.call)
			f.model:Destroy()
			fires[id] = nil
		elseif #f.flames > 0 and #f.flames < Incidents.FIRE_MAX_FLAMES and rng:NextNumber() < 0.35 then
			local from = f.flames[rng:NextInteger(1, #f.flames)].Position
			addFlame(id, from + Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-1, 4), rng:NextNumber(-8, 8)))
		end
	end
end

-- 🤕 Patients ---------------------------------------------------------------------------

local MEDICS = { "Rettungsdienst", "Notarzt" }
local patients: { [Model]: { call: string, treated: boolean, pos: Vector3, t: number } } = {}
local carrying: { [Player]: { from: Vector3, treated: boolean } } = {}

-- pay for bringing a patient in (`dist` = studs from the pickup to the Klinikum)
function Incidents.PatientPay(dist: number, treated: boolean): number
	return math.floor(150 + dist * 0.04 + (if treated then 50 else 0))
end

local function isMedic(p: Player): boolean
	return table.find(MEDICS, JobService.Get(p)) ~= nil
end

function Incidents.SpawnPatient(): Model?
	local pos = streetSpot()
	if not pos then
		return nil
	end
	local m =
		person(pos, true, Color3.fromRGB(rng:NextInteger(40, 220), rng:NextInteger(40, 220), rng:NextInteger(40, 220)))
	local torso = m.PrimaryPart :: BasePart
	label(torso, "🤕 Verletzte Person", Color3.fromRGB(255, 120, 120))
	patients[m] = {
		call = Emergency.System("112", MEDICS, "🤕 Verletzte Person", pos, "Leitstelle Rettungsdienst"),
		treated = false,
		pos = pos,
		t = os.clock(),
	}
	local firstAid = prompt(torso, "🩺 Erstversorgung", "Verletzte Person", 3)
	firstAid.Triggered:Connect(function(p)
		local info = patients[m]
		if not info or not isMedic(p) then
			notify(p, "medic_only", nil, true)
			return
		end
		if not info.treated then
			info.treated = true
			firstAid.Enabled = false
			Economy.Earn(p, 80, "Erstversorgung")
			XPService.Earn(p, JobService.Get(p), 30, "Erstversorgung")
			notify(p, "patient_treated")
		end
	end)
	local load = prompt(torso, "🛏️ Einladen", "Verletzte Person", 2)
	load.KeyboardKeyCode = Enum.KeyCode.F
	load.Triggered:Connect(function(p)
		local info = patients[m]
		if not info or not isMedic(p) then
			notify(p, "medic_only", nil, true)
			return
		end
		if carrying[p] then
			notify(p, "patient_already", nil, true)
			return
		end
		carrying[p] = { from = info.pos, treated = info.treated }
		p:SetAttribute("Patient", true)
		Emergency.Close(info.call)
		patients[m] = nil
		m:Destroy()
		notify(p, "patient_loaded")
		local h = hospital()
		if h then
			waypoint(p, h, "🏥 Klinikum")
		end
	end)
	return m
end

-- 🔧 Breakdowns (ADMC) --------------------------------------------------------------------

local breakdowns: { [Model]: { call: string, t: number } } = {}
local towing: { [Player]: Vector3 } = {}

local function brokenCar(pos: Vector3): Model?
	local ok, Generator = pcall(require, script.Parent.Cars.VehicleModelGenerator)
	if not ok then
		return nil
	end
	local list = VehicleConfig.GetByCategory("Dealership")
	local vcfg = list[rng:NextInteger(1, math.max(1, #list))]
	local template = vcfg and Generator.Get(vcfg)
	if not template then
		return nil
	end
	local m = template:Clone()
	for _, d in m:GetDescendants() do
		if
			d:IsA("Seat")
			or d:IsA("VehicleSeat")
			or d:IsA("ProximityPrompt")
			or d:IsA("Script")
			or d:IsA("LocalScript")
		then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local _, size = m:GetBoundingBox()
	m:PivotTo(CFrame.new(pos + Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	m.Name = "Panne"
	return m
end

function Incidents.SpawnBreakdown(): Model?
	local pos = streetSpot()
	if not pos then
		return nil
	end
	local m = brokenCar(pos)
	if not m then
		return nil
	end
	local cf, size = m:GetBoundingBox()
	local hood = part(m, "Hood", Vector3.new(1, 1, 1), cf * CFrame.new(0, size.Y / 2, -size.Z / 3), Color3.new(), nil)
	hood.Transparency = 1
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(200, 200, 200)
	smoke.Size = 3
	smoke.RiseVelocity = 4
	smoke.Opacity = 0.3
	smoke.Parent = hood
	label(hood, "🔧 Panne", Color3.fromRGB(250, 205, 0))
	m.Parent = root()
	breakdowns[m] = { call = Emergency.System("ADMC", { "ADMC" }, "🔧 Panne", pos, "ADMC Pannenruf"), t = os.clock() }
	local fixable = rng:NextNumber() < 0.65
	local repair = prompt(hood, "🔧 Reparieren", "Panne", 5)
	local tow = prompt(hood, "🚛 Abschleppen", "Panne", 3)
	tow.Enabled = false
	tow.KeyboardKeyCode = Enum.KeyCode.F
	repair.Triggered:Connect(function(p)
		local info = breakdowns[m]
		if not info or JobService.Get(p) ~= "ADMC" then
			notify(p, "admc_only", nil, true)
			return
		end
		if fixable then
			local paid = Economy.Earn(p, 200, "Panne behoben")
			XPService.Earn(p, "ADMC", 60, "Panne behoben")
			CareerService.Progress(p, "repair")
			notify(p, "breakdown_fixed", { paid })
			Emergency.Close(info.call)
			breakdowns[m] = nil
			task.delay(2, function()
				m:Destroy()
			end)
		else
			repair.Enabled = false
			tow.Enabled = true
			notify(p, "breakdown_tow", nil, true)
		end
	end)
	tow.Triggered:Connect(function(p)
		local info = breakdowns[m]
		if not info or JobService.Get(p) ~= "ADMC" then
			notify(p, "admc_only", nil, true)
			return
		end
		if towing[p] then
			notify(p, "tow_already", nil, true)
			return
		end
		towing[p] = pos
		p:SetAttribute("Towing", true)
		Emergency.Close(info.call)
		breakdowns[m] = nil
		m:Destroy()
		notify(p, "tow_loaded")
		local b = admcBase()
		if b then
			waypoint(p, b, "🚛 ADMC-Werkstatt")
		end
	end)
	return m
end

-- 🚕 Taxi ---------------------------------------------------------------------------------

type Fare = { driver: Player, npc: Model?, dest: BasePart?, from: Vector3, ends: number }
local fares: { [Player]: Fare } = {}

function Incidents.TaxiPay(dist: number): number
	return math.floor(40 + dist * 0.05)
end

local function endFare(p: Player)
	local f = fares[p]
	if f then
		if f.npc then
			f.npc:Destroy()
		end
		if f.dest then
			f.dest:Destroy()
		end
		fares[p] = nil
	end
end

local function newFare(p: Player)
	local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pos = streetSpot(r and r.Position, 250, 1500)
	if not pos then
		return
	end
	local npc =
		person(pos, false, Color3.fromRGB(rng:NextInteger(40, 220), rng:NextInteger(40, 220), rng:NextInteger(40, 220)))
	local torso = npc.PrimaryPart :: BasePart
	label(torso, "🙋 Taxi!", Color3.fromRGB(255, 220, 90))
	local fare: Fare = { driver = p, npc = npc, from = pos, ends = os.clock() + 10 * 60 }
	fares[p] = fare
	waypoint(p, pos, "🙋 Fahrgast")
	notify(p, "taxi_new_fare")
	local pick = prompt(torso, "🚕 Einsteigen lassen", "Fahrgast", 0.5, 25)
	pick.Triggered:Connect(function(who)
		if who ~= p or fares[p] ~= fare then
			return
		end
		if not isDriving(p) then
			notify(p, "taxi_need_car", nil, true)
			return
		end
		npc:Destroy()
		fare.npc = nil
		local dest = streetSpot(pos, 800, 3000)
		if not dest then
			endFare(p)
			return
		end
		local marker = part(
			root(),
			"TaxiDestination",
			Vector3.new(0.4, 14, 14),
			CFrame.new(dest + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(60, 220, 90),
			Enum.Material.Neon
		)
		marker.Shape = Enum.PartType.Cylinder
		marker.Transparency = 0.5
		fare.dest = marker
		waypoint(p, dest, "🏁 Fahrziel")
		notify(p, "taxi_picked_up")
		local drop = prompt(marker, "🏁 Fahrgast aussteigen lassen", "Fahrziel", 0.5, 30)
		drop.Triggered:Connect(function(who2)
			if who2 ~= p or fares[p] ~= fare or not isDriving(p) then
				return
			end
			local dist = ((dest - fare.from) * Vector3.new(1, 0, 1)).Magnitude
			local paid = Economy.Earn(p, Incidents.TaxiPay(dist), "Taxifahrt")
			XPService.Earn(p, "Taxi", 50, "Taxifahrt")
			CareerService.Progress(p, "taxi")
			notify(p, "taxi_done", { paid })
			waypoint(p, nil)
			endFare(p)
		end)
	end)
end

-- the taxi meter for real passengers: they pay the driver by distance when they get out
local rides: { [Player]: { model: Model, last: Vector3, dist: number } } = {}

function Incidents.MeterFare(dist: number): number
	return math.floor((5 + dist * 0.02) * 100 + 0.5) / 100
end

local function meterTick()
	local folderV = Workspace:FindFirstChild("Vehicles")
	local seen: { [Player]: boolean } = {}
	for _, model in (if folderV then folderV:GetChildren() else {}) do
		local def = Vehicles.ById[tostring(model:GetAttribute("VehicleId"))]
		if model:IsA("Model") and def and def.job == "Taxi" then
			for _, s in model:GetChildren() do
				if s:IsA("Seat") and s.Occupant then
					local pl = Players:GetPlayerFromCharacter(s.Occupant.Parent)
					local pos = model:GetPivot().Position
					if pl then
						seen[pl] = true
						local r = rides[pl]
						if r and r.model == model then
							r.dist += ((pos - r.last) * Vector3.new(1, 0, 1)).Magnitude
							r.last = pos
						else
							rides[pl] = { model = model, last = pos, dist = 0 }
						end
					end
				end
			end
		end
	end
	for pl, r in rides do
		if not seen[pl] then
			rides[pl] = nil
			local driverSeat = r.model:FindFirstChild("DriverSeat") :: VehicleSeat?
			local driver = driverSeat
				and driverSeat.Occupant
				and Players:GetPlayerFromCharacter(driverSeat.Occupant.Parent)
			if driver and driver ~= pl and pl.Parent and r.dist > 100 then
				local fare = math.min(Incidents.MeterFare(r.dist), Economy.Balance(pl))
				if fare > 0 and Economy.TrySpend(pl, fare, "Taxifahrt") then
					Economy.Add(driver, fare, "Taxifahrt: " .. pl.Name)
					CareerService.Progress(driver, "taxi")
					notify(pl, "taxi_paid", { fare })
					notify(driver, "taxi_got_paid", { pl.DisplayName, fare })
					GameLog.Add("money", pl, ("taxi %.2f € -> %s"):format(fare, driver.Name))
				end
			end
		end
	end
end

-- Delivery points: Klinikum (patients) and ADMC base (towed cars) ----------------------

local function deliveryPoint(pos: Vector3?, action: string, object: string, fn: (Player) -> ())
	if not pos then
		return
	end
	local ok, CityBuilder = pcall(require, script.Parent.CityBuilder)
	local y = if ok then CityBuilder.GroundY(pos.X, pos.Z) else 0
	local p = part(
		root(),
		"Delivery",
		Vector3.new(0.3, 12, 12),
		CFrame.new(pos.X, y + 0.15, pos.Z) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(60, 150, 255),
		Enum.Material.Neon
	)
	p.Shape = Enum.PartType.Cylinder
	p.Transparency = 0.6
	local pr = prompt(p, action, object, 1, 30)
	pr.Triggered:Connect(fn)
end

function Incidents.Start()
	if not Config.On(Config.Update2) then
		return
	end
	Config.EmergencyNumbers[Config.TaxiNumber] = { "Taxi" }

	deliveryPoint(hospital(), "🏥 Patient übergeben", "Klinikum", function(p)
		local c = carrying[p]
		local h = hospital()
		if not c or not h then
			return
		end
		carrying[p] = nil
		p:SetAttribute("Patient", nil)
		local dist = ((h - c.from) * Vector3.new(1, 0, 1)).Magnitude
		local paid = Economy.Earn(p, Incidents.PatientPay(dist, c.treated), "Patient eingeliefert")
		XPService.Earn(p, JobService.Get(p), 80, "Patient eingeliefert")
		CareerService.Progress(p, "patient")
		notify(p, "patient_delivered", { paid })
		waypoint(p, nil)
	end)
	deliveryPoint(admcBase(), "🚛 Fahrzeug abliefern", "ADMC-Werkstatt", function(p)
		if not towing[p] then
			return
		end
		towing[p] = nil
		p:SetAttribute("Towing", nil)
		local paid = Economy.Earn(p, 380, "Abschleppauftrag")
		XPService.Earn(p, "ADMC", 100, "Abschleppauftrag")
		CareerService.Progress(p, "repair")
		notify(p, "tow_delivered", { paid })
		waypoint(p, nil)
	end)

	Players.PlayerRemoving:Connect(function(p)
		carrying[p] = nil
		towing[p] = nil
		rides[p] = nil
		endFare(p)
	end)
	JobService.Changed:Connect(function(p)
		endFare(p)
		carrying[p] = nil
		towing[p] = nil
		p:SetAttribute("Patient", nil)
		p:SetAttribute("Towing", nil)
	end)

	-- the city clock: new things to do while people are on duty
	task.spawn(function()
		local nextFire, nextPatient, nextBreak = os.clock() + 60, os.clock() + 45, os.clock() + 50
		while true do
			task.wait(5)
			local now = os.clock()
			local nFires, nPatients, nBreaks = 0, 0, 0
			for _ in fires do
				nFires += 1
			end
			for _ in patients do
				nPatients += 1
			end
			for _ in breakdowns do
				nBreaks += 1
			end
			if now >= nextFire then
				nextFire = now + rng:NextNumber(180, 360)
				if #onDuty("Fire") > 0 and nFires < 2 then
					Incidents.StartFire()
				end
			end
			if now >= nextPatient then
				nextPatient = now + rng:NextNumber(150, 300)
				if (#onDuty("Rettungsdienst") + #onDuty("Notarzt")) > 0 and nPatients < 2 then
					Incidents.SpawnPatient()
				end
			end
			if now >= nextBreak then
				nextBreak = now + rng:NextNumber(150, 300)
				if #onDuty("ADMC") > 0 and nBreaks < 2 then
					Incidents.SpawnBreakdown()
				end
			end
			for _, p in onDuty("Taxi") do
				local f = fares[p]
				if f and now > f.ends then
					endFare(p)
					waypoint(p, nil)
				elseif not f and rng:NextNumber() < 0.15 then
					newFare(p)
				end
			end
			-- patients / breakdowns nobody came for go away after 12 minutes
			fireTick()
			for m, info in patients do
				if now - info.t > 12 * 60 then
					Emergency.Close(info.call)
					patients[m] = nil
					m:Destroy()
				end
			end
			for m, info in breakdowns do
				if now - info.t > 12 * 60 then
					Emergency.Close(info.call)
					breakdowns[m] = nil
					m:Destroy()
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			meterTick()
		end
	end)
end

return Incidents
