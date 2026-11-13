-- Minimal Vector3 / CFrame / Color3 stand-ins so the simulation runs in the
-- plain Luau CLI, outside Roblox.

local Vector3 = {}
local V = {}
V.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	end
	return V[k]
end
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end
V.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V.__mul = function(a, b)
	if type(a) == "number" then
		return Vector3.new(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b)
	return Vector3.new(a.X / b, a.Y / b, a.Z / b)
end
V.__unm = function(a)
	return Vector3.new(-a.X, -a.Y, -a.Z)
end
function V.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V.Cross(a, b)
	return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end

-- CFrame as position + 3x3 rotation matrix (columns = right, up, back).
local CFrame = {}
local C = {}
C.__index = function(c, k)
	if k == "Position" then
		return c.p
	elseif k == "RightVector" then
		return Vector3.new(c.m[1], c.m[4], c.m[7])
	elseif k == "UpVector" then
		return Vector3.new(c.m[2], c.m[5], c.m[8])
	elseif k == "LookVector" then
		return Vector3.new(-c.m[3], -c.m[6], -c.m[9])
	end
	return C[k]
end
function CFrame.fromMatrix(p, m)
	return setmetatable({ p = p, m = m }, C)
end
function CFrame.new(x, y, z)
	if type(x) == "table" then
		return CFrame.fromMatrix(x, { 1, 0, 0, 0, 1, 0, 0, 0, 1 })
	end
	return CFrame.fromMatrix(Vector3.new(x or 0, y or 0, z or 0), { 1, 0, 0, 0, 1, 0, 0, 0, 1 })
end
function C.VectorToWorldSpace(c, v)
	local m = c.m
	return Vector3.new(
		m[1] * v.X + m[2] * v.Y + m[3] * v.Z,
		m[4] * v.X + m[5] * v.Y + m[6] * v.Z,
		m[7] * v.X + m[8] * v.Y + m[9] * v.Z
	)
end
function C.PointToWorldSpace(c, v)
	return c.p + C.VectorToWorldSpace(c, v)
end
function C.VectorToObjectSpace(c, v)
	local m = c.m
	return Vector3.new(
		m[1] * v.X + m[4] * v.Y + m[7] * v.Z,
		m[2] * v.X + m[5] * v.Y + m[8] * v.Z,
		m[3] * v.X + m[6] * v.Y + m[9] * v.Z
	)
end

local Color3 = {}
function Color3.fromRGB(r, g, b)
	return { R = r / 255, G = g / 255, B = b / 255 }
end

return { Vector3 = Vector3, CFrame = CFrame, Color3 = Color3 }
