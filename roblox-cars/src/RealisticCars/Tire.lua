--[[
	Tire model: Pacejka "magic formula" with combined slip.

	slip ratio  (kappa) = (wheel surface speed - road speed) / road speed
	slip angle  (alpha) = angle between where the tire points and where it moves

	Grip rises with slip up to a peak (about 10% slip / 8 degrees), then falls
	off into a slide. Braking and cornering share one budget of grip: brake
	hard in a corner and the car runs wide, like a real one.
]]

local Tire = {}

local atan, sin, sqrt = math.atan, math.sin, math.sqrt

function Tire.magic(x, B, C, D, E)
	local Bx = B * x
	return D * sin(C * atan(Bx - E * (Bx - atan(Bx))))
end

-- Slip value where the magic formula peaks, found numerically.
function Tire.peak(B, C, E)
	local best, bestX = -math.huge, 0
	for i = 1, 400 do
		local x = i * 0.001
		local f = Tire.magic(x, B, C, 1, E)
		if f > best then
			best, bestX = f, x
		end
	end
	return bestX
end

-- Precompute the peaks for a tire parameter table (done once per car).
function Tire.prepare(t)
	t.kPeak = Tire.peak(t.longB, t.longC, t.longE)
	t.aPeak = Tire.peak(t.latB, t.latC, t.latE)
	return t
end

--[[
	Returns longitudinal and lateral force (newtons).
	kappa : slip ratio (positive = wheel spinning faster than the road)
	alpha : slip angle in radians (positive = sliding to the tire's right)
	Fz    : vertical load (N)
	Fz0   : nominal load used for load sensitivity (N)
	Fx > 0 pushes the car forward; Fy > 0 pushes it to the tire's right.
]]
function Tire.forces(kappa, alpha, Fz, Fz0, t)
	if Fz <= 0 then
		return 0, 0
	end
	local sk = kappa / t.kPeak
	local sa = alpha / t.aPeak
	local rho = sqrt(sk * sk + sa * sa)
	if rho < 1e-9 then
		return 0, 0
	end
	local mu = t.grip * math.max(0.6, 1 - t.loadSensitivity * (Fz / Fz0 - 1))
	local D = mu * Fz
	local Fx = Tire.magic(rho * t.kPeak, t.longB, t.longC, D, t.longE) * (sk / rho)
	local Fy = -Tire.magic(rho * t.aPeak, t.latB, t.latC, D, t.latE) * (sa / rho)
	return Fx, Fy
end

return Tire
