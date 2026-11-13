--[[
	Car geometry shared by the builder and the simulation.

	Car space: origin on the ground, midway between the axles, centered left to
	right. -Z is forward (Roblox LookVector), +X is right, +Y is up.
]]

local Configs = require(script.Parent.Configs)
local MPS = Configs.METERS_PER_STUD

local Layout = {}

function Layout.compute(cfg)
	local b = cfg.body
	local wb = cfg.wheelbase
	local r = cfg.wheelRadius
	local s = cfg.suspension
	local G = 9.81

	local L = {}
	L.frontZ = -(wb / 2 + b.frontOverhang) -- front bumper (m)
	L.rearZ = L.frontZ + b.length -- rear bumper (m)
	-- distance from the front bumper -> car-space z
	L.z = function(fromFront)
		return L.frontZ + fromFront
	end

	-- Centre of mass: weight distribution sets how far it sits behind the front axle.
	L.com = Vector3.new(0, cfg.comHeight, -wb / 2 + wb * (1 - cfg.weightFront))

	local function sag(freq)
		return G / (2 * math.pi * freq) ^ 2
	end
	local track = cfg.trackWidth
	L.wheels = {}
	for _, name in ipairs({ "FL", "FR", "RL", "RR" }) do
		local front = name:sub(1, 1) == "F"
		local x = (name:sub(2, 2) == "L" and -1 or 1) * track / 2
		local z = front and -wb / 2 or wb / 2
		local mountY = r + s.restLength - sag(front and s.frequencyFront or s.frequencyRear)
		local mount = Vector3.new(x, mountY, z)
		L.wheels[name] = {
			mount = mount, -- car space, meters
			mountLocal = (mount - L.com) / MPS, -- relative to the chassis root, studs
			rest = Vector3.new(x, r, z), -- wheel centre at static ride height
		}
	end

	-- The invisible root part carries all the mass. Its size sets the car's
	-- moments of inertia, so it is car-sized rather than physically realistic.
	L.ballastSize = Vector3.new(b.width * 1.2, 0.6, b.length * 0.9) / MPS
	return L
end

return Layout
