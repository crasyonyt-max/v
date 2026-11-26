--!strict
-- V1.0 weapons. Police on duty carry the service pistol; civilians buy weapons at the
-- black market (Schwarzmarkt). Shooting is checked by the server.
-- Config.Guns2 ("test" = testing server only): real gun models held in the hand (shots
-- come out of the muzzle), and the AK-47, the sniper rifle and grenades.

local Weapons = {}

export type Weapon = {
	id: string,
	name: string,
	damage: number,
	rate: number, -- seconds between shots
	mag: number,
	reload: number, -- seconds
	range: number, -- studs
	price: number?, -- black market (nil = not for sale)
	auto: boolean?, -- hold to keep firing
	scope: boolean?, -- zoom
	grenade: boolean?, -- thrown, explodes after `fuse`
	radius: number?, -- grenade: damage radius (studs)
	fuse: number?, -- grenade: seconds
	maxCount: number?, -- grenade: how many you can carry
	new: boolean?, -- part of Config.Guns2
}

Weapons.List = {
	{ id = "service_pistol", name = "Dienstpistole P99", damage = 25, rate = 0.3, mag = 15, reload = 1.8, range = 320 },
	{ id = "pistol", name = "Pistole", damage = 20, rate = 0.4, mag = 12, reload = 2.2, range = 260, price = 8000 },
	{
		id = "ak47",
		name = "AK-47",
		damage = 16,
		rate = 0.11,
		mag = 30,
		reload = 2.6,
		range = 340,
		price = 25000,
		auto = true,
		new = true,
	},
	{
		id = "sniper",
		name = "Scharfschützengewehr",
		damage = 95,
		rate = 1.6,
		mag = 5,
		reload = 3.2,
		range = 1100,
		price = 40000,
		scope = true,
		new = true,
	},
	{
		id = "grenade",
		name = "Granate",
		damage = 85,
		rate = 1.2,
		mag = 1,
		reload = 0,
		range = 90,
		price = 1500,
		grenade = true,
		radius = 16,
		fuse = 2.5,
		maxCount = 5,
		new = true,
	},
} :: { Weapon }

Weapons.ById = {} :: { [string]: Weapon }
for _, w in Weapons.List do
	Weapons.ById[w.id] = w
end

-- Models ---------------------------------------------------------------------------
-- Built from parts around the hand grip: "Handle" (the grip, origin), the barrel
-- points to -Z, the top is +Y (that is how a Tool is held with its default Grip).
-- "Muzzle" attachment = where the shots come out. Nothing collides, nothing has mass.

local BLACK = Color3.fromRGB(28, 28, 30)
local STEEL = Color3.fromRGB(62, 64, 68)
local WOOD = Color3.fromRGB(128, 78, 42)
local OLIVE = Color3.fromRGB(70, 82, 48)

local function part(
	m: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = m
	return p
end

-- a cylinder along Z (barrels, scopes)
local function tube(
	m: Model,
	name: string,
	d: number,
	len: number,
	at: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	return part(
		m,
		name,
		Vector3.new(len, d, d),
		CFrame.new(at) * CFrame.Angles(0, math.pi / 2, 0),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

local function muzzle(p: BasePart, at: Vector3)
	local a = Instance.new("Attachment")
	a.Name = "Muzzle"
	a.Position = p.CFrame:PointToObjectSpace(at)
	a.Parent = p
end

local builders: { [string]: (Model) -> () } = {}

builders.pistol = function(m)
	part(
		m,
		"Handle",
		Vector3.new(0.24, 0.62, 0.34),
		CFrame.new(0, -0.05, 0.05) * CFrame.Angles(math.rad(-12), 0, 0),
		BLACK,
		Enum.Material.SmoothPlastic
	)
	local slide = part(m, "Slide", Vector3.new(0.24, 0.26, 1.05), CFrame.new(0, 0.36, -0.28), STEEL)
	part(m, "Frame", Vector3.new(0.22, 0.14, 0.8), CFrame.new(0, 0.2, -0.22), BLACK, Enum.Material.SmoothPlastic)
	part(
		m,
		"TriggerGuard",
		Vector3.new(0.06, 0.18, 0.28),
		CFrame.new(0, 0.06, -0.25),
		BLACK,
		Enum.Material.SmoothPlastic
	)
	part(m, "Sight", Vector3.new(0.06, 0.06, 0.06), CFrame.new(0, 0.51, -0.75), BLACK)
	tube(m, "Barrel", 0.1, 0.08, Vector3.new(0, 0.36, -0.82), BLACK)
	muzzle(slide, Vector3.new(0, 0.36, -0.86))
end
builders.service_pistol = builders.pistol

builders.ak47 = function(m)
	part(
		m,
		"Handle",
		Vector3.new(0.22, 0.6, 0.3),
		CFrame.new(0, -0.05, 0.06) * CFrame.Angles(math.rad(-18), 0, 0),
		BLACK,
		Enum.Material.SmoothPlastic
	)
	local receiver = part(m, "Receiver", Vector3.new(0.26, 0.34, 1.3), CFrame.new(0, 0.34, -0.3), STEEL)
	part(m, "DustCover", Vector3.new(0.24, 0.1, 1.1), CFrame.new(0, 0.55, -0.25), STEEL)
	part(m, "Handguard", Vector3.new(0.3, 0.3, 0.75), CFrame.new(0, 0.33, -1.3), WOOD, Enum.Material.Wood)
	part(m, "GasTube", Vector3.new(0.14, 0.12, 0.7), CFrame.new(0, 0.55, -1.3), WOOD, Enum.Material.Wood)
	tube(m, "Barrel", 0.11, 1.2, Vector3.new(0, 0.37, -2.15), BLACK)
	part(m, "FrontSight", Vector3.new(0.06, 0.2, 0.08), CFrame.new(0, 0.52, -2.55), BLACK)
	tube(m, "MuzzleBrake", 0.15, 0.18, Vector3.new(0, 0.37, -2.8), BLACK)
	-- the curved magazine (two pieces) and the wooden stock
	part(
		m,
		"Magazine",
		Vector3.new(0.18, 0.5, 0.32),
		CFrame.new(0, -0.02, -0.62) * CFrame.Angles(math.rad(12), 0, 0),
		Color3.fromRGB(150, 70, 30),
		Enum.Material.SmoothPlastic
	)
	part(
		m,
		"Magazine",
		Vector3.new(0.18, 0.4, 0.3),
		CFrame.new(0, -0.38, -0.52) * CFrame.Angles(math.rad(30), 0, 0),
		Color3.fromRGB(150, 70, 30),
		Enum.Material.SmoothPlastic
	)
	part(m, "TriggerGuard", Vector3.new(0.06, 0.16, 0.3), CFrame.new(0, 0.1, -0.24), BLACK)
	part(
		m,
		"Stock",
		Vector3.new(0.22, 0.34, 1.1),
		CFrame.new(0, 0.18, 0.85) * CFrame.Angles(math.rad(8), 0, 0),
		WOOD,
		Enum.Material.Wood
	)
	part(m, "Butt", Vector3.new(0.24, 0.5, 0.12), CFrame.new(0, 0.12, 1.4), BLACK, Enum.Material.SmoothPlastic)
	muzzle(receiver, Vector3.new(0, 0.37, -2.9))
end

builders.sniper = function(m)
	part(
		m,
		"Handle",
		Vector3.new(0.22, 0.6, 0.3),
		CFrame.new(0, -0.05, 0.06) * CFrame.Angles(math.rad(-15), 0, 0),
		BLACK,
		Enum.Material.SmoothPlastic
	)
	local body =
		part(m, "Body", Vector3.new(0.28, 0.32, 1.6), CFrame.new(0, 0.32, -0.45), OLIVE, Enum.Material.SmoothPlastic)
	part(m, "Forend", Vector3.new(0.3, 0.28, 1.0), CFrame.new(0, 0.3, -1.55), OLIVE, Enum.Material.SmoothPlastic)
	tube(m, "Barrel", 0.12, 2.0, Vector3.new(0, 0.36, -2.6), BLACK)
	tube(m, "Suppressor", 0.2, 0.5, Vector3.new(0, 0.36, -3.8), BLACK)
	-- scope with lenses and mounts
	tube(m, "Scope", 0.26, 1.3, Vector3.new(0, 0.82, -0.55), BLACK)
	tube(m, "ScopeFront", 0.34, 0.25, Vector3.new(0, 0.82, -1.25), BLACK)
	tube(m, "ScopeBack", 0.3, 0.2, Vector3.new(0, 0.82, 0.1), BLACK)
	part(
		m,
		"Lens",
		Vector3.new(0.02, 0.28, 0.28),
		CFrame.new(0, 0.82, -1.38) * CFrame.Angles(0, math.pi / 2, 0),
		Color3.fromRGB(90, 160, 220),
		Enum.Material.Glass,
		Enum.PartType.Cylinder
	).Reflectance =
		0.4
	for _, z in { -0.9, -0.2 } do
		part(m, "Mount", Vector3.new(0.12, 0.3, 0.12), CFrame.new(0, 0.6, z), BLACK)
	end
	part(m, "Bolt", Vector3.new(0.25, 0.08, 0.08), CFrame.new(0.2, 0.42, 0.05), STEEL)
	part(m, "Magazine", Vector3.new(0.18, 0.32, 0.4), CFrame.new(0, 0.02, -0.65), BLACK)
	part(m, "Stock", Vector3.new(0.24, 0.42, 1.2), CFrame.new(0, 0.2, 0.9), OLIVE, Enum.Material.SmoothPlastic)
	part(m, "CheekRest", Vector3.new(0.22, 0.12, 0.6), CFrame.new(0, 0.46, 0.85), OLIVE, Enum.Material.SmoothPlastic)
	-- folded bipod
	for _, x in { -0.08, 0.08 } do
		part(m, "Bipod", Vector3.new(0.05, 0.05, 0.7), CFrame.new(x, 0.12, -1.75), BLACK)
	end
	muzzle(body, Vector3.new(0, 0.36, -4.06))
end

builders.grenade = function(m)
	part(
		m,
		"Handle",
		Vector3.new(0.62, 0.62, 0.62),
		CFrame.new(0, 0.1, 0),
		OLIVE,
		Enum.Material.Slate,
		Enum.PartType.Ball
	)
	part(m, "Top", Vector3.new(0.24, 0.18, 0.24), CFrame.new(0, 0.46, 0), STEEL)
	part(m, "Lever", Vector3.new(0.08, 0.5, 0.12), CFrame.new(0, 0.3, 0.3) * CFrame.Angles(math.rad(-15), 0, 0), STEEL)
	part(
		m,
		"Ring",
		Vector3.new(0.04, 0.22, 0.22),
		CFrame.new(0.16, 0.52, -0.05),
		Color3.fromRGB(200, 200, 205),
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
end

-- a fresh weapon model (nil for unknown ids); PrimaryPart = "Handle" at the origin
function Weapons.BuildModel(id: string): Model?
	local build = builders[id]
	if not build then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = id
	build(m)
	m.PrimaryPart = m:FindFirstChild("Handle") :: BasePart
	return m
end

-- weapons that exist right now (Config.Guns2 off: only the pistols)
function Weapons.Enabled(id: string, newOn: boolean): boolean
	local w = Weapons.ById[id]
	return w ~= nil and (newOn or not w.new)
end

return Weapons
