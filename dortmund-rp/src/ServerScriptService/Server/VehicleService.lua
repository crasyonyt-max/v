--!strict
-- The motorbike: everyone owns one (free), job bikes in livery, plates, paint, fuel, lights.
-- The old cars were removed; their owners get the price back once (see migrate).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Plate = require(ReplicatedStorage.Shared.Plate)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local Interaction = require(script.Parent.InteractionService)
local JobService = require(script.Parent.JobService)
local Remotes = require(script.Parent.Remotes)
local Roles = require(script.Parent.Roles)
local State = require(script.Parent.State)
local StationBuilder = require(script.Parent.StationBuilder)
local TextService = game:GetService("TextService")
local VehicleBuilder = require(script.Parent.VehicleBuilder)
local GarageService = require(script.Parent.GarageService)
local CarGenerator = require(script.Parent.Cars.VehicleModelGenerator)
local LiveryApplier = require(script.Parent.Cars.LiveryApplier)
local VehicleConfig = require(ReplicatedStorage:WaitForChild("VehicleConfig")) :: any
local XPService = require(script.Parent.XPService)
local GameLog = require(script.Parent.GameLog)

local VehicleService = {}

local PLATE_FEE = 250
local PAINT_FEE = 500
local SELL_BACK = 0.5 -- the dealer buys cars back at 50 %

local folder = Instance.new("Folder")
folder.Name = "Vehicles"
folder.Parent = Workspace

local plateStore: DataStore? = nil
pcall(function()
	plateStore = DataStoreService:GetDataStore(Config.DataStoreName .. "_Plates")
end)

local spawned: { [Player]: Model } = {}
local rng = Random.new()

local PALETTE = Vehicles.Palette
local addCarDetails: (Model) -> ()

local function toColor(c: any): Color3
	if typeof(c) == "table" then
		return Color3.fromRGB(c[1] or 200, c[2] or 200, c[3] or 200)
	end
	return Color3.new(0.8, 0.8, 0.8)
end

local function fromColor(c: Color3): { number }
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

-- Plates are unique across the whole game: plate -> userId.
local function claimPlate(text: string, userId: number): boolean
	if not plateStore then
		return true
	end
	local result = false
	local ok = pcall(function()
		(plateStore :: DataStore):UpdateAsync("p_" .. text, function(old: any)
			if old == nil or old == userId then
				result = true
				return userId
			end
			result = false
			return nil
		end)
	end)
	return ok and result
end

local function releasePlate(text: string, userId: number)
	if not plateStore then
		return
	end
	pcall(function()
		local current = (plateStore :: DataStore):GetAsync("p_" .. text)
		if current == userId then
			(plateStore :: DataStore):RemoveAsync("p_" .. text)
		end
	end)
end

local function newPlate(userId: number): string
	for _ = 1, 8 do
		local text = Plate.Random(Config.DefaultCityCode, rng)
		if claimPlate(text, userId) then
			return text
		end
	end
	return Plate.Random(Config.DefaultCityCode, rng)
end

local function addOwned(player: Player, vehicleId: string)
	local data = DataService.Get(player) :: { [string]: any }
	local def = Vehicles.ById[vehicleId]
	local uid = "v" .. data.nextUid
	data.nextUid += 1
	data.vehicles[uid] = {
		id = vehicleId,
		color = fromColor(def.color),
		plate = newPlate(player.UserId),
		fuel = 100,
	}
	State.MarkDirty(player)
	return uid
end

function VehicleService.Despawn(player: Player)
	local model = spawned[player]
	if not model then
		return
	end
	spawned[player] = nil
	-- remember fuel of owned cars
	local uid = model:GetAttribute("Uid")
	local data = DataService.Get(player)
	if data and typeof(uid) == "string" and data.vehicles[uid] then
		data.vehicles[uid].fuel = math.floor((model:GetAttribute("Fuel") or 100) :: number)
	end
	model:Destroy()
end

-- Ground-level CFrame beside the player; `width` keeps big trucks clear of them.
local setupSeats: (Model, Player, { [string]: any }) -> ()

local function spawnCFrame(player: Player, width: number): CFrame?
	-- in an underground garage: a free parking bay
	local bay = GarageService.SpawnSpot(player)
	if bay then
		return bay
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	local right = look:Cross(Vector3.yAxis)
	local city = Workspace:FindFirstChild("City")
	local ground = RaycastParams.new()
	ground.FilterType = Enum.RaycastFilterType.Include
	ground.FilterDescendantsInstances = if city
		then {
			city:FindFirstChild("Ground"),
			city:FindFirstChild("Roads"),
			city:FindFirstChild("Pavements"),
			city:FindFirstChild("Areas"),
		}
		else { Workspace }
	local blockers = OverlapParams.new()
	blockers.FilterType = Enum.RaycastFilterType.Include
	blockers.FilterDescendantsInstances = { city and city:FindFirstChild("Buildings") or Workspace.Terrain, folder }
	-- try beside the player (right, left), then ahead and behind; first free spot wins
	local side = width / 2 + 5
	local candidates = {
		right * side,
		-right * side,
		right * (side + 8),
		-right * (side + 8),
		look * 20,
		-look * 20,
		right * side + look * 12,
		-right * side - look * 12,
	}
	for _, offset in candidates do
		local origin = root.Position + offset + Vector3.new(0, 40, 0)
		local hit = Workspace:Raycast(origin, Vector3.new(0, -100, 0), ground)
		if hit then
			local pos = Vector3.new(origin.X, hit.Position.Y, origin.Z)
			local cf = CFrame.lookAt(pos, pos + look)
			local inWay =
				Workspace:GetPartBoundsInBox(cf * CFrame.new(0, 4, 0), Vector3.new(width + 1, 6, width * 2.6), blockers)
			if #inWay == 0 then
				return cf
			end
		end
	end
	return nil
end

-- Who may take the driver's seat of a car spawned by `owner`.
local function mayDrive(driver: Player, owner: Player, meta: { [string]: any }): boolean
	return driver == owner or Roles.IsServerAdmin(driver) or (meta.Job ~= nil and JobService.Get(driver) == meta.Job)
end

-- "Einsteigen" prompts on every seat. Seats sit inside the car body, so players
-- can't touch them; the server seats them instead and puts them beside the door
-- again when they get out (otherwise they'd be stuck inside the body).
function setupSeats(model: Model, owner: Player, meta: { [string]: any })
	local chassis = model.PrimaryPart :: BasePart
	for _, seat in model:GetChildren() do
		if not (seat:IsA("Seat") or seat:IsA("VehicleSeat")) then
			continue
		end
		local seatPart = seat :: BasePart
		seatPart.CanTouch = false
		local isDriver = seat:IsA("VehicleSeat")
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = if isDriver then "Fahren" else "Einsteigen"
		prompt.ObjectText = model.Name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.G
		prompt.Parent = seatPart

		local lastOccupant: Humanoid? = nil
		seatPart:GetPropertyChangedSignal("Occupant"):Connect(function()
			local occupant = (seat :: any).Occupant :: Humanoid?
			prompt.Enabled = occupant == nil
			if occupant then
				lastOccupant = occupant
				return
			end
			-- got out: place them next to their door, on the ground
			local hum = lastOccupant
			lastOccupant = nil
			local character = hum and hum.Parent
			if character and character:IsA("Model") and character.Parent then
				local side = if chassis.CFrame:PointToObjectSpace(seatPart.Position).X < 0 then -1 else 1
				local out = chassis.CFrame * CFrame.new(side * (chassis.Size.X / 2 + 2.5), 0, 0)
				task.defer(function()
					character:PivotTo(
						CFrame.new(out.Position + Vector3.new(0, 3, 0)) * (chassis.CFrame - chassis.CFrame.Position)
					)
				end)
			end
		end)

		prompt.Triggered:Connect(function(player)
			local character = player.Character
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 or hum.SeatPart or (seat :: any).Occupant then
				return
			end
			if isDriver and not mayDrive(player, owner, meta) then
				Remotes.Push(player, "Notify", { key = "not_your_car", error = true })
				return
			end
			(seat :: any):Sit(hum)
		end)
	end
end

-- ADMC: a vehicle with an (almost) empty tank gets an "Auftanken" prompt that
-- only players on ADMC duty can use. They fill it up and get paid for it.
local ADMC_REFUEL_PAY = 120
local ADMC_REFUEL_XP = 25
local function setupRefuel(model: Model)
	local chassis = model.PrimaryPart :: BasePart
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ADMCRefuel"
	prompt.ActionText = "Auftanken (ADMC)"
	prompt.ObjectText = model.Name
	prompt.HoldDuration = 2
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.T
	prompt.Enabled = false
	prompt.Parent = chassis
	local function check()
		prompt.Enabled = ((model:GetAttribute("Fuel") or 100) :: number) < 10
	end
	model:GetAttributeChangedSignal("Fuel"):Connect(check)
	check()
	prompt.Triggered:Connect(function(player)
		if JobService.Get(player) ~= "ADMC" then
			Remotes.Push(player, "Notify", { key = "admc_only", error = true })
			return
		end
		if ((model:GetAttribute("Fuel") or 100) :: number) >= 10 then
			return
		end
		model:SetAttribute("Fuel", 100)
		local ownerId = model:GetAttribute("OwnerId")
		local owner = if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
		if owner and owner ~= player then
			Economy.Earn(player, ADMC_REFUEL_PAY, "ADMC Pannenhilfe")
			XPService.Earn(player, "ADMC", ADMC_REFUEL_XP, "Pannenhilfe")
			Remotes.Push(owner, "Notify", { key = "admc_refueled_you", args = { player.DisplayName } })
		end
		Remotes.Push(player, "Notify", { key = "admc_refueled" })
	end)
end

-- Car plates (with text, on the model's plate spots) and indicators (next to the
-- head- and taillights; WorldController makes them blink like on the bike).
local AMBER_OFF = Color3.fromRGB(120, 70, 0)
addCarDetails = function(model: Model)
	local chassis = model.PrimaryPart :: BasePart
	local function weldTo(p: BasePart)
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		local w = Instance.new("WeldConstraint")
		w.Part0 = chassis
		w.Part1 = p
		w.Parent = p
	end
	for _, spot in
		{ { "FrontPlate", "PlateFront", Enum.NormalId.Front }, { "RearPlate", "PlateRear", Enum.NormalId.Back } }
	do
		local base = model:FindFirstChild(spot[1], true) :: BasePart?
		if base and base:IsA("BasePart") then
			local p = VehicleBuilder.MakePlate(model, spot[2], base.CFrame, spot[3])
			p.Size = Vector3.new(math.max(base.Size.X, 1.6), math.max(base.Size.Y, 0.4), 0.06)
			p.CFrame = base.CFrame
			weldTo(p)
			base.Transparency = 1
		end
	end
	local lights = model:FindFirstChild("Lights")
	for _, lamp in (if lights then lights:GetChildren() else {}) do
		if lamp:IsA("BasePart") and (lamp.Name == "Headlight" or lamp.Name == "Taillight") then
			local localPos = chassis.CFrame:PointToObjectSpace(lamp.Position)
			local side = if localPos.X < 0 then -1 else 1
			local ind = Instance.new("Part")
			ind.Name = if side < 0 then "IndicatorL" else "IndicatorR"
			ind.Size = Vector3.new(math.max(lamp.Size.X * 0.35, 0.3), lamp.Size.Y, lamp.Size.Z)
			ind.CFrame = lamp.CFrame * CFrame.new(side * (lamp.Size.X / 2 + ind.Size.X / 2 + 0.02), 0, 0)
			ind.Color = AMBER_OFF
			ind.Material = Enum.Material.Glass
			ind.Parent = model -- direct child: WorldController finds it
			weldTo(ind)
		end
	end
end

-- Cars (RealisticCars): the model comes from VehicleConfig + the generator, the
-- livery from LiveryApplier; CarServer / CarClient (ReplicatedStorage.RealisticCars)
-- do the driving. Our part: ownership, who may drive, getting out, plates, despawn.
local function spawnCar(
	player: Player,
	def: any,
	color: Color3?,
	plateText: string?,
	meta: { [string]: any }
): (boolean, string?)
	local vcfg = VehicleConfig.Get(def.car)
	local template = vcfg and CarGenerator.Get(vcfg)
	if not template then
		return false, "error"
	end
	VehicleService.Despawn(player)
	local model = template:Clone()
	local boxCf, size = model:GetBoundingBox()
	local cf = meta.SpawnAt or spawnCFrame(player, math.max(size.X, 6))
	meta.SpawnAt = nil
	if not cf then
		model:Destroy()
		return false, "no_space"
	end
	-- bottom of the car on the ground
	local pivot = model:GetPivot()
	local above = pivot.Position.Y - (boxCf.Position.Y - size.Y / 2)
	model.Name = def.name
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("VehicleId", def.id)
	model:SetAttribute("Fuel", 100)
	for k, v in meta do
		model:SetAttribute(k, v)
	end
	local custom = if color and vcfg.Repaintable then { Body = color } else nil
	pcall(LiveryApplier.ApplyVehicle, model, vcfg, custom)
	addCarDetails(model)
	VehicleBuilder.SetPlate(model, plateText or Plate.Random(Config.DefaultCityCode, rng))
	model:PivotTo(CFrame.new(cf.Position + Vector3.new(0, above + 0.3, 0)) * (cf - cf.Position))
	model.Parent = folder -- CarServer takes it over (tag "RealisticCar")

	-- only the owner (or the job / admins) may drive; getting out puts you beside the car
	local chassis = model.PrimaryPart :: BasePart
	for _, seat in model:GetChildren() do
		if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
			local seatPart = seat :: BasePart
			local isDriver = seat.Name == "DriverSeat"
			local last: Humanoid? = nil
			seatPart:GetPropertyChangedSignal("Occupant"):Connect(function()
				local hum = (seat :: any).Occupant :: Humanoid?
				if hum then
					last = hum
					local driver = Players:GetPlayerFromCharacter(hum.Parent)
					if isDriver and (not driver or not mayDrive(driver, player, meta)) then
						task.defer(function()
							hum.Sit = false
							hum.Jump = true
						end)
						if driver then
							Remotes.Push(driver, "Notify", { key = "not_your_car", error = true })
						end
					end
					return
				end
				local character = last and last.Parent
				last = nil
				if character and character:IsA("Model") and character.Parent and chassis.Parent then
					local side = if chassis.CFrame:PointToObjectSpace(seatPart.Position).X < 0 then -1 else 1
					local out = chassis.CFrame * CFrame.new(side * (size.X / 2 + 2.5), 0, 0)
					task.defer(function()
						character:PivotTo(
							CFrame.new(out.Position + Vector3.new(0, 2, 0)) * (chassis.CFrame - chassis.CFrame.Position)
						)
					end)
				end
			end)
		end
	end
	spawned[player] = model
	GameLog.Add(
		"vehicle",
		player,
		"spawned " .. def.name .. (if meta.Job then " (" .. tostring(meta.Job) .. ")" else "")
	)
	return true, nil
end

local function spawnModel(
	player: Player,
	def: any,
	color: Color3?,
	plateText: string?,
	meta: { [string]: any }
): (boolean, string?)
	if def.car then
		return spawnCar(player, def, color, plateText, meta)
	end
	VehicleService.Despawn(player)
	local model = VehicleBuilder.Build(def, color)
	local built = model.PrimaryPart :: BasePart
	local cf = meta.SpawnAt or spawnCFrame(player, built.Size.X)
	meta.SpawnAt = nil
	if not cf then
		model:Destroy()
		return false, "no_space"
	end
	-- the model is built with the tyres touching y = 0; lift the chassis to its build height
	cf *= CFrame.new(0, built.Position.Y + 0.3, 0)
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("VehicleId", def.id)
	for k, v in meta do
		model:SetAttribute(k, v)
	end
	VehicleBuilder.SetPlate(model, plateText or Plate.Random(Config.DefaultCityCode, rng))
	model:PivotTo(cf)
	model.Parent = folder
	local chassis = model.PrimaryPart :: BasePart
	pcall(function()
		chassis:SetNetworkOwner(player)
	end)

	local seat = model:FindFirstChild("DriveSeat") :: VehicleSeat
	local lastRider: Model? = nil
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local humanoid = seat.Occupant
		if lastRider then
			lastRider:SetAttribute("BikeHands", nil) -- stunts end when you get off
			lastRider = nil
		end
		if humanoid and humanoid.Parent and humanoid.Parent:IsA("Model") then
			lastRider = humanoid.Parent :: Model
		end
		if not humanoid then
			pcall(function()
				chassis:SetNetworkOwner(player.Parent and player or nil)
			end)
			model:SetAttribute("Brake", false)
			return
		end
		local driver = Players:GetPlayerFromCharacter(humanoid.Parent)
		local allowed = driver ~= nil and mayDrive(driver, player, meta)
		if not allowed then
			-- not your car: get out
			task.defer(function()
				humanoid.Sit = false
				humanoid.Jump = true
			end)
			if driver then
				Remotes.Push(driver, "Notify", { key = "not_your_car", error = true })
			end
			return
		end
		pcall(function()
			chassis:SetNetworkOwner(driver)
		end)
	end)

	setupSeats(model, player, meta)
	setupRefuel(model)
	GameLog.Add(
		"vehicle",
		player,
		"spawned " .. def.name .. (if meta.Job then " (" .. tostring(meta.Job) .. ")" else "")
	)
	spawned[player] = model
	return true, nil
end

local function driverOf(player: Player): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat and seat:IsA("VehicleSeat") and (seat.Name == "DriveSeat" or seat.Name == "DriverSeat") then
		local model = seat.Parent
		if model and model:IsA("Model") and model.Parent == folder then
			return model
		end
	end
	return nil
end
VehicleService.DriverOf = driverOf

-- Job and admin cars aren't owned, so they carry the player's personal plate
-- (chosen once, city DO). Without one the client is asked to choose it first and
-- then repeats `retry`.
local function personalPlateOrAsk(player: Player, def: any, retry: { any }): (boolean, string?)
	if not def.car then
		return true, nil
	end
	local data = DataService.Get(player)
	local p = data and data.personalPlate
	if typeof(p) == "string" then
		return true, p
	end
	Remotes.Push(player, "PlateRequired", { personal = true, retry = retry })
	return false, nil
end

function VehicleService.SpawnAny(player: Player, vehicleId: string): (boolean, string?)
	local def = Vehicles.ById[vehicleId]
	if not def then
		return false, "bad_item"
	end
	local ok, plate = personalPlateOrAsk(player, def, { "Admin.Do", "spawn_vehicle", { vehicleId = vehicleId } })
	if not ok then
		return false, "plate_required"
	end
	return spawnModel(player, def, nil, plate, { Temporary = true, Job = def.job })
end

function VehicleService.GiveVehicle(player: Player, vehicleId: string): boolean
	if not Vehicles.ById[vehicleId] or not DataService.Get(player) then
		return false
	end
	addOwned(player, vehicleId)
	return true
end

-- The car refund is paid ONCE per player, ever. Besides a flag in the player's data,
-- a separate store records who was paid (claimed atomically), so a failed save,
-- an old server or a second join can never pay it again.
local REFUND_REASON = "Erstattung Fahrzeuge"
local refundStore: DataStore? = nil
pcall(function()
	refundStore = DataStoreService:GetDataStore(Config.DataStoreName .. "_CarRefunds")
end)

-- "new" = first time, pay it · "paid" = already paid before · "error" = try next join
local function claimRefund(userId: number, amount: number): string
	if not refundStore then
		return "error"
	end
	local result = "error"
	local ok = pcall(function()
		(refundStore :: DataStore):UpdateAsync("u_" .. userId, function(old: any)
			if old ~= nil then
				result = "paid"
				return nil
			end
			result = "new"
			return { amount = amount, t = os.time() }
		end)
	end)
	return if ok then result else "error"
end

-- Takes back refunds that were paid more than once (before this fix). Runs once.
local function correctDuplicates(player: Player, data: { [string]: any })
	if data.refundChecked then
		return
	end
	local count, extra = 0, 0
	for _, tx in data.tx do
		if typeof(tx) == "table" and tx.reason == REFUND_REASON and typeof(tx.amount) == "number" then
			count += 1
			if count > 1 then
				extra += tx.amount
			end
		end
	end
	if count > 0 then
		data.carsRefunded = true
		-- record the first refund so it can never be paid again
		claimRefund(player.UserId, 0)
	end
	if extra > 0 then
		local take = math.min(extra, math.max(0, data.bank))
		if take > 0 then
			Economy.TrySpend(player, take, "Korrektur: doppelte Erstattung")
		end
		warn(string.format("[Vehicles] took back %.2f duplicate refund from %s", take, player.Name))
	end
	data.refundChecked = true
end

-- Every car that was bought is refunded at full price (once) and replaced by the free motorbike.
local function migrate(player: Player, data: { [string]: any })
	correctDuplicates(player, data)
	local refund = 0
	local hasBike = false
	local oldCars: { string } = {}
	for uid, entry in data.vehicles do
		local def = Vehicles.ById[entry.id]
		if entry.id == Vehicles.BikeId then
			hasBike = true
		elseif not def then
			-- a car of the old system (removed): refunded once
			refund += Vehicles.LegacyPrices[entry.id] or 0
			table.insert(oldCars, uid)
		end
	end
	data.starterChosen = true

	local pay = false
	if #oldCars > 0 then
		if refund > 0 and not data.carsRefunded then
			local claim = claimRefund(player.UserId, refund)
			if claim == "error" then
				-- can't check right now: keep the cars, decide on the next join
				oldCars = {}
			elseif claim == "new" then
				pay = true
			end
		end
		for _, uid in oldCars do
			local entry = data.vehicles[uid]
			data.vehicles[uid] = nil
			if entry and typeof(entry.plate) == "string" then
				task.spawn(releasePlate, entry.plate, player.UserId)
			end
		end
		if #oldCars > 0 then
			data.carsRefunded = true
		end
	end
	if pay then
		Economy.Add(player, refund, REFUND_REASON)
		task.delay(6, function()
			if player.Parent then
				Remotes.Push(player, "Notify", { key = "cars_refunded", args = { Locale.Euro(refund) } })
			end
		end)
	end
	if not hasBike then
		addOwned(player, Vehicles.BikeId)
	end
	State.MarkDirty(player)
	-- save right away so the removed cars stay removed
	task.spawn(DataService.Save, player, false)
end

VehicleService._migrate = migrate -- tests

function VehicleService.Start()
	DataService.Loaded:Connect(function(player, data)
		task.spawn(migrate, player, data)
	end)
	Players.PlayerRemoving:Connect(VehicleService.Despawn)

	JobService.Changed:Connect(function(player)
		local model = spawned[player]
		if model and model:GetAttribute("Job") then
			VehicleService.Despawn(player)
		end
	end)

	-- one free car to pick (once)
	Remotes.Handle("Vehicle.ChooseStarter", function(player, vehicleId: any)
		local data = DataService.Get(player) :: { [string]: any }
		if data.carStarterChosen then
			return Remotes.Fail("already_owned")
		end
		if typeof(vehicleId) ~= "string" or not table.find(Vehicles.CarStarterIds, vehicleId) then
			return Remotes.Fail("bad_item")
		end
		data.carStarterChosen = true
		addOwned(player, vehicleId)
		return Remotes.Ok()
	end, { rate = 3 })

	Remotes.Handle("Vehicle.Buy", function(player, vehicleId: any)
		local data = DataService.Get(player) :: { [string]: any }
		local def = typeof(vehicleId) == "string" and Vehicles.ById[vehicleId] or nil
		if not def or (def.category ~= "Dealer" and def.category ~= "Pack") then
			return Remotes.Fail("bad_item")
		end
		if not Interaction.IsNear(player, "Shop", 40, "UI", "Dealership") then
			return Remotes.Fail("not_near")
		end
		if def.category == "Pack" and not State.OwnsPack(player, def.pack :: string) then
			return Remotes.Fail("pack_locked")
		end
		for _, e in data.vehicles do
			if e.id == def.id then
				return Remotes.Fail("already_owned")
			end
		end
		local count = 0
		for _ in data.vehicles do
			count += 1
		end
		if count >= 40 then
			return Remotes.Fail("garage_full")
		end
		if not Economy.TrySpend(player, def.price, "Autohaus: " .. def.name) then
			return Remotes.Fail("no_money")
		end
		addOwned(player, def.id)
		return Remotes.Ok()
	end, { rate = 5 })

	Remotes.Handle("Vehicle.Sell", function(player, uid: any)
		local data = DataService.Get(player) :: { [string]: any }
		local entry = typeof(uid) == "string" and data.vehicles[uid] or nil
		if not entry or entry.id == Vehicles.BikeId then
			return Remotes.Fail("not_owned")
		end
		if not Interaction.IsNear(player, "Shop", 40, "UI", "Dealership") then
			return Remotes.Fail("not_near")
		end
		local def = Vehicles.ById[entry.id]
		local spawnedModel = spawned[player]
		if spawnedModel and spawnedModel:GetAttribute("Uid") == uid then
			VehicleService.Despawn(player)
		end
		data.vehicles[uid] = nil
		task.spawn(releasePlate, entry.plate, player.UserId)
		local value = if def then math.floor(def.price * SELL_BACK) else 0
		if value > 0 then
			Economy.Add(player, value, "Autohaus Ankauf: " .. (def and def.name or "?"))
		end
		State.MarkDirty(player)
		return Remotes.Ok({ value = value })
	end, { rate = 3 })

	Remotes.Handle("Vehicle.Spawn", function(player, uid: any)
		local data = DataService.Get(player) :: { [string]: any }
		local entry = typeof(uid) == "string" and data.vehicles[uid] or nil
		if not entry then
			return Remotes.Fail("not_owned")
		end
		local def = Vehicles.ById[entry.id]
		if not def then
			return Remotes.Fail("bad_item")
		end
		-- a car needs its own plate before it goes on the road
		if def.car and not entry.plateChosen then
			Remotes.Push(player, "PlateRequired", { uid = uid, name = def.name, retry = { "Vehicle.Spawn", uid } })
			return Remotes.Fail("plate_required")
		end
		local ok, err = spawnModel(player, def, toColor(entry.color), entry.plate, { Uid = uid })
		if not ok then
			return Remotes.Fail(err or "error")
		end
		local model = spawned[player]
		model:SetAttribute("Fuel", entry.fuel or 100)
		return Remotes.Ok()
	end, { rate = 4 })

	Remotes.Handle("Vehicle.SpawnJob", function(player, vehicleId: any)
		local def = typeof(vehicleId) == "string" and Vehicles.ById[vehicleId] or nil
		if not def or def.category ~= "Job" then
			return Remotes.Fail("bad_item")
		end
		local job = JobService.Get(player)
		if def.job ~= job then
			return Remotes.Fail("wrong_job")
		end
		if XPService.JobXP(player, job) < (def.xp or 0) and not Roles.IsGameAdmin(player) then
			return Remotes.Fail("need_xp")
		end
		if not Interaction.IsNear(player, "JobGarage", 40, "JobId", job) then
			return Remotes.Fail("not_near")
		end
		-- spawn in a free garage bay if the job has a proper station
		local bay: CFrame? = nil
		for _, b in StationBuilder.Bays[job] or {} do
			local taken = false
			for _, other in folder:GetChildren() do
				if
					other:IsA("Model")
					and other.PrimaryPart
					and (other.PrimaryPart.Position - b.Position).Magnitude < 9
				then
					taken = true
					break
				end
			end
			if not taken then
				bay = b
				break
			end
		end
		local hasPlate, personal = personalPlateOrAsk(player, def, { "Vehicle.SpawnJob", def.id })
		if not hasPlate then
			return Remotes.Fail("plate_required")
		end
		local ok, err = spawnModel(
			player,
			def,
			nil,
			personal or Plate.Random(Config.DefaultCityCode, rng),
			{ Job = job, SpawnAt = bay }
		)
		return if ok then Remotes.Ok() else Remotes.Fail(err or "error")
	end, { rate = 4 })

	Remotes.Handle("Vehicle.Despawn", function(player)
		VehicleService.Despawn(player)
		return Remotes.Ok()
	end, { rate = 5 })

	Remotes.Handle("Vehicle.SetPlate", function(player, uid: any, text: any)
		local data = DataService.Get(player) :: { [string]: any }
		local entry = typeof(uid) == "string" and data.vehicles[uid] or nil
		if not entry then
			return Remotes.Fail("not_owned")
		end
		local plateText = typeof(text) == "string" and Plate.NormalizeDO(text) or nil
		if not plateText then
			return Remotes.Fail("bad_plate")
		end
		-- Plates are visible to everyone, so they must pass the text filter unchanged.
		local okFilter, filtered = pcall(function()
			local result = TextService:FilterStringAsync(plateText, player.UserId, Enum.TextFilterContext.PublicChat)
			return result:GetNonChatStringForBroadcastAsync()
		end)
		if not okFilter or filtered ~= plateText then
			return Remotes.Fail("bad_plate")
		end
		-- the first own plate of a vehicle is free; changing it later costs a fee and
		-- only works at the ADMC Kennzeichen-Service
		local fee = if entry.plateChosen then PLATE_FEE else 0
		if entry.plateChosen and not Interaction.IsNear(player, "Shop", 25, "UI", "Plates") then
			return Remotes.Fail("plate_service_only")
		end
		if data.bank < fee then
			return Remotes.Fail("no_money")
		end
		if not claimPlate(plateText, player.UserId) then
			return Remotes.Fail("plate_taken")
		end
		if fee > 0 and not Economy.TrySpend(player, fee, "Kennzeichen " .. plateText) then
			task.spawn(releasePlate, plateText, player.UserId)
			return Remotes.Fail("no_money")
		end
		local old = entry.plate
		entry.plate = plateText
		entry.plateChosen = true
		task.spawn(releasePlate, old, player.UserId)
		local model = spawned[player]
		if model and model:GetAttribute("Uid") == uid then
			VehicleBuilder.SetPlate(model, plateText)
		end
		State.MarkDirty(player)
		return Remotes.Ok()
	end, { rate = 3 })

	-- the personal plate (job + admin cars); first one free, changes cost the fee
	Remotes.Handle("Vehicle.SetPersonalPlate", function(player, text: any)
		local data = DataService.Get(player) :: { [string]: any }
		local plateText = typeof(text) == "string" and Plate.NormalizeDO(text) or nil
		if not plateText then
			return Remotes.Fail("bad_plate")
		end
		local okFilter, filtered = pcall(function()
			local result = TextService:FilterStringAsync(plateText, player.UserId, Enum.TextFilterContext.PublicChat)
			return result:GetNonChatStringForBroadcastAsync()
		end)
		if not okFilter or filtered ~= plateText then
			return Remotes.Fail("bad_plate")
		end
		local fee = if data.personalPlate then PLATE_FEE else 0
		if data.personalPlate and not Interaction.IsNear(player, "Shop", 25, "UI", "Plates") then
			return Remotes.Fail("plate_service_only")
		end
		if data.bank < fee then
			return Remotes.Fail("no_money")
		end
		if data.personalPlate ~= plateText and not claimPlate(plateText, player.UserId) then
			return Remotes.Fail("plate_taken")
		end
		if fee > 0 and not Economy.TrySpend(player, fee, "Kennzeichen " .. plateText) then
			return Remotes.Fail("no_money")
		end
		local old = data.personalPlate
		data.personalPlate = plateText
		if old and old ~= plateText then
			task.spawn(releasePlate, old, player.UserId)
		end
		State.MarkDirty(player)
		return Remotes.Ok()
	end, { rate = 3 })

	Remotes.Handle("Vehicle.SetColor", function(player, uid: any, index: any)
		local data = DataService.Get(player) :: { [string]: any }
		local entry = typeof(uid) == "string" and data.vehicles[uid] or nil
		local i = Remotes.Check.Int(index, 1, #PALETTE)
		if not entry or not i then
			return Remotes.Fail("bad_request")
		end
		local def = Vehicles.ById[entry.id]
		if def and def.car and not def.repaintable then
			return Remotes.Fail("livery_locked")
		end
		if not Economy.TrySpend(player, PAINT_FEE, "Lackierung") then
			return Remotes.Fail("no_money")
		end
		entry.color = table.clone(PALETTE[i])
		local model = spawned[player]
		if model and model:GetAttribute("Uid") == uid then
			if def and def.car then
				pcall(LiveryApplier.ApplyVehicle, model, VehicleConfig.Get(def.car), { Body = toColor(entry.color) })
			else
				VehicleBuilder.SetColor(model, toColor(entry.color))
			end
		end
		State.MarkDirty(player)
		return Remotes.Ok()
	end, { rate = 5 })

	-- Lights / indicators / blue lights / siren. Driver only.
	Remotes.Handle("Vehicle.Control", function(player, action: any, value: any)
		local model = driverOf(player)
		if not model then
			return Remotes.Fail("not_driving")
		end
		if action == "Headlights" then
			model:SetAttribute("Headlights", not model:GetAttribute("Headlights"))
		elseif action == "Indicator" then
			local v = Remotes.Check.OneOf(value, { "", "L", "R", "H" })
			if v == nil then
				return Remotes.Fail("bad_request")
			end
			model:SetAttribute("Indicator", if model:GetAttribute("Indicator") == v then "" else v)
		elseif action == "Brake" then
			model:SetAttribute("Brake", value == true)
		elseif action == "Hands" then
			-- motorbike stunts: one hand / no hands (everyone sees the arms go up)
			local v = Remotes.Check.OneOf(value, { "", "OneHand", "NoHands" })
			if v == nil or not model:GetAttribute("Bike") then
				return Remotes.Fail("bad_request")
			end
			if player.Character then
				player.Character:SetAttribute("BikeHands", v)
			end
		elseif action == "Bluelight" or action == "Siren" then
			if not model:GetAttribute("Emergency") then
				return Remotes.Fail("not_emergency")
			end
			local on = not model:GetAttribute(action)
			model:SetAttribute(action, on)
			if action == "Siren" then
				local siren = (model.PrimaryPart :: BasePart):FindFirstChild("Siren") :: Sound?
				if siren then
					if on then
						siren:Play()
					else
						siren:Stop()
					end
				end
			end
		else
			return Remotes.Fail("bad_request")
		end
		return Remotes.Ok()
	end, { rate = 30, needsData = false })

	-- Fuel: burn while driving, refuel at Arol stations.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, model in folder:GetChildren() do
				if model:IsA("Model") and model.PrimaryPart then
					local speed = (model.PrimaryPart :: BasePart).AssemblyLinearVelocity.Magnitude
					if speed > 2 then
						local top = (model:GetAttribute("TopSpeed") or 100) :: number
						local fuel = (model:GetAttribute("Fuel") or 100) :: number
						-- a full tank lasts roughly 25 minutes at average speed
						fuel = math.max(0, fuel - (0.05 + 0.08 * speed / top))
						model:SetAttribute("Fuel", fuel)
					end
				end
			end
		end
	end)

	Interaction.OnTrigger("Refuel", function(player, marker)
		local model = spawned[player]
		if not model or not model.PrimaryPart then
			Remotes.Push(player, "Notify", { key = "no_vehicle", error = true })
			return
		end
		if ((model.PrimaryPart :: BasePart).Position - marker.Position).Magnitude > 30 then
			Remotes.Push(player, "Notify", { key = "vehicle_too_far", error = true })
			return
		end
		local fuel = (model:GetAttribute("Fuel") or 100) :: number
		local liters = math.floor((100 - fuel) * 0.5) -- 50 l tank
		if liters <= 0 then
			Remotes.Push(player, "Notify", { key = "tank_full" })
			return
		end
		local cost = math.ceil(liters * Config.FuelPricePerLiter)
		if not Economy.TrySpend(player, cost, "Arol Tankstelle") then
			Remotes.Push(player, "Notify", { key = "no_money", error = true })
			return
		end
		model:SetAttribute("Fuel", 100)
		Remotes.Push(player, "Notify", { key = "refueled", args = { liters, cost } })
	end)
end

return VehicleService
