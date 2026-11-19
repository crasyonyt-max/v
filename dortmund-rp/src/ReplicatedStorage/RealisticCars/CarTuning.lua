--!strict
-- Dortmund RP: a car's physics config = its body type (Configs.Cars[CarType]) tuned
-- with the model's own attributes: Power (PS) scales the torque curve, TopSpeed
-- (km/h) is the limiter (Sim reads cfg.topSpeed). Results are cached per tuning.

local Configs = require(script.Parent.Configs)

local CarTuning = {}

local cache: { [string]: any } = {}

-- every car: extra braking on top of the tires (m/s² at full pedal)
CarTuning.BRAKE_ASSIST = 5

-- handling per body type, on top of Configs (only grip / steering / brakes, the
-- body itself stays as built)
CarTuning.TypeTweaks = {
	Bus = {
		brakes = { maxTorque = 65000 },
		tires = { grip = 1.05 },
		steering = { maxAngle = 50, speedFactor = 0.035 },
		brakeAssist = 4,
	},
	Truck = {
		brakes = { maxTorque = 55000 },
		steering = { speedFactor = 0.04 },
		brakeAssist = 4,
	},
} :: { [string]: { [string]: any } }

local function merged(base: any, carType: string): any
	local cfg = table.clone(base)
	cfg.brakeAssist = CarTuning.BRAKE_ASSIST
	for k, v in CarTuning.TypeTweaks[carType] or {} do
		if typeof(v) == "table" then
			local t = table.clone(cfg[k] or {})
			for k2, v2 in v do
				t[k2] = v2
			end
			cfg[k] = t
		else
			cfg[k] = v
		end
	end
	return cfg
end

-- peak power of a torque curve, in PS
function CarTuning.PeakPS(torque: { { number } }): number
	local best = 0
	for _, p in torque do
		best = math.max(best, p[1] * p[2] / 7023)
	end
	return best
end

function CarTuning.Get(carType: string?, power: number?, topSpeed: number?): any
	local base = carType and Configs.Cars[carType]
	if not base then
		return nil
	end
	local key = ("%s|%s|%s"):format(carType :: string, tostring(power), tostring(topSpeed))
	local cfg = cache[key]
	if cfg then
		return cfg
	end
	cfg = merged(base, carType :: string)
	cfg.engine = table.clone(base.engine)
	if power then
		local scale = math.clamp(power / CarTuning.PeakPS(base.engine.torque), 0.35, 3.2)
		local curve = {}
		for i, p in base.engine.torque do
			curve[i] = { p[1], p[2] * scale }
		end
		cfg.engine.torque = curve
		cfg.powerScale = scale
	end
	cfg.topSpeed = topSpeed
	cache[key] = cfg
	return cfg
end

function CarTuning.For(model: Instance): any
	return CarTuning.Get(model:GetAttribute("CarType"), model:GetAttribute("Power"), model:GetAttribute("TopSpeed"))
end

return CarTuning
