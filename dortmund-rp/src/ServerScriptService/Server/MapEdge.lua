--!strict
-- The end of the map (Config.Dunes, "test" = testing server first): instead of the flat
-- baseplate, sand dunes (terrain) all around the playable area – low at the city edge,
-- higher further out so they hide what lies behind – and an invisible wall at their
-- outer edge so nobody gets past them.
-- Playable area = Locations.Bounds plus Locations.Annex (the port on the bigger map).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local MapEdge = {}

MapEdge.MARGIN = 450 -- studs of dunes around the playable area
MapEdge.CELL = 60 -- dune grid
MapEdge.WALL_H = 1200

type Rect = { number } -- minX, minZ, maxX, maxZ

-- how far a point is outside the playable area (0 = inside)
function MapEdge.Outside(rects: { Rect }, x: number, z: number): number
	local best = math.huge
	for _, r in rects do
		local dx = math.max(r[1] - x, 0, x - r[3])
		local dz = math.max(r[2] - z, 0, z - r[4])
		best = math.min(best, math.sqrt(dx * dx + dz * dz))
	end
	return best
end

-- dune top height at a point `d` studs outside the city (smooth, a bit wavy)
function MapEdge.DuneHeight(d: number, x: number, z: number): number
	if d <= 0 then
		return 0
	end
	local t = math.clamp(d / MapEdge.MARGIN, 0, 1)
	local wave = math.noise(x / 140, z / 140, 7.3) * 0.5 + math.noise(x / 55, z / 55, 1.1) * 0.25
	return math.max(0.5, t ^ 1.4 * 70 + wave * 18 * t + 2)
end

-- the outer outline of the dune belt as wall segments: { {a: Vector2, b: Vector2} }
-- (edges of the grid cells inside the belt that border cells outside it)
function MapEdge.WallSegments(rects: { Rect }): { { Vector2 } }
	local C, M = MapEdge.CELL, MapEdge.MARGIN
	local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
	for _, r in rects do
		x0, z0 = math.min(x0, r[1] - M), math.min(z0, r[2] - M)
		x1, z1 = math.max(x1, r[3] + M), math.max(z1, r[4] + M)
	end
	local nx, nz = math.ceil((x1 - x0) / C), math.ceil((z1 - z0) / C)
	local function inside(i: number, j: number): boolean
		if i < 0 or j < 0 or i >= nx or j >= nz then
			return false
		end
		return MapEdge.Outside(rects, x0 + (i + 0.5) * C, z0 + (j + 0.5) * C) <= M
	end
	local segs: { { Vector2 } } = {}
	-- horizontal edges (along X), merged per row
	for j = 0, nz do
		for side = 0, 1 do
			local start: number? = nil
			for i = 0, nx do
				local edge = i < nx
					and (
						if side == 0
							then inside(i, j) and not inside(i, j - 1)
							else inside(i, j - 1) and not inside(i, j)
					)
				if edge and not start then
					start = i
				elseif not edge and start then
					local z = z0 + j * C
					table.insert(segs, { Vector2.new(x0 + start * C, z), Vector2.new(x0 + i * C, z) })
					start = nil
				end
			end
		end
	end
	-- vertical edges (along Z), merged per column
	for i = 0, nx do
		for side = 0, 1 do
			local start: number? = nil
			for j = 0, nz do
				local edge = j < nz
					and (
						if side == 0
							then inside(i, j) and not inside(i - 1, j)
							else inside(i - 1, j) and not inside(i, j)
					)
				if edge and not start then
					start = j
				elseif not edge and start then
					local x = x0 + i * C
					table.insert(segs, { Vector2.new(x, z0 + start * C), Vector2.new(x, z0 + j * C) })
					start = nil
				end
			end
		end
	end
	return segs
end

-- What the dunes are made of (pure, so it can be tested):
--   floor = { {x, z, size} } sand squares, never reaching into the playable area
--   balls = { {x, z, top, radius} } dune tops, their foot never reaching it either
function MapEdge.Plan(rects: { Rect }): { floor: { { number } }, balls: { { number } } }
	local C, M = MapEdge.CELL, MapEdge.MARGIN
	local floor, balls = {}, {}
	local seen: { [string]: boolean } = {}
	local function outsideSquare(cx: number, cz: number, size: number): boolean
		local h = size / 2
		-- a square is clear of every rect when it lies fully on one side of it
		for _, r in rects do
			if cx + h > r[1] and cx - h < r[3] and cz + h > r[2] and cz - h < r[4] then
				return false
			end
		end
		return true
	end
	for _, r in rects do
		local x = r[1] - M
		while x < r[3] + M do
			local z = r[2] - M
			while z < r[4] + M do
				local cx, cz = x + C / 2, z + C / 2
				local key = ("%d,%d"):format(math.floor(cx / C), math.floor(cz / C))
				local d = MapEdge.Outside(rects, cx, cz)
				if not seen[key] and d > 0 and d <= M then
					seen[key] = true
					if outsideSquare(cx, cz, C + 2) then
						table.insert(floor, { cx, cz, C + 2 })
					else
						-- next to the city: small squares, only those fully outside it
						local q = C / 4
						for i = 0, 3 do
							for j = 0, 3 do
								local sx, sz = x + (i + 0.5) * q, z + (j + 0.5) * q
								if outsideSquare(sx, sz, q) then
									table.insert(floor, { sx, sz, q })
								end
							end
						end
					end
					local h = MapEdge.DuneHeight(d, cx, cz)
					local rad = C * 0.75 + h * 0.6
					-- the dune's foot (its circle at ground level) stays out of the city
					local foot = math.sqrt(math.max(0, 2 * rad * h - h * h))
					if foot < d - 4 then
						table.insert(balls, { cx, cz, h, rad })
					end
				end
				z += C
			end
			x += C
		end
	end
	return { floor = floor, balls = balls }
end

function MapEdge.Build(bounds: Rect, extra: { Rect }?): Folder?
	if not Config.On(Config.Dunes) then
		return nil
	end
	local rects: { Rect } = { bounds }
	for _, a in extra or {} do
		table.insert(rects, a)
	end
	local folder = Instance.new("Folder")
	folder.Name = "MapEdge"
	folder.Parent = Workspace

	-- invisible wall along the outside of the dune belt
	local walls = 0
	for _, seg in MapEdge.WallSegments(rects) do
		local a, b = seg[1], seg[2]
		local len = (b - a).Magnitude
		if len > 0 then
			local mid = (a + b) / 2
			local w = Instance.new("Part")
			w.Name = "EdgeWall"
			w.Anchored = true
			w.CanCollide = true
			w.CanQuery = false
			w.CanTouch = false
			w.Transparency = 1
			w.CastShadow = false
			local along = Vector3.new(b.X - a.X, 0, b.Y - a.Y).Unit
			w.Size = Vector3.new(4, MapEdge.WALL_H, len + 4)
			w.CFrame = CFrame.lookAt(
				Vector3.new(mid.X, MapEdge.WALL_H / 2 - 20, mid.Y),
				Vector3.new(mid.X, MapEdge.WALL_H / 2 - 20, mid.Y) + along
			)
			w.Parent = folder
			walls += 1
		end
	end
	folder:SetAttribute("Walls", walls)

	-- city pieces that reach far out (long rail lines, canals, roads past the edge):
	-- whatever lies beyond the dune crest goes, the rest just runs into the sand
	local city = Workspace:FindFirstChild("City")
	local cut = 0
	for _, p in (if city then city:GetDescendants() else {}) do
		if p:IsA("BasePart") and p.Parent and p.Parent.Name ~= "Ground" then
			local pos = p.CFrame.Position
			if MapEdge.Outside(rects, pos.X, pos.Z) > MapEdge.MARGIN - 60 then
				p:Destroy()
				cut += 1
			end
		end
	end
	folder:SetAttribute("CutOff", cut)

	-- the dunes (terrain): a sand floor on the whole belt and round dune tops on it
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local ok, err = pcall(function()
			local plan = MapEdge.Plan(rects)
			local n = 0
			for _, f in plan.floor do
				-- (top a little above the baseplate, so the sand covers it)
				terrain:FillBlock(CFrame.new(f[1], -1.2, f[2]), Vector3.new(f[3], 3, f[3]), Enum.Material.Sand)
				n += 1
				if n % 400 == 0 then
					task.wait()
				end
			end
			for _, b in plan.balls do
				terrain:FillBall(Vector3.new(b[1], b[3] - b[4], b[2]), b[4], Enum.Material.Sand)
				n += 1
				if n % 400 == 0 then
					task.wait()
				end
			end
			folder:SetAttribute("Dunes", #plan.balls)
		end)
		if not ok then
			warn("[MapEdge] dunes failed: " .. tostring(err))
		end
	end
	return folder
end

return MapEdge
