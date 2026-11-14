--[[
	Realistic Cars - server

	* Spawns one of every car in a showroom row near the SpawnLocation.
	* Gives the driver network ownership so their client runs the physics.
	* Holds parked cars on their suspension with the brakes on.
	* Runs lights, sirens and respawns.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local root = script.Parent
local Configs = require(root.Configs)
local Builder = require(root.Builder)
local Sim = require(root.Sim)

-- The showroom is skipped when a game's own vehicle system spawns the cars
-- (e.g. Dortmund RP's ServerScriptService/VehicleSystem).
local SPAWN_SHOWROOM = not game:GetService("ServerScriptService"):FindFirstChild("VehicleSystem")
local SPACING = 16 -- studs between showroom cars
local ROW_DISTANCE = 45 -- studs in front of the SpawnLocation
local RETURN_ABANDONED_AFTER = 180 -- seconds before an empty car away from home respawns

local stateRemote = Instance.new("RemoteEvent")
stateRemote.Name = "CarState"
stateRemote.Parent = root
local commandRemote = Instance.new("RemoteEvent")
commandRemote.Name = "CarCommand"
commandRemote.Parent = root

local carFolder = Instance.new("Folder")
carFolder.Name = "RealisticCars"
carFolder.Parent = workspace

local cars = {} -- [model] = record

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function updateLights(rec)
	local model = rec.model
	local lights = model:FindFirstChild("Lights")
	if not lights then
		return
	end
	local brake = model:GetAttribute("Brake")
	local head = model:GetAttribute("Headlights")
	local reverse = model:GetAttribute("Gear") == -1
	for _, p in ipairs(lights:GetChildren()) do
		if p.Name == "Headlight" then
			p.Color = head and rgb(255, 252, 238) or rgb(205, 205, 200)
			local beam = p:FindFirstChildOfClass("SpotLight")
			if beam then
				beam.Enabled = head
			end
		elseif p.Name == "Taillight" then
			p.Color = brake and rgb(255, 30, 30) or head and rgb(170, 12, 12) or rgb(110, 10, 10)
		elseif p.Name == "ReverseLight" then
			p.Color = reverse and rgb(255, 255, 250) or rgb(110, 110, 110)
			p.Material = reverse and Enum.Material.Neon or Enum.Material.Glass
		end
	end
end

local function park(rec)
	local model = rec.model
	rec.driver = nil
	pcall(function()
		model.Chassis:SetNetworkOwner(nil)
	end)
	rec.sim = Sim.fromModel(model, rec.cfg)
	rec.sim:setParked(true)
	model:SetAttribute("Throttle", 0)
	model:SetAttribute("Brake", false)
	model:SetAttribute("Gear", 0)
	model:SetAttribute("Steer", 0)
	model:SetAttribute("RPM", rec.cfg.engine.idleRPM)
end

-- Takes over any car model in the workspace: parked physics, driver hand-off,
-- seats, lights.
local function setupCar(model, cfg, key, home)
	if cars[model] then
		return cars[model]
	end
	local rec = { model = model, cfg = cfg, key = key, home = home, abandonedSince = nil }
	cars[model] = rec
	park(rec)

	local engine = model.Chassis:FindFirstChild("Engine")
	if engine then
		engine.Playing = true
	end

	local driverSeat = model:FindFirstChild("DriverSeat")
	driverSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local hum = driverSeat.Occupant
		local plr = hum and Players:GetPlayerFromCharacter(hum.Parent)
		if plr then
			rec.driver = plr
			rec.sim = nil
			pcall(function()
				model.Chassis:SetNetworkOwner(plr)
			end)
		else
			park(rec)
		end
	end)

	for _, seat in ipairs(model:GetChildren()) do
		if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
			local prompt = seat:FindFirstChild("EnterPrompt")
			if prompt then
				prompt.Triggered:Connect(function(plr)
					local char = plr.Character
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 and not hum.SeatPart and not seat.Occupant then
						seat:Sit(hum)
					end
				end)
				seat:GetPropertyChangedSignal("Occupant"):Connect(function()
					prompt.Enabled = seat.Occupant == nil
				end)
			end
		end
	end

	for _, attr in ipairs({ "Brake", "Headlights", "Gear" }) do
		model:GetAttributeChangedSignal(attr):Connect(function()
			updateLights(rec)
		end)
	end
	model.Destroying:Connect(function()
		cars[model] = nil
	end)
	updateLights(rec)
	return rec
end

local function spawnCar(key, cframe)
	local cfg = Configs.Cars[key]
	assert(cfg, "Unknown car type: " .. tostring(key))
	local model = Builder.build(cfg, cframe)
	model.Parent = carFolder
	return setupCar(model, cfg, key, cframe)
end

-- Cars spawned by other scripts (cloned from ServerStorage etc.)
local function register(model)
	if cars[model] or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end
	local key = model:GetAttribute("CarType")
	local cfg = Configs.Cars[key]
	if cfg and model:FindFirstChild("Chassis") and model:FindFirstChild("DriverSeat") then
		setupCar(model, cfg, key, model:GetPivot())
	end
end
CollectionService:GetInstanceAddedSignal("RealisticCar"):Connect(register)
for _, model in ipairs(CollectionService:GetTagged("RealisticCar")) do
	task.spawn(register, model)
end

-- Client -> server: the driver reports steering, rpm and pedals for everyone else's visuals.
stateRemote.OnServerEvent:Connect(function(plr, model, steer, rpm, gear, brake, throttle)
	local rec = typeof(model) == "Instance" and cars[model]
	if not rec or rec.driver ~= plr then
		return
	end
	if type(steer) ~= "number" or type(rpm) ~= "number" or type(gear) ~= "number" or type(throttle) ~= "number" then
		return
	end
	if steer ~= steer or rpm ~= rpm or throttle ~= throttle then
		return -- NaN
	end
	model:SetAttribute("Steer", math.clamp(math.round(steer * 100) / 100, -1, 1))
	model:SetAttribute("RPM", math.clamp(math.round(rpm / 25) * 25, 0, 20000))
	model:SetAttribute("Gear", math.clamp(math.round(gear), -1, 10))
	model:SetAttribute("Brake", brake == true)
	model:SetAttribute("Throttle", math.clamp(math.round(throttle * 10) / 10, 0, 1))
end)

commandRemote.OnServerEvent:Connect(function(plr, model, command)
	local rec = typeof(model) == "Instance" and cars[model]
	if not rec or rec.driver ~= plr then
		return
	end
	if command == "Headlights" then
		model:SetAttribute("Headlights", not model:GetAttribute("Headlights"))
	elseif command == "Siren" and (rec.cfg.police or (model:GetAttribute("LightType") or "none") ~= "none") then
		model:SetAttribute("Siren", not model:GetAttribute("Siren"))
	end
end)

-- Parked cars: the server holds them on their springs.
RunService.Heartbeat:Connect(function(dt)
	for _, rec in pairs(cars) do
		if rec.sim and rec.model.Parent then
			rec.sim:step(dt)
		end
	end
end)

-- Police lights
task.spawn(function()
	local flash = false
	while true do
		task.wait(0.13)
		flash = not flash
		for _, rec in pairs(cars) do
			local lightType = rec.model:GetAttribute("LightType")
			if lightType and lightType ~= "none" then
				-- Livery-driven lights (tagged EmergencyLight), alternating left/right.
				local on = rec.model:GetAttribute("Siren")
				local hiddenWhenOff = lightType == "hidden_blue"
				if not rec.emergency then
					rec.emergency = {}
					for _, part in ipairs(rec.model:GetDescendants()) do
						if part:IsA("BasePart") and CollectionService:HasTag(part, "EmergencyLight") then
							table.insert(rec.emergency, part)
						end
					end
				end
				local update = on or rec.sirenWasOn
				rec.sirenWasOn = on
				for _, part in ipairs(update and rec.emergency or {}) do
					if part.Parent then
						local left = rec.model.PrimaryPart.CFrame:PointToObjectSpace(part.Position).X < 0
						local lit = on and (left == flash)
						local base = part:GetAttribute("BaseTransparency") or 0
						part.Transparency = lit and 0 or (on and 0.7 or (hiddenWhenOff and 1 or base))
						part.Material = Enum.Material.Neon
						for _, light in ipairs(part:GetChildren()) do
							if light:IsA("Light") then
								light.Enabled = lit
							end
						end
					end
				end
			elseif rec.cfg.police then
				local on = rec.model:GetAttribute("Siren")
				local lights = rec.model:FindFirstChild("Lights")
				local red = lights and lights:FindFirstChild("SirenRed")
				local blue = lights and lights:FindFirstChild("SirenBlue")
				if red and blue then
					local redOn, blueOn = on and flash, on and not flash
					red.Color = redOn and rgb(255, 40, 40) or rgb(90, 0, 0)
					blue.Color = blueOn and rgb(50, 90, 255) or rgb(0, 0, 90)
					red.PointLight.Enabled = redOn
					blue.PointLight.Enabled = blueOn
				end
			end
		end
	end
end)

-------------------------------------------------------------------------------
-- Showroom
-------------------------------------------------------------------------------

local function groundAt(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { carFolder }
	return workspace:Raycast(pos + Vector3.new(0, 300, 0), Vector3.new(0, -1200, 0), params)
end

local slots = {}

local function spawnShowroom()
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = spawn and spawn.Position or Vector3.new(0, 0, 0)
	if not groundAt(origin) then
		local ground = Instance.new("Part")
		ground.Name = "CarTestGround"
		ground.Anchored = true
		ground.Size = Vector3.new(2048, 4, 2048)
		ground.Position = Vector3.new(origin.X, origin.Y - 2, origin.Z)
		ground.Material = Enum.Material.Asphalt
		ground.Color = Color3.fromRGB(70, 72, 76)
		ground.Parent = workspace
	end
	local n = #Configs.Order
	for i, key in ipairs(Configs.Order) do
		local p = origin + Vector3.new((i - (n + 1) / 2) * SPACING, 0, -ROW_DISTANCE)
		local hit = groundAt(p)
		local y = hit and hit.Position.Y or origin.Y
		local cf = CFrame.new(p.X, y + 0.2, p.Z) -- facing -Z, away from the spawn
		slots[i] = { key = key, cframe = cf, rec = spawnCar(key, cf) }
	end
end

-- Respawn destroyed cars, and return abandoned ones.
task.spawn(function()
	while true do
		task.wait(3)
		for _, slot in ipairs(slots) do
			local rec = slot.rec
			local model = rec.model
			local occupied = false
			if model.Parent then
				for _, s in ipairs(model:GetChildren()) do
					if (s:IsA("Seat") or s:IsA("VehicleSeat")) and s.Occupant then
						occupied = true
					end
				end
			end
			local away = model.Parent and model.PrimaryPart
				and (model.PrimaryPart.Position - slot.cframe.Position).Magnitude > 40
			if not model.Parent then
				slot.rec = spawnCar(slot.key, slot.cframe)
			elseif away and not occupied then
				rec.abandonedSince = rec.abandonedSince or os.clock()
				if os.clock() - rec.abandonedSince > RETURN_ABANDONED_AFTER then
					model:Destroy()
					slot.rec = spawnCar(slot.key, slot.cframe)
				end
			else
				rec.abandonedSince = nil
			end
		end
	end
end)

_G.RealisticCars = {
	Spawn = spawnCar, -- _G.RealisticCars.Spawn("Supercar", CFrame.new(0, 0, 0))
	Configs = Configs,
}

if SPAWN_SHOWROOM then
	spawnShowroom()
end
