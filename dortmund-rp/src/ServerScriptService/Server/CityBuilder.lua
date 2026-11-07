--!strict
-- Builds real Dortmund from ServerStorage.CityData (generated from OpenStreetMap by
-- tools/osm_convert.py): buildings at their real footprint and height, every street
-- at its real width, pavements, centre lines, zebra crossings, tram/rail tracks,
-- parks, water, parking, trees and street lights. 1 stud = 0.28 m.
-- Map data © OpenStreetMap contributors (ODbL).

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Meta = require(ServerStorage.CityMeta)

local CityBuilder = {}

local M = 1 / 0.28 -- studs per metre

-- surface heights (top of each layer)
local Y_GROUND = 0
local Y_AREA = 0.08
local Y_PLAZA = 0.12
local Y_WALK = 0.18
local Y_ROAD = 0.22
local Y_LINE = 0.235

local ASPHALT = Color3.fromRGB(62, 64, 68)
local PAVEMENT = Color3.fromRGB(168, 164, 156)
local PLAZA = Color3.fromRGB(186, 178, 164)
local LINE = Color3.fromRGB(236, 236, 230)

local AREA_STYLE: { [number]: { Color3 | Enum.Material } } = {
	[1] = { Color3.fromRGB(86, 128, 62), Enum.Material.Grass }, -- park / grass
	[2] = { Color3.fromRGB(74, 108, 52), Enum.Material.LeafyGrass }, -- scrub / allotments
	[3] = { Color3.fromRGB(56, 92, 46), Enum.Material.LeafyGrass }, -- wood
	[4] = { Color3.fromRGB(70, 130, 70), Enum.Material.Grass }, -- sports pitch
	[5] = { PLAZA, Enum.Material.Pavement }, -- pedestrian zone
	[6] = { Color3.fromRGB(52, 92, 120), Enum.Material.Glass }, -- water
	[7] = { Color3.fromRGB(78, 80, 84), Enum.Material.Asphalt }, -- parking
}

local count = 0
local function yieldSometimes()
	count += 1
	if count % 1500 == 0 then
		task.wait()
	end
end

local function newPart(class: string, parent: Instance, color: Color3, material: Enum.Material): BasePart
	local p = Instance.new(class) :: BasePart
	p.Anchored = true
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.Parent = parent
	yieldSometimes()
	return p
end

-- Right-triangle prism: right angle at d, legs to p1 and p2 (Vector2 = x, z).
local function rightPrism(
	parent: Instance,
	d: Vector2,
	p1: Vector2,
	p2: Vector2,
	base: number,
	h: number,
	color: Color3,
	material: Enum.Material,
	collide: boolean
)
	local a = (p1 - d).Magnitude
	local b = (p2 - d).Magnitude
	if a < 0.05 or b < 0.05 then
		return
	end
	-- WedgePart: right angle at local (-Y, +Z); its -Z leg goes to p1, +Y leg to p2.
	local z = Vector3.new(d.X - p1.X, 0, d.Y - p1.Y).Unit
	local y = Vector3.new(p2.X - d.X, 0, p2.Y - d.Y).Unit
	local x = y:Cross(z)
	local c = d + (p1 - d) / 2 + (p2 - d) / 2
	local w = newPart("WedgePart", parent, color, material)
	w.Size = Vector3.new(h, b, a)
	w.CFrame = CFrame.fromMatrix(Vector3.new(c.X, base + h / 2, c.Y), x, y, z)
	w.CanCollide = collide
end

-- Any triangle as a vertical prism from `base` to `base + h` (two wedges).
local function triPrism(
	parent: Instance,
	a: Vector2,
	b: Vector2,
	c: Vector2,
	base: number,
	h: number,
	color: Color3,
	material: Enum.Material,
	collide: boolean
)
	local ab, bc, ca = (b - a).Magnitude, (c - b).Magnitude, (a - c).Magnitude
	-- make AB the longest edge
	if bc >= ab and bc >= ca then
		a, b, c = b, c, a
	elseif ca >= ab and ca >= bc then
		a, b, c = c, a, b
	end
	local e = b - a
	local len2 = e:Dot(e)
	if len2 < 0.01 then
		return
	end
	local t = (c - a):Dot(e) / len2
	local foot = a + e * t
	rightPrism(parent, foot, a, c, base, h, color, material, collide)
	rightPrism(parent, foot, b, c, base, h, color, material, collide)
end

local function strip(
	parent: Instance,
	from: Vector2,
	to: Vector2,
	width: number,
	top: number,
	thickness: number,
	color: Color3,
	material: Enum.Material,
	collide: boolean
): BasePart?
	local delta = to - from
	local len = delta.Magnitude
	if len < 0.05 then
		return nil
	end
	local mid = (from + to) / 2
	local p = newPart("Part", parent, color, material)
	p.Size = Vector3.new(width, thickness, len)
	local pos = Vector3.new(mid.X, top - thickness / 2, mid.Y)
	p.CFrame = CFrame.lookAt(pos, pos + Vector3.new(delta.X, 0, delta.Y))
	p.CanCollide = collide
	return p
end

local function disc(
	parent: Instance,
	at: Vector2,
	diameter: number,
	top: number,
	color: Color3,
	material: Enum.Material
)
	local p = newPart("Part", parent, color, material)
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.4, diameter, diameter)
	p.CFrame = CFrame.new(at.X, top - 0.2, at.Y) * CFrame.Angles(0, 0, math.pi / 2)
end

local function points(row: { number }, from: number): { Vector2 }
	local out = {}
	for i = from, #row - 1, 2 do
		table.insert(out, Vector2.new(row[i], row[i + 1]))
	end
	return out
end

-- Buildings ------------------------------------------------------------------
local palette: { Color3 } = {}
for i, c in Meta.palette do
	palette[i] = Color3.fromRGB(c[1], c[2], c[3])
end
local brick: { [number]: boolean } = {}
for _, i in Meta.brick do
	brick[i] = true
end

local function buildBuilding(parent: Instance, row: { number })
	local kind, base, h, col = row[1], row[2], row[3], row[4] + 1
	local color = palette[col] or palette[1]
	local material = if brick[col] then Enum.Material.Brick else Enum.Material.Concrete
	if kind == 1 then
		local p = newPart("Part", parent, color, material)
		p.Size = Vector3.new(row[7], h, row[8])
		p.CFrame = CFrame.new(row[5], base + h / 2, row[6]) * CFrame.Angles(0, -math.rad(row[9]), 0)
		-- dark flat roof cap
		local roof = newPart("Part", parent, Color3.fromRGB(84, 82, 80), Enum.Material.Slate)
		roof.Size = Vector3.new(row[7] - 0.6, 0.3, row[8] - 0.6)
		roof.CFrame = p.CFrame * CFrame.new(0, h / 2 + 0.15, 0)
		roof.CanCollide = false
	else
		local pts = points(row, 5)
		for i = 1, #pts - 2, 3 do
			triPrism(parent, pts[i], pts[i + 1], pts[i + 2], base, h, color, material, true)
		end
	end
end

-- Roads ------------------------------------------------------------------------
local MAIN = { primary = true, secondary = true, tertiary = true, trunk = true, motorway = true }

local function buildRoad(folders: { [string]: Instance }, row: { number }, lamps: { Vector3 })
	local typeName = Meta.roadTypes[row[1]]
	local kind = Meta.roadKinds[row[1]]
	local width, oneway, crossing = row[2], row[3] == 1, row[4] == 1
	local pts = points(row, 5)
	if kind == 1 then
		local walk = if typeName == "service" then 0 else 2.6 * M
		for i = 1, #pts - 1 do
			-- pavement band under the road (covered by the asphalt in the middle)
			if walk > 0 then
				strip(
					folders.walk,
					pts[i],
					pts[i + 1],
					width + walk * 2,
					Y_WALK,
					0.3,
					PAVEMENT,
					Enum.Material.Pavement,
					true
				)
			end
			strip(folders.road, pts[i], pts[i + 1], width, Y_ROAD, 0.3, ASPHALT, Enum.Material.Asphalt, true)
		end
		for i = 2, #pts - 1 do
			disc(folders.road, pts[i], width, Y_ROAD, ASPHALT, Enum.Material.Asphalt)
		end
		-- dashed centre line on bigger two-way roads (German: 3 m dash, 6 m gap)
		if MAIN[typeName] and not oneway and width > 7 * M then
			local carry = 0
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local seg = (b - a).Magnitude
				local dir = (b - a).Unit
				local s = carry
				while s < seg do
					local e = math.min(s + 3 * M, seg)
					strip(
						folders.lines,
						a + dir * s,
						a + dir * e,
						0.12 * M,
						Y_LINE,
						0.05,
						LINE,
						Enum.Material.SmoothPlastic,
						false
					)
					s += 9 * M
				end
				carry = s - seg
			end
		end
		-- street lights along main and residential roads, every 32 m, alternating sides
		if typeName ~= "service" then
			local acc = 0
			local side = 1
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local seg = (b - a).Magnitude
				local dir = (b - a).Unit
				local normal = Vector2.new(-dir.Y, dir.X)
				local s = 32 * M - acc
				while s < seg do
					local p = a + dir * s + normal * side * (width / 2 + 0.8 * M)
					table.insert(lamps, Vector3.new(p.X, p.Y, side)) -- (x, z, side)
					side = -side
					s += 32 * M
				end
				acc = (acc + seg) % (32 * M)
			end
		end
	elseif kind == 3 then
		for i = 1, #pts - 1 do
			strip(folders.walk, pts[i], pts[i + 1], width, Y_PLAZA, 0.3, PLAZA, Enum.Material.Pavement, true)
		end
	else
		local color = if typeName == "cycleway" then Color3.fromRGB(150, 82, 74) else PAVEMENT
		local top = if crossing then Y_LINE + 0.005 else Y_WALK
		for i = 1, #pts - 1 do
			if crossing then
				-- zebra crossing: white stripes across the road
				local a, b = pts[i], pts[i + 1]
				local seg = (b - a).Magnitude
				local dir = (b - a).Unit
				local s = 0.25 * M
				while s < seg do
					local c = a + dir * s
					local normal = Vector2.new(-dir.Y, dir.X)
					strip(
						folders.lines,
						c - normal * 1.5 * M,
						c + normal * 1.5 * M,
						0.5 * M,
						top,
						0.05,
						LINE,
						Enum.Material.SmoothPlastic,
						false
					)
					s += 1 * M
				end
			else
				strip(folders.walk, pts[i], pts[i + 1], width, top, 0.3, color, Enum.Material.Pavement, true)
			end
		end
	end
end

local function buildRail(parent: Instance, row: { number })
	local isRail = row[1] == 1
	local pts = points(row, 2)
	local gauge = 1.435 * M
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dir = (b - a).Unit
		local normal = Vector2.new(-dir.Y, dir.X)
		if isRail then
			strip(parent, a, b, 3.2 * M, Y_ROAD - 0.02, 0.3, Color3.fromRGB(96, 90, 84), Enum.Material.Pebble, true)
		end
		for _, side in { -1, 1 } do
			local o = normal * side * gauge / 2
			strip(
				parent,
				a + o,
				b + o,
				0.25,
				Y_ROAD + 0.12,
				0.3,
				Color3.fromRGB(120, 116, 110),
				Enum.Material.Metal,
				false
			)
		end
	end
end

local function buildArea(parent: Instance, row: { number })
	local style = AREA_STYLE[row[1]] or AREA_STYLE[1]
	local top = if row[1] == 5 then Y_PLAZA elseif row[1] == 7 then Y_AREA + 0.02 else Y_AREA
	local pts = points(row, 2)
	for i = 1, #pts - 2, 3 do
		triPrism(
			parent,
			pts[i],
			pts[i + 1],
			pts[i + 2],
			top - 0.3,
			0.3,
			style[1] :: Color3,
			style[2] :: Enum.Material,
			false
		)
	end
end

local function buildTree(parent: Instance, x: number, z: number, rng: Random)
	local height = rng:NextNumber(7, 12) * M
	local trunk = newPart("Part", parent, Color3.fromRGB(88, 66, 48), Enum.Material.Wood)
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Size = Vector3.new(height * 0.55, 0.35 * M, 0.35 * M)
	trunk.CFrame = CFrame.new(x, height * 0.275, z) * CFrame.Angles(0, 0, math.pi / 2)
	local crown = newPart(
		"Part",
		parent,
		Color3.fromRGB(58 + rng:NextInteger(0, 20), 96 + rng:NextInteger(0, 25), 46),
		Enum.Material.LeafyGrass
	)
	crown.Shape = Enum.PartType.Ball
	local d = height * rng:NextNumber(0.5, 0.65)
	crown.Size = Vector3.new(d, d, d)
	crown.CFrame = CFrame.new(x, height * 0.7, z)
	crown.CanCollide = false
	crown.CastShadow = true
end

local function buildLamp(parent: Instance, x: number, z: number, side: number)
	local pole = newPart("Part", parent, Color3.fromRGB(70, 74, 78), Enum.Material.Metal)
	pole.Size = Vector3.new(0.5, 8 * M, 0.5)
	pole.Position = Vector3.new(x, 4 * M, z)
	local lamp = newPart("Part", parent, Color3.fromRGB(230, 225, 210), Enum.Material.SmoothPlastic)
	lamp.Name = "Lamp"
	lamp.Size = Vector3.new(1.6, 0.5, 2.2)
	lamp.Position = Vector3.new(x, 8 * M, z)
	lamp.CanCollide = false
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Range = 16 * M
	light.Angle = 120
	light.Brightness = 1.6
	light.Color = Color3.fromRGB(255, 214, 160)
	light.Shadows = false
	light.Enabled = false
	light.Parent = lamp
	CollectionService:AddTag(lamp, "StreetLamp")
	local _ = side
end

CityBuilder._triPrism = triPrism -- exposed for tests

-- Main -----------------------------------------------------------------------------
function CityBuilder.Build(bounds: { number }): Folder
	local city = Instance.new("Folder")
	city.Name = "City"
	city.Parent = Workspace

	local function folder(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = city
		return f
	end
	local folders = {
		ground = folder("Ground"),
		buildings = folder("Buildings"),
		road = folder("Roads"),
		walk = folder("Pavements"),
		lines = folder("Markings"),
		areas = folder("Areas"),
		rail = folder("Tracks"),
		trees = folder("Trees"),
		lights = folder("StreetLights"),
	}

	-- ground plate (max part size is 2048)
	local minX, minZ, maxX, maxZ = bounds[1] - 400, bounds[2] - 400, bounds[3] + 400, bounds[4] + 400
	local TILE = 2000
	local x = minX
	while x < maxX do
		local z = minZ
		while z < maxZ do
			local sx, sz = math.min(TILE, maxX - x), math.min(TILE, maxZ - z)
			local g = newPart("Part", folders.ground, Color3.fromRGB(132, 128, 120), Enum.Material.Concrete)
			g.Size = Vector3.new(sx, 2, sz)
			g.Position = Vector3.new(x + sx / 2, Y_GROUND - 1, z + sz / 2)
			z += TILE
		end
		x += TILE
	end

	local rng = Random.new(51517)
	local lamps: { Vector3 } = {}
	local chunks = ServerStorage:WaitForChild("CityData"):GetChildren()
	table.sort(chunks, function(a, b)
		return a.Name < b.Name
	end)
	for _, module in chunks do
		if module:IsA("ModuleScript") then
			local data = require(module) :: any
			for _, row in data.a do
				buildArea(folders.areas, row)
			end
			for _, row in data.r do
				buildRoad(folders, row, lamps)
			end
			for _, row in data.rail do
				buildRail(folders.rail, row)
			end
			for _, row in data.b do
				buildBuilding(folders.buildings, row)
			end
			for _, t in data.t do
				buildTree(folders.trees, t[1], t[2], rng)
			end
		end
	end
	for _, l in lamps do
		buildLamp(folders.lights, l.X, l.Y, l.Z)
	end
	print(string.format("[City] built %d parts", count))
	return city
end

-- Highest walkable surface at (x, z), for placing markers and spawns.
function CityBuilder.GroundY(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local city = Workspace:FindFirstChild("City")
	if not city then
		return 0.5
	end
	params.FilterDescendantsInstances = { city.Ground, city.Roads, city.Pavements, city.Areas }
	local hit = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0), params)
	return if hit then hit.Position.Y else 0.5
end

return CityBuilder
