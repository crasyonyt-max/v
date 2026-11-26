--!strict
-- The Stadthafen (Dortmund port) as a closed construction site, on the bigger map
-- (Config.BigMap: LocationsXL.Port = the fenced area; the port's quays, water and roads
-- come from the map data, its buildings were left out except the Altes Hafenamt).
--   * a construction fence all around (it really blocks: people and cars stay out),
--     "UNDER CONSTRUCTION" signs on it and a locked main gate at the Hafen stop
--   * inside: tower cranes, sand and gravel piles, earthworks, excavators, a dump truck,
--     site containers, steel beams, concrete pipes, pallets, cones, floodlights

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Locations = require(ReplicatedStorage.Shared.Locations)

local PortBuilder = {}

local YELLOW = Color3.fromRGB(245, 190, 20)
local DARK = Color3.fromRGB(40, 40, 44)
local GREY = Color3.fromRGB(150, 152, 156)
local SAND = Color3.fromRGB(214, 186, 130)
local GRAVEL = Color3.fromRGB(128, 126, 120)
local DIRT = Color3.fromRGB(120, 92, 64)
local RED = Color3.fromRGB(205, 30, 30)
local WHITE = Color3.fromRGB(240, 240, 240)

local SIGN_TEXT = "⚠ UNDER CONSTRUCTION ⚠"
local SIGN_SUB = "Hafen Dortmund · Baustelle – Betreten verboten"

type Opts = { [string]: any }

local function box(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	opts: Opts?
): BasePart
	local p = Instance.new(opts and opts.class or "Part") :: BasePart
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts then
		for k, v in opts do
			if k ~= "class" then
				(p :: any)[k] = v
			end
		end
	end
	p.Parent = parent
	return p
end

-- a beam between two points (lattice members, cables)
local function beam(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	thick: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	local len = (b - a).Magnitude
	return box(
		parent,
		"Beam",
		Vector3.new(thick, thick, len),
		CFrame.lookAt((a + b) / 2, b),
		color,
		material or Enum.Material.Metal
	)
end

local function sign(parent: Instance, cf: CFrame, w: number, h: number): BasePart
	local p = box(parent, "Sign", Vector3.new(w, h, 0.3), cf, YELLOW, Enum.Material.SmoothPlastic)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.Parent = p
		local list = Instance.new("UIListLayout")
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Parent = gui
		local title = Instance.new("TextLabel")
		title.Size = UDim2.fromScale(0.95, 0.6)
		title.BackgroundTransparency = 1
		title.TextScaled = true
		title.Font = Enum.Font.GothamBlack
		title.TextColor3 = Color3.new(0, 0, 0)
		title.Text = SIGN_TEXT
		title.Parent = gui
		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.fromScale(0.95, 0.3)
		sub.BackgroundTransparency = 1
		sub.TextScaled = true
		sub.Font = Enum.Font.GothamBold
		sub.TextColor3 = Color3.new(0, 0, 0)
		sub.Text = SIGN_SUB
		sub.Parent = gui
	end
	-- black and yellow edge
	box(parent, "SignFrame", Vector3.new(w + 0.6, 0.4, 0.4), cf * CFrame.new(0, h / 2 + 0.2, 0), DARK)
	box(parent, "SignFrame", Vector3.new(w + 0.6, 0.4, 0.4), cf * CFrame.new(0, -h / 2 - 0.2, 0), DARK)
	return p
end

-- Fence ---------------------------------------------------------------------------------

local FENCE_H = 12
local PANEL = 30

-- one side of the fence from a to b (ground points), posts + mesh + feet, signs
local function fenceSide(parent: Instance, a: Vector3, b: Vector3, signEvery: number): number
	local dir = (b - a)
	local len = dir.Magnitude
	local u = dir.Unit
	local n = math.max(1, math.ceil(len / PANEL))
	local seg = len / n
	local signs = 0
	for i = 0, n - 1 do
		local p0 = a + u * (seg * i)
		local mid = p0 + u * (seg / 2)
		local cf = CFrame.lookAt(mid, mid + u) * CFrame.Angles(0, math.pi / 2, 0) -- local X along the fence
		box(
			parent,
			"FenceMesh",
			Vector3.new(seg, FENCE_H - 1, 0.4),
			cf * CFrame.new(0, (FENCE_H - 1) / 2 + 0.6, 0),
			GREY,
			Enum.Material.Metal,
			{
				Transparency = 0.55,
			}
		)
		box(parent, "FenceRail", Vector3.new(seg, 0.4, 0.5), cf * CFrame.new(0, FENCE_H, 0), GREY, Enum.Material.Metal)
		box(
			parent,
			"FencePost",
			Vector3.new(0.6, FENCE_H + 0.6, 0.6),
			CFrame.new(p0 + Vector3.new(0, (FENCE_H + 0.6) / 2, 0)),
			GREY,
			Enum.Material.Metal
		)
		box(
			parent,
			"FenceFoot",
			Vector3.new(1.6, 0.8, 3),
			CFrame.lookAt(p0, p0 + u) * CFrame.new(0, 0.4, 0),
			Color3.fromRGB(110, 110, 112),
			Enum.Material.Concrete
		)
		-- privacy banner on the lower half, a sign every few panels
		box(
			parent,
			"FenceBanner",
			Vector3.new(seg - 0.8, 4, 0.2),
			cf * CFrame.new(0, 2.6, 0.25),
			Color3.fromRGB(30, 90, 60),
			Enum.Material.Fabric,
			{
				CanCollide = false,
			}
		)
		if i % signEvery == math.floor(signEvery / 2) then
			sign(parent, cf * CFrame.new(0, 7.5, 0.5), 14, 4.4)
			signs += 1
		end
	end
	return signs
end

-- Equipment ------------------------------------------------------------------------------

local function towerCrane(parent: Instance, base: Vector3, yaw: number, height: number, jib: number)
	local m = Instance.new("Model")
	m.Name = "TowerCrane"
	m.Parent = parent
	local rot = CFrame.new(base) * CFrame.Angles(0, yaw, 0)
	local half = 2.2
	box(
		m,
		"Foundation",
		Vector3.new(9, 2, 9),
		rot * CFrame.new(0, 1, 0),
		Color3.fromRGB(120, 120, 118),
		Enum.Material.Concrete
	)
	-- lattice mast: four corner posts and zig-zag braces on every side
	local corners = {
		Vector3.new(-half, 0, -half),
		Vector3.new(half, 0, -half),
		Vector3.new(half, 0, half),
		Vector3.new(-half, 0, half),
	}
	for _, c in corners do
		beam(
			m,
			(rot * CFrame.new(c + Vector3.new(0, 2, 0))).Position,
			(rot * CFrame.new(c + Vector3.new(0, height, 0))).Position,
			0.5,
			YELLOW
		)
	end
	local step = 5
	local y = 2
	local flip = false
	while y + step <= height do
		for k = 1, 4 do
			local c1, c2 = corners[k], corners[k % 4 + 1]
			local lo = if flip then c1 else c2
			local hi = if flip then c2 else c1
			beam(
				m,
				(rot * CFrame.new(lo + Vector3.new(0, y, 0))).Position,
				(rot * CFrame.new(hi + Vector3.new(0, y + step, 0))).Position,
				0.25,
				YELLOW
			)
		end
		flip = not flip
		y += step
	end
	-- slewing ring, cab, tower top
	local top = height
	box(m, "Slewing", Vector3.new(6, 1.6, 6), rot * CFrame.new(0, top + 0.8, 0), DARK, Enum.Material.Metal)
	local cab = box(
		m,
		"Cab",
		Vector3.new(3.4, 3, 3.6),
		rot * CFrame.new(half + 1.6, top + 3, -2.5),
		WHITE,
		Enum.Material.SmoothPlastic
	)
	box(
		m,
		"CabGlass",
		Vector3.new(3.5, 1.8, 0.2),
		cab.CFrame * CFrame.new(0, 0.3, -1.85),
		Color3.fromRGB(80, 120, 150),
		Enum.Material.Glass,
		{
			Transparency = 0.3,
		}
	)
	box(m, "Peak", Vector3.new(2, 9, 2), rot * CFrame.new(0, top + 6, 0), YELLOW, Enum.Material.Metal)
	-- jib (front, -Z) as a triangular truss, counter jib (+Z) with weights
	local jy = top + 2
	local function at(x: number, yy: number, z: number): Vector3
		return (rot * CFrame.new(x, yy, z)).Position
	end
	local w = 1.3
	beam(m, at(-w, jy, 0), at(-w, jy, -jib), 0.35, YELLOW)
	beam(m, at(w, jy, 0), at(w, jy, -jib), 0.35, YELLOW)
	beam(m, at(0, jy + 2.4, 0), at(0, jy + 2.4, -jib + 2), 0.35, YELLOW)
	local zz = 0
	while zz < jib - 4 do
		beam(m, at(-w, jy, -zz), at(0, jy + 2.4, -zz - 4), 0.2, YELLOW)
		beam(m, at(w, jy, -zz), at(0, jy + 2.4, -zz - 4), 0.2, YELLOW)
		zz += 4
	end
	local cj = jib * 0.32
	box(m, "CounterJib", Vector3.new(2.6, 0.8, cj), rot * CFrame.new(0, jy, cj / 2), YELLOW, Enum.Material.Metal)
	box(
		m,
		"Counterweight",
		Vector3.new(3.2, 3.4, 4),
		rot * CFrame.new(0, jy - 1.6, cj - 2.5),
		Color3.fromRGB(130, 130, 128),
		Enum.Material.Concrete
	)
	beam(m, at(0, top + 10.5, 0), at(0, jy + 2.4, -jib + 2), 0.12, DARK)
	beam(m, at(0, top + 10.5, 0), at(0, jy, cj), 0.12, DARK)
	-- trolley, cable and hook with a load of beams
	local tz = -jib * (0.45 + 0.3 * ((yaw * 7) % 1))
	box(m, "Trolley", Vector3.new(2.4, 0.8, 2), rot * CFrame.new(0, jy - 0.6, tz), DARK, Enum.Material.Metal)
	local hookY = math.max(8, top * 0.45)
	beam(m, at(0, jy - 1, tz), at(0, hookY + 1, tz), 0.12, DARK)
	box(m, "Hook", Vector3.new(1, 1.4, 1), rot * CFrame.new(0, hookY, tz), RED, Enum.Material.Metal)
	for k = -1, 1 do
		box(
			m,
			"LoadBeam",
			Vector3.new(0.6, 0.6, 10),
			rot * CFrame.new(k * 0.7, hookY - 2.4, tz) * CFrame.Angles(0, math.rad(30), 0),
			Color3.fromRGB(90, 60, 40),
			Enum.Material.Metal
		)
	end
	local light =
		box(m, "Warning", Vector3.new(0.6, 0.6, 0.6), rot * CFrame.new(0, top + 11, 0), RED, Enum.Material.Neon, {
			Shape = Enum.PartType.Ball,
		})
	local pl = Instance.new("PointLight")
	pl.Color = RED
	pl.Range = 10
	pl.Parent = light
end

-- a pile from stacked discs (sand / gravel), collides like a hill
local function pile(parent: Instance, pos: Vector3, r: number, h: number, color: Color3, material: Enum.Material)
	local layers = 4
	for i = 0, layers - 1 do
		local rr = r * (1 - i / layers) ^ 0.9
		local lh = h / layers
		box(
			parent,
			"Pile",
			Vector3.new(lh, rr * 2, rr * 2),
			CFrame.new(pos + Vector3.new(0, lh * (i + 0.5), 0)) * CFrame.Angles(0, 0, math.pi / 2),
			color,
			material,
			{
				Shape = Enum.PartType.Cylinder,
			}
		)
	end
end

local function excavator(parent: Instance, base: CFrame)
	local m = Instance.new("Model")
	m.Name = "Excavator"
	m.Parent = parent
	for _, s in { -1, 1 } do
		box(m, "Track", Vector3.new(2, 2, 10), base * CFrame.new(s * 3.2, 1, 0), DARK, Enum.Material.DiamondPlate)
	end
	box(m, "Turntable", Vector3.new(5, 1, 5), base * CFrame.new(0, 2.5, 0), DARK, Enum.Material.Metal)
	box(m, "Body", Vector3.new(7, 3, 7), base * CFrame.new(0, 4.5, 1), YELLOW, Enum.Material.SmoothPlastic)
	local cab =
		box(m, "Cab", Vector3.new(3, 3.6, 3.4), base * CFrame.new(-1.8, 7.8, -1), YELLOW, Enum.Material.SmoothPlastic)
	box(
		m,
		"Glass",
		Vector3.new(2.6, 2.4, 3.5),
		cab.CFrame * CFrame.new(0.2, 0.3, 0),
		Color3.fromRGB(70, 100, 120),
		Enum.Material.Glass,
		{
			Transparency = 0.35,
		}
	)
	local b0 = (base * CFrame.new(1.2, 5.5, -2.5)).Position
	local b1 = (base * CFrame.new(1.2, 11, -9)).Position
	local b2 = (base * CFrame.new(1.2, 3, -13)).Position
	beam(m, b0, b1, 1.4, YELLOW, Enum.Material.SmoothPlastic)
	beam(m, b1, b2, 1.1, YELLOW, Enum.Material.SmoothPlastic)
	box(
		m,
		"Bucket",
		Vector3.new(2.6, 2, 2),
		CFrame.new(b2) * (base - base.Position) * CFrame.new(0, -1, -0.6),
		DARK,
		Enum.Material.Metal
	)
end

local function dumpTruck(parent: Instance, base: CFrame)
	local m = Instance.new("Model")
	m.Name = "DumpTruck"
	m.Parent = parent
	box(
		m,
		"Cab",
		Vector3.new(6, 5, 5),
		base * CFrame.new(0, 4, -7),
		Color3.fromRGB(220, 120, 20),
		Enum.Material.SmoothPlastic
	)
	box(
		m,
		"Windshield",
		Vector3.new(5.4, 2, 0.2),
		base * CFrame.new(0, 5, -9.55),
		Color3.fromRGB(70, 100, 120),
		Enum.Material.Glass
	)
	box(m, "Chassis", Vector3.new(5, 1, 18), base * CFrame.new(0, 1.8, 0), DARK, Enum.Material.Metal)
	box(
		m,
		"Bed",
		Vector3.new(6.4, 3.6, 11),
		base * CFrame.new(0, 4.4, 2.8),
		Color3.fromRGB(200, 110, 20),
		Enum.Material.Metal
	)
	box(m, "Load", Vector3.new(5.6, 1.2, 10), base * CFrame.new(0, 6.6, 2.8), SAND, Enum.Material.Sand)
	for _, z in { -6, 3, 7 } do
		for _, s in { -1, 1 } do
			box(
				m,
				"Wheel",
				Vector3.new(1.4, 3.4, 3.4),
				base * CFrame.new(s * 2.9, 1.7, z),
				DARK,
				Enum.Material.SmoothPlastic,
				{
					Shape = Enum.PartType.Cylinder,
				}
			)
		end
	end
end

local function siteContainer(parent: Instance, base: CFrame, color: Color3, label: string?)
	local c = box(parent, "Container", Vector3.new(8, 8, 20), base * CFrame.new(0, 4, 0), color, Enum.Material.Metal)
	for _, z in { -5, 0, 5 } do
		box(
			parent,
			"ContainerWindow",
			Vector3.new(0.2, 2.4, 3),
			c.CFrame * CFrame.new(-4.05, 0.8, z),
			Color3.fromRGB(70, 100, 120),
			Enum.Material.Glass
		)
	end
	box(
		parent,
		"ContainerDoor",
		Vector3.new(0.2, 6, 2.6),
		c.CFrame * CFrame.new(-4.05, -1, -8.2),
		DARK,
		Enum.Material.Metal
	)
	if label then
		local p = box(
			parent,
			"ContainerSign",
			Vector3.new(0.2, 1.6, 8),
			c.CFrame * CFrame.new(-4.15, 3, 0),
			WHITE,
			Enum.Material.SmoothPlastic
		)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Left
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.Parent = p
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.Text = label
		t.TextColor3 = Color3.fromRGB(20, 60, 140)
		t.Parent = gui
	end
end

local function cone(parent: Instance, pos: Vector3)
	box(
		parent,
		"ConeBase",
		Vector3.new(1.4, 0.2, 1.4),
		CFrame.new(pos + Vector3.new(0, 0.1, 0)),
		Color3.fromRGB(30, 30, 30)
	)
	for i = 0, 2 do
		box(
			parent,
			"Cone",
			Vector3.new(0.7, 1.1 - i * 0.3, 1.1 - i * 0.3),
			CFrame.new(pos + Vector3.new(0, 0.55 + i * 0.7, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			if i == 1 then WHITE else Color3.fromRGB(255, 100, 0),
			nil,
			{
				Shape = Enum.PartType.Cylinder,
			}
		)
	end
end

local function floodlight(parent: Instance, pos: Vector3)
	box(
		parent,
		"LightMast",
		Vector3.new(0.5, 16, 0.5),
		CFrame.new(pos + Vector3.new(0, 8, 0)),
		GREY,
		Enum.Material.Metal
	)
	box(
		parent,
		"LightBase",
		Vector3.new(3, 1, 3),
		CFrame.new(pos + Vector3.new(0, 0.5, 0)),
		YELLOW,
		Enum.Material.Metal
	)
	local lamp = box(
		parent,
		"Floodlight",
		Vector3.new(3, 1.4, 0.6),
		CFrame.new(pos + Vector3.new(0, 16.4, 0)),
		WHITE,
		Enum.Material.Neon
	)
	local l = Instance.new("SpotLight")
	l.Range = 50
	l.Angle = 80
	l.Brightness = 2
	l.Face = Enum.NormalId.Bottom
	l.Parent = lamp
end

-- Build ----------------------------------------------------------------------------------

-- the fenced rectangle (studs): minX, minZ, maxX, maxZ (nil = no port on this map)
function PortBuilder.Rect(): { number }?
	return (Locations :: any).Port
end

function PortBuilder.Build(): Model?
	if not Config.On(Config.BigMap) then
		return nil
	end
	local r = PortBuilder.Rect()
	if not r then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "Hafen Baustelle"
	local fence = Instance.new("Model")
	fence.Name = "Bauzaun"
	fence.Parent = m
	local site = Instance.new("Model")
	site.Name = "Baustelle"
	site.Parent = m

	-- the fence: a closed ring along the rectangle
	local x0, z0, x1, z1 = r[1], r[2], r[3], r[4]
	local corners = { Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1), Vector3.new(x0, 0, z1) }
	local signs = 0
	for i = 1, 4 do
		signs += fenceSide(fence, corners[i], corners[i % 4 + 1], 5)
	end
	m:SetAttribute("Signs", signs)

	-- locked main gate on the city side (south), at the "Dortmund Hafen" stop
	local gx = math.clamp(-3950, x0 + 40, x1 - 40)
	local gate = CFrame.new(gx, 0, z1) * CFrame.Angles(0, 0, 0)
	for _, s in { -1, 1 } do
		box(
			fence,
			"GatePillar",
			Vector3.new(2, 16, 2),
			gate * CFrame.new(s * 16, 8, 0),
			RED,
			Enum.Material.SmoothPlastic
		)
		box(
			fence,
			"GatePillarStripe",
			Vector3.new(2.1, 2, 2.1),
			gate * CFrame.new(s * 16, 12, 0),
			WHITE,
			Enum.Material.SmoothPlastic
		)
	end
	box(fence, "GateBar", Vector3.new(30, 1.2, 1), gate * CFrame.new(0, 5, 1), RED, Enum.Material.SmoothPlastic)
	box(
		fence,
		"GateBarStripe",
		Vector3.new(8, 1.25, 1.05),
		gate * CFrame.new(0, 5, 1),
		WHITE,
		Enum.Material.SmoothPlastic
	)
	box(
		fence,
		"GateChain",
		Vector3.new(0.3, 1.2, 0.3),
		gate * CFrame.new(0, 3.6, 1.4),
		Color3.fromRGB(60, 60, 60),
		Enum.Material.Metal
	)
	local big = sign(fence, gate * CFrame.new(0, 19, 0.6) * CFrame.Angles(0, math.pi, 0), 34, 9)
	big.Name = "GateSign"
	for _, s in { -1, 1 } do
		cone(fence, (gate * CFrame.new(s * 10, 0, 8)).Position)
	end

	-- what stands inside: only on land (not water, not the old harbour office)
	local rng = Random.new(1899) -- the year the port opened
	local function spot(margin: number): Vector3?
		for _ = 1, 30 do
			local x = rng:NextNumber(x0 + margin, x1 - margin)
			local z = rng:NextNumber(z0 + margin, z1 - margin)
			local ok, hit = pcall(function()
				return Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0))
			end)
			if ok and hit then
				local inst = hit.Instance
				local water = inst.Material == Enum.Material.Glass and inst.Color.B > inst.Color.R
				local building = inst.Parent and inst.Parent.Name == "Buildings"
				if not water and not building and hit.Position.Y < 3 and not inst:IsDescendantOf(m) then
					return hit.Position
				end
			end
		end
		return nil
	end
	local placed = 0
	local function place(n: number, margin: number, fn: (Vector3) -> ())
		for _ = 1, n do
			local p = spot(margin)
			if p then
				fn(p)
				placed += 1
			end
		end
	end
	-- earthworks first (so the rest stands on them)
	place(14, 40, function(p)
		box(
			site,
			"Earthworks",
			Vector3.new(rng:NextNumber(50, 110), 0.4, rng:NextNumber(40, 90)),
			CFrame.new(p + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			DIRT,
			Enum.Material.Ground
		)
	end)
	place(7, 60, function(p)
		towerCrane(site, p, rng:NextNumber(0, math.pi * 2), rng:NextNumber(70, 100), rng:NextNumber(50, 75))
	end)
	place(10, 30, function(p)
		pile(site, p, rng:NextNumber(10, 18), rng:NextNumber(6, 11), SAND, Enum.Material.Sand)
	end)
	place(7, 30, function(p)
		pile(site, p, rng:NextNumber(8, 14), rng:NextNumber(5, 8), GRAVEL, Enum.Material.Pebble)
	end)
	place(5, 30, function(p)
		excavator(site, CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	end)
	place(3, 30, function(p)
		dumpTruck(site, CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	end)
	place(4, 30, function(p)
		local cf = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		siteContainer(site, cf, Color3.fromRGB(40, 90, 170), "BAUBÜRO")
		siteContainer(site, cf * CFrame.new(10, 0, 0), WHITE, nil)
		siteContainer(site, cf * CFrame.new(5, 8, 0), Color3.fromRGB(40, 90, 170), nil)
	end)
	place(8, 20, function(p)
		-- steel beams / concrete pipes / brick pallets
		local cf = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		local kind = rng:NextInteger(1, 3)
		if kind == 1 then
			for i = 0, 5 do
				box(
					site,
					"SteelBeam",
					Vector3.new(1, 1.2, 24),
					cf * CFrame.new((i % 3) * 1.3, 0.6 + (i // 3) * 1.2, 0),
					Color3.fromRGB(120, 70, 40),
					Enum.Material.Metal
				)
			end
		elseif kind == 2 then
			for i = 0, 2 do
				box(
					site,
					"ConcretePipe",
					Vector3.new(8, 4, 4),
					cf * CFrame.new(i * 4.2, 2, 0),
					Color3.fromRGB(170, 168, 160),
					Enum.Material.Concrete,
					{
						Shape = Enum.PartType.Cylinder,
					}
				)
			end
		else
			for i = 0, 3 do
				box(
					site,
					"Pallet",
					Vector3.new(4, 0.5, 4),
					cf * CFrame.new(i * 4.6, 0.25, 0),
					Color3.fromRGB(170, 130, 80),
					Enum.Material.Wood
				)
				box(
					site,
					"Bricks",
					Vector3.new(3.6, 3, 3.6),
					cf * CFrame.new(i * 4.6, 2, 0),
					Color3.fromRGB(170, 80, 60),
					Enum.Material.Brick
				)
			end
		end
	end)
	place(18, 15, function(p)
		cone(site, p)
	end)
	place(8, 30, function(p)
		floodlight(site, p)
	end)
	place(4, 20, function(p)
		local cf = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		box(
			site,
			"Toilet",
			Vector3.new(3.4, 7.4, 3.4),
			cf * CFrame.new(0, 3.7, 0),
			Color3.fromRGB(30, 110, 200),
			Enum.Material.SmoothPlastic
		)
	end)
	m:SetAttribute("Placed", placed)
	m.Parent = Workspace
	return m
end

return PortBuilder
