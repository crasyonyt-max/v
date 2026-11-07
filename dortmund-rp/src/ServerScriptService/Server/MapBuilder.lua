--!strict
-- Builds real Dortmund (CityBuilder) and places every station, shop and pump at
-- its real-world location (Shared/Locations, generated from OpenStreetMap).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Jobs = require(ReplicatedStorage.Shared.Jobs)
local Locations = require(ReplicatedStorage.Shared.Locations)
local CityBuilder = require(script.Parent.CityBuilder)
local Interaction = require(script.Parent.InteractionService)

local MapBuilder = {}

local map: Folder

local function label(part: BasePart, text: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 44)
	gui.StudsOffset = Vector3.new(0, 9, 0)
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	gui.Parent = part
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
	l.BackgroundTransparency = 0.2
	l.TextColor3 = color
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.Text = text
	l.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = l
end

local function marker(kind: string, x: number, z: number, color: Color3, attrs: { [string]: any }, title: string?): Part
	local y = CityBuilder.GroundY(x, z)
	local p = Instance.new("Part")
	p.Name = "Marker_" .. kind
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.15, 7, 7)
	p.CFrame = CFrame.new(x, y + 0.1, z) * CFrame.Angles(0, 0, math.pi / 2)
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = 0.45
	p.Parent = map
	Interaction.Mark(p, kind, attrs)
	if title then
		label(p, title, color:Lerp(Color3.new(1, 1, 1), 0.5))
	end
	return p
end

function MapBuilder.Build()
	CityBuilder.Build(Locations.Bounds)

	map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = Workspace

	-- Spawn at Dortmund Hbf
	local sx, sz = Locations.Spawn[1], Locations.Spawn[2]
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn_Hbf"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.2, 10)
	spawn.Position = Vector3.new(sx, CityBuilder.GroundY(sx, sz) + 0.1, sz)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = map

	-- Job stations. Several jobs can share one building (Feuer- und Rettungswache),
	-- so markers at the same place are spread along the street.
	local used: { [string]: number } = {}
	for _, f in Locations.Fuel do
		used[string.format("%d,%d", f[1] // 10, f[2] // 10)] = 1
	end
	for _, job in Jobs.List do
		local loc = (Locations.Jobs :: any)[job.id]
		if loc then
			local key = string.format("%d,%d", loc.marker[1] // 10, loc.marker[2] // 10)
			local n = used[key] or 0
			used[key] = n + 1
			local dir = Vector3.new(math.cos(math.rad(loc.angle)), 0, math.sin(math.rad(loc.angle)))
			local mx, mz = loc.marker[1] + dir.X * n * 22, loc.marker[2] + dir.Z * n * 22
			local title = Jobs.Name(job.id, "de")
			marker(
				"JobStart",
				mx,
				mz,
				job.color,
				{ JobId = job.id, ActionText = "Dienst antreten", ObjectText = loc.title },
				loc.title .. " · " .. title
			)
			marker("JobEnd", mx - dir.X * 9, mz - dir.Z * 9, Color3.fromRGB(120, 120, 120), {
				ActionText = "Dienst beenden",
				ObjectText = loc.title,
			}, nil)
			marker("JobGarage", mx + dir.X * 9, mz + dir.Z * 9, job.color, {
				JobId = job.id,
				UI = "JobGarage",
				Arg = job.id,
				ActionText = "Dienstfahrzeug",
				ObjectText = title,
			}, nil)
		end
	end

	local shops = Locations.Shops :: any
	marker(
		"Shop",
		shops.Handyland.marker[1],
		shops.Handyland.marker[2],
		Color3.fromRGB(0, 110, 220),
		{ UI = "Handyland", ActionText = "Handys ansehen", ObjectText = "Handyland" },
		"📱 Handyland"
	)
	marker(
		"Shop",
		shops.Dealership.marker[1],
		shops.Dealership.marker[2],
		Color3.fromRGB(240, 240, 240),
		{ UI = "Dealership", ActionText = "Autohaus", ObjectText = "Autohaus Westfalendamm" },
		"🚗 Autohaus"
	)

	for _, f in Locations.Fuel do
		marker(
			"Refuel",
			f[1],
			f[2],
			Color3.fromRGB(0, 120, 255),
			{ ActionText = "Tanken", ObjectText = "Arol", Hold = 1.5 },
			"⛽ Arol"
		)
	end
end

return MapBuilder
