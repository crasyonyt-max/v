--[[
	VehicleModelGenerator (server only)

	For every vehicle in VehicleConfig whose model is missing from
	ServerStorage/Vehicles, this builds a drivable placeholder car out of parts
	(using ReplicatedStorage/RealisticCars). Each placeholder comes with the
	tagged livery parts (Body, Stripe, Accent, Lettering, EmergencyLight,
	extras, Trailer).

	When you add a real model with the same name, the generator leaves it alone.
	Placeholders get the attribute Placeholder = true.

	BODY_RULES decides which body/physics type a vehicle gets: the first rule
	whose text appears in the model name wins. Add a rule to change the shape.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local VehicleConfig = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local CarPerformance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CarPerformance"))

local Generator = {}

-- Body tweaks (meters) on top of a RealisticCars type. Only shape changes here;
-- size-critical values (width, wheelbase, wheels) stay with the type's physics.
local KOMBI = { roofRear = 4.25, rearBase = 4.65 } -- estate roof on the Sedan
local LKW = { length = 9.0, cargoBox = { from = 2.45, height = 3.6, trailer = true } }

local GELENKBUS = { length = 18.0, roofRear = 17.90, rearBase = 18.0 } -- articulated: 18 m

local CATEGORY_RULES = {
	LKW = { Type = "Truck", Body = LKW },
}

local BODY_RULES = {
	{ Type = "Bus", Body = GELENKBUS, Match = { "Sitaro G" } },
	{ Type = "Bus", Match = { "Sitaro", "Lion's", "Urbano" } },
	{ Type = "Supercar", Match = { "Chiran", "Jesco", "Huayro", "AMX Uno", "Neverra", "Black Series", "750S", "SF90", "Venino", "One:1" } },
	{ Type = "Sports", Match = { "Elfer", "Kayman", "Kontinental", "300 SL", "Taikan", "e-tran" } },
	{ Type = "Pickup", Match = { "Raptur" } },
	{ Type = "Truck", Match = { "Ategon", "TGM", "Econ", "Panter", "TGL", "Atekon", "TGX", "Aktros", "Skandia", "FH16", "Arokos", "Unimug" } },
	{ Type = "Van", Match = { "Sprintor", "Vitto", "Transporta", "Krafter", "TGE", "Kaddy", "E-Van" } },
	{ Type = "Sedan", Body = KOMBI, Match = { "Kombi", "Variant", "Touring", "Avant", "E-Klasse T" } },
	{ Type = "SUV", Match = { "Tiguar", "Makan", "G-Klasse", "Uros", "Kullinan", "Turan", "S-Maxx", "X1", "GLX", "G 63", "Defendor", "Kruiser", "Range Rider", "DBX", "Active Tourer" } },
	{ Type = "Muscle", Match = { "Fantom", "Maybeck", "i7", "EQS" } }, -- big, heavy saloons
	{ Type = "Hatchback", Match = { "Sanderro", "Pikanto", "Korsa", "Pollo", "Golfo", "Fiesto", "Käfa", "Mantra", "Formentor", "RX3" } },
}
local DEFAULT_RULE = { Type = "Sedan" }

function Generator.RuleFor(vehicle)
	-- V1.0 Creator Store bodies name their physics type directly
	if vehicle.CarType then
		return { Type = vehicle.CarType }
	end
	local byCategory = CATEGORY_RULES[vehicle.Category]
	if byCategory then
		return byCategory
	end
	for _, rule in ipairs(BODY_RULES) do
		for _, text in ipairs(rule.Match) do
			if string.find(vehicle.Model, text, 1, true) then
				return rule
			end
		end
	end
	return DEFAULT_RULE
end

-- Dortmund RP: builds the model for ONE vehicle (cached in ServerStorage/Vehicles),
-- so the server doesn't build all ~80 cars at start. Returns the template or nil.
function Generator.Get(vehicle)
	local folderName = VehicleConfig.Settings.VehiclesFolder
	local folder = ServerStorage:FindFirstChild(folderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = ServerStorage
	end
	local existing = folder:FindFirstChild(vehicle.Model)
	if existing then
		return existing
	end
	local carsFolder = ReplicatedStorage:FindFirstChild("RealisticCars")
	if not carsFolder then
		return nil
	end
	local Builder = require(carsFolder:WaitForChild("Builder"))
	local Configs = require(carsFolder:WaitForChild("Configs"))
	local rule = Generator.RuleFor(vehicle)
	local preset = Configs.Cars[rule.Type]
	if not preset then
		return nil
	end
	local cfg = table.clone(preset)
	cfg.body = table.clone(preset.body)
	for k, val in pairs(rule.Body or {}) do
		cfg.body[k] = val
	end
	cfg.displayName = vehicle.Model
	cfg.police = nil
	cfg.accentColor = nil
	cfg.liveryParts = true
	cfg.color = vehicle.Livery.Colors.Body or preset.color
	-- V1.0 real bodies: the physics wheels get the body's own wheel size and track,
	-- so its wheels fill the arches and stand on the road (CarTuning reads them back)
	local wheelR, track = Generator.WheelFit(vehicle, cfg, Configs.METERS_PER_STUD)
	if wheelR then
		cfg.wheelRadius, cfg.trackWidth = wheelR, track
	end
	local ok, model = pcall(Builder.build, cfg, CFrame.new(0, 0, 0))
	if ok and wheelR then
		model:SetAttribute("WheelRadius", wheelR)
		model:SetAttribute("TrackWidth", track)
	end
	if not ok then
		warn(("[VehicleModelGenerator] could not build %s: %s"):format(vehicle.Model, tostring(model)))
		return nil
	end
	model.Name = vehicle.Model
	model:SetAttribute("Placeholder", true)
	-- V1.0: a real (cleaned Creator Store) body when it is available; until then the
	-- car keeps its generated body and is not cached, so it gets the real one later
	if vehicle.Toolbox then
		local ToolboxBodies = require(script.Parent.ToolboxBodies)
		if not ToolboxBodies.Apply(model, vehicle) then
			local topSpeed, power = CarPerformance.Get(vehicle.Model)
			model:SetAttribute("TopSpeed", topSpeed)
			model:SetAttribute("Power", power)
			return model
		end
	end
	-- Dortmund RP: every car its own top speed + power (Shared/CarPerformance)
	local topSpeed, power = CarPerformance.Get(vehicle.Model)
	model:SetAttribute("TopSpeed", topSpeed)
	model:SetAttribute("Power", power)
	model.Parent = folder
	return model
end

-- wheel radius + track (meters) of a real body at the size it gets on this car
function Generator.WheelFit(vehicle: any, cfg: any, mps: number): (number?, number?)
	if not vehicle.Toolbox then
		return nil, nil
	end
	local ok, bodies = pcall(function()
		return require(game:GetService("ServerStorage"):WaitForChild("ToolboxBodies", 5) :: any)
	end)
	local info = ok and bodies and bodies[vehicle.Toolbox]
	if not info then
		return nil, nil
	end
	local w = info.wheels
	local bodyBase = math.abs(w.FL[3] - w.RL[3])
	if bodyBase < 0.1 then
		return nil, nil
	end
	local s = cfg.wheelbase / mps / bodyBase
	local r = (w.FL[4] + w.RL[4]) / 2 * s * mps
	local tr = (math.abs(w.FL[1] - w.FR[1]) + math.abs(w.RL[1] - w.RR[1])) / 2 * s * mps
	return math.clamp(r, cfg.wheelRadius * 0.6, cfg.wheelRadius * 1.4),
		math.clamp(tr, cfg.trackWidth * 0.6, cfg.trackWidth * 1.2)
end

-- Builds placeholders for missing models. Returns how many were built.
function Generator.GenerateMissing()
	local carsFolder = ReplicatedStorage:FindFirstChild("RealisticCars")
	if not carsFolder then
		warn("[VehicleModelGenerator] ReplicatedStorage/RealisticCars is missing, so no placeholder cars can be built.")
		return 0
	end
	local Builder = require(carsFolder:WaitForChild("Builder"))
	local Configs = require(carsFolder:WaitForChild("Configs"))

	local folderName = VehicleConfig.Settings.VehiclesFolder
	local folder = ServerStorage:FindFirstChild(folderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = ServerStorage
	end

	local built = 0
	for _, vehicle in ipairs(VehicleConfig.List) do
		if not folder:FindFirstChild(vehicle.Model) then
			local rule = Generator.RuleFor(vehicle)
			local preset = Configs.Cars[rule.Type]
			if not preset then
				warn(("[VehicleModelGenerator] unknown body type %q for %s"):format(rule.Type, vehicle.Model))
				continue
			end
			local cfg = table.clone(preset)
			cfg.body = table.clone(preset.body)
			for k, val in pairs(rule.Body or {}) do
				cfg.body[k] = val
			end
			cfg.displayName = vehicle.Model
			cfg.police = nil
			cfg.accentColor = nil
			cfg.liveryParts = true
			cfg.color = vehicle.Livery.Colors.Body or preset.color

			local ok, model = pcall(Builder.build, cfg, CFrame.new(0, 0, 0))
			if ok then
				model.Name = vehicle.Model
				model:SetAttribute("Placeholder", true)
				model.Parent = folder
				built += 1
			else
				warn(("[VehicleModelGenerator] could not build %s: %s"):format(vehicle.Model, tostring(model)))
			end
		end
	end
	if built > 0 then
		print(("[VehicleModelGenerator] built %d placeholder vehicle model(s) in ServerStorage/%s"):format(built, folderName))
	end
	return built
end

return Generator
