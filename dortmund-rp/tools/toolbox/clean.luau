-- lune run clean.luau <in.rbxm> <out.rbxm> <out.json>
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local root = roblox.deserializeModel(fs.readFile(process.args[1]))[1]

-- wheels: Wheels.FL/FR/RL/RR (part or model) or parts named "FL Wheel" ...
local wheelSets: { [string]: { any } } = {}
for _, d in root:GetDescendants() do
	local key = nil
	if (d.Name == "FL" or d.Name == "FR" or d.Name == "RL" or d.Name == "RR") and d.Parent and d.Parent.Name == "Wheels" then
		key = d.Name
	elseif d:IsA("BasePart") and d.Name:match("^[FR][LR] Wheel$") then
		key = d.Name:sub(1, 2)
	end
	if key and not wheelSets[key] then
		local parts = {}
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
		for _, p in d:GetDescendants() do
			if p:IsA("BasePart") then
				table.insert(parts, p)
			end
		end
		wheelSets[key] = parts
	end
end
local wheel = {}
local inWheel: { [any]: boolean } = {}
for key, parts in wheelSets do
	-- centre = middle of the bounding box of all visible wheel parts (tyres are often
	-- split into pieces, so one part's centre is not the axle); radius = the biggest
	-- part's largest size / 2, at most half the box height
	local lo, hi = nil, nil
	local r = 0
	for _, p in parts do
		inWheel[p] = true
		if p.Transparency < 0.98 then
			local cf, h = p.CFrame, p.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local c = cf * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
						lo = if lo then Vector3.new(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z)) else c
						hi = if hi then Vector3.new(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z)) else c
					end
				end
			end
			r = math.max(r, math.max(p.Size.X, p.Size.Y, p.Size.Z) / 2)
		end
	end
	if lo and hi then
		wheel[key] = { pos = (lo + hi) / 2, r = math.min(r, (hi.Y - lo.Y) / 2) }
	end
end
assert(wheel.FL and wheel.FR and wheel.RL and wheel.RR, "wheels not found")

-- trucks with two rear axles: RL and RR can come from different axles. Then RR is
-- RL turned around the car's centre line, and the other axle stays on the body
-- (it doesn't turn, but it is where it belongs).
do
	local lat = (wheel.FR.pos - wheel.FL.pos) * Vector3.new(1, 0, 1)
	lat = lat.Unit
	local along = Vector3.new(-lat.Z, 0, lat.X)
	if math.abs((wheel.RL.pos - wheel.RR.pos):Dot(along)) > 1 then
		local c = (wheel.FL.pos + wheel.FR.pos) / 2
		local d = (wheel.RL.pos - c):Dot(lat)
		local P = wheel.RL.pos - lat * d
		local turn = CFrame.new(P) * CFrame.Angles(0, math.pi, 0) * CFrame.new(-P)
		for _, p in wheelSets.RR do
			inWheel[p] = nil
		end
		local mirrored = {}
		for _, p in wheelSets.RL do
			local q = p:Clone()
			for _, ch in q:GetChildren() do
				if not ch:IsA("SpecialMesh") and not ch:IsA("SurfaceAppearance") then
					ch:Destroy()
				end
			end
			q.CFrame = turn * p.CFrame
			table.insert(mirrored, q)
		end
		wheelSets.RR = mirrored
		wheel.RR = { pos = turn * wheel.RL.pos, r = wheel.RL.r }
		print("rear axles differ: RR mirrored from RL")
	end
end

local front = (wheel.FL.pos + wheel.FR.pos) / 2
local rear = (wheel.RL.pos + wheel.RR.pos) / 2
local fwd = (front - rear) * Vector3.new(1, 0, 1)
fwd = fwd.Unit
local origin = (front + rear) / 2
local frame = CFrame.lookAt(origin, origin + fwd)
local inv = frame:Inverse()

local car = roblox.Instance.new("Model")
car.Name = "Car"
local DROP_NAME = { "logo", "badge", "emblem", "hitbox", "collision", "seat" }
local KEEP_CHILD = { SpecialMesh = true, SurfaceAppearance = true }
local kept, removed = 0, 0
local function dropName(n: string): boolean
	n = n:lower()
	for _, w in DROP_NAME do
		if n:find(w, 1, true) then
			return true
		end
	end
	return false
end
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then
		if inWheel[d] or d.Transparency >= 0.98 or dropName(d.Name) or d:IsA("VehicleSeat") or d:IsA("Seat") then
			removed += 1
			continue
		end
		local p = d:Clone()
		for _, c in p:GetChildren() do
			if not KEEP_CHILD[c.ClassName] then
				c:Destroy()
			end
		end
		p.CFrame = inv * d.CFrame
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.Parent = car
		kept += 1
	end
end

-- the car's own wheels: one model per corner (WheelFL ...) inside Car, same frame.
-- The game welds each one to its physics wheel so it turns and steers with it.
local wheelParts = 0
for key, parts in wheelSets do
	local wm = roblox.Instance.new("Model")
	wm.Name = "Wheel" .. key
	for _, d in parts do
		if d.Transparency >= 0.98 or dropName(d.Name) then
			continue
		end
		local p = d:Clone()
		for _, c in p:GetChildren() do
			if not KEEP_CHILD[c.ClassName] then
				c:Destroy()
			end
		end
		p.CFrame = inv * d.CFrame
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.Parent = wm
		wheelParts += 1
	end
	if #wm:GetChildren() > 0 then
		wm.Parent = car
	end
end

-- paint: the colour with the biggest surface (not glass / neon / see-through / dark trim)
local area: { [string]: number } = {}
local function key(c)
	return string.format("%d,%d,%d", math.floor(c.R * 20 + 0.5), math.floor(c.G * 20 + 0.5), math.floor(c.B * 20 + 0.5))
end
local function skipPaint(p)
	local n = p.Name:lower()
	return p.Transparency > 0.2
		or p.Material == roblox.Enum.Material.Glass
		or p.Material == roblox.Enum.Material.Neon
		or n:find("interior") or n:find("glass") or n:find("light") or n:find("lamp")
		or n:find("engine") or n:find("chas") or n:find("window")
end
for _, p in car:GetChildren() do
	if p:IsA("BasePart") and not skipPaint(p) then
		local s = p.Size
		local lum = 0.3 * p.Color.R + 0.59 * p.Color.G + 0.11 * p.Color.B
		if lum > 0.06 then
			local k = key(p.Color)
			area[k] = (area[k] or 0) + 2 * (s.X * s.Y + s.Y * s.Z + s.X * s.Z)
		end
	end
end
local paintKey, best = nil, 0
for k, a in area do
	if a > best then
		paintKey, best = k, a
	end
end
local painted = 0
for _, p in car:GetChildren() do
	if p:IsA("BasePart") and paintKey and not skipPaint(p) and key(p.Color) == paintKey then
		p:SetAttribute("Paint", true)
		painted += 1
	end
end

-- bounding box (local)
local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
for _, p in car:GetChildren() do
	if not p:IsA("BasePart") then
		continue
	end
	local cf, s = p.CFrame, p.Size / 2
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local w = cf * Vector3.new(sx * s.X, sy * s.Y, sz * s.Z)
				minV = Vector3.new(math.min(minV.X, w.X), math.min(minV.Y, w.Y), math.min(minV.Z, w.Z))
				maxV = Vector3.new(math.max(maxV.X, w.X), math.max(maxV.Y, w.Y), math.max(maxV.Z, w.Z))
			end
		end
	end
end
local function lw(k)
	local v = inv * wheel[k].pos
	return { v.X, v.Y, v.Z, wheel[k].r }
end
local holder = roblox.Instance.new("Model")
holder.Name = "CleanedBody"
car.Parent = holder
fs.writeFile(process.args[2], roblox.serializeModel({ holder }))
fs.writeFile(process.args[3], serde.encode("json", {
	name = root.Name,
	parts = kept,
	removed = removed,
	painted = painted,
	paint = paintKey,
	min = { minV.X, minV.Y, minV.Z },
	max = { maxV.X, maxV.Y, maxV.Z },
	wheels = { FL = lw("FL"), FR = lw("FR"), RL = lw("RL"), RR = lw("RR") },
}))
print(("%s: %d parts kept, %d dropped, %d painted, %d wheel parts, length %.1f"):format(root.Name, kept, removed, painted, wheelParts, maxV.Z - minV.Z))
