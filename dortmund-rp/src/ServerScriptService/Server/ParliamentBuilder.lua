--!strict
-- Parlament: a parliament in the style of the Reichstag building (Bundestag) on the
-- Klinikum grounds south of the city centre. Switch: Config.Parliament ("test" = only
-- on the admin testing server until the owner's OK).
--   * sandstone building with four corner towers, a portico with six columns, pediment
--     and the inscription "DEM DEUTSCHEN VOLKE", glass dome with a mirror funnel
--   * open to everyone: wide stairs and an open main entrance, no doors
--   * inside: entrance hall, plenary hall with blue seats in rows (you can sit),
--     presidium, lectern, federal eagle; flags of the Netherlands, Denmark, Germany,
--     the EU, Belgium and France hang above the presidium
--   * outside only the German and the EU flag (forecourt and towers)
-- The city's buildings, small roads and trees on the site are removed first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CityBuilder = require(script.Parent.CityBuilder)

local ParliamentBuilder = {}

-- site (world): centre, half extents of the cleared area; front (-Z) faces north
ParliamentBuilder.Site = { x = -610, z = 3905, halfX = 270, halfZ = 325 }

local STONE = Color3.fromRGB(205, 192, 165) -- sandstone
local STONE_DARK = Color3.fromRGB(176, 163, 138)
local STONE_LIGHT = Color3.fromRGB(222, 212, 190)
local GLASS = Color3.fromRGB(150, 185, 200)
local WINDOW = Color3.fromRGB(70, 90, 105)
local FLOOR = Color3.fromRGB(226, 222, 212)
local WALL_IN = Color3.fromRGB(238, 238, 234)
local SEAT_BLUE = Color3.fromRGB(62, 82, 168) -- "Reichstagsblau"
local GOLD = Color3.fromRGB(212, 175, 55)
local GRASS = Color3.fromRGB(86, 128, 62)
local PAVING = Color3.fromRGB(190, 186, 176)
local STEEL = Color3.fromRGB(150, 155, 160)

local W, D = 440, 300 -- footprint (x, z)
local FL = 10 -- inside floor height
local ROOF = 96
local T = 6 -- outer wall thickness

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
	local class = opts and opts.class or "Part"
	local p = Instance.new(class) :: BasePart
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

local function text(p: BasePart, face: Enum.NormalId, str: string, color: Color3, bg: Color3?, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 12
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = if bg then 0 else 1
	l.BackgroundColor3 = bg or Color3.new()
	l.TextColor3 = color
	l.TextScaled = true
	l.Font = font or Enum.Font.Garamond
	l.Text = str
	l.Parent = gui
end

-- Flags ------------------------------------------------------------------------------
-- A flag is a thin board in the XY plane of `cf` (hoist at local -X), seen from both
-- sides. Proportions are the real ones; `h` = height.

local FLAGS: { [string]: { ratio: number, stripes: { Color3 }, vertical: boolean? } } = {
	DE = {
		ratio = 5 / 3,
		stripes = { Color3.fromRGB(0, 0, 0), Color3.fromRGB(221, 0, 0), Color3.fromRGB(255, 206, 0) },
	},
	NL = {
		ratio = 3 / 2,
		stripes = { Color3.fromRGB(174, 28, 40), Color3.fromRGB(255, 255, 255), Color3.fromRGB(33, 70, 139) },
	},
	BE = {
		ratio = 15 / 13,
		vertical = true,
		stripes = { Color3.fromRGB(0, 0, 0), Color3.fromRGB(253, 218, 36), Color3.fromRGB(239, 51, 64) },
	},
	FR = {
		ratio = 3 / 2,
		vertical = true,
		stripes = { Color3.fromRGB(0, 35, 149), Color3.fromRGB(255, 255, 255), Color3.fromRGB(237, 41, 57) },
	},
	DK = { ratio = 37 / 28, stripes = { Color3.fromRGB(200, 16, 46) } },
	EU = { ratio = 3 / 2, stripes = { Color3.fromRGB(0, 51, 153) } },
}
ParliamentBuilder.Flags = FLAGS

local function flag(parent: Instance, id: string, cf: CFrame, h: number): Model
	local def = FLAGS[id]
	local m = Instance.new("Model")
	m.Name = "Flag_" .. id
	local w = h * def.ratio
	local th = 0.25
	local n = #def.stripes
	for i, c in def.stripes do
		if def.vertical then
			local sw = w / n
			box(
				m,
				"Stripe",
				Vector3.new(sw, h, th),
				cf * CFrame.new(-w / 2 + sw * (i - 0.5), 0, 0),
				c,
				nil,
				{ CanCollide = false }
			)
		else
			local sh = h / n
			box(
				m,
				"Stripe",
				Vector3.new(w, sh, th),
				cf * CFrame.new(0, h / 2 - sh * (i - 0.5), 0),
				c,
				nil,
				{ CanCollide = false }
			)
		end
	end
	if id == "DK" then
		-- white Nordic cross: bars 4/28 of the height, the upright 12/37 + 2/37 from the hoist
		local bar = h * 4 / 28
		local ux = -w / 2 + w * 14 / 37
		local white = Color3.new(1, 1, 1)
		box(m, "Cross", Vector3.new(w, bar, th + 0.05), cf, white, nil, { CanCollide = false })
		box(m, "Cross", Vector3.new(bar, h, th + 0.05), cf * CFrame.new(ux, 0, 0), white, nil, { CanCollide = false })
	elseif id == "EU" then
		-- twelve golden stars in a circle (radius = a third of the height), both faces
		local board = m:FindFirstChild("Stripe") :: BasePart
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 20
			gui.LightInfluence = 0.3
			gui.Parent = board
			for k = 0, 11 do
				local a = k * math.pi / 6
				local star = Instance.new("TextLabel")
				star.AnchorPoint = Vector2.new(0.5, 0.5)
				star.Position = UDim2.fromScale(0.5 + math.sin(a) * (h / 3) / w, 0.5 - math.cos(a) * 1 / 3)
				star.Size = UDim2.fromScale(h / 9 / w * 1.4, 1 / 9 * 1.4)
				star.BackgroundTransparency = 1
				star.Text = "★"
				star.TextScaled = true
				star.TextColor3 = Color3.fromRGB(255, 204, 0)
				star.Font = Enum.Font.SourceSans
				star.Parent = gui
			end
		end
	end
	m.Parent = parent
	return m
end
ParliamentBuilder.Flag = flag

-- outdoor flagpole with a flag flying from the top (towards local +X)
local function flagpole(parent: Instance, id: string, base: CFrame, height: number, flagH: number)
	box(parent, "FlagpoleBase", Vector3.new(3, 1, 3), base * CFrame.new(0, 0.5, 0), STONE_DARK)
	box(
		parent,
		"Flagpole",
		Vector3.new(height, 0.8, 0.8),
		base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(235, 235, 235),
		Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder }
	)
	box(
		parent,
		"PoleTop",
		Vector3.new(1.4, 1.4, 1.4),
		base * CFrame.new(0, height + 0.5, 0),
		GOLD,
		Enum.Material.Metal,
		{
			Shape = Enum.PartType.Ball,
		}
	)
	local w = flagH * FLAGS[id].ratio
	flag(parent, id, base * CFrame.new(0.4 + w / 2, height - flagH / 2 - 1, 0), flagH)
end

-- Clearing ---------------------------------------------------------------------------

local CLEAR = { "Buildings", "Roads", "Pavements", "Markings", "Areas", "Trees", "StreetLights" }

local function clearSite(origin: CFrame, hx: number, hz: number): number
	local city = Workspace:FindFirstChild("City")
	if not city then
		return 0
	end
	local removed = 0
	for _, name in CLEAR do
		local f = city:FindFirstChild(name)
		for _, p in (if f then f:GetDescendants() else {}) do
			if p:IsA("BasePart") then
				local l = origin:PointToObjectSpace(p.CFrame.Position)
				-- buildings: also when they only reach into the site
				local reach = if name == "Buildings" then math.max(p.Size.X, p.Size.Z) / 2 else 0
				if math.abs(l.X) - reach < hx and math.abs(l.Z) - reach < hz then
					p:Destroy()
					removed += 1
				end
			end
		end
	end
	return removed
end

-- Building ---------------------------------------------------------------------------

function ParliamentBuilder.Build(): Model?
	if not Config.On(Config.Parliament) then
		return nil
	end
	local site = ParliamentBuilder.Site
	local flat = CFrame.new(site.x, 0, site.z)
	clearSite(flat, site.halfX, site.halfZ)
	local y0 = CityBuilder.GroundY(site.x, site.z)
	local origin = CFrame.new(site.x, y0 + 0.6, site.z)
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end

	local m = Instance.new("Model")
	m.Name = "Parlament"
	local outside = Instance.new("Model")
	outside.Name = "Outside"
	outside.Parent = m
	local shell = Instance.new("Model")
	shell.Name = "Building"
	shell.Parent = m
	local inside = Instance.new("Model")
	inside.Name = "Inside"
	inside.Parent = m

	-- grounds: lawn ("Platz der Republik") with paved paths --------------------------
	local HX, HZ = site.halfX, site.halfZ
	box(outside, "Lawn", Vector3.new(HX * 2, 0.6, HZ * 2), at(0, -0.3, 0), GRASS, Enum.Material.Grass)
	box(outside, "Apron", Vector3.new(W + 30, 0.2, D + 30), at(0, 0.1, 0), PAVING, Enum.Material.Pavement)
	box(
		outside,
		"Path",
		Vector3.new(80, 0.2, HZ - D / 2),
		at(0, 0.1, -(HZ + D / 2) / 2),
		PAVING,
		Enum.Material.Pavement
	)
	box(outside, "CrossPath", Vector3.new(HX * 2, 0.2, 18), at(0, 0.1, -HZ + 30), PAVING, Enum.Material.Pavement)

	-- floor block (the building stands on a plinth: inside floor at FL) ----------------
	box(shell, "Plinth", Vector3.new(W, FL, D), at(0, FL / 2, 0), STONE_DARK, Enum.Material.Sandstone)
	box(inside, "Floor", Vector3.new(W - 2 * T, 0.2, D - 2 * T), at(0, FL + 0.1, 0), FLOOR, Enum.Material.Marble)

	-- outer walls with two rows of windows ----------------------------------------
	local wallH = ROOF - FL
	local function facade(len: number, cf: CFrame, door: boolean)
		-- cf: centre of the wall at floor height, local -Z = outwards
		local gap = if door then 40 else 0
		local doorH = 34
		if door then
			local side = (len - gap) / 2
			for _, s in { -1, 1 } do
				box(
					shell,
					"Wall",
					Vector3.new(side, wallH, T),
					cf * CFrame.new(s * (gap / 2 + side / 2), wallH / 2, 0),
					STONE,
					Enum.Material.Sandstone
				)
			end
			box(
				shell,
				"Wall",
				Vector3.new(gap, wallH - doorH, T),
				cf * CFrame.new(0, doorH + (wallH - doorH) / 2, 0),
				STONE,
				Enum.Material.Sandstone
			)
			-- portal frame
			for _, s in { -1, 1 } do
				box(
					shell,
					"Portal",
					Vector3.new(3, doorH, T + 2),
					cf * CFrame.new(s * (gap / 2 + 1.5), doorH / 2, 0),
					STONE_LIGHT,
					Enum.Material.Sandstone
				)
			end
		else
			box(
				shell,
				"Wall",
				Vector3.new(len, wallH, T),
				cf * CFrame.new(0, wallH / 2, 0),
				STONE,
				Enum.Material.Sandstone
			)
		end
		-- ground floor band (rustication) and the cornice
		box(
			shell,
			"Band",
			Vector3.new(len, 1.2, 1),
			cf * CFrame.new(0, 26, -T / 2 - 0.5),
			STONE_LIGHT,
			Enum.Material.Sandstone
		)
		box(
			shell,
			"Cornice",
			Vector3.new(len + 4, 5, 4),
			cf * CFrame.new(0, wallH - 9, -T / 2 - 1),
			STONE_LIGHT,
			Enum.Material.Sandstone
		)
		box(
			shell,
			"Attic",
			Vector3.new(len, 4, 1.5),
			cf * CFrame.new(0, wallH - 2, -T / 2 - 0.75),
			STONE_DARK,
			Enum.Material.Sandstone
		)
		-- windows + pilasters, keeping the towers (56 at each end) free
		local usable = len - 2 * 56
		local n = math.max(1, math.floor(usable / 22))
		local step = usable / n
		for i = 0, n - 1 do
			local x = -usable / 2 + step * (i + 0.5)
			if door and math.abs(x) < gap / 2 + 6 then
				continue
			end
			box(
				shell,
				"Window",
				Vector3.new(8, 13, 0.4),
				cf * CFrame.new(x, 9, -T / 2 - 0.1),
				WINDOW,
				Enum.Material.Glass,
				{ Reflectance = 0.15 }
			)
			box(
				shell,
				"Window",
				Vector3.new(8, 26, 0.4),
				cf * CFrame.new(x, 44, -T / 2 - 0.1),
				WINDOW,
				Enum.Material.Glass,
				{ Reflectance = 0.15 }
			)
			box(
				shell,
				"WindowHead",
				Vector3.new(10, 2, 1),
				cf * CFrame.new(x, 58, -T / 2 - 0.5),
				STONE_LIGHT,
				Enum.Material.Sandstone
			)
		end
		for i = 0, n do
			local x = -usable / 2 + step * i
			if door and math.abs(x) < gap / 2 + 8 then
				continue
			end
			box(
				shell,
				"Pilaster",
				Vector3.new(3, wallH - 36, 1.2),
				cf * CFrame.new(x, 27 + (wallH - 36) / 2, -T / 2 - 0.6),
				STONE_LIGHT,
				Enum.Material.Sandstone
			)
		end
	end
	-- front (north, -Z) with the entrance, back, left, right
	facade(W, at(0, FL, -D / 2 + T / 2), true)
	facade(W, at(0, FL, D / 2 - T / 2) * CFrame.Angles(0, math.pi, 0), false)
	facade(D, at(-W / 2 + T / 2, FL, 0) * CFrame.Angles(0, math.pi / 2, 0), false)
	facade(D, at(W / 2 - T / 2, FL, 0) * CFrame.Angles(0, -math.pi / 2, 0), false)

	-- corner towers (taller, with their own cornice), flags: DE + EU only ------------
	local TW, TH = 56, 124
	local towerFlags = { { -1, -1, "DE" }, { 1, -1, "EU" }, { -1, 1, "DE" }, { 1, 1, "DE" } }
	for _, tf in towerFlags do
		local sx, sz = tf[1], tf[2]
		local cx, cz = sx * (W / 2 - TW / 2), sz * (D / 2 - TW / 2)
		box(
			shell,
			"Tower",
			Vector3.new(TW, TH - FL, TW),
			at(cx, FL + (TH - FL) / 2, cz),
			STONE,
			Enum.Material.Sandstone
		)
		box(
			shell,
			"TowerCornice",
			Vector3.new(TW + 4, 4, TW + 4),
			at(cx, TH - 6, cz),
			STONE_LIGHT,
			Enum.Material.Sandstone
		)
		box(shell, "TowerTop", Vector3.new(TW - 8, 6, TW - 8), at(cx, TH + 3, cz), STONE_DARK, Enum.Material.Sandstone)
		for _, face in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
			for _, off in { -12, 12 } do
				for _, wy in { 46, 84 } do
					local px = cx + face[1] * (TW / 2 + 0.1) + (if face[1] == 0 then off else 0)
					local pz = cz + face[2] * (TW / 2 + 0.1) + (if face[2] == 0 then off else 0)
					local size = if face[1] == 0 then Vector3.new(7, 20, 0.4) else Vector3.new(0.4, 20, 7)
					box(shell, "TowerWindow", size, at(px, wy, pz), WINDOW, Enum.Material.Glass, { Reflectance = 0.15 })
				end
			end
		end
		flagpole(outside, tf[3], at(cx, TH + 6, cz), 30, 12)
	end

	-- portico: stairs, six columns, entablature with the inscription, pediment --------
	local PZ = -D / 2 -- front wall line
	box(shell, "Podium", Vector3.new(150, FL, 30), at(0, FL / 2, PZ - 15), STONE_DARK, Enum.Material.Sandstone)
	for i = 1, 10 do
		local h = FL * (11 - i) / 10
		box(
			outside,
			"Step",
			Vector3.new(150, h, 3),
			at(0, h / 2, PZ - 30 - (i - 0.5) * 3),
			STONE_LIGHT,
			Enum.Material.Sandstone
		)
	end
	local colTop = 84
	for i = 0, 5 do
		local x = -62.5 + i * 25
		box(shell, "ColumnBase", Vector3.new(10, 3, 10), at(x, FL + 1.5, PZ - 18), STONE_LIGHT, Enum.Material.Sandstone)
		box(
			shell,
			"Column",
			Vector3.new(colTop - FL - 6, 7.5, 7.5),
			at(x, FL + 3 + (colTop - FL - 6) / 2, PZ - 18) * CFrame.Angles(0, 0, math.pi / 2),
			STONE_LIGHT,
			Enum.Material.Sandstone,
			{ Shape = Enum.PartType.Cylinder }
		)
		box(
			shell,
			"Capital",
			Vector3.new(11, 3, 11),
			at(x, colTop - 1.5, PZ - 18),
			STONE_LIGHT,
			Enum.Material.Sandstone
		)
	end
	local frieze =
		box(shell, "Frieze", Vector3.new(160, 10, 30), at(0, colTop + 5, PZ - 15), STONE, Enum.Material.Sandstone)
	text(frieze, Enum.NormalId.Front, "DEM DEUTSCHEN VOLKE", GOLD, nil, Enum.Font.Garamond)
	box(
		shell,
		"FriezeCornice",
		Vector3.new(164, 2, 32),
		at(0, colTop + 11, PZ - 15),
		STONE_LIGHT,
		Enum.Material.Sandstone
	)
	for _, s in { -1, 1 } do
		-- pediment halves: the high side of each wedge at the middle
		box(
			shell,
			"Pediment",
			Vector3.new(30, 24, 80),
			at(s * 40, colTop + 12 + 12, PZ - 15) * CFrame.Angles(0, -s * math.pi / 2, 0),
			STONE,
			Enum.Material.Sandstone,
			{ class = "WedgePart" }
		)
	end
	-- the open entrance: a glass frame high above the doorway, no door to block anyone
	box(
		shell,
		"EntranceGlass",
		Vector3.new(40, 6, 0.4),
		at(0, FL + 37, PZ + 0.5),
		GLASS,
		Enum.Material.Glass,
		{ Transparency = 0.4 }
	)
	local sign = box(
		outside,
		"NameSign",
		Vector3.new(36, 5, 0.6),
		at(-100, 4, PZ - 40),
		Color3.fromRGB(30, 30, 34),
		Enum.Material.Metal
	)
	text(
		sign,
		Enum.NormalId.Front,
		"PARLAMENT · Eintritt frei",
		Color3.new(1, 1, 1),
		Color3.fromRGB(30, 30, 34),
		Enum.Font.GothamBold
	)

	-- forecourt flagpoles: Germany and the EU ------------------------------------------
	flagpole(outside, "DE", at(-95, 0, PZ - 75), 70, 18)
	flagpole(outside, "EU", at(95, 0, PZ - 75) * CFrame.Angles(0, math.pi, 0), 70, 18)

	-- roof with an opening under the dome (glass ceiling over the plenary hall) -------
	local HOLE = 120
	local hallZ = 25 -- dome / hall centre
	local roofY = ROOF
	local rz1, rz2 = hallZ - HOLE / 2, hallZ + HOLE / 2
	box(
		shell,
		"Roof",
		Vector3.new(W, 2, rz1 + D / 2),
		at(0, roofY + 1, (-D / 2 + rz1) / 2),
		STONE_DARK,
		Enum.Material.Slate
	)
	box(
		shell,
		"Roof",
		Vector3.new(W, 2, D / 2 - rz2),
		at(0, roofY + 1, (rz2 + D / 2) / 2),
		STONE_DARK,
		Enum.Material.Slate
	)
	for _, s in { -1, 1 } do
		box(
			shell,
			"Roof",
			Vector3.new((W - HOLE) / 2, 2, HOLE),
			at(s * (HOLE / 2 + (W - HOLE) / 4), roofY + 1, hallZ),
			STONE_DARK,
			Enum.Material.Slate
		)
	end
	box(
		shell,
		"CeilingGlass",
		Vector3.new(HOLE, 0.6, HOLE),
		at(0, roofY + 0.3, hallZ),
		GLASS,
		Enum.Material.Glass,
		{ Transparency = 0.55 }
	)

	-- glass dome: drum, ribs, rings, glass skin, mirror funnel ------------------------
	local dome = Instance.new("Model")
	dome.Name = "Kuppel"
	dome.Parent = m
	local R, HD = 58, 70
	local base = roofY + 2
	box(
		dome,
		"Drum",
		Vector3.new(6, R * 2 + 6, R * 2 + 6),
		at(0, base + 3, hallZ) * CFrame.Angles(0, 0, math.pi / 2),
		STONE,
		Enum.Material.Sandstone,
		{
			Shape = Enum.PartType.Cylinder,
		}
	)
	local top = base + 6
	local function r(h: number): number
		return R * math.sqrt(math.max(0, 1 - (h / HD) ^ 2))
	end
	local LAYERS = 9
	for i = 0, LAYERS - 1 do
		local h0, h1 = HD * i / LAYERS, HD * (i + 1) / LAYERS
		local rr = (r(h0) + r(h1)) / 2
		box(
			dome,
			"DomeGlass",
			Vector3.new(h1 - h0, rr * 2, rr * 2),
			at(0, top + (h0 + h1) / 2, hallZ) * CFrame.Angles(0, 0, math.pi / 2),
			GLASS,
			Enum.Material.Glass,
			{
				Shape = Enum.PartType.Cylinder,
				Transparency = 0.78,
				CanCollide = false,
			}
		)
	end
	local RIBS, SEG = 24, 7
	for k = 0, RIBS - 1 do
		local a = k * 2 * math.pi / RIBS
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		for j = 0, SEG - 1 do
			local h0, h1 = HD * j / SEG * 0.97, HD * (j + 1) / SEG * 0.97
			local p0 = Vector3.new(0, top + h0, 0) + dir * r(h0)
			local p1 = Vector3.new(0, top + h1, 0) + dir * r(h1)
			local len = (p1 - p0).Magnitude
			local mid = (p0 + p1) / 2
			box(
				dome,
				"Rib",
				Vector3.new(0.6, 0.6, len),
				origin * CFrame.lookAt(mid + Vector3.new(0, 0, hallZ), p1 + Vector3.new(0, 0, hallZ)),
				STEEL,
				Enum.Material.Metal,
				{
					CanCollide = false,
				}
			)
		end
	end
	for _, f in { 0.18, 0.38, 0.58, 0.76, 0.9 } do
		local h = HD * f
		local rr = r(h)
		local n = 24
		for k = 0, n - 1 do
			local a0, a1 = k * 2 * math.pi / n, (k + 1) * 2 * math.pi / n
			local p0 = Vector3.new(math.cos(a0) * rr, top + h, math.sin(a0) * rr + hallZ)
			local p1 = Vector3.new(math.cos(a1) * rr, top + h, math.sin(a1) * rr + hallZ)
			box(
				dome,
				"Ring",
				Vector3.new(0.6, 0.6, (p1 - p0).Magnitude),
				origin * CFrame.lookAt((p0 + p1) / 2, p1),
				STEEL,
				Enum.Material.Metal,
				{
					CanCollide = false,
				}
			)
		end
	end
	box(
		dome,
		"Oculus",
		Vector3.new(1.5, 24, 24),
		at(0, top + HD - 0.5, hallZ) * CFrame.Angles(0, 0, math.pi / 2),
		STEEL,
		Enum.Material.Metal,
		{
			Shape = Enum.PartType.Cylinder,
		}
	)
	-- the mirror funnel: wide at the top, narrow above the plenary hall
	for i = 0, 7 do
		local hh = 6
		local rr = 4 + i * 2.6
		box(
			dome,
			"Funnel",
			Vector3.new(hh, rr * 2, rr * 2),
			at(0, roofY - 4 + i * hh + hh / 2, hallZ) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(210, 215, 220),
			Enum.Material.Glass,
			{
				Shape = Enum.PartType.Cylinder,
				Reflectance = 0.6,
				Transparency = 0.15,
				CanCollide = false,
			}
		)
	end

	-- inside: entrance hall, plenary hall ------------------------------------------------
	local HW = 240 -- hall width (x)
	local hz1, hz2 = -70, 130 -- hall front / back wall
	local inH = ROOF - FL
	local function wallIn(size: Vector3, cf: CFrame)
		box(inside, "InnerWall", size, cf, WALL_IN, Enum.Material.SmoothPlastic)
	end
	-- front wall of the hall with three wide openings
	local openings = { -60, 0, 60 }
	local ow, oh = 20, 26
	local xs = { -HW / 2, -60 - ow / 2, -60 + ow / 2, -ow / 2, ow / 2, 60 - ow / 2, 60 + ow / 2, HW / 2 }
	for i = 1, #xs - 1, 2 do
		local a, b = xs[i], xs[i + 1]
		wallIn(Vector3.new(b - a, inH, 2), at((a + b) / 2, FL + inH / 2, hz1))
	end
	for _, x in openings do
		wallIn(Vector3.new(ow, inH - oh, 2), at(x, FL + oh + (inH - oh) / 2, hz1))
	end
	for _, s in { -1, 1 } do
		wallIn(Vector3.new(2, inH, hz2 - hz1), at(s * HW / 2, FL + inH / 2, (hz1 + hz2) / 2))
	end
	wallIn(Vector3.new(HW, inH, 2), at(0, FL + inH / 2, hz2))
	box(
		inside,
		"HallFloor",
		Vector3.new(HW - 2, 0.2, hz2 - hz1 - 2),
		at(0, FL + 0.25, (hz1 + hz2) / 2),
		Color3.fromRGB(70, 90, 140),
		Enum.Material.Fabric
	)
	-- entrance hall: information desk and benches
	local desk = box(
		inside,
		"InfoDesk",
		Vector3.new(30, 4, 5),
		at(0, FL + 2, -110),
		Color3.fromRGB(120, 90, 60),
		Enum.Material.Wood
	)
	text(
		desk,
		Enum.NormalId.Front,
		"Besucherdienst",
		Color3.new(1, 1, 1),
		Color3.fromRGB(120, 90, 60),
		Enum.Font.GothamBold
	)

	-- presidium, lectern, government benches
	local pz = hz2 - 14
	box(
		inside,
		"Presidium",
		Vector3.new(90, 6, 20),
		at(0, FL + 3, pz),
		Color3.fromRGB(150, 120, 85),
		Enum.Material.Wood
	)
	box(
		inside,
		"PresidiumDesk",
		Vector3.new(60, 4, 4),
		at(0, FL + 8, pz - 6),
		Color3.fromRGB(130, 100, 70),
		Enum.Material.Wood
	)
	for _, x in { -20, 0, 20 } do
		local s = box(
			inside,
			"PresidentSeat",
			Vector3.new(4, 0.6, 4),
			at(x, FL + 7.3, pz - 1),
			SEAT_BLUE,
			Enum.Material.Fabric,
			{ class = "Seat" }
		)
		box(
			inside,
			"SeatBack",
			Vector3.new(4, 5, 0.6),
			s.CFrame * CFrame.new(0, 2.6, 2),
			SEAT_BLUE,
			Enum.Material.Fabric
		)
	end
	local lectern = box(
		inside,
		"Rednerpult",
		Vector3.new(7, 8, 4),
		at(0, FL + 4, pz - 22),
		Color3.fromRGB(150, 120, 85),
		Enum.Material.Wood
	)
	box(
		inside,
		"Microphone",
		Vector3.new(0.2, 2, 0.2),
		lectern.CFrame * CFrame.new(0, 5, 1) * CFrame.Angles(math.rad(-25), 0, 0),
		Color3.fromRGB(30, 30, 30),
		Enum.Material.Metal
	)
	for _, s in { -1, 1 } do
		-- government (left) and Bundesrat (right) benches, facing the hall
		for row = 0, 1 do
			for k = 0, 5 do
				local cf = at(s * (76 + row * 7), FL + 1.5 + row * 1.5, pz - 28 + k * 5)
					* CFrame.Angles(0, s * math.pi / 2, 0)
				local seat = box(
					inside,
					"BenchSeat",
					Vector3.new(3.4, 0.6, 3.4),
					cf,
					SEAT_BLUE,
					Enum.Material.Fabric,
					{ class = "Seat" }
				)
				box(
					inside,
					"SeatBack",
					Vector3.new(3.4, 4, 0.6),
					seat.CFrame * CFrame.new(0, 2.2, 1.8),
					SEAT_BLUE,
					Enum.Material.Fabric
				)
			end
			box(
				inside,
				"BenchStep",
				Vector3.new(6, 1.5 + row * 1.5, 32),
				at(s * (76 + row * 7), FL + (1.5 + row * 1.5) / 2 - 0.3, pz - 15.5),
				Color3.fromRGB(150, 120, 85),
				Enum.Material.Wood
			)
		end
	end

	-- members' seats: rows in arcs facing the presidium (everyone may sit) ------------
	local C = Vector3.new(0, 0, pz - 8)
	local seats = 0
	for row = 0, 7 do
		local rr = 42 + row * 12
		-- not wider than the hall, and in front of the government benches
		local amax = math.min(math.rad(75), math.asin(math.min(1, 100 / rr)), math.acos(math.min(1, 30 / rr)))
		local n = math.floor(rr * 2 * amax / 5.2)
		local rise = row * 0.8
		if rise > 0 then
			-- low tiers so the back rows see the lectern
			for k = 0, n - 1 do
				local a = -amax + 2 * amax * (k + 0.5) / n
				local pos = C + Vector3.new(math.sin(a) * rr, 0, -math.cos(a) * rr)
				local face = origin
					* CFrame.lookAt(Vector3.new(pos.X, FL + rise / 2, pos.Z), Vector3.new(C.X, FL + rise / 2, C.Z))
				box(inside, "Tier", Vector3.new(5.6, rise, 10), face, Color3.fromRGB(60, 78, 130), Enum.Material.Fabric)
			end
		end
		for k = 0, n - 1 do
			local a = -amax + 2 * amax * (k + 0.5) / n
			local pos = C + Vector3.new(math.sin(a) * rr, 0, -math.cos(a) * rr)
			local y = FL + rise + 1.6
			local cf = origin * CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(C.X, y, C.Z))
			local seat = box(
				inside,
				"AbgeordnetenSitz",
				Vector3.new(3.4, 0.6, 3.4),
				cf,
				SEAT_BLUE,
				Enum.Material.Fabric,
				{ class = "Seat" }
			)
			box(
				inside,
				"SeatBack",
				Vector3.new(3.4, 4.2, 0.6),
				seat.CFrame * CFrame.new(0, 2.3, 1.8),
				SEAT_BLUE,
				Enum.Material.Fabric
			)
			box(
				inside,
				"SeatLeg",
				Vector3.new(0.6, 1.3, 0.6),
				seat.CFrame * CFrame.new(0, -0.95, 0),
				STEEL,
				Enum.Material.Metal
			)
			seats += 1
		end
	end
	m:SetAttribute("Seats", seats)

	-- federal eagle on the wall behind the presidium (stylised) -------------------------
	local EAGLE = Color3.fromRGB(105, 108, 114)
	local ez = hz2 - 1.6
	local eagle = Instance.new("Model")
	eagle.Name = "Bundesadler"
	eagle.Parent = inside
	local ey = FL + 40
	local function ep(name: string, size: Vector3, x: number, y: number, rot: number, shape: Enum.PartType?)
		box(eagle, name, size, at(x, ey + y, ez) * CFrame.Angles(0, 0, math.rad(rot)), EAGLE, Enum.Material.Metal, {
			Shape = shape or Enum.PartType.Block,
			CanCollide = false,
		})
	end
	ep("Body", Vector3.new(12, 22, 1), 0, 0, 0)
	ep("Breast", Vector3.new(15, 15, 1), 0, 2, 0)
	ep("Head", Vector3.new(7, 7, 7), -1.5, 14, 0, Enum.PartType.Ball)
	ep("Beak", Vector3.new(3, 2, 1.2), -5.5, 13, -20)
	for _, s in { -1, 1 } do
		for i = 0, 4 do
			ep("Feather", Vector3.new(4.5, 18 - i * 1.5, 1), s * (11 + i * 4.6), 4 - i * 1.2, s * (-35 + i * 9))
		end
		ep("Wing", Vector3.new(20, 7, 1), s * 15, 9, s * 15)
		ep("Leg", Vector3.new(2, 7, 1), s * 3.5, -13, 0)
		ep("Claw", Vector3.new(5, 1.5, 1), s * 4.5, -16.5, 0)
	end
	for i = -1, 1 do
		ep("Tail", Vector3.new(3.5, 10, 1), i * 3.5, -15, i * 14)
	end

	-- the flags inside: Netherlands, Denmark, Germany, EU, Belgium, France --------------
	local inFlags = { "NL", "DK", "DE", "EU", "BE", "FR" }
	local fh = 16
	local widths = {}
	local total = 0
	for _, id in inFlags do
		local w = fh * FLAGS[id].ratio
		table.insert(widths, w)
		total += w
	end
	local gapF = 9
	total += gapF * (#inFlags - 1)
	local fx = total / 2 -- seen from the seats, world +X is on the left
	local fy = FL + 70
	for i, id in inFlags do
		local w = widths[i]
		local cx = fx - w / 2
		-- hung from a brass rod with two cords, a little in front of the wall
		local cf = at(cx, fy, hz2 - 3) * CFrame.Angles(0, math.pi, 0)
		flag(inside, id, cf, fh)
		box(
			inside,
			"FlagRod",
			Vector3.new(w + 2, 0.5, 0.5),
			at(cx, fy + fh / 2 + 0.4, hz2 - 3),
			GOLD,
			Enum.Material.Metal,
			{
				CanCollide = false,
			}
		)
		for _, s in { -1, 1 } do
			box(
				inside,
				"Cord",
				Vector3.new(0.15, 10, 0.15),
				at(cx + s * (w / 2 - 1), fy + fh / 2 + 5.4, hz2 - 2.5),
				Color3.fromRGB(60, 60, 60),
				nil,
				{
					CanCollide = false,
				}
			)
		end
		fx -= w + gapF
	end

	-- light -------------------------------------------------------------------------
	for _, lp in { { 0, -110 }, { -70, 0 }, { 70, 0 }, { 0, 60 }, { -150, 0 }, { 150, 0 } } do
		local l = box(
			inside,
			"Light",
			Vector3.new(6, 0.4, 6),
			at(lp[1], ROOF - 1, lp[2]),
			Color3.fromRGB(255, 250, 235),
			Enum.Material.Neon,
			{
				CanCollide = false,
			}
		)
		local pl = Instance.new("PointLight")
		pl.Range = 60
		pl.Brightness = 1.2
		pl.Color = Color3.fromRGB(255, 244, 225)
		pl.Parent = l
	end

	m.Parent = Workspace
	return m
end

return ParliamentBuilder
