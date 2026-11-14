--!strict
-- Bus stops ("Haltestellen") at the real stop positions from OpenStreetMap
-- (Shared/BusStopData): an H sign with the stop's name, a glass shelter, a bench.
-- Bus drivers on duty get paid when they open the doors at a stop (BusService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BusStopData = require(ReplicatedStorage.Shared.BusStopData)
local CityBuilder = require(script.Parent.CityBuilder)

local BusStopService = {}

export type Stop = { index: number, name: string, pos: Vector3 }
BusStopService.Stops = {} :: { Stop }

local GREEN = Color3.fromRGB(0, 130, 70)
local YELLOW = Color3.fromRGB(255, 205, 0)
local FRAME = Color3.fromRGB(60, 64, 70)

local function box(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	transparency: number?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function text(p: BasePart, face: Enum.NormalId, value: string, color: Color3, bg: Color3, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = bg
	l.BorderSizePixel = 0
	l.TextScaled = true
	l.Font = font or Enum.Font.GothamBold
	l.TextColor3 = color
	l.Text = value
	l.Parent = gui
end

-- one stop; `cf` stands on the ground, looking at the road (-Z = road side)
local function build(parent: Instance, name: string, cf: CFrame)
	local m = Instance.new("Model")
	m.Name = "Haltestelle " .. name
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	-- the H sign on a pole at the kerb
	box(m, "Pole", Vector3.new(0.4, 10, 0.4), at(-7, 5, -2), FRAME, Enum.Material.Metal)
	-- (the sign faces along the road: drivers see it from both directions)
	local disc = box(m, "Sign", Vector3.new(0.2, 3, 3), at(-7, 10.5, -2), YELLOW)
	disc.Shape = Enum.PartType.Cylinder
	local h = box(m, "H", Vector3.new(0.3, 2, 2), at(-7, 10.5, -2), YELLOW, nil, 1)
	for _, face in { Enum.NormalId.Right, Enum.NormalId.Left } do
		text(h, face, "H", GREEN, YELLOW, Enum.Font.GothamBlack)
	end
	local plate = box(m, "NamePlate", Vector3.new(0.2, 1.1, 5.5), at(-7, 8.4, -2), Color3.new(1, 1, 1))
	for _, face in { Enum.NormalId.Right, Enum.NormalId.Left } do
		text(plate, face, name, Color3.new(0, 0, 0), Color3.new(1, 1, 1))
	end
	-- glass shelter: back wall, two side panes, roof, bench
	box(
		m,
		"Back",
		Vector3.new(10, 7.5, 0.3),
		at(0, 3.75 + 0.2, 2.5),
		Color3.fromRGB(170, 200, 215),
		Enum.Material.Glass,
		0.45
	)
	for _, sx in { -1, 1 } do
		box(
			m,
			"Side",
			Vector3.new(0.3, 7.5, 3.6),
			at(sx * 5, 3.95, 0.9),
			Color3.fromRGB(170, 200, 215),
			Enum.Material.Glass,
			0.45
		)
		box(m, "Post", Vector3.new(0.35, 8, 0.35), at(sx * 5, 4, 2.6), FRAME, Enum.Material.Metal)
	end
	box(m, "Roof", Vector3.new(11, 0.4, 4.6), at(0, 8.1, 0.6), FRAME, Enum.Material.Metal)
	local fascia = box(m, "Fascia", Vector3.new(11, 1, 0.2), at(0, 7.6, -1.75), GREEN)
	text(fascia, Enum.NormalId.Front, "🚏 " .. name, Color3.new(1, 1, 1), GREEN)
	box(m, "Bench", Vector3.new(7, 0.4, 1.4), at(0, 1.6, 1.6), Color3.fromRGB(150, 110, 75), Enum.Material.Wood)
	for _, sx in { -3, 3 } do
		box(m, "BenchLeg", Vector3.new(0.3, 1.4, 1), at(sx, 0.7, 1.6), FRAME, Enum.Material.Metal)
	end
	-- the bay: a yellow "BUS" marking on the road edge
	local bay = box(m, "BusBay", Vector3.new(30, 0.05, 0.4), at(0, 0.05, -4.5), YELLOW, Enum.Material.SmoothPlastic)
	bay.CanCollide = false
	m.Parent = parent
end

function BusStopService.Build()
	local folder = Instance.new("Folder")
	folder.Name = "BusStops"
	for i, s in BusStopData do
		local name, x, z, face = s[1] :: string, s[2] :: number, s[3] :: number, s[4] :: number
		local y = CityBuilder.GroundY(x, z)
		-- facing: the stop looks at the road (-Z of the frame points that way)
		local a = math.rad(face)
		local look = Vector3.new(math.cos(a), 0, math.sin(a))
		local pos = Vector3.new(x, y, z)
		local cf = CFrame.lookAt(pos, pos + look)
		build(folder, name, cf)
		table.insert(BusStopService.Stops, { index = i, name = name, pos = pos + look * 10 })
	end
	folder.Parent = Workspace
end

-- the closest stop to a position (within maxDist studs, ignoring height)
function BusStopService.Nearest(pos: Vector3, maxDist: number): Stop?
	local best, bestD = nil, maxDist
	for _, s in BusStopService.Stops do
		local d = ((s.pos - pos) * Vector3.new(1, 0, 1)).Magnitude
		if d < bestD then
			best, bestD = s, d
		end
	end
	return best
end

return BusStopService
