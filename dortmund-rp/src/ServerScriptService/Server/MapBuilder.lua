--!strict
-- Phase 1 TEST AREA: a compact block around Dortmund Hbf with every station needed
-- to test the core systems. The real-scale districts (Innenstadt, Phoenix-See, Hörde, ...)
-- replace this in the map phase. 1 stud = 0.28 m.

local Workspace = game:GetService("Workspace")

local Interaction = require(script.Parent.InteractionService)

local MapBuilder = {}

local ROAD = Color3.fromRGB(55, 57, 60)
local WALK = Color3.fromRGB(165, 160, 150)
local GRASS = Color3.fromRGB(80, 120, 60)
local LINE = Color3.fromRGB(235, 235, 235)

local map: Folder

local function box(
	name: string,
	size: Vector3,
	pos: Vector3,
	color: Color3,
	material: Enum.Material?,
	parent: Instance?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or map
	return p
end

local function sign(p: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if bg then 0 else 1
	label.BackgroundColor3 = bg or Color3.new()
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
end

local function road(name: string, from: Vector3, to: Vector3, width: number)
	local delta = to - from
	local length = delta.Magnitude
	local mid = (from + to) / 2
	local horizontal = math.abs(delta.X) > math.abs(delta.Z)
	local size = if horizontal then Vector3.new(length + width, 0.2, width) else Vector3.new(width, 0.2, length + width)
	local p = box(name, size, Vector3.new(mid.X, 0.1, mid.Z), ROAD, Enum.Material.Asphalt)
	p:SetAttribute("Street", name)
	-- dashed centre line
	local dashes = math.floor(length / 24)
	for i = 0, dashes do
		local t = i / math.max(dashes, 1)
		local pos = from:Lerp(to, t)
		local dashSize = if horizontal then Vector3.new(10, 0.05, 0.6) else Vector3.new(0.6, 0.05, 10)
		local d = box("Line", dashSize, Vector3.new(pos.X, 0.22, pos.Z), LINE, Enum.Material.SmoothPlastic, p)
		d.CanCollide = false
	end
	-- sidewalks
	for _, side in { -1, 1 } do
		local offset = if horizontal
			then Vector3.new(0, 0, side * (width / 2 + 6))
			else Vector3.new(side * (width / 2 + 6), 0, 0)
		local wsize = if horizontal
			then Vector3.new(length + width + 24, 0.45, 12)
			else Vector3.new(12, 0.45, length + width + 24)
		box("Sidewalk", wsize, Vector3.new(mid.X, 0.225, mid.Z) + offset, WALK, Enum.Material.Pavement, p)
	end
	-- street name signs at both ends
	for _, pos in { from, to } do
		local pole = box(
			"SignPole",
			Vector3.new(0.5, 10, 0.5),
			Vector3.new(pos.X + width / 2 + 4, 5, pos.Z + width / 2 + 4),
			Color3.fromRGB(120, 120, 120),
			Enum.Material.Metal,
			p
		)
		local plate = box(
			"StreetSign",
			Vector3.new(10, 1.6, 0.3),
			pole.Position + Vector3.new(0, 4.5, 0),
			Color3.new(1, 1, 1),
			nil,
			p
		)
		sign(plate, Enum.NormalId.Front, name, Color3.new(0, 0, 0))
		sign(plate, Enum.NormalId.Back, name, Color3.new(0, 0, 0))
	end
end

-- A simple building: walls, roof, a sign facing `faceDir` (unit vector towards the street).
local function building(
	name: string,
	center: Vector3,
	size: Vector3,
	color: Color3,
	signText: string?,
	faceDir: Vector3,
	signColor: Color3?,
	signBg: Color3?
): Part
	local b = box(name, size, center + Vector3.new(0, size.Y / 2, 0), color, Enum.Material.Concrete)
	-- window bands
	for y = 8, size.Y - 6, 12 do
		local band = box(
			"Windows",
			Vector3.new(size.X + 0.2, 4, size.Z + 0.2),
			center + Vector3.new(0, y, 0),
			Color3.fromRGB(60, 80, 100),
			Enum.Material.Glass,
			b
		)
		band.Transparency = 0.2
		band.CanCollide = false
	end
	if signText then
		local faceId = if faceDir.Z > 0.5
			then Enum.NormalId.Back
			elseif faceDir.Z < -0.5 then Enum.NormalId.Front
			elseif faceDir.X > 0.5 then Enum.NormalId.Right
			else Enum.NormalId.Left
		local signPart = box(
			name .. "Sign",
			Vector3.new(math.min(size.X, size.Z) * 0.8, 6, math.min(size.X, size.Z) * 0.8),
			center + Vector3.new(0, size.Y + 3.5, 0),
			signBg or Color3.new(1, 1, 1),
			nil,
			b
		)
		sign(signPart, faceId, signText, signColor or Color3.new(0, 0, 0), signBg)
	end
	return b
end

local function marker(kind: string, pos: Vector3, color: Color3, attrs: { [string]: any }): Part
	local p = box("Marker_" .. kind, Vector3.new(6, 0.4, 6), pos + Vector3.new(0, 0.8, 0), color, Enum.Material.Neon)
	p.Transparency = 0.35
	p.CanCollide = false
	Interaction.Mark(p, kind, attrs)
	return p
end

local function station(
	jobId: string,
	title: string,
	center: Vector3,
	color: Color3,
	faceDir: Vector3,
	extraJobs: { { string } }?
)
	local b = building(
		title,
		center,
		Vector3.new(90, 26, 70),
		Color3.fromRGB(215, 215, 210),
		title,
		faceDir,
		Color3.new(1, 1, 1),
		color
	)
	local _ = b
	local front = center + faceDir * 55
	local right = Vector3.new(faceDir.Z, 0, -faceDir.X)
	marker(
		"JobStart",
		front + right * -14,
		color,
		{ JobId = jobId, ActionText = "Dienst antreten", ObjectText = title }
	)
	marker(
		"JobGarage",
		front + right * 14,
		color,
		{ JobId = jobId, UI = "JobGarage", Arg = jobId, ActionText = "Dienstfahrzeug", ObjectText = title }
	)
	if extraJobs then
		for i, info in extraJobs do
			marker(
				"JobStart",
				front + right * (-14 - i * 8),
				color,
				{ JobId = info[1], ActionText = "Dienst antreten", ObjectText = info[2] }
			)
			marker("JobGarage", front + right * (14 + i * 8), color, {
				JobId = info[1],
				UI = "JobGarage",
				Arg = info[1],
				ActionText = "Dienstfahrzeug",
				ObjectText = info[2],
			})
		end
	end
end

function MapBuilder.Build()
	map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = Workspace

	box("Ground", Vector3.new(2400, 2, 2400), Vector3.new(0, -1, 0), GRASS, Enum.Material.Grass)

	local W = 44
	road("Königswall", Vector3.new(-700, 0, 0), Vector3.new(700, 0, 0), W)
	road("Burgwall", Vector3.new(600, 0, -300), Vector3.new(600, 0, 600), W)
	road("Hiltropwall", Vector3.new(-600, 0, -300), Vector3.new(-600, 0, 600), W)
	road("Südwall", Vector3.new(-700, 0, 600), Vector3.new(700, 0, 600), W)
	road("Katharinenstraße", Vector3.new(0, 0, 0), Vector3.new(0, 0, 250), 30)
	road("Kampstraße", Vector3.new(0, 0, 400), Vector3.new(0, 0, 600), 30)
	road("Ferdinandstraße", Vector3.new(-300, 0, -300), Vector3.new(-300, 0, 0), 30)

	-- Westenhellweg (pedestrian zone)
	local zone = box(
		"Westenhellweg",
		Vector3.new(900, 0.4, 60),
		Vector3.new(0, 0.2, 325),
		Color3.fromRGB(190, 180, 165),
		Enum.Material.Pavement
	)
	zone:SetAttribute("Street", "Westenhellweg")

	-- Hauptbahnhof + forecourt
	box("Bahnhofsvorplatz", Vector3.new(380, 0.4, 60), Vector3.new(0, 0.2, -60), WALK, Enum.Material.Pavement)
	building(
		"Hauptbahnhof",
		Vector3.new(0, 0, -160),
		Vector3.new(360, 50, 130),
		Color3.fromRGB(200, 190, 170),
		"Dortmund Hbf",
		Vector3.new(0, 0, 1),
		Color3.fromRGB(0, 60, 140)
	)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn_Hbf"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 0.4, 12)
	spawn.Position = Vector3.new(0, 0.6, -60)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = map

	-- Starter apartment (housing comes in a later phase)
	building(
		"Ferdinandstraße 24",
		Vector3.new(-380, 0, -150),
		Vector3.new(70, 60, 60),
		Color3.fromRGB(190, 170, 150),
		"Ferdinandstraße 24",
		Vector3.new(1, 0, 0)
	)
	marker(
		"Shop",
		Vector3.new(-335, 0, -150),
		Color3.fromRGB(255, 255, 255),
		{ UI = "Housing", ActionText = "Wohnung", ObjectText = "Ferdinandstraße 24" }
	)

	-- Westenhellweg shops
	building(
		"Handyland",
		Vector3.new(-200, 0, 395),
		Vector3.new(60, 30, 60),
		Color3.fromRGB(230, 230, 230),
		"Handyland",
		Vector3.new(0, 0, -1),
		Color3.new(1, 1, 1),
		Color3.fromRGB(0, 110, 220)
	)
	marker(
		"Shop",
		Vector3.new(-200, 0, 358),
		Color3.fromRGB(0, 110, 220),
		{ UI = "Handyland", ActionText = "Handys ansehen", ObjectText = "Handyland" }
	)
	building(
		"Rewo",
		Vector3.new(-80, 0, 395),
		Vector3.new(60, 24, 60),
		Color3.fromRGB(230, 230, 230),
		"REWO",
		Vector3.new(0, 0, -1),
		Color3.new(1, 1, 1),
		Color3.fromRGB(200, 20, 20)
	)
	building(
		"Modehaus",
		Vector3.new(120, 0, 395),
		Vector3.new(80, 30, 60),
		Color3.fromRGB(220, 215, 205),
		"Modehaus",
		Vector3.new(0, 0, -1)
	)
	building(
		"Lindl",
		Vector3.new(250, 0, 255),
		Vector3.new(80, 22, 60),
		Color3.fromRGB(230, 230, 230),
		"LINDL",
		Vector3.new(0, 0, 1),
		Color3.fromRGB(250, 220, 0),
		Color3.fromRGB(0, 60, 150)
	)

	-- Hospital
	building(
		"Klinikum Dortmund",
		Vector3.new(300, 0, 120),
		Vector3.new(140, 45, 90),
		Color3.fromRGB(235, 235, 235),
		"Klinikum Dortmund",
		Vector3.new(0, 0, -1),
		Color3.new(1, 1, 1),
		Color3.fromRGB(0, 120, 90)
	)

	-- Dealership
	building(
		"Autohaus Dortmund",
		Vector3.new(760, 0, 200),
		Vector3.new(110, 28, 90),
		Color3.fromRGB(240, 240, 240),
		"Autohaus Dortmund",
		Vector3.new(-1, 0, 0),
		Color3.new(1, 1, 1),
		Color3.fromRGB(30, 30, 30)
	)
	marker(
		"Shop",
		Vector3.new(690, 0, 200),
		Color3.fromRGB(255, 255, 255),
		{ UI = "Dealership", ActionText = "Autohaus", ObjectText = "Autohaus Dortmund" }
	)

	-- Arol gas station
	local canopy = box("ArolCanopy", Vector3.new(60, 2, 40), Vector3.new(700, 14, 450), Color3.fromRGB(0, 70, 160))
	sign(canopy, Enum.NormalId.Left, "AROL", Color3.new(1, 1, 1))
	for i, z in { 435, 465 } do
		local pump = box("Pump" .. i, Vector3.new(3, 6, 2), Vector3.new(700, 3, z), Color3.fromRGB(240, 240, 240))
		local _ = pump
		marker(
			"Refuel",
			Vector3.new(692, 0, z),
			Color3.fromRGB(0, 120, 255),
			{ ActionText = "Tanken", ObjectText = "Arol", Hold = 1.5 }
		)
	end
	box(
		"ArolShop",
		Vector3.new(30, 14, 24),
		Vector3.new(750, 7, 450),
		Color3.fromRGB(240, 240, 240),
		Enum.Material.Concrete
	)

	-- Job stations (west side, along Hiltropwall)
	station("Police", "Polizeiwache", Vector3.new(-720, 0, 80), Color3.fromRGB(30, 80, 180), Vector3.new(1, 0, 0))
	station("Fire", "Feuerwache 1", Vector3.new(-720, 0, 260), Color3.fromRGB(200, 30, 30), Vector3.new(1, 0, 0))
	station(
		"Rettungsdienst",
		"Rettungswache DRH",
		Vector3.new(-720, 0, 440),
		Color3.fromRGB(230, 120, 20),
		Vector3.new(1, 0, 0),
		{ { "Notarzt", "Notarzt (NEF)" } }
	)
	-- South side (along Südwall)
	station("ADMC", "ADMC Stützpunkt", Vector3.new(350, 0, 710), Color3.fromRGB(250, 205, 0), Vector3.new(0, 0, -1))
	station("DXL", "DXL Paketzentrum", Vector3.new(-350, 0, 710), Color3.fromRGB(210, 20, 30), Vector3.new(0, 0, -1))
	station("LKW", "Spedition Dortmund", Vector3.new(0, 0, 710), Color3.fromRGB(90, 140, 90), Vector3.new(0, 0, -1))

	-- Street lights (switched on at night by the client)
	local lights = Instance.new("Folder")
	lights.Name = "StreetLights"
	lights.Parent = map
	for x = -650, 650, 80 do
		local pole = box(
			"Pole",
			Vector3.new(0.6, 18, 0.6),
			Vector3.new(x, 9, -30),
			Color3.fromRGB(90, 90, 95),
			Enum.Material.Metal,
			lights
		)
		local lamp = box(
			"Lamp",
			Vector3.new(2, 0.6, 1.2),
			Vector3.new(x, 18, -27),
			Color3.fromRGB(255, 230, 170),
			Enum.Material.SmoothPlastic,
			pole
		)
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = 40
		light.Angle = 110
		light.Brightness = 2
		light.Color = Color3.fromRGB(255, 220, 160)
		light.Enabled = false
		light.Parent = lamp
	end
end

return MapBuilder
