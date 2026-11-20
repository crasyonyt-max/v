--!strict
-- v0.4 furniture from Swedea (the Swedish furniture store). Every piece is built
-- from parts here, so the server (placed furniture) and the client (the preview
-- in build mode) use the same model. Pivot = bottom centre, front = -Z.

local Furniture = {}

export type Item = {
	id: string,
	name: string,
	kind: string, -- what it is (German), shown under the name
	price: number,
	category: string,
	size: Vector3, -- bounding box (studs)
	color: Color3,
}

local WOOD = Color3.fromRGB(190, 150, 105)
local DARKWOOD = Color3.fromRGB(110, 75, 50)
local WHITE = Color3.fromRGB(240, 240, 238)
local GREY = Color3.fromRGB(120, 122, 128)
local BLACK = Color3.fromRGB(30, 30, 34)
local FABRIC = Color3.fromRGB(70, 90, 120)
local BED = Color3.fromRGB(245, 245, 250)

Furniture.Categories = { "Schlafzimmer", "Wohnzimmer", "Küche", "Bad", "Büro", "Deko", "Garten" }

Furniture.List = {
	-- Schlafzimmer
	{
		id = "bed_single",
		name = "SLÄPPA",
		kind = "Einzelbett",
		price = 900,
		category = "Schlafzimmer",
		size = Vector3.new(5, 3, 9),
		color = WOOD,
	},
	{
		id = "bed_double",
		name = "DRÖMMA",
		kind = "Doppelbett",
		price = 2500,
		category = "Schlafzimmer",
		size = Vector3.new(8, 3.4, 9.5),
		color = DARKWOOD,
	},
	{
		id = "wardrobe",
		name = "GARDEROBSK",
		kind = "Kleiderschrank",
		price = 1500,
		category = "Schlafzimmer",
		size = Vector3.new(7, 9, 2.6),
		color = WHITE,
	},
	{
		id = "nightstand",
		name = "NATTBORD",
		kind = "Nachttisch",
		price = 300,
		category = "Schlafzimmer",
		size = Vector3.new(2, 2.2, 2),
		color = WOOD,
	},
	{
		id = "dresser",
		name = "BYRÅN",
		kind = "Kommode",
		price = 800,
		category = "Schlafzimmer",
		size = Vector3.new(5, 3.6, 2),
		color = WHITE,
	},
	-- Wohnzimmer
	{
		id = "sofa",
		name = "SÖFFA",
		kind = "Sofa",
		price = 1800,
		category = "Wohnzimmer",
		size = Vector3.new(9, 3.4, 3.6),
		color = FABRIC,
	},
	{
		id = "armchair",
		name = "FÅTÖLJ",
		kind = "Sessel",
		price = 700,
		category = "Wohnzimmer",
		size = Vector3.new(3.6, 3.4, 3.6),
		color = FABRIC,
	},
	{
		id = "coffee_table",
		name = "LÅGBORD",
		kind = "Couchtisch",
		price = 400,
		category = "Wohnzimmer",
		size = Vector3.new(5, 1.6, 2.6),
		color = WOOD,
	},
	{
		id = "tv_stand",
		name = "TEVEBÄNK",
		kind = "TV-Board",
		price = 500,
		category = "Wohnzimmer",
		size = Vector3.new(7, 1.8, 1.8),
		color = BLACK,
	},
	{
		id = "tv",
		name = "BILDSKÄRM",
		kind = 'Fernseher 55"',
		price = 1200,
		category = "Wohnzimmer",
		size = Vector3.new(5.4, 3.4, 0.6),
		color = BLACK,
	},
	{
		id = "shelf",
		name = "HYLLA",
		kind = "Regal",
		price = 350,
		category = "Wohnzimmer",
		size = Vector3.new(3, 7, 1.4),
		color = WHITE,
	},
	{
		id = "rug",
		name = "MATTAN",
		kind = "Teppich",
		price = 250,
		category = "Wohnzimmer",
		size = Vector3.new(8, 0.1, 6),
		color = Color3.fromRGB(170, 70, 60),
	},
	-- Küche
	{
		id = "kitchen",
		name = "KÖKSBÄNK",
		kind = "Küchenzeile",
		price = 1500,
		category = "Küche",
		size = Vector3.new(10, 3.4, 2.4),
		color = WHITE,
	},
	{
		id = "fridge",
		name = "KYLSKÅP",
		kind = "Kühlschrank",
		price = 900,
		category = "Küche",
		size = Vector3.new(2.4, 6.4, 2.4),
		color = GREY,
	},
	{
		id = "stove",
		name = "SPISEN",
		kind = "Herd",
		price = 800,
		category = "Küche",
		size = Vector3.new(2.4, 3.4, 2.4),
		color = BLACK,
	},
	{
		id = "dining_table",
		name = "MATBORD",
		kind = "Esstisch",
		price = 600,
		category = "Küche",
		size = Vector3.new(6, 2.8, 3.6),
		color = WOOD,
	},
	{
		id = "chair",
		name = "STOLEN",
		kind = "Stuhl",
		price = 150,
		category = "Küche",
		size = Vector3.new(1.8, 3.6, 1.8),
		color = WOOD,
	},
	-- Bad
	{
		id = "toilet",
		name = "TOALETT",
		kind = "Toilette",
		price = 350,
		category = "Bad",
		size = Vector3.new(1.6, 2.8, 2.4),
		color = WHITE,
	},
	{
		id = "sink",
		name = "HANDFAT",
		kind = "Waschbecken",
		price = 300,
		category = "Bad",
		size = Vector3.new(2.4, 3, 1.6),
		color = WHITE,
	},
	{
		id = "bathtub",
		name = "BADKAR",
		kind = "Badewanne",
		price = 1600,
		category = "Bad",
		size = Vector3.new(3.6, 2, 6.4),
		color = WHITE,
	},
	-- Büro
	{
		id = "desk",
		name = "SKRIVBORD",
		kind = "Schreibtisch",
		price = 450,
		category = "Büro",
		size = Vector3.new(5, 2.6, 2.6),
		color = WHITE,
	},
	{
		id = "office_chair",
		name = "KONTORSTOL",
		kind = "Bürostuhl",
		price = 300,
		category = "Büro",
		size = Vector3.new(2, 3.8, 2),
		color = BLACK,
	},
	-- Deko
	{
		id = "plant",
		name = "GRÖNSAK",
		kind = "Zimmerpflanze",
		price = 120,
		category = "Deko",
		size = Vector3.new(1.6, 4, 1.6),
		color = Color3.fromRGB(60, 130, 60),
	},
	{
		id = "floor_lamp",
		name = "LAMPA",
		kind = "Stehlampe",
		price = 200,
		category = "Deko",
		size = Vector3.new(1.4, 6, 1.4),
		color = BLACK,
	},
	-- Garten
	{
		id = "bbq",
		name = "GRILLA",
		kind = "Grill",
		price = 600,
		category = "Garten",
		size = Vector3.new(2.6, 3.6, 2),
		color = BLACK,
	},
	{
		id = "sunbed",
		name = "SOLSÄNG",
		kind = "Sonnenliege",
		price = 300,
		category = "Garten",
		size = Vector3.new(2.4, 1.6, 6),
		color = WHITE,
	},
} :: { Item }

Furniture.ById = {} :: { [string]: Item }
for _, f in Furniture.List do
	Furniture.ById[f.id] = f
end

Furniture.FREE_BED = "bed_single" -- everyone gets one bed for free

-- does an item rotated by r degrees, standing at (x, y, z) (plot frame), stay inside
-- the area half.X / half.Z wide and maxY high? (server and build preview)
function Furniture.Fits(id: string, x: number, y: number, z: number, r: number, half: Vector3, maxY: number): boolean
	local it = Furniture.ById[id]
	if not it or x ~= x or y ~= y or z ~= z or r ~= r then
		return false
	end
	local a = math.rad(r)
	local ex = math.abs(math.cos(a)) * it.size.X / 2 + math.abs(math.sin(a)) * it.size.Z / 2
	local ez = math.abs(math.sin(a)) * it.size.X / 2 + math.abs(math.cos(a)) * it.size.Z / 2
	return math.abs(x) + ex <= half.X + 0.01
		and math.abs(z) + ez <= half.Z + 0.01
		and y >= -0.5
		and y + it.size.Y <= maxY
end

-- Model ----------------------------------------------------------------------------

local function p(
	m: Model,
	name: string,
	size: Vector3,
	pos: Vector3,
	color: Color3,
	material: Enum.Material?,
	extra: { [string]: any }?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = CFrame.new(pos)
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in extra do
			(part :: any)[k] = v
		end
	end
	part.Parent = m
	return part
end

-- builds at the origin (bottom centre on y = 0)
local builders: { [string]: (Model, Item) -> () } = {
	bed_single = function(m, it)
		local s = it.size
		p(m, "Frame", Vector3.new(s.X, 1.2, s.Z), Vector3.new(0, 0.6, 0), it.color, Enum.Material.Wood)
		p(m, "Mattress", Vector3.new(s.X - 0.4, 0.8, s.Z - 0.6), Vector3.new(0, 1.6, 0.2), BED, Enum.Material.Fabric)
		p(
			m,
			"Pillow",
			Vector3.new(s.X - 1.4, 0.5, 1.4),
			Vector3.new(0, 2.2, s.Z / 2 - 1.2),
			WHITE,
			Enum.Material.Fabric
		)
		p(
			m,
			"Blanket",
			Vector3.new(s.X - 0.2, 0.3, s.Z * 0.55),
			Vector3.new(0, 2.1, -s.Z * 0.2),
			FABRIC,
			Enum.Material.Fabric
		)
		p(m, "Headboard", Vector3.new(s.X, 3, 0.4), Vector3.new(0, 1.5, s.Z / 2 - 0.2), it.color, Enum.Material.Wood)
	end,
	wardrobe = function(m, it)
		local s = it.size
		p(m, "Body", s, Vector3.new(0, s.Y / 2, 0), it.color)
		p(m, "Gap", Vector3.new(0.1, s.Y - 0.4, 0.05), Vector3.new(0, s.Y / 2, -s.Z / 2 - 0.02), GREY)
		for _, x in { -0.4, 0.4 } do
			p(
				m,
				"Handle",
				Vector3.new(0.15, 1.2, 0.15),
				Vector3.new(x, s.Y / 2, -s.Z / 2 - 0.1),
				GREY,
				Enum.Material.Metal
			)
		end
	end,
	sofa = function(m, it)
		local s = it.size
		p(m, "Seat", Vector3.new(s.X, 1.4, s.Z), Vector3.new(0, 0.9, 0), it.color, Enum.Material.Fabric)
		p(m, "Back", Vector3.new(s.X, 2, 0.8), Vector3.new(0, 2.4, s.Z / 2 - 0.4), it.color, Enum.Material.Fabric)
		for _, sx in { -1, 1 } do
			p(
				m,
				"Arm",
				Vector3.new(0.8, 1.2, s.Z),
				Vector3.new(sx * (s.X / 2 - 0.4), 2.2, 0),
				it.color,
				Enum.Material.Fabric
			)
		end
		p(m, "Feet", Vector3.new(s.X - 0.4, 0.2, s.Z - 0.4), Vector3.new(0, 0.1, 0), BLACK)
	end,
	tv = function(m, it)
		local s = it.size
		p(
			m,
			"Screen",
			Vector3.new(s.X, s.Y - 0.6, 0.25),
			Vector3.new(0, 0.6 + (s.Y - 0.6) / 2, 0),
			it.color,
			Enum.Material.Glass
		)
		p(m, "Stand", Vector3.new(1.6, 0.6, 0.6), Vector3.new(0, 0.3, 0), GREY, Enum.Material.Metal)
	end,
	plant = function(m, it)
		p(
			m,
			"Pot",
			Vector3.new(1.4, 1.4, 1.4),
			Vector3.new(0, 0.7, 0),
			Color3.fromRGB(180, 100, 60),
			Enum.Material.Slate
		)
		p(
			m,
			"Leaves",
			Vector3.new(1.6, 2.6, 1.6),
			Vector3.new(0, 2.7, 0),
			it.color,
			Enum.Material.Grass,
			{ Shape = Enum.PartType.Ball }
		)
	end,
	floor_lamp = function(m, it)
		p(m, "Base", Vector3.new(1.2, 0.2, 1.2), Vector3.new(0, 0.1, 0), it.color, Enum.Material.Metal)
		p(m, "Pole", Vector3.new(0.2, 5, 0.2), Vector3.new(0, 2.6, 0), it.color, Enum.Material.Metal)
		local shade = p(
			m,
			"Shade",
			Vector3.new(1.4, 1, 1.4),
			Vector3.new(0, 5.5, 0),
			Color3.fromRGB(250, 240, 220),
			Enum.Material.Neon
		)
		local l = Instance.new("PointLight")
		l.Range = 16
		l.Brightness = 0.7
		l.Color = Color3.fromRGB(255, 230, 200)
		l.Parent = shade
	end,
	chair = function(m, it)
		local s = it.size
		p(m, "Seat", Vector3.new(s.X, 0.3, s.Z), Vector3.new(0, 1.8, 0), it.color, Enum.Material.Wood)
		p(m, "Back", Vector3.new(s.X, 1.8, 0.2), Vector3.new(0, 2.8, s.Z / 2 - 0.1), it.color, Enum.Material.Wood)
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				p(
					m,
					"Leg",
					Vector3.new(0.2, 1.7, 0.2),
					Vector3.new(x * (s.X / 2 - 0.2), 0.85, z * (s.Z / 2 - 0.2)),
					it.color,
					Enum.Material.Wood
				)
			end
		end
	end,
	toilet = function(m, it)
		p(m, "Bowl", Vector3.new(1.4, 1.6, 1.8), Vector3.new(0, 0.8, -0.2), it.color, Enum.Material.Marble)
		p(m, "Tank", Vector3.new(1.6, 2.6, 0.6), Vector3.new(0, 1.3, 0.9), it.color, Enum.Material.Marble)
	end,
	bathtub = function(m, it)
		local s = it.size
		p(m, "Tub", s, Vector3.new(0, s.Y / 2, 0), it.color, Enum.Material.Marble)
		p(
			m,
			"Water",
			Vector3.new(s.X - 0.6, 0.1, s.Z - 0.6),
			Vector3.new(0, s.Y - 0.3, 0),
			Color3.fromRGB(120, 180, 230),
			Enum.Material.Glass,
			{
				Transparency = 0.4,
			}
		)
	end,
	rug = function(m, it)
		p(m, "Rug", it.size, Vector3.new(0, 0.05, 0), it.color, Enum.Material.Fabric, { CanCollide = false })
	end,
}
builders.bed_double = builders.bed_single
builders.armchair = builders.sofa
builders.office_chair = builders.chair

local function table4(m: Model, it: Item)
	local s = it.size
	p(m, "Top", Vector3.new(s.X, 0.3, s.Z), Vector3.new(0, s.Y - 0.15, 0), it.color, Enum.Material.Wood)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			p(
				m,
				"Leg",
				Vector3.new(0.3, s.Y - 0.3, 0.3),
				Vector3.new(x * (s.X / 2 - 0.3), (s.Y - 0.3) / 2, z * (s.Z / 2 - 0.3)),
				it.color,
				Enum.Material.Wood
			)
		end
	end
end
builders.coffee_table = table4
builders.dining_table = table4
builders.desk = table4

local function cabinet(m: Model, it: Item)
	local s = it.size
	p(m, "Body", s, Vector3.new(0, s.Y / 2, 0), it.color)
	p(
		m,
		"Top",
		Vector3.new(s.X + 0.1, 0.2, s.Z + 0.1),
		Vector3.new(0, s.Y + 0.1, 0),
		if it.id == "kitchen" then GREY else it.color,
		Enum.Material.Marble
	)
end
for _, id in { "nightstand", "dresser", "tv_stand", "shelf", "kitchen", "fridge", "stove", "sink", "bbq", "sunbed" } do
	builders[id] = builders[id] or cabinet
end

function Furniture.Build(id: string): Model?
	local it = Furniture.ById[id]
	if not it then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = it.id
	local build = builders[id] or cabinet
	build(m, it)
	-- invisible hitbox = the item's bounding box (pivot at the bottom centre)
	local hit = p(m, "Hitbox", it.size, Vector3.new(0, it.size.Y / 2, 0), it.color, nil, {
		Transparency = 1,
		CanCollide = false,
	})
	m.PrimaryPart = hit
	m.WorldPivot = CFrame.new()
	m:SetAttribute("Furniture", id)
	return m
end

-- puts a freshly built piece (built at the origin) at cf
function Furniture.Place(m: Model, cf: CFrame)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.CFrame = cf * p.CFrame
		end
	end
end

return Furniture
