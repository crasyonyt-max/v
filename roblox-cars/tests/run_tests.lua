-- Drives every car on a flat virtual test track with a simple rigid-body
-- integrator (Roblox-like: 240 Hz physics, 60 Hz scripts, default gravity)
-- and reports performance plus stability checks.

local M = require("./mocks")
local Vector3, CFrame = M.Vector3, M.CFrame
local Configs = require("./Configs")
local Layout = require("./Layout")
local Sim = require("./Sim")

local MPS = Configs.METERS_PER_STUD
local GRAVITY = 196.2 -- Roblox default, the sim must correct it itself
local FRAME = 1 / 60
local SUB = 4

local function orthonormalize(m)
	local c1 = Vector3.new(m[1], m[4], m[7]).Unit
	local c2 = Vector3.new(m[2], m[5], m[8])
	c2 = (c2 - c1 * c1:Dot(c2)).Unit
	local c3 = c1:Cross(c2)
	return { c1.X, c2.X, c3.X, c1.Y, c2.Y, c3.Y, c1.Z, c2.Z, c3.Z }
end

local function rotate(m, w, dt)
	local ang = w.Magnitude * dt
	if ang < 1e-12 then
		return m
	end
	local a = w.Unit
	local c, s = math.cos(ang), math.sin(ang)
	local t = 1 - c
	local x, y, z = a.X, a.Y, a.Z
	local r = {
		t * x * x + c, t * x * y - s * z, t * x * z + s * y,
		t * x * y + s * z, t * y * y + c, t * y * z - s * x,
		t * x * z - s * y, t * y * z + s * x, t * z * z + c,
	}
	local o = {}
	for i = 0, 2 do
		for j = 0, 2 do
			local sum = 0
			for k = 0, 2 do
				sum += r[i * 3 + k + 1] * m[k * 3 + j + 1]
			end
			o[i * 3 + j + 1] = sum
		end
	end
	return orthonormalize(o)
end

local function newWorld(cfg)
	local L = Layout.compute(cfg)
	local st = {
		p = Vector3.new(0, L.com.Y / MPS, 0),
		v = Vector3.new(0, 0, 0),
		w = Vector3.new(0, 0, 0),
		m = { 1, 0, 0, 0, 1, 0, 0, 0, 1 },
		M = 480, -- arbitrary Roblox mass units; the sim must not care
		minClear = math.huge,
		nan = false,
	}
	local sz = L.ballastSize
	local Ib = {
		st.M * (sz.Y ^ 2 + sz.Z ^ 2) / 12,
		st.M * (sz.X ^ 2 + sz.Z ^ 2) / 12,
		st.M * (sz.X ^ 2 + sz.Y ^ 2) / 12,
	}
	local queue = {}
	local function cf()
		return CFrame.fromMatrix(st.p, st.m)
	end
	local function iinv(vec)
		local c = cf()
		local l = c:VectorToObjectSpace(vec)
		return c:VectorToWorldSpace(Vector3.new(l.X / Ib[1], l.Y / Ib[2], l.Z / Ib[3]))
	end
	local body = {
		getCFrame = cf,
		getVelocity = function()
			return st.v
		end,
		velocityAt = function(p)
			return st.v + st.w:Cross(p - st.p)
		end,
		getMass = function()
			return st.M
		end,
		getGravity = function()
			return GRAVITY
		end,
		impulse = function(j)
			table.insert(queue, { j, nil })
		end,
		impulseAt = function(j, p)
			table.insert(queue, { j, p })
		end,
		raycast = function(o, d)
			if d.Y < 0 and o.Y > 0 then
				local t = o.Y / -d.Y
				if t <= 1 then
					return { Position = o + d * t, Normal = Vector3.new(0, 1, 0) }
				end
			end
			return nil
		end,
	}
	local mounts = {}
	for name, w in pairs(L.wheels) do
		mounts[name] = w.mountLocal
	end
	-- lowest point of the collision hitbox, relative to the root
	local b = cfg.body
	local hbY = (b.clearance + 0.1 - L.com.Y) / MPS
	local corners = {}
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz2 in ipairs({ -1, 1 }) do
			local z = sz2 < 0 and L.frontZ or L.rearZ
			table.insert(corners, Vector3.new(sx * b.width / 2 / MPS, hbY, (z - L.com.Z) / MPS))
		end
	end

	local world = { st = st, body = body, mounts = mounts, L = L }
	function world.physics()
		for _, q in ipairs(queue) do
			st.v += q[1] / st.M
			if q[2] then
				st.w += iinv((q[2] - st.p):Cross(q[1]))
			end
		end
		table.clear(queue)
		local dt = FRAME / SUB
		for _ = 1, SUB do
			st.v += Vector3.new(0, -GRAVITY * dt, 0)
			st.p += st.v * dt
			st.m = rotate(st.m, st.w, dt)
		end
		local c = cf()
		for _, k in ipairs(corners) do
			st.minClear = math.min(st.minClear, c:PointToWorldSpace(k).Y * MPS)
		end
		if st.p.X ~= st.p.X or st.v.Magnitude > 1e5 then
			st.nan = true
		end
	end
	return world
end

local function newSim(world, cfg)
	return Sim.new(world.body, cfg, world.mounts)
end

local function settle(world, cfg, seconds)
	local sim = newSim(world, cfg)
	sim:setParked(true)
	for _ = 1, math.floor(seconds / FRAME) do
		sim:step(FRAME)
		world.physics()
	end
	return sim
end

local function run(world, sim, seconds, inputFn, stopFn)
	local t = 0
	while t < seconds do
		inputFn(sim, t)
		local tel = sim:step(FRAME)
		world.physics()
		t += FRAME
		if world.st.nan then
			return t, "NaN"
		end
		if stopFn and stopFn(tel, t) then
			return t
		end
	end
	return t
end

local function fmt(n, d)
	return string.format("%." .. (d or 1) .. "f", n)
end

local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("    FAIL: " .. msg)
	end
end

local KMH = 3.6
print(string.format("%-10s %7s %8s %8s %8s %8s %7s %7s", "car", "ride(m)", "0-100", "1/4mi", "top", "100-0", "lat g", "roll"))
for _, key in ipairs(Configs.Order) do
	local cfg = Configs.Cars[key]

	-- 1. Settle on the suspension while parked.
	local world = newWorld(cfg)
	local sim = settle(world, cfg, 3)
	local st = world.st
	local rideErr = st.p.Y * MPS - cfg.comHeight
	check(math.abs(rideErr) < 0.03, key .. " ride height off by " .. fmt(rideErr, 3) .. " m")
	check(st.v.Magnitude * MPS < 0.05, key .. " parked car drifting at " .. fmt(st.v.Magnitude * MPS, 3) .. " m/s")

	-- 2. Standing start, full throttle, automatic.
	sim = newSim(world, cfg)
	local t100, tQuarter, top = nil, nil, 0
	local startZ = st.p.Z
	run(world, sim, 70, function(s, t)
		s.input.throttle = 1
	end, function(tel, t)
		top = math.max(top, tel.speed)
		if not t100 and tel.speed >= 100 / KMH then
			t100 = t
		end
		if not tQuarter and (startZ - st.p.Z) * MPS >= 402 then
			tQuarter = t
		end
		return false
	end)
	check(t100 ~= nil, key .. " never reached 100 km/h")
	check(math.abs(st.p.X * MPS) < 3, key .. " drifted sideways " .. fmt(st.p.X * MPS) .. " m on a straight launch")

	-- 3. Braking from 100 km/h.
	world = newWorld(cfg)
	settle(world, cfg, 1.5)
	sim = newSim(world, cfg)
	local v0 = 100 / KMH
	st = world.st
	st.v = Vector3.new(0, 0, -v0 / MPS)
	for _, w in ipairs(sim.wheels) do
		w.omega = v0 / w.radius
	end
	sim.gear = 4
	local z0 = st.p.Z
	run(world, sim, 15, function(s)
		s.input.brake = 1
		s.auto = false -- stay in gear, no reverse
	end, function(tel)
		return tel.speed < 0.3
	end)
	local brakeDist = (z0 - st.p.Z) * MPS
	check(brakeDist > 25 and brakeDist < 50, key .. " 100-0 braking distance " .. fmt(brakeDist) .. " m")
	check(math.abs(st.p.X * MPS) < 1.5, key .. " pulled " .. fmt(st.p.X * MPS) .. " m sideways under braking")

	-- 4. Steady cornering at 70 km/h with a fixed steering input.
	world = newWorld(cfg)
	settle(world, cfg, 1.5)
	sim = newSim(world, cfg)
	st = world.st
	local vc = 70 / KMH
	st.v = Vector3.new(0, 0, -vc / MPS)
	for _, w in ipairs(sim.wheels) do
		w.omega = vc / w.radius
	end
	sim.gear = 3
	local maxLat, maxRoll, flipped = 0, 0, false
	local err = run(world, sim, 8, function(s, t)
		s.input.analog = true
		s.input.steer = math.min(1, t / 1.5) * 0.9
		-- hold speed roughly constant
		s.input.throttle = s.telemetry.speed < vc and 0.6 or 0.15
	end, function(tel, t)
		local c = world.body.getCFrame()
		if c.UpVector.Y < 0.7 then
			flipped = true
			return true
		end
		if t > 3 then
			local v = st.v * MPS
			local lat = (st.w.Y * v.Magnitude) / 9.81 -- centripetal acceleration
			maxLat = math.max(maxLat, math.abs(lat))
			maxRoll = math.max(maxRoll, math.deg(math.asin(math.abs(c.RightVector.Y))))
		end
		return false
	end)
	check(err ~= "NaN", key .. " NaN while cornering")
	check(not flipped, key .. " rolled over while cornering")
	check(maxLat > 0.5, key .. " only " .. fmt(maxLat, 2) .. " g cornering")
	check(maxLat < 1.6, key .. " unrealistic " .. fmt(maxLat, 2) .. " g cornering")
	check(st.minClear > -0.02, key .. " body scraped the ground (" .. fmt(st.minClear, 3) .. " m)")

	print(string.format("%-10s %7s %7ss %7ss %5skm/h %7sm %6sg %6s°",
		key, fmt(rideErr, 3), t100 and fmt(t100) or "-", tQuarter and fmt(tQuarter) or "-",
		fmt(top * KMH, 0), fmt(brakeDist), fmt(maxLat, 2), fmt(maxRoll)))
end

print(failures == 0 and "\nAll checks passed." or ("\n" .. failures .. " check(s) failed."))
