--[[
	Dortmund RP bridge between the car client (CarClient) and the game's own driving
	GUI (VehicleController), so cars use the same dashboard and touch pedals as the
	motorbike.

	VehicleController writes: external, throttle (0..1), brake (0..1), steer (-1..1)
	CarClient writes: telemetry = { kmh, gear, rpm, maxRPM, redline }, flip = function
]]
return {
	external = false,
	throttle = 0,
	brake = 0,
	steer = 0,
	telemetry = { kmh = 0, gear = 0, rpm = 0, maxRPM = 1, redline = 1 },
	flip = nil,
}
