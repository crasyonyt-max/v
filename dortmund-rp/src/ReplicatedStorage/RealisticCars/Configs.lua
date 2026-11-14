--[[
	Realistic Cars - vehicle specifications

	Every number here is in real-world SI units (meters, kilograms, newton-meters,
	seconds). The simulation converts to studs using METERS_PER_STUD, so cars keep
	their real proportions and performance whatever the place's Gravity is.

	To add a car: copy an entry, give it a new key, and change the numbers.
	Body measurements are taken from the FRONT BUMPER backwards (in meters).
]]

local Configs = {}

-- 1 stud = 0.25 m. Roblox characters are about 5 studs tall, so this keeps
-- people and cars in believable proportion.
Configs.METERS_PER_STUD = 0.25

-- Optional looping engine sound (an asset you own or one from the Creator
-- Store, e.g. "rbxassetid://1234567890"). Leave empty for no sound.
Configs.ENGINE_SOUND_ID = ""

-- Order the showroom spawns cars in.
Configs.Order = { "Sedan", "Hatchback", "Sports", "Supercar", "Muscle", "SUV", "Pickup", "Police", "Van", "Truck" }

-- Shared defaults. Each car only lists what differs.
local DEFAULT = {
	tires = {
		grip = 1.0, -- peak friction coefficient on dry tarmac
		longB = 17, longC = 1.5, longE = 0, -- Pacejka "magic formula", longitudinal
		latB = 16, latC = 1.35, latE = 0, -- Pacejka, lateral
		loadSensitivity = 0.08, -- grip per unit load falls as load rises
		rollingResistance = 0.014,
		wheelInertia = 1.1, -- kg*m^2 per wheel (tire + rim + brake disc)
	},
	suspension = {
		restLength = 0.30, -- spring length at full extension (m)
		travel = 0.22, -- compression before the bump stop (m)
		frequencyFront = 1.45, -- ride frequency (Hz): 1.2 soft .. 2.5 race car
		frequencyRear = 1.6,
		dampingRatio = 0.38, -- 0.25 floaty .. 0.6 stiff
		antiRollFront = 16000, -- N per meter of left/right compression difference
		antiRollRear = 9000,
		rollCenterHeight = 0.22, -- tire forces act this high above the road (m)
	},
	brakes = {
		maxTorque = 3400, -- total brake torque at full pedal (N*m)
		frontBias = 0.67,
		handbrakeTorque = 1600, -- rear wheels only
	},
	steering = {
		maxAngle = 36, -- degrees at full lock, standing still
		speedFactor = 0.055, -- lock is divided by (1 + speedFactor * m/s)
	},
	aero = { cd = 0.30, area = 2.2, downforce = 0 },
	assists = { abs = true, tcs = true },
	engine = {
		inertia = 0.22, -- flywheel + crank (kg*m^2)
		engineBrake = 55, -- N*m of drag at max rpm, throttle closed
		launchRPM = 2400, -- clutch slips until this rpm at full throttle
		creepTorque = 30, -- automatic gearbox idle creep (N*m)
	},
	transmission = {
		shiftTime = 0.28,
		efficiency = 0.86,
		lsd = 0, -- limited slip lock (N*m per rad/s of wheel speed difference)
		awdFrontSplit = 0.4,
	},
	colors = {
		trim = Color3.fromRGB(28, 28, 30),
		glass = Color3.fromRGB(22, 28, 34),
		rim = Color3.fromRGB(190, 192, 198),
	},
}

local Cars = {}

Cars.Sedan = {
	displayName = "Sedan",
	mass = 1450, weightFront = 0.59, comHeight = 0.52,
	color = Color3.fromRGB(46, 74, 122),
	body = {
		length = 4.80, width = 1.83, height = 1.45, clearance = 0.15, belt = 0.95, frontOverhang = 0.95,
		windshieldBase = 1.75, roofFront = 2.45, roofRear = 3.45, rearBase = 4.00, cabinInset = 0.09,
	},
	wheelbase = 2.75, wheelRadius = 0.32, wheelWidth = 0.22,
	engine = {
		idleRPM = 750, redline = 6500, maxRPM = 6800,
		torque = { { 1000, 175 }, { 2500, 228 }, { 4000, 245 }, { 5000, 240 }, { 6000, 214 }, { 6800, 188 } },
	},
	transmission = { drivetrain = "FWD", gears = { 3.60, 2.10, 1.45, 1.10, 0.87, 0.70 }, reverse = 3.4, finalDrive = 3.6 },
	aero = { cd = 0.29, area = 2.2 },
	seats = 5, doors = 4,
}

Cars.Hatchback = {
	displayName = "Hot Hatch",
	mass = 1250, weightFront = 0.62, comHeight = 0.52,
	color = Color3.fromRGB(196, 32, 38),
	body = {
		length = 4.20, width = 1.79, height = 1.46, clearance = 0.14, belt = 0.95, frontOverhang = 0.88,
		windshieldBase = 1.45, roofFront = 2.15, roofRear = 3.70, rearBase = 4.05, cabinInset = 0.09,
	},
	wheelbase = 2.62, wheelRadius = 0.32, wheelWidth = 0.23,
	engine = {
		idleRPM = 800, redline = 6800, maxRPM = 7000,
		torque = { { 1000, 150 }, { 1800, 300 }, { 4500, 310 }, { 5500, 290 }, { 6500, 245 }, { 7000, 220 } },
	},
	transmission = { drivetrain = "FWD", gears = { 3.50, 2.05, 1.40, 1.08, 0.87, 0.72 }, reverse = 3.3, finalDrive = 3.95, lsd = 40, shiftTime = 0.2 },
	suspension = { frequencyFront = 1.8, frequencyRear = 2.0, antiRollRear = 14000 },
	tires = { grip = 1.05 },
	brakes = { maxTorque = 3600 },
	aero = { cd = 0.32, area = 2.15 },
	seats = 4, doors = 4,
}

Cars.Sports = {
	displayName = "Sports Coupe",
	mass = 1400, weightFront = 0.52, comHeight = 0.46,
	color = Color3.fromRGB(240, 196, 25),
	body = {
		length = 4.45, width = 1.86, height = 1.28, clearance = 0.12, belt = 0.82, frontOverhang = 0.92,
		windshieldBase = 1.80, roofFront = 2.50, roofRear = 3.15, rearBase = 4.00, cabinInset = 0.12,
	},
	wheelbase = 2.57, wheelRadius = 0.33, wheelWidth = 0.27,
	engine = {
		idleRPM = 850, redline = 7600, maxRPM = 7900,
		torque = { { 1000, 230 }, { 3000, 340 }, { 4500, 380 }, { 6000, 368 }, { 7500, 325 }, { 7900, 300 } },
	},
	transmission = { drivetrain = "RWD", gears = { 3.25, 2.20, 1.62, 1.26, 1.00, 0.82 }, reverse = 3.2, finalDrive = 3.73, lsd = 90, shiftTime = 0.16 },
	suspension = { frequencyFront = 2.0, frequencyRear = 2.2, dampingRatio = 0.45, antiRollFront = 22000, antiRollRear = 14000, restLength = 0.26, travel = 0.17 },
	tires = { grip = 1.12 },
	brakes = { maxTorque = 4400, frontBias = 0.64 },
	aero = { cd = 0.32, area = 2.0, downforce = 0.15 },
	steering = { maxAngle = 34 },
	seats = 2,
}

Cars.Supercar = {
	displayName = "Supercar",
	mass = 1520, weightFront = 0.42, comHeight = 0.42,
	color = Color3.fromRGB(110, 190, 60),
	body = {
		length = 4.60, width = 1.98, height = 1.14, clearance = 0.10, belt = 0.80, frontOverhang = 1.00,
		windshieldBase = 1.45, roofFront = 2.30, roofRear = 2.95, rearBase = 3.95, cabinInset = 0.16,
	},
	wheelbase = 2.65, wheelRadius = 0.35, wheelWidth = 0.31,
	engine = {
		idleRPM = 950, redline = 8500, maxRPM = 8700, inertia = 0.16,
		torque = { { 1000, 310 }, { 3000, 460 }, { 5000, 545 }, { 6500, 565 }, { 8000, 525 }, { 8700, 480 } },
		launchRPM = 3800,
	},
	transmission = { drivetrain = "AWD", awdFrontSplit = 0.32, gears = { 3.13, 2.12, 1.62, 1.30, 1.08, 0.90, 0.75 }, reverse = 3.0, finalDrive = 3.5, lsd = 120, shiftTime = 0.09 },
	suspension = { frequencyFront = 2.3, frequencyRear = 2.5, dampingRatio = 0.5, antiRollFront = 28000, antiRollRear = 20000, restLength = 0.24, travel = 0.14 },
	tires = { grip = 1.22, wheelInertia = 1.3 },
	brakes = { maxTorque = 6200, frontBias = 0.62, handbrakeTorque = 2000 },
	aero = { cd = 0.36, area = 2.0, downforce = 0.55 },
	steering = { maxAngle = 32, speedFactor = 0.06 },
	seats = 2,
}

Cars.Muscle = {
	displayName = "Muscle Car",
	mass = 1780, weightFront = 0.55, comHeight = 0.53,
	color = Color3.fromRGB(24, 24, 26),
	body = {
		length = 4.82, width = 1.92, height = 1.37, clearance = 0.14, belt = 0.93, frontOverhang = 1.00,
		windshieldBase = 2.05, roofFront = 2.65, roofRear = 3.40, rearBase = 4.15, cabinInset = 0.12,
	},
	wheelbase = 2.85, wheelRadius = 0.345, wheelWidth = 0.28,
	engine = {
		idleRPM = 700, redline = 6200, maxRPM = 6500, inertia = 0.3,
		torque = { { 1000, 390 }, { 2500, 525 }, { 4000, 565 }, { 5000, 535 }, { 6000, 480 }, { 6500, 440 } },
	},
	transmission = { drivetrain = "RWD", gears = { 2.97, 2.07, 1.43, 1.00, 0.84, 0.56 }, reverse = 3.3, finalDrive = 3.55, lsd = 70 },
	suspension = { frequencyFront = 1.6, frequencyRear = 1.7 },
	tires = { grip = 1.03 },
	brakes = { maxTorque = 4600 },
	aero = { cd = 0.35, area = 2.3 },
	seats = 4,
}

Cars.SUV = {
	displayName = "SUV",
	mass = 2150, weightFront = 0.53, comHeight = 0.68,
	color = Color3.fromRGB(170, 172, 168),
	body = {
		length = 4.85, width = 1.95, height = 1.78, clearance = 0.21, belt = 1.12, frontOverhang = 0.90,
		windshieldBase = 1.55, roofFront = 2.20, roofRear = 4.55, rearBase = 4.78, cabinInset = 0.08,
	},
	wheelbase = 2.90, wheelRadius = 0.38, wheelWidth = 0.26,
	engine = {
		idleRPM = 700, redline = 6000, maxRPM = 6200,
		torque = { { 1000, 290 }, { 2000, 400 }, { 4000, 420 }, { 5000, 400 }, { 6000, 350 } },
	},
	transmission = { drivetrain = "AWD", awdFrontSplit = 0.4, gears = { 4.05, 2.40, 1.55, 1.15, 0.86, 0.69 }, reverse = 3.6, finalDrive = 3.73, shiftTime = 0.32 },
	suspension = { restLength = 0.36, travel = 0.26, frequencyFront = 1.3, frequencyRear = 1.45, antiRollFront = 26000, antiRollRear = 14000 },
	tires = { grip = 0.96, wheelInertia = 1.6 },
	brakes = { maxTorque = 5200 },
	aero = { cd = 0.37, area = 2.9 },
	seats = 5, doors = 4,
}

Cars.Pickup = {
	displayName = "Pickup Truck",
	mass = 2300, weightFront = 0.58, comHeight = 0.72,
	color = Color3.fromRGB(122, 30, 28),
	body = {
		length = 5.60, width = 2.00, height = 1.90, clearance = 0.23, belt = 1.18, frontOverhang = 0.95,
		windshieldBase = 1.75, roofFront = 2.35, roofRear = 3.30, rearBase = 3.38, cabinInset = 0.07,
		bedStart = 3.45,
	},
	wheelbase = 3.60, wheelRadius = 0.39, wheelWidth = 0.27,
	engine = {
		idleRPM = 650, redline = 5600, maxRPM = 5800, inertia = 0.35,
		torque = { { 1000, 430 }, { 2500, 565 }, { 3500, 600 }, { 4500, 560 }, { 5600, 470 } },
	},
	transmission = { drivetrain = "RWD", gears = { 4.17, 2.34, 1.52, 1.14, 0.86, 0.69 }, reverse = 3.4, finalDrive = 3.55, shiftTime = 0.34 },
	suspension = { restLength = 0.38, travel = 0.28, frequencyFront = 1.35, frequencyRear = 1.7, antiRollFront = 24000, antiRollRear = 6000 },
	tires = { grip = 0.94, wheelInertia = 1.8 },
	brakes = { maxTorque = 5400, frontBias = 0.7 },
	aero = { cd = 0.42, area = 3.1 },
	seats = 2,
}

Cars.Police = {
	displayName = "Police Interceptor",
	mass = 1850, weightFront = 0.55, comHeight = 0.54,
	color = Color3.fromRGB(20, 22, 26),
	accentColor = Color3.fromRGB(235, 235, 235), -- doors
	police = true,
	body = {
		length = 5.05, width = 1.89, height = 1.48, clearance = 0.15, belt = 0.97, frontOverhang = 0.96,
		windshieldBase = 1.85, roofFront = 2.55, roofRear = 3.62, rearBase = 4.20, cabinInset = 0.09,
	},
	wheelbase = 2.95, wheelRadius = 0.335, wheelWidth = 0.245,
	engine = {
		idleRPM = 700, redline = 6000, maxRPM = 6300, inertia = 0.28,
		torque = { { 1000, 340 }, { 3000, 480 }, { 4400, 520 }, { 5500, 475 }, { 6300, 430 } },
	},
	transmission = { drivetrain = "RWD", gears = { 3.00, 2.10, 1.50, 1.15, 0.92, 0.72 }, reverse = 3.2, finalDrive = 3.40, lsd = 60, shiftTime = 0.22 },
	suspension = { frequencyFront = 1.7, frequencyRear = 1.85, dampingRatio = 0.42, antiRollFront = 22000, antiRollRear = 12000 },
	tires = { grip = 1.04 },
	brakes = { maxTorque = 5000 },
	aero = { cd = 0.31, area = 2.3 },
	seats = 4, doors = 4,
}

Cars.Van = {
	displayName = "Van",
	mass = 2450, weightFront = 0.55, comHeight = 0.82,
	color = Color3.fromRGB(235, 235, 235),
	body = {
		length = 5.90, width = 2.00, height = 2.55, clearance = 0.18, belt = 1.15, frontOverhang = 0.95,
		windshieldBase = 0.55, roofFront = 1.25, roofRear = 5.85, rearBase = 5.90, cabinInset = 0.04,
		sideWindowsTo = 2.0, seatHeight = 0.78,
	},
	wheelbase = 3.66, wheelRadius = 0.36, wheelWidth = 0.24,
	engine = {
		idleRPM = 750, redline = 4200, maxRPM = 4500, inertia = 0.35, launchRPM = 1800, engineBrake = 70,
		torque = { { 1000, 250 }, { 1600, 400 }, { 2800, 400 }, { 3800, 330 }, { 4500, 260 } },
	},
	transmission = { drivetrain = "RWD", gears = { 4.38, 2.86, 1.92, 1.37, 1.00, 0.82 }, reverse = 3.9, finalDrive = 3.92, shiftTime = 0.35 },
	suspension = { restLength = 0.34, travel = 0.24, frequencyFront = 1.4, frequencyRear = 1.6, antiRollFront = 26000, antiRollRear = 12000 },
	tires = { grip = 0.95, wheelInertia = 1.6 },
	brakes = { maxTorque = 5200 },
	aero = { cd = 0.36, area = 4.6 },
	steering = { maxAngle = 38 },
	seats = 2,
}

Cars.Truck = {
	displayName = "Truck",
	mass = 11000, weightFront = 0.5, comHeight = 1.3,
	color = Color3.fromRGB(235, 235, 235),
	body = {
		length = 8.00, width = 2.50, height = 3.20, clearance = 0.30, belt = 1.50, frontOverhang = 1.30,
		windshieldBase = 0.12, roofFront = 0.70, roofRear = 2.30, rearBase = 2.34, cabinInset = 0.04,
		sideWindowsTo = 1.8, seatHeight = 1.25, noseLength = 0.12,
		cargoBox = { from = 2.45, height = 3.45 },
	},
	wheelbase = 4.50, wheelRadius = 0.50, wheelWidth = 0.32,
	engine = {
		idleRPM = 600, redline = 2300, maxRPM = 2500, inertia = 2.5, launchRPM = 1200, engineBrake = 300, creepTorque = 150,
		torque = { { 800, 500 }, { 1100, 900 }, { 1700, 900 }, { 2200, 750 }, { 2500, 600 } },
	},
	transmission = { drivetrain = "RWD", gears = { 9.5, 6.6, 4.6, 3.3, 2.4, 1.7, 1.25, 1.0 }, reverse = 9.0, finalDrive = 3.1, shiftTime = 0.5, efficiency = 0.9 },
	suspension = {
		restLength = 0.40, travel = 0.20, frequencyFront = 1.6, frequencyRear = 1.8, dampingRatio = 0.4,
		antiRollFront = 300000, antiRollRear = 250000, rollCenterHeight = 0.5,
	},
	tires = { grip = 0.85, wheelInertia = 12 },
	brakes = { maxTorque = 40000, handbrakeTorque = 15000 },
	aero = { cd = 0.6, area = 8.0 },
	steering = { maxAngle = 40, speedFactor = 0.08 },
	seats = 2,
}

-- Fill each car's missing values from DEFAULT.
local function merge(defaults, overrides)
	local out = {}
	for k, v in pairs(defaults) do
		out[k] = v
	end
	for k, v in pairs(overrides or {}) do
		if type(v) == "table" and type(defaults[k]) == "table" and #v == 0 then
			out[k] = merge(defaults[k], v)
		else
			out[k] = v
		end
	end
	return out
end

for key, car in pairs(Cars) do
	local full = merge(DEFAULT, car)
	full.key = key
	-- Wheel centres sit just inside the body sides.
	full.trackWidth = full.body.width - full.wheelWidth - 0.04
	Cars[key] = full
end

Configs.Cars = Cars
return Configs
