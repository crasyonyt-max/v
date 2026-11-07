--!strict
-- Walk-in stores at real Dortmund locations (Locations.Stores): the ground floor of the
-- real building becomes a shop with glass front, door, shelves, coolers, a checkout and
-- an NPC cashier; the floors above stay. Arol petrol stations get a cashier kiosk.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Items = require(ReplicatedStorage.Shared.Items)
local Locations = require(ReplicatedStorage.Shared.Locations)
local CityBuilder = require(script.Parent.CityBuilder)
local Interaction = require(script.Parent.InteractionService)

local StoreBuilder = {}

local FACADE = Color3.fromRGB(222, 214, 198)
local TILE = Color3.fromRGB(226, 223, 216)
local SHELF = Color3.fromRGB(205, 208, 212)
local GLASS = Color3.fromRGB(150, 180, 200)
local PRODUCT_COLORS = {
	Color3.fromRGB(200, 40, 40),
	Color3.fromRGB(240, 190, 40),
	Color3.fromRGB(40, 120, 200),
	Color3.fromRGB(60, 160, 80),
	Color3.fromRGB(240, 240, 235),
	Color3.fromRGB(150, 90, 50),
	Color3.fromRGB(230, 120, 30),
	Color3.fromRGB(120, 60, 150),
}

local rng = Random.new(4401)

local function box(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	props: { [string]: any }?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function signText(part: BasePart, face: Enum.NormalId, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0.3
	gui.Parent = part
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = color
	l.Text = text
	l.Parent = gui
end

-- NPC built from a HumanoidDescription; anchored, can't be pushed.
local function npc(parent: Instance, name: string, cf: CFrame, shirt: Color3): Model?
	local ok, model = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		local skins = {
			Color3.fromRGB(234, 192, 160),
			Color3.fromRGB(198, 150, 110),
			Color3.fromRGB(140, 95, 65),
			Color3.fromRGB(245, 210, 180),
		}
		local skin = skins[rng:NextInteger(1, #skins)]
		desc.HeadColor = skin
		desc.LeftArmColor = skin
		desc.RightArmColor = skin
		desc.TorsoColor = shirt
		desc.LeftLegColor = Color3.fromRGB(40, 42, 50)
		desc.RightLegColor = Color3.fromRGB(40, 42, 50)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		return nil
	end
	local m = model :: Model
	m.Name = name
	local hum = m:FindFirstChildOfClass("Humanoid")
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then
		m:Destroy()
		return nil
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.BreakJointsOnDeath = false
	hum.MaxHealth = math.huge
	hum.Health = math.huge
	root.Anchored = true
	local height = hum.HipHeight + root.Size.Y / 2
	m:PivotTo(cf * CFrame.new(0, height, 0))
	m.Parent = parent
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(120, 26)
	tag.StudsOffset = Vector3.new(0, 3, 0)
	tag.MaxDistance = 45
	tag.Parent = m:FindFirstChild("Head")
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
	l.Text = name
	l.Parent = tag
	return m
end

local function shopMarker(parent: Instance, kind: string, cf: CFrame, title: string)
	local p = box(parent, "Marker_Store", Vector3.new(2, 2, 2), cf * CFrame.new(0, 2.5, 0), Color3.new(1, 1, 1), nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	Interaction.Mark(
		p,
		"Store",
		{ Store = kind, UI = "Store", Arg = kind, ActionText = "Einkaufen", ObjectText = title }
	)
end

-- One store in the ground floor of a real building.
local function buildStore(root: Instance, s: any)
	local def = Items.Stores[s.kind]
	if not def then
		return
	end
	local folder = Instance.new("Model")
	folder.Name = s.name
	folder.Parent = root

	local W, D = s.width, s.depth
	local yaw = CFrame.Angles(0, math.rad(s.yaw), 0)
	local center = CFrame.new(s.x, 0, s.z) * yaw
	local door = center * CFrame.new(0, 0, -D / 2 - 4)
	local floorY = CityBuilder.GroundY(door.Position.X, door.Position.Z) + 0.05
	local top = math.max(s.top, floorY + 13)
	local H = math.min(16, top - floorY)
	local base = CFrame.new(s.x, floorY, s.z) * yaw -- local origin on the floor

	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end

	-- shell
	box(folder, "Floor", Vector3.new(W, 0.4, D), at(0, -0.2, 0), TILE, Enum.Material.Marble)
	box(folder, "Ceiling", Vector3.new(W, 0.8, D), at(0, H - 0.4, 0), Color3.fromRGB(240, 240, 238))
	local T = 1
	box(folder, "WallBack", Vector3.new(W, H, T), at(0, H / 2, D / 2 - T / 2), FACADE, Enum.Material.Concrete)
	box(folder, "WallLeft", Vector3.new(T, H, D), at(-W / 2 + T / 2, H / 2, 0), FACADE, Enum.Material.Concrete)
	box(folder, "WallRight", Vector3.new(T, H, D), at(W / 2 - T / 2, H / 2, 0), FACADE, Enum.Material.Concrete)
	-- glass shop front with a door opening in the middle
	local doorW, doorH = 8, 10
	local side = (W - doorW) / 2
	for _, sgn in { -1, 1 } do
		box(
			folder,
			"ShopWindow",
			Vector3.new(side, H - 4, 0.4),
			at(sgn * (doorW / 2 + side / 2), (H - 4) / 2, -D / 2 + 0.2),
			GLASS,
			Enum.Material.Glass,
			{ Transparency = 0.55 }
		)
		box(
			folder,
			"Mullion",
			Vector3.new(0.4, H - 4, 0.6),
			at(sgn * (doorW / 2 + 0.2), (H - 4) / 2, -D / 2 + 0.2),
			Color3.fromRGB(70, 72, 76),
			Enum.Material.Metal
		)
	end
	box(
		folder,
		"DoorHeader",
		Vector3.new(doorW, H - doorH, 0.6),
		at(0, doorH + (H - doorH) / 2, -D / 2 + 0.2),
		Color3.fromRGB(70, 72, 76),
		Enum.Material.Metal
	)
	local fascia = box(folder, "Fascia", Vector3.new(W, 4, 1), at(0, H - 2, -D / 2 - 0.3), def.color)
	signText(fascia, Enum.NormalId.Front, def.title, Color3.new(1, 1, 1))
	box(
		folder,
		"Doormat",
		Vector3.new(doorW, 0.06, 4),
		at(0, 0.03, -D / 2 + 2.5),
		Color3.fromRGB(50, 50, 55),
		Enum.Material.Fabric,
		{ CanCollide = false }
	)

	-- floors above stay (as a solid block, like the rest of the city)
	if top > floorY + H + 2 then
		box(
			folder,
			"UpperFloors",
			Vector3.new(W, top - floorY - H, D),
			at(0, H + (top - floorY - H) / 2, 0),
			FACADE,
			Enum.Material.Concrete
		)
	end

	-- lights
	local cols = math.max(1, math.floor(W / 18))
	local rows = math.max(1, math.floor(D / 18))
	for i = 1, cols do
		for j = 1, rows do
			local lx = -W / 2 + W * (i - 0.5) / cols
			local lz = -D / 2 + D * (j - 0.5) / rows
			local lamp = box(
				folder,
				"Lamp",
				Vector3.new(4, 0.2, 1.2),
				at(lx, H - 0.9, lz),
				Color3.fromRGB(255, 252, 240),
				Enum.Material.Neon,
				{ CanCollide = false }
			)
			local light = Instance.new("PointLight")
			light.Range = 26
			light.Brightness = 1.2
			light.Color = Color3.fromRGB(255, 248, 235)
			light.Shadows = false
			light.Parent = lamp
		end
	end

	-- checkout near the door (left side), cashier behind it facing the aisle
	local cx, cz = -W / 2 + 7, -D / 2 + 9
	box(folder, "Checkout", Vector3.new(2.4, 3.2, 7), at(cx, 1.6, cz), Color3.fromRGB(70, 74, 80))
	box(folder, "Belt", Vector3.new(1.6, 0.1, 6), at(cx, 3.25, cz), Color3.fromRGB(25, 25, 25), Enum.Material.Rubber)
	box(folder, "Register", Vector3.new(1.2, 1.1, 1.2), at(cx, 3.8, cz + 2.4), Color3.fromRGB(30, 30, 32))
	local cashierCf = at(cx - 2.6, 0, cz) * CFrame.Angles(0, math.rad(-90), 0)
	npc(folder, if rng:NextNumber() < 0.5 then "Kassiererin" else "Kassierer", cashierCf, def.color)
	shopMarker(folder, s.kind, at(cx + 2.8, 0, cz), def.title)

	-- interior by store type
	local isMarket = s.kind == "Rewo" or s.kind == "Lindl" or s.kind == "Alda"
	if isMarket then
		-- coolers along the back wall
		box(folder, "Cooler", Vector3.new(W - 4, 7, 2.4), at(0, 3.5, D / 2 - 2.2), Color3.fromRGB(235, 238, 240))
		box(
			folder,
			"CoolerGlass",
			Vector3.new(W - 4.4, 5.6, 0.2),
			at(0, 3.8, D / 2 - 3.5),
			Color3.fromRGB(190, 220, 240),
			Enum.Material.Glass,
			{ Transparency = 0.5 }
		)
		-- shelf rows
		local first = -W / 2 + 15
		local x = first
		while x < W / 2 - 4 do
			local len = math.max(8, D - 24)
			local z0 = -D / 2 + 15 + len / 2
			box(folder, "Shelf", Vector3.new(2.6, 6.5, len), at(x, 3.25, z0), SHELF, Enum.Material.Metal)
			for level = 1, 3 do
				for _, sgn in { -1, 1 } do
					local c = PRODUCT_COLORS[rng:NextInteger(1, #PRODUCT_COLORS)]
					box(
						folder,
						"Products",
						Vector3.new(0.5, 1.2, len - 0.6),
						at(x + sgn * 1.55, 0.9 + level * 1.8, z0),
						c,
						nil,
						{ CanCollide = false }
					)
				end
			end
			x += 9
		end
	else
		-- bakery / kiosk: display counter across the room
		box(
			folder,
			"Counter",
			Vector3.new(W - 8, 3.4, 2.4),
			at(0, 1.7, D * 0.1),
			Color3.fromRGB(150, 110, 70),
			Enum.Material.Wood
		)
		box(
			folder,
			"Display",
			Vector3.new(W - 8.4, 1.6, 2.2),
			at(0, 4.2, D * 0.1),
			Color3.fromRGB(200, 225, 240),
			Enum.Material.Glass,
			{ Transparency = 0.5 }
		)
		for i = 1, math.floor((W - 10) / 3) do
			local c = if s.kind == "Baeckerei"
				then Color3.fromRGB(200 + rng:NextInteger(-20, 20), 140 + rng:NextInteger(-20, 20), 70)
				else PRODUCT_COLORS[rng:NextInteger(1, #PRODUCT_COLORS)]
			box(
				folder,
				"Goods",
				Vector3.new(1.6, 0.6, 1.2),
				at(-W / 2 + 6 + i * 3, 3.7, D * 0.1),
				c,
				nil,
				{ CanCollide = false }
			)
		end
		box(
			folder,
			"BackShelf",
			Vector3.new(W - 4, 8, 1.6),
			at(0, 4, D / 2 - 1.8),
			Color3.fromRGB(160, 120, 80),
			Enum.Material.Wood
		)
	end
end

-- Arol: a small cashier kiosk next to the pumps, placed where there is room.
local function buildArolKiosk(root: Instance, x: number, z: number, index: number)
	local city = Workspace:FindFirstChild("City")
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { city and city:FindFirstChild("Buildings") or Workspace.Terrain }
	local spot: CFrame? = nil
	for _, off in { Vector3.new(16, 0, 0), Vector3.new(-16, 0, 0), Vector3.new(0, 0, 16), Vector3.new(0, 0, -16) } do
		local pos = Vector3.new(x, 0, z) + off
		local y = CityBuilder.GroundY(pos.X, pos.Z)
		local cf = CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(x, y, z))
		if #Workspace:GetPartBoundsInBox(cf * CFrame.new(0, 6, 0), Vector3.new(14, 10, 12), params) == 0 then
			spot = cf
			break
		end
	end
	if not spot then
		return
	end
	local m = Instance.new("Model")
	m.Name = "Arol Shop " .. index
	m.Parent = root
	local base = spot :: CFrame
	box(m, "Floor", Vector3.new(14, 0.4, 12), base * CFrame.new(0, -0.2, 0), TILE, Enum.Material.Marble)
	box(m, "Roof", Vector3.new(16, 0.8, 14), base * CFrame.new(0, 10.4, 0), Color3.fromRGB(0, 70, 160))
	box(m, "Back", Vector3.new(14, 10, 0.8), base * CFrame.new(0, 5, 5.6), Color3.fromRGB(240, 240, 240))
	box(m, "Left", Vector3.new(0.8, 10, 12), base * CFrame.new(-6.6, 5, 0), Color3.fromRGB(240, 240, 240))
	box(m, "Right", Vector3.new(0.8, 10, 12), base * CFrame.new(6.6, 5, 0), Color3.fromRGB(240, 240, 240))
	box(
		m,
		"FrontGlassL",
		Vector3.new(4, 9, 0.3),
		base * CFrame.new(-4.6, 4.5, -5.8),
		GLASS,
		Enum.Material.Glass,
		{ Transparency = 0.5 }
	)
	box(
		m,
		"FrontGlassR",
		Vector3.new(4, 9, 0.3),
		base * CFrame.new(4.6, 4.5, -5.8),
		GLASS,
		Enum.Material.Glass,
		{ Transparency = 0.5 }
	)
	local fascia =
		box(m, "Fascia", Vector3.new(16, 2.4, 0.6), base * CFrame.new(0, 9.6, -7.2), Color3.fromRGB(0, 70, 160))
	signText(fascia, Enum.NormalId.Front, "AROL", Color3.new(1, 1, 1))
	box(m, "Counter", Vector3.new(8, 3.4, 2), base * CFrame.new(0, 1.7, 1.6), Color3.fromRGB(70, 74, 80))
	npc(m, "Kassierer", base * CFrame.new(0, 0, 3.6) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(0, 70, 160))
	shopMarker(m, "Arol", base * CFrame.new(0, 0, -1), "AROL Shop")
	local lamp =
		box(m, "Lamp", Vector3.new(4, 0.2, 1), base * CFrame.new(0, 9.8, 0), Color3.new(1, 1, 1), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Parent = lamp
end

-- Salespeople at Handyland and the car dealership (decorative, the marker opens the shop).
local function salesperson(root: Instance, loc: any, title: string, shirt: Color3)
	local x, z = loc.marker[1], loc.marker[2]
	local y = CityBuilder.GroundY(x, z)
	local dir = Vector3.new(math.cos(math.rad(loc.angle)), 0, math.sin(math.rad(loc.angle)))
	local pos = Vector3.new(x, y, z) + dir * 4
	npc(root, title, CFrame.lookAt(pos, Vector3.new(x, y, z)), shirt)
end

function StoreBuilder.Build()
	local root = Instance.new("Folder")
	root.Name = "Stores"
	root.Parent = Workspace
	for _, s in Locations.Stores do
		local ok, err = pcall(buildStore, root, s)
		if not ok then
			warn("[Stores] " .. s.name .. ": " .. tostring(err))
		end
	end
	for i, f in Locations.Fuel do
		pcall(buildArolKiosk, root, f[1], f[2], i)
	end
	local shops = Locations.Shops :: any
	pcall(salesperson, root, shops.Handyland, "Verkäuferin", Color3.fromRGB(0, 110, 220))
	pcall(salesperson, root, shops.Dealership, "Autoverkäufer", Color3.fromRGB(30, 30, 35))
end

return StoreBuilder
