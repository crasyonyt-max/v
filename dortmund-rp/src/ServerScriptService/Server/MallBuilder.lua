--!strict
-- "Dortmund Mall": a shopping tower on Locations.Sites.Mall. Walk in through the
-- front; every floor has four shops around a central hall, an NPC at each counter
-- and a lift. Ground floor: dealership + Handyland branches, supermarket, bakery.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Items = require(ReplicatedStorage.Shared.Items)
local Locations = require(ReplicatedStorage.Shared.Locations)
local CityBuilder = require(script.Parent.CityBuilder)
local Interaction = require(script.Parent.InteractionService)
local StoreBuilder = require(script.Parent.StoreBuilder)

local MallBuilder = {}

local FH = 18 -- floor height
local FLOORS = 4
local W, D = 140, 140

-- per floor: four shops (front-left, front-right, back-left, back-right)
-- kind = a store of Items.Stores, or "Dealership" / "Handyland" (special shops)
local LAYOUT = {
	{ "Dealership", "Handyland", "Rewo", "Baeckerei" },
	{ "Lindl", "Alda", "Kiosk", "Baeckerei" },
	{ "Rewo", "Kiosk", "Alda", "Lindl" },
	{ "Arol", "Baeckerei", "Kiosk", "Rewo" },
}

local SPECIAL = {
	Dealership = { title = "AUTOHAUS", color = Color3.fromRGB(40, 40, 46), action = "Autohaus" },
	Handyland = { title = "HANDYLAND", color = Color3.fromRGB(0, 110, 220), action = "Handys ansehen" },
}

MallBuilder.Spots = {} :: { [number]: CFrame } -- lift arrival per floor (0 = ground)

local GLASS = Color3.fromRGB(110, 140, 160)
local WALL = Color3.fromRGB(214, 210, 202)
local DARK = Color3.fromRGB(40, 42, 46)

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
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function sign(p: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = if bg then 0 else 1
	l.BackgroundColor3 = bg or Color3.new()
	l.TextScaled = true
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = color
	l.Text = text
	l.Parent = gui
end

local function lamp(parent: Instance, cf: CFrame)
	local p = box(
		parent,
		"Lamp",
		Vector3.new(6, 0.3, 2),
		cf,
		Color3.fromRGB(245, 242, 230),
		Enum.Material.Glass,
		{ CanCollide = false }
	)
	local l = Instance.new("PointLight")
	l.Range = 28
	l.Brightness = 0.7
	l.Color = Color3.fromRGB(255, 238, 215)
	l.Parent = p
end

-- one shop unit: open front to the hall, sign, counter with cashier, shelves
local function shop(
	m: Instance,
	at: (number, number, number) -> CFrame,
	kind: string,
	cx: number,
	cz: number,
	y: number,
	facing: number
)
	local special = SPECIAL[kind]
	local store = Items.Stores[kind]
	local title = if special then special.title elseif store then store.title else kind
	local color = if special then special.color elseif store and store.color then store.color else DARK
	local w, d = 44, 40
	-- local frame of the unit: -Z (front) looks into the central hall
	local function u(x: number, yy: number, z: number): CFrame
		return at(cx, y, cz) * CFrame.Angles(0, facing, 0) * CFrame.new(x, yy, z)
	end
	box(m, "ShopBack", Vector3.new(w, FH - 1, 0.8), u(0, (FH - 1) / 2, d / 2), WALL)
	for _, sx in { -1, 1 } do
		box(m, "ShopSide", Vector3.new(0.8, FH - 1, d), u(sx * w / 2, (FH - 1) / 2, 0), WALL)
	end
	local signPart = box(m, "ShopSign", Vector3.new(w - 6, 3, 0.4), u(0, FH - 4, -d / 2), color)
	sign(signPart, Enum.NormalId.Front, title, Color3.new(1, 1, 1))
	-- counter + cashier
	box(
		m,
		"Counter",
		Vector3.new(10, 3.4, 3),
		u(-w / 4, 1.7, -d / 2 + 10),
		Color3.fromRGB(150, 110, 75),
		Enum.Material.Wood
	)
	pcall(StoreBuilder.Npc, m, title, u(-w / 4, 0, -d / 2 + 13) * CFrame.Angles(0, math.pi, 0), color)
	-- shelves
	for i = -1, 1 do
		box(m, "Shelf", Vector3.new(2.4, 6, 14), u(w / 6 + i * 7, 3, 4), Color3.fromRGB(235, 235, 235))
		box(m, "Goods", Vector3.new(2.6, 0.8, 13), u(w / 6 + i * 7, 4.6, 4), color:Lerp(Color3.new(1, 1, 1), 0.3))
	end
	lamp(m, u(0, FH - 1.6, 0))
	-- the marker opens the right shop window (same as everywhere else in the city)
	local spot = u(-w / 4, 0, -d / 2 + 6)
	if special then
		local p = box(m, "Marker_Shop", Vector3.new(2, 2, 2), spot * CFrame.new(0, 2.5, 0), Color3.new(1, 1, 1), nil, {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		Interaction.Mark(p, "Shop", { UI = kind, ActionText = special.action, ObjectText = title .. " (Mall)" })
	else
		StoreBuilder.ShopMarker(m, kind, spot, title)
	end
end

function MallBuilder.Build()
	local site = (Locations.Sites :: any).Mall
	if not site then
		return
	end
	local y0 = CityBuilder.GroundY(site.x, site.z) + 0.05
	local origin = CFrame.new(site.x, y0, site.z) * CFrame.Angles(0, math.rad(site.yaw), 0)
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end
	local root = Instance.new("Model")
	root.Name = "Dortmund Mall"

	local H = FLOORS * FH
	-- facade: glass between concrete columns, entrance gap in the front
	for i = -3, 3 do
		for _, sz in { -1, 1 } do
			box(
				root,
				"Column",
				Vector3.new(3, H + 4, 3),
				at(i * (W / 6), (H + 4) / 2, sz * (D / 2)),
				DARK,
				Enum.Material.Concrete
			)
		end
		for _, sx in { -1, 1 } do
			box(
				root,
				"Column",
				Vector3.new(3, H + 4, 3),
				at(sx * (W / 2), (H + 4) / 2, i * (D / 6)),
				DARK,
				Enum.Material.Concrete
			)
		end
	end
	local door = 24
	for f = 0, FLOORS - 1 do
		local y = f * FH
		box(root, "Floor", Vector3.new(W, 1, D), at(0, y - 0.5, 0), Color3.fromRGB(225, 222, 216), Enum.Material.Marble)
		-- back + sides
		box(
			root,
			"Glass",
			Vector3.new(W, FH, 1),
			at(0, y + FH / 2, D / 2),
			GLASS,
			Enum.Material.Glass,
			{ Transparency = 0.3 }
		)
		for _, sx in { -1, 1 } do
			box(
				root,
				"Glass",
				Vector3.new(1, FH, D),
				at(sx * W / 2, y + FH / 2, 0),
				GLASS,
				Enum.Material.Glass,
				{ Transparency = 0.3 }
			)
		end
		-- front (ground floor: open entrance in the middle)
		if f == 0 then
			local side = (W - door) / 2
			for _, sx in { -1, 1 } do
				box(
					root,
					"Glass",
					Vector3.new(side, FH, 1),
					at(sx * (door / 2 + side / 2), y + FH / 2, -D / 2),
					GLASS,
					Enum.Material.Glass,
					{ Transparency = 0.3 }
				)
			end
			box(root, "EntranceTop", Vector3.new(door, FH - 12, 1), at(0, y + 12 + (FH - 12) / 2, -D / 2), DARK)
		else
			box(
				root,
				"Glass",
				Vector3.new(W, FH, 1),
				at(0, y + FH / 2, -D / 2),
				GLASS,
				Enum.Material.Glass,
				{ Transparency = 0.3 }
			)
		end
		-- four shops around the hall
		local kinds = LAYOUT[f + 1]
		-- (a unit's front is its local -Z; Angles(0, -90°) turns it to +X, i.e. the hall)
		shop(root, at, kinds[1], -W / 4 - 2, -D / 4 + 8, y, math.rad(-90)) -- front-left
		shop(root, at, kinds[2], W / 4 + 2, -D / 4 + 8, y, math.rad(90)) -- front-right
		shop(root, at, kinds[3], -W / 4 - 2, D / 4 + 4, y, math.rad(-90)) -- back-left
		shop(root, at, kinds[4], W / 4 + 2, D / 4 + 4, y, math.rad(90)) -- back-right
		-- hall lights + lift
		lamp(root, at(0, y + FH - 1.6, -20))
		lamp(root, at(0, y + FH - 1.6, 20))
		local lift = box(root, "Lift", Vector3.new(10, 12, 2), at(0, y + 6, D / 2 - 2), DARK, Enum.Material.Metal)
		sign(lift, Enum.NormalId.Front, "🛗 " .. (if f == 0 then "EG" else f .. ". OG"), Color3.fromRGB(255, 200, 80))
		MallBuilder.Spots[f] = at(0, y + 0.5, D / 2 - 10) * CFrame.Angles(0, math.pi, 0)
		local panel =
			box(root, "Marker_Lift", Vector3.new(2, 2, 2), at(-7, y + 3, D / 2 - 3), Color3.new(1, 1, 1), nil, {
				Transparency = 1,
				CanCollide = false,
			})
		Interaction.Mark(panel, "MallLift", { ActionText = "Aufzug", ObjectText = "Dortmund Mall", Floor = f })
	end
	box(root, "Roof", Vector3.new(W + 4, 2, D + 4), at(0, H + 1, 0), DARK, Enum.Material.Concrete)
	local roofSign = box(root, "RoofSign", Vector3.new(80, 12, 1), at(0, H + 8, -D / 2), DARK)
	sign(roofSign, Enum.NormalId.Front, "🛍️ DORTMUND MALL", Color3.fromRGB(255, 205, 70))
	root.Parent = Workspace
end

-- next floor up (wraps to the ground floor) for whoever uses a lift
function MallBuilder.Start()
	Interaction.OnTrigger("MallLift", function(player, marker)
		local f = tonumber(marker:GetAttribute("Floor")) or 0
		local target = MallBuilder.Spots[(f + 1) % FLOORS]
		local c = player.Character
		if c and target then
			c:PivotTo(target + Vector3.new(0, 3, 0))
		end
	end)
end

return MallBuilder
