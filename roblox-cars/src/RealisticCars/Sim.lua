--[[
	Realistic Cars - vehicle simulation

	Runs on whoever owns the car's physics: the driver's client while someone is
	driving, the server while it is parked. Works in SI units internally and
	converts to studs at the edges.

	Per frame:
	  1. Raycast suspension per wheel: spring + damper + anti-roll bars.
	  2. Engine -> clutch -> gearbox -> differential -> wheel torque.
	  3. Wheel spin integrated semi-implicitly (stable at 60 Hz).
	  4. Pacejka tire forces with combined slip, applied at the contact patch.
	  5. Aerodynamic drag and downforce.
	  6. Gravity corrected to real 9.81 m/s^2 for the car.
]]

local Tire = require(script.Parent.Tire)
local Configs = require(script.Parent.Configs)

local MPS = Configs.METERS_PER_STUD
local G = 9.81
local AIR_DENSITY = 1.225
local LOW_SPEED = 2.0 -- m/s, below this slip uses a fixed denominator
local TAU = math.pi * 2
local RADS_PER_RPM = TAU / 60

local abs, max, min, clamp, sign, sqrt = math.abs, math.max, math.min, math.clamp, math.sign, math.sqrt

local function moveTowards(a, b, step)
	if a < b then
		return min(a + step, b)
	end
	return max(a - step, b)
end

local function torqueAt(curve, rpm)
	if rpm <= curve[1][1] then
		return curve[1][2] * max(rpm, 0) / curve[1][1]
	end
	for i = 2, #curve do
		local a, b = curve[i - 1], curve[i]
		if rpm <= b[1] then
			return a[2] + (b[2] - a[2]) * (rpm - a[1]) / (b[1] - a[1])
		end
	end
	return curve[#curve][2]
end

local Sim = {}
Sim.__index = Sim
Sim.torqueAt = torqueAt

--[[
	body: adapter table with
	  getCFrame() -> CFrame of the root part
	  getVelocity() -> Vector3 studs/s
	  velocityAt(worldPos) -> Vector3 studs/s
	  getMass() -> assembly mass (Roblox units)
	  getGravity() -> studs/s^2
	  impulse(Vector3), impulseAt(Vector3, worldPos)
	  raycast(origin, direction) -> {Position, Normal} or nil
	mounts: { FL = Vector3, FR = ..., RL = ..., RR = ... } in root-local studs
]]
function Sim.new(body, cfg, mounts)
	local self = setmetatable({}, Sim)
	self.body = body
	self.cfg = cfg
	self.tire = Tire.prepare(table.clone(cfg.tires))

	local tr = cfg.transmission
	local driven = { FL = false, FR = false, RL = false, RR = false }
	local share = { FL = 0, FR = 0, RL = 0, RR = 0 }
	if tr.drivetrain == "FWD" then
		driven.FL, driven.FR, share.FL, share.FR = true, true, 0.5, 0.5
	elseif tr.drivetrain == "RWD" then
		driven.RL, driven.RR, share.RL, share.RR = true, true, 0.5, 0.5
	else
		local f = tr.awdFrontSplit
		driven.FL, driven.FR, driven.RL, driven.RR = true, true, true, true
		share.FL, share.FR, share.RL, share.RR = f / 2, f / 2, (1 - f) / 2, (1 - f) / 2
	end

	local s = cfg.suspension
	self.wheels = {}
	for _, name in ipairs({ "FL", "FR", "RL", "RR" }) do
		local front = name:sub(1, 1) == "F"
		local cornerMass = cfg.mass * (front and cfg.weightFront or 1 - cfg.weightFront) / 2
		local freq = front and s.frequencyFront or s.frequencyRear
		local k = cornerMass * (TAU * freq) ^ 2
		local w = {
			name = name,
			front = front,
			left = name:sub(2, 2) == "L",
			mount = mounts[name],
			cornerMass = cornerMass,
			Fz0 = cornerMass * G,
			k = k,
			c = 2 * s.dampingRatio * sqrt(k * cornerMass),
			radius = cfg.wheelRadius,
			inertia = cfg.tires.wheelInertia,
			driven = driven[name],
			driveShare = share[name],
			brakeShare = front and cfg.brakes.frontBias / 2 or (1 - cfg.brakes.frontBias) / 2,
			omega = 0,
			spin = 0,
			length = s.restLength - cornerMass * G / k,
			comp = 0,
			grounded = false,
			steer = 0,
			kappa = 0,
			alpha = 0,
			Fz = 0,
			absCut = 0,
		}
		self.wheels[name] = w
		table.insert(self.wheels, w)
	end

	self.gear = 1
	self.rpm = cfg.engine.idleRPM
	self.shiftTimer = 0
	self.sinceShift = 0
	self.auto = true
	self.tcsOn = cfg.assists.tcs
	self.absOn = cfg.assists.abs
	self.tcsCut = 0
	self.steer = 0
	self.steerAngle = 0
	self.coupled = false
	self.parked = false
	self.input = { throttle = 0, brake = 0, steer = 0, handbrake = 0, analog = false }
	self.telemetry = { speed = 0, rpm = self.rpm, gear = 1, tcsActive = false, absActive = false }
	return self
end

function Sim:ratio(gear)
	local tr = self.cfg.transmission
	if gear == -1 then
		return -tr.reverse
	elseif gear == 0 then
		return 0
	end
	return tr.gears[gear]
end

function Sim:shift(gear)
	gear = clamp(gear, -1, #self.cfg.transmission.gears)
	if gear ~= self.gear then
		self.gear = gear
		self.shiftTimer = self.cfg.transmission.shiftTime
		self.sinceShift = 0
	end
end

function Sim:shiftUp()
	self:shift(self.gear + 1)
end

function Sim:shiftDown()
	self:shift(self.gear - 1)
end

-- Holds the car still with every brake on (used while nobody is driving).
function Sim:setParked(parked)
	self.parked = parked
	if parked then
		self.auto = false
		self.gear = 0
		self.input = { throttle = 0, brake = 1, steer = 0, handbrake = 1, analog = false }
	end
end

function Sim:step(dt)
	dt = clamp(dt, 1 / 240, 1 / 30)
	local cfg, body, inp = self.cfg, self.body, self.input
	local e, tr, s = cfg.engine, cfg.transmission, cfg.suspension

	local cf = body.getCFrame()
	local up = cf.UpVector
	local look = cf.LookVector
	local massR = body.getMass()
	-- Newtons -> Roblox force units, so the car accelerates like `cfg.mass` kg.
	local K = massR / (cfg.mass * MPS)
	local vel = body.getVelocity() * MPS
	local speed = vel.Magnitude
	local vForward = vel:Dot(look)

	-- 6. Real gravity for the car, whatever workspace.Gravity is.
	body.impulse(Vector3.new(0, massR * (body.getGravity() - G / MPS) * dt, 0))

	-- Pedals. In automatic, holding brake at a stop selects reverse.
	local throttle, brake = inp.throttle, inp.brake
	if self.auto then
		if self.gear >= 1 and inp.brake > 0.1 and inp.throttle < 0.05 and vForward < 0.6 then
			self:shift(-1)
		elseif self.gear == -1 and inp.throttle > 0.1 and inp.brake < 0.05 and vForward > -0.6 then
			self:shift(1)
		elseif self.gear == 0 then
			self:shift(1)
		end
		if self.gear == -1 then
			throttle, brake = inp.brake, inp.throttle
		end
	end

	-- Steering: speed-sensitive lock with Ackermann geometry.
	if inp.analog then
		self.steer = inp.steer
	else
		local returning = inp.steer == 0 or inp.steer * self.steer < 0
		self.steer = moveTowards(self.steer, inp.steer, (returning and 5 or 2.6) * dt)
	end
	local maxAngle = math.rad(cfg.steering.maxAngle) / (1 + cfg.steering.speedFactor * max(vForward, 0))
	local steerAngle = -self.steer * maxAngle -- positive = left
	self.steerAngle = steerAngle
	local track = cfg.trackWidth
	if abs(steerAngle) > 1e-4 then
		local R = cfg.wheelbase / math.tan(abs(steerAngle))
		local inner = math.atan(cfg.wheelbase / (R - track / 2)) * sign(steerAngle)
		local outer = math.atan(cfg.wheelbase / (R + track / 2)) * sign(steerAngle)
		local leftInner = steerAngle > 0
		self.wheels.FL.steer = leftInner and inner or outer
		self.wheels.FR.steer = leftInner and outer or inner
	else
		self.wheels.FL.steer, self.wheels.FR.steer = 0, 0
	end

	-- 2. Drivetrain.
	local ratio = self:ratio(self.gear)
	local totalRatio = ratio * tr.finalDrive
	local wheelOmega = 0
	for _, w in ipairs(self.wheels) do
		wheelOmega += w.omega * w.driveShare
	end
	local clutchRPM = wheelOmega * totalRatio / RADS_PER_RPM
	self.shiftTimer = max(0, self.shiftTimer - dt)
	self.sinceShift += dt

	local thr = throttle * (1 - self.tcsCut)
	local engineTorque = 0
	self.coupled = false
	if ratio == 0 or self.shiftTimer > 0 then
		local target = e.idleRPM + thr * (e.redline - e.idleRPM)
		self.rpm = moveTowards(self.rpm, target, (target > self.rpm and 9000 or 5000) * dt)
	else
		local slipTarget = e.idleRPM + thr * (e.launchRPM - e.idleRPM)
		if clutchRPM < slipTarget then
			-- Clutch / torque converter slipping: engine held near slipTarget.
			self.rpm = moveTowards(self.rpm, slipTarget, 8000 * dt)
			engineTorque = torqueAt(e.torque, self.rpm) * thr
			if self.auto and thr < 0.05 and brake < 0.05 then
				engineTorque = e.creepTorque
			end
		else
			self.coupled = true
			self.rpm = clutchRPM
			if self.rpm >= e.maxRPM then
				thr = 0 -- rev limiter
			end
			engineTorque = torqueAt(e.torque, self.rpm) * thr - e.engineBrake * (1 - thr) * (self.rpm / e.maxRPM)
		end
	end

	-- Automatic gear changes.
	if self.auto and self.gear >= 1 and self.shiftTimer == 0 and self.sinceShift > 0.6 then
		local gears = tr.gears
		if self.rpm > e.redline - 250 and self.gear < #gears and self.coupled then
			self:shift(self.gear + 1)
		elseif self.gear > 1 then
			local lowerRPM = clutchRPM * gears[self.gear - 1] / gears[self.gear]
			local downAt = e.idleRPM + (0.22 + 0.45 * throttle) * (e.redline - e.idleRPM)
			if self.rpm < downAt and lowerRPM < e.redline - 900 then
				self:shift(self.gear - 1)
			end
		end
	end

	local axleTorque = engineTorque * totalRatio * tr.efficiency
	local reflectedInertia = self.coupled and e.inertia * totalRatio * totalRatio or 0

	-- 1. Suspension.
	local wheels = self.wheels
	for _, w in ipairs(wheels) do
		local origin = cf:PointToWorldSpace(w.mount)
		w.origin = origin
		local hit = body.raycast(origin, -up * ((s.restLength + w.radius) / MPS))
		if hit then
			local springLen = (hit.Position - origin).Magnitude * MPS - w.radius
			local minLen = s.restLength - s.travel
			w.bump = max(0, minLen - springLen)
			w.length = max(springLen, minLen)
			w.comp = s.restLength - w.length
			w.grounded = true
			w.hitPos = hit.Position
			w.normal = hit.Normal
		else
			w.grounded = false
			w.comp = 0
			w.bump = 0
			w.length = moveTowards(w.length, s.restLength, dt * 2)
		end
	end
	local function antiRoll(l, r, stiffness)
		local f = stiffness * (l.comp - r.comp)
		l.arb = l.grounded and f or 0
		r.arb = r.grounded and -f or 0
	end
	antiRoll(wheels.FL, wheels.FR, s.antiRollFront)
	antiRoll(wheels.RL, wheels.RR, s.antiRollRear)

	local maxSlip, absActive = 0, false
	local tp = self.tire
	local hb = inp.handbrake
	local brakeTorque = cfg.brakes.maxTorque * brake

	for _, w in ipairs(wheels) do
		local r = w.radius
		local I = w.inertia + reflectedInertia * w.driveShare
		local Tdrive = axleTorque * w.driveShare
		if w.driven and tr.lsd > 0 then
			local other = wheels[(w.front and "F" or "R") .. (w.left and "R" or "L")]
			Tdrive += tr.lsd * (other.omega - w.omega) * 0.5
		end
		local Tb = brakeTorque * w.brakeShare * (1 - w.absCut)
		if not w.front then
			Tb += cfg.brakes.handbrakeTorque * 0.5 * hb
		end

		if not w.grounded then
			w.Fz = 0
			w.omega += Tdrive / I * dt
			w.omega *= 1 - min(1, 0.4 * dt)
			local stop = Tb * dt / I
			w.omega = abs(w.omega) <= stop and 0 or w.omega - sign(w.omega) * stop
		else
			-- Spring + damper + anti-roll + bump stop, pushing the body up.
			local compVel = -(body.velocityAt(w.origin) * MPS):Dot(up)
			local Fs = w.k * w.comp + w.c * compVel + w.arb + w.k * 8 * w.bump
			Fs = clamp(Fs, 0, w.Fz0 * 8)
			w.Fz = Fs
			body.impulseAt(up * (Fs * K * dt), w.origin)

			-- Tire frame on the road surface.
			local n = w.normal
			local a = w.steer
			local fwd = cf:VectorToWorldSpace(Vector3.new(-math.sin(a), 0, -math.cos(a)))
			fwd = fwd - n * fwd:Dot(n)
			if fwd.Magnitude > 1e-3 then
				fwd = fwd.Unit
				local right = fwd:Cross(n)
				local vC = body.velocityAt(w.hitPos) * MPS
				local vx, vy = vC:Dot(fwd), vC:Dot(right)
				local denom = max(abs(vx), LOW_SPEED)
				local alpha = math.atan(vy / denom)

				-- 3. Wheel spin, linearised implicit step against tire force.
				local function fx(om)
					local Fx = Tire.forces((om * r - vx) / denom, alpha, Fs, w.Fz0, tp)
					return Fx
				end
				local F0 = fx(w.omega)
				local dF = (fx(w.omega + 0.05) - F0) / 0.05
				w.omega += (Tdrive - r * F0) / (I / dt + r * max(dF, 0))
				local stop = Tb * dt / I
				w.omega = abs(w.omega) <= stop and 0 or w.omega - sign(w.omega) * stop

				-- 4. Tire forces with the new wheel speed.
				local kappa = (w.omega * r - vx) / denom
				local Fx, Fy = Tire.forces(kappa, alpha, Fs, w.Fz0, tp)
				Fx -= sign(vx) * tp.rollingResistance * Fs * min(1, abs(vx) / 0.5)
				-- Never push the contact patch past the wheel's own surface speed
				-- (or sideways past zero) in a single frame.
				local slipV = w.omega * r - vx
				if Fx * slipV > 0 then
					local lim = w.cornerMass * abs(slipV) / dt
					Fx = clamp(Fx, -lim, lim)
				elseif slipV == 0 then
					Fx = 0
				end
				local limY = w.cornerMass * abs(vy) / dt
				Fy = clamp(Fy, -limY, limY)

				w.kappa, w.alpha, w.vx = kappa, alpha, vx
				local point = w.hitPos + up * (s.rollCenterHeight / MPS)
				body.impulseAt((fwd * Fx + right * Fy) * (K * dt), point)

				-- ABS releases a wheel that starts to lock.
				if self.absOn and brake > 0.05 and kappa < -0.12 and abs(vx) > 2 then
					w.absCut = moveTowards(w.absCut, 0.75, dt * 25)
					absActive = true
				else
					w.absCut = moveTowards(w.absCut, 0, dt * 12)
				end
				if w.driven and abs(vx) < 60 then
					maxSlip = max(maxSlip, kappa * sign(totalRatio))
				end
			end
		end
		w.spin = (w.spin + w.omega * dt) % TAU
	end

	-- Traction control trims the throttle when the driven wheels spin up.
	if self.tcsOn and maxSlip > 0.14 then
		self.tcsCut = moveTowards(self.tcsCut, 0.85, dt * 6)
	else
		self.tcsCut = moveTowards(self.tcsCut, 0, dt * 2.5)
	end

	-- 5. Aerodynamics.
	if speed > 0.5 then
		local q = 0.5 * AIR_DENSITY * speed * speed
		local ae = cfg.aero
		local force = vel.Unit * (-q * ae.cd * ae.area) - up * (q * ae.downforce * ae.area)
		body.impulse(force * (K * dt))
	end

	local t = self.telemetry
	t.speed = speed
	t.forward = vForward
	t.rpm = self.rpm
	t.gear = self.gear
	t.tcsActive = self.tcsCut > 0.05
	t.absActive = absActive
	t.throttle = throttle
	t.brake = brake
	return t
end

-- Positions the visual wheels (Motor6D.Transform) from the simulated state.
function Sim:updateVisuals(motors)
	for _, w in ipairs(self.wheels) do
		local m = motors[w.name]
		if m then
			m.Transform = CFrame.new(0, -w.length / MPS, 0) * CFrame.Angles(0, w.steer, 0) * CFrame.Angles(-w.spin, 0, 0)
		end
	end
end

-------------------------------------------------------------------------------
-- Roblox bindings
-------------------------------------------------------------------------------

function Sim.getMounts(model)
	local chassis = model:FindFirstChild("Chassis")
	local mounts = {}
	for _, name in ipairs({ "FL", "FR", "RL", "RR" }) do
		mounts[name] = chassis:FindFirstChild("Mount" .. name).Position
	end
	return mounts
end

function Sim.getMotors(model)
	local motors = {}
	for _, name in ipairs({ "FL", "FR", "RL", "RR" }) do
		local tire = model:FindFirstChild("Wheel" .. name, true)
		motors[name] = tire and tire:FindFirstChild("Motor")
	end
	return motors
end

function Sim.makeRaycastParams(model)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = false
	local list = { model }
	for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
		if plr.Character then
			table.insert(list, plr.Character)
		end
	end
	params.FilterDescendantsInstances = list
	return params
end

function Sim.fromModel(model, cfg)
	local root = model:FindFirstChild("Chassis")
	local params = Sim.makeRaycastParams(model)
	local lastRefresh = os.clock()
	local body = {
		getCFrame = function()
			return root.CFrame
		end,
		getVelocity = function()
			return root.AssemblyLinearVelocity
		end,
		velocityAt = function(p)
			return root:GetVelocityAtPosition(p)
		end,
		getMass = function()
			return root.AssemblyMass
		end,
		getGravity = function()
			return workspace.Gravity
		end,
		impulse = function(j)
			root:ApplyImpulse(j)
		end,
		impulseAt = function(j, p)
			root:ApplyImpulseAtPosition(j, p)
		end,
		raycast = function(origin, dir)
			if os.clock() - lastRefresh > 1 then
				lastRefresh = os.clock()
				params = Sim.makeRaycastParams(model)
			end
			return workspace:Raycast(origin, dir, params)
		end,
	}
	local sim = Sim.new(body, cfg, Sim.getMounts(model))
	sim.model = model
	sim.root = root
	sim.motors = Sim.getMotors(model)
	return sim
end

return Sim
