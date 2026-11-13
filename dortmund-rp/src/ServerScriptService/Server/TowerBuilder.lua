--!strict
-- "Dortmund Tower": 16 floors x 2 furnished apartments (32), lobby with concierge,
-- elevator on every floor, glass facade and roof helipad. Built on Locations.Sites.Tower.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Locations = require(ReplicatedStorage.Shared.Locations)
local CityBuilder = require(script.Parent.CityBuilder)
local Interaction = require(script.Parent.InteractionService)
local StoreBuilder = require(script.Parent.StoreBuilder)

local TowerBuilder = {}

TowerBuilder.FLOORS = 16
TowerBuilder.PER_FLOOR = 2
TowerBuilder.FLOOR_H = 13
TowerBuilder.LOBBY_H = 18

-- frame: centre of the flat at floor level; local -Z = hallway side, +Z = facade
export type Unit = {
	number: number,
	floor: number,
	door: BasePart,
	label: TextLabel,
	inside: CFrame,
	frame: CFrame?,
	w: number?,
	d: number?,
}
TowerBuilder.Units = {} :: { Unit }
TowerBuilder.FloorSpots = {} :: { [number]: CFrame } -- 0 = lobby

local GLASS = Color3.fromRGB(120, 150, 175)
local SLAB = Color3.fromRGB(205, 205, 208)
local WALL = Color3.fromRGB(236, 233, 226)
local WOOD = Color3.fromRGB(165, 125, 85)
local DARK = Color3.fromRGB(45, 46, 50)

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

local function lamp(parent: Instance, cf: CFrame, range: number)
	local p = box(
		parent,
		"Lamp",
		Vector3.new(2.4, 0.2, 2.4),
		cf,
		Color3.fromRGB(255, 250, 238),
		Enum.Material.Neon,
		{ CanCollide = false, Shape = Enum.PartType.Cylinder }
	)
	p.Size = Vector3.new(0.2, 2.4, 2.4)
	p.CFrame = cf * CFrame.Angles(0, 0, math.pi / 2)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = 1
	l.Color = Color3.fromRGB(255, 240, 220)
	l.Shadows = false
	l.Parent = p
end

-- Furnished apartment: local origin = floor centre of the flat, -Z = door side (hallway).
local function furnish(m: Instance, o: CFrame, w: number, d: number, accent: Color3)
	local function at(x: number, y: number, z: number): CFrame
		return o * CFrame.new(x, y, z)
	end
	box(
		m,
		"Parquet",
		Vector3.new(w - 1, 0.1, d - 1),
		at(0, 0.05, 0),
		Color3.fromRGB(176, 136, 96),
		Enum.Material.WoodPlanks,
		{ CanCollide = false }
	)
	-- bedroom corner (back left)
	local bx, bz = -w / 2 + 8, d / 2 - 8
	box(m, "BedFrame", Vector3.new(7, 1.4, 9), at(bx, 0.8, bz), WOOD, Enum.Material.Wood)
	box(m, "Mattress", Vector3.new(6.6, 0.9, 8.6), at(bx, 1.9, bz), Color3.fromRGB(240, 240, 240), Enum.Material.Fabric)
	box(m, "Blanket", Vector3.new(6.7, 0.3, 5.5), at(bx, 2.45, bz - 1.4), accent, Enum.Material.Fabric)
	box(
		m,
		"Pillow",
		Vector3.new(5.5, 0.6, 1.6),
		at(bx, 2.6, bz + 3.3),
		Color3.fromRGB(250, 250, 250),
		Enum.Material.Fabric
	)
	box(m, "Headboard", Vector3.new(7, 4, 0.5), at(bx, 2.5, bz + 4.6), WOOD, Enum.Material.Wood)
	box(m, "Nightstand", Vector3.new(2, 2, 2), at(bx + 5, 1, bz + 3.5), WOOD, Enum.Material.Wood)
	box(
		m,
		"Wardrobe",
		Vector3.new(2.4, 8.5, 8),
		at(-w / 2 + 1.8, 4.25, 4),
		Color3.fromRGB(230, 228, 222),
		Enum.Material.Wood
	)
	-- living room (back right): sofa, table, TV
	local lx, lz = w / 2 - 14, d / 2 - 6
	box(m, "Sofa", Vector3.new(11, 1.6, 3.4), at(lx, 1.2, lz + 1.2), Color3.fromRGB(80, 85, 95), Enum.Material.Fabric)
	box(m, "SofaBack", Vector3.new(11, 2.4, 1), at(lx, 2.4, lz + 2.6), Color3.fromRGB(80, 85, 95), Enum.Material.Fabric)
	box(m, "CoffeeTable", Vector3.new(5, 1.2, 2.6), at(lx, 0.7, lz - 3), WOOD, Enum.Material.Wood)
	box(
		m,
		"Rug",
		Vector3.new(12, 0.06, 8),
		at(lx, 0.12, lz - 2),
		Color3.fromRGB(180, 170, 150),
		Enum.Material.Fabric,
		{ CanCollide = false }
	)
	box(m, "TVStand", Vector3.new(8, 1.6, 1.8), at(lx, 0.8, lz - 9), Color3.fromRGB(40, 40, 42), Enum.Material.Wood)
	box(m, "TV", Vector3.new(7, 4, 0.3), at(lx, 4, lz - 9.2), DARK, Enum.Material.Glass)
	-- kitchen along the right wall (front right)
	box(m, "Kitchen", Vector3.new(2.6, 3.2, 13), at(w / 2 - 2.1, 1.6, -d / 2 + 9), Color3.fromRGB(245, 245, 245))
	box(
		m,
		"Worktop",
		Vector3.new(2.8, 0.25, 13),
		at(w / 2 - 2.1, 3.3, -d / 2 + 9),
		Color3.fromRGB(60, 60, 62),
		Enum.Material.Granite
	)
	box(
		m,
		"Hob",
		Vector3.new(2, 0.05, 2.4),
		at(w / 2 - 2.1, 3.45, -d / 2 + 6),
		Color3.fromRGB(15, 15, 15),
		Enum.Material.Glass
	)
	box(
		m,
		"Fridge",
		Vector3.new(2.8, 7.5, 2.8),
		at(w / 2 - 2.2, 3.75, -d / 2 + 17.2),
		Color3.fromRGB(220, 222, 225),
		Enum.Material.Metal
	)
	box(m, "DiningTable", Vector3.new(5, 0.3, 3.5), at(w / 2 - 10, 2.9, -d / 2 + 9), WOOD, Enum.Material.Wood)
	box(m, "TableLeg", Vector3.new(0.5, 2.8, 0.5), at(w / 2 - 10, 1.4, -d / 2 + 9), DARK, Enum.Material.Metal)
	for _, sx in { -1, 1 } do
		box(m, "Chair", Vector3.new(1.8, 2, 1.8), at(w / 2 - 10 + sx * 3.3, 1, -d / 2 + 9), Color3.fromRGB(60, 62, 66))
	end
	-- bathroom box (front left) with door gap
	local bwid, bdep = 10, 9
	local bcx, bcz = -w / 2 + bwid / 2 + 0.6, -d / 2 + bdep / 2 + 5
	box(m, "BathWall", Vector3.new(bwid, 10, 0.4), at(bcx, 5, bcz + bdep / 2), WALL)
	box(m, "BathWall", Vector3.new(0.4, 10, bdep - 4), at(bcx + bwid / 2, 5, bcz - 2), WALL)
	box(
		m,
		"Tiles",
		Vector3.new(bwid - 0.4, 0.12, bdep),
		at(bcx, 0.12, bcz),
		Color3.fromRGB(220, 225, 228),
		Enum.Material.Marble,
		{ CanCollide = false }
	)
	box(
		m,
		"ShowerGlass",
		Vector3.new(0.2, 7, 3.6),
		at(bcx + 1, 3.5, bcz + 2.4),
		Color3.fromRGB(200, 225, 240),
		Enum.Material.Glass,
		{ Transparency = 0.6 }
	)
	box(m, "Toilet", Vector3.new(1.6, 1.8, 2.2), at(bcx - 3.5, 0.9, bcz - 2.5), Color3.fromRGB(250, 250, 250))
	box(m, "Sink", Vector3.new(2.4, 0.6, 1.6), at(bcx - 3.4, 3, bcz + 3.4), Color3.fromRGB(250, 250, 250))
	-- lights
	lamp(m, at(-w / 4, TowerBuilder.FLOOR_H - 1.6, d / 4), 26)
	lamp(m, at(w / 4, TowerBuilder.FLOOR_H - 1.6, d / 4), 26)
	lamp(m, at(w / 4, TowerBuilder.FLOOR_H - 1.6, -d / 4), 22)
end

function TowerBuilder.Build()
	local site = ((Locations :: any).Sites or {}).Tower
	if not site then
		return
	end
	local root = Instance.new("Model")
	root.Name = "Dortmund Tower"
	root.Parent = Workspace

	local W, D = 92, 86 -- footprint (26 x 24 m) inside the site
	local yaw = CFrame.Angles(0, math.rad(site.yaw), 0)
	local front = (CFrame.new(site.x, 0, site.z) * yaw * CFrame.new(0, 0, -D / 2 - 6)).Position
	local y0 = CityBuilder.GroundY(front.X, front.Z) + 0.05
	local base = CFrame.new(site.x, y0, site.z) * yaw
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	local FH, LH = TowerBuilder.FLOOR_H, TowerBuilder.LOBBY_H
	local total = LH + TowerBuilder.FLOORS * FH

	-- forecourt + plaza
	box(
		root,
		"Plaza",
		Vector3.new(site.width, 0.5, site.depth),
		at(0, -0.25, 0),
		Color3.fromRGB(190, 186, 178),
		Enum.Material.Pavement
	)

	-- structure: slabs, corner columns, glass facade (solid for collisions)
	local t = 1
	for f = 1, TowerBuilder.FLOORS do
		local fy = LH + (f - 1) * FH
		box(root, "Slab", Vector3.new(W, 1, D), at(0, fy - 0.5, 0), SLAB, Enum.Material.Concrete)
	end
	box(root, "RoofSlab", Vector3.new(W + 2, 1.5, D + 2), at(0, total + 0.75, 0), SLAB, Enum.Material.Concrete)
	for _, cx in { -1, 1 } do
		for _, cz in { -1, 1 } do
			box(
				root,
				"Column",
				Vector3.new(3, total, 3),
				at(cx * (W / 2 - 1.5), total / 2, cz * (D / 2 - 1.5)),
				Color3.fromRGB(70, 74, 80),
				Enum.Material.Metal
			)
		end
	end
	-- facade per floor (lobby front gets an entrance gap)
	for f = 1, TowerBuilder.FLOORS do
		local fy = LH + (f - 1) * FH
		for _, side in { -1, 1 } do
			box(
				root,
				"Facade",
				Vector3.new(W - 6, FH - 1, t),
				at(0, fy + FH / 2, side * (D / 2 - t / 2)),
				GLASS,
				Enum.Material.Glass,
				{ Transparency = 0.35 }
			)
			box(
				root,
				"Facade",
				Vector3.new(t, FH - 1, D - 6),
				at(side * (W / 2 - t / 2), fy + FH / 2, 0),
				GLASS,
				Enum.Material.Glass,
				{ Transparency = 0.35 }
			)
		end
	end
	-- lobby walls
	local entrance = 14
	box(
		root,
		"LobbyGlass",
		Vector3.new((W - 6 - entrance) / 2, LH - 1, t),
		at(-(entrance / 2 + (W - 6 - entrance) / 4), LH / 2, -D / 2 + t / 2),
		GLASS,
		Enum.Material.Glass,
		{ Transparency = 0.4 }
	)
	box(
		root,
		"LobbyGlass",
		Vector3.new((W - 6 - entrance) / 2, LH - 1, t),
		at(entrance / 2 + (W - 6 - entrance) / 4, LH / 2, -D / 2 + t / 2),
		GLASS,
		Enum.Material.Glass,
		{ Transparency = 0.4 }
	)
	box(
		root,
		"EntranceHeader",
		Vector3.new(entrance, LH - 11, t),
		at(0, 11 + (LH - 11) / 2, -D / 2 + t / 2),
		DARK,
		Enum.Material.Metal
	)
	box(root, "LobbyWall", Vector3.new(W - 6, LH, t), at(0, LH / 2, D / 2 - t / 2), WALL, Enum.Material.Concrete)
	for _, side in { -1, 1 } do
		box(
			root,
			"LobbyWall",
			Vector3.new(t, LH, D - 6),
			at(side * (W / 2 - t / 2), LH / 2, 0),
			WALL,
			Enum.Material.Concrete
		)
	end
	box(root, "Canopy", Vector3.new(entrance + 10, 0.8, 10), at(0, 12, -D / 2 - 4.5), DARK, Enum.Material.Metal)
	local signPart =
		box(root, "TowerSign", Vector3.new(30, 4, 0.6), at(0, LH - 2.5, -D / 2 - 0.6), Color3.fromRGB(20, 20, 24))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.Parent = signPart
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.Text = "DORTMUND TOWER"
	l.Parent = gui
	-- lobby interior
	box(
		root,
		"LobbyFloor",
		Vector3.new(W - 2, 0.1, D - 2),
		at(0, 0.06, 0),
		Color3.fromRGB(225, 222, 215),
		Enum.Material.Marble,
		{ CanCollide = false }
	)
	box(
		root,
		"Concierge",
		Vector3.new(14, 3.6, 3),
		at(-20, 1.8, -D / 2 + 22),
		Color3.fromRGB(60, 60, 64),
		Enum.Material.Marble
	)
	StoreBuilder.Npc(
		root,
		"Concierge",
		at(-20, 0, -D / 2 + 25) * CFrame.Angles(0, math.pi, 0),
		Color3.fromRGB(30, 30, 40)
	)
	for i = 0, 7 do
		box(
			root,
			"Mailbox",
			Vector3.new(2.6, 2.6, 1),
			at(W / 2 - 3, 3 + (i % 4) * 2.8, -10 + (i // 4) * 2.8 * 0),
			Color3.fromRGB(150, 150, 155),
			Enum.Material.Metal
		)
	end
	lamp(root, at(-15, LH - 1, -15), 40)
	lamp(root, at(15, LH - 1, -15), 40)
	lamp(root, at(0, LH - 1, 15), 40)

	-- core: elevator shaft in the middle-back, hallway across the middle on every floor
	local coreW, coreD = 14, 10
	local coreZ = 0
	local hallD = 12
	local function elevator(floorIndex: number, fy: number)
		local cf = at(0, fy, coreZ)
		box(
			root,
			"Shaft",
			Vector3.new(coreW, (if floorIndex == 0 then LH else FH) - 1, 0.6),
			cf * CFrame.new(0, ((if floorIndex == 0 then LH else FH) - 1) / 2, coreD / 2),
			DARK,
			Enum.Material.Metal
		)
		box(
			root,
			"ElevatorDoors",
			Vector3.new(7, 9, 0.4),
			cf * CFrame.new(0, 4.5, coreD / 2 - 0.5),
			Color3.fromRGB(190, 192, 196),
			Enum.Material.Metal
		)
		local panel = box(
			root,
			"Marker_Elevator",
			Vector3.new(1, 1.6, 0.2),
			cf * CFrame.new(5, 4.5, coreD / 2 - 0.6),
			Color3.fromRGB(30, 30, 32),
			Enum.Material.Neon,
			{ CanCollide = false }
		)
		Interaction.Mark(panel, "Elevator", {
			Floor = floorIndex,
			UI = "Elevator",
			Arg = floorIndex,
			ActionText = "Aufzug",
			ObjectText = if floorIndex == 0 then "Lobby" else "Etage " .. floorIndex,
		})
		TowerBuilder.FloorSpots[floorIndex] = cf * CFrame.new(0, 3, coreD / 2 - 6) * CFrame.Angles(0, math.pi, 0)
	end
	elevator(0, 0.1)

	local unitW = W - 4
	local unitD = (D - hallD) / 2 - 2
	local n = 0
	for f = 1, TowerBuilder.FLOORS do
		local fy = LH + (f - 1) * FH + 0.01
		elevator(f, fy)
		-- hallway walls with one door per flat (front flat: -Z side, back flat: +Z side)
		for _, side in { -1, 1 } do
			n += 1
			local wallZ = side * hallD / 2
			local doorX = if side < 0 then -20 else 20
			local doorW = 6
			local leftW = (unitW / 2 + doorX) - doorW / 2
			local rightW = (unitW / 2 - doorX) - doorW / 2
			box(
				root,
				"HallWall",
				Vector3.new(leftW, FH - 1, 0.6),
				at(-unitW / 2 + leftW / 2, fy + (FH - 1) / 2, wallZ),
				WALL,
				Enum.Material.Concrete
			)
			box(
				root,
				"HallWall",
				Vector3.new(rightW, FH - 1, 0.6),
				at(unitW / 2 - rightW / 2, fy + (FH - 1) / 2, wallZ),
				WALL,
				Enum.Material.Concrete
			)
			box(
				root,
				"DoorHeader",
				Vector3.new(doorW, FH - 10, 0.6),
				at(doorX, fy + 9 + (FH - 10) / 2, wallZ),
				WALL,
				Enum.Material.Concrete
			)
			local door = box(
				root,
				"AptDoor",
				Vector3.new(doorW, 9, 0.5),
				at(doorX, fy + 4.5, wallZ),
				Color3.fromRGB(120, 90, 60),
				Enum.Material.Wood
			)
			-- number plate (owner name is shown here too)
			local plateGui = Instance.new("SurfaceGui")
			plateGui.Face = if side < 0 then Enum.NormalId.Back else Enum.NormalId.Front
			plateGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			plateGui.PixelsPerStud = 30
			plateGui.Parent = door
			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 0.25, 0)
			label.Position = UDim2.fromScale(0, 0.12)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBold
			label.TextScaled = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.Text = string.format("Wohnung %d\nFrei", n)
			label.Parent = plateGui
			Interaction.Mark(
				door,
				"AptDoor",
				{ Unit = n, ActionText = "Tür", ObjectText = "Wohnung " .. n, Hold = 0.3 }
			)
			-- dividing wall between the two flats is the hallway; side walls are the facade
			local inside = at(doorX, fy + 3, wallZ + side * 6) * CFrame.Angles(0, if side < 0 then math.pi else 0, 0)
			table.insert(TowerBuilder.Units, { number = n, floor = f, door = door, label = label, inside = inside })
			local flatCenter = at(0, fy, side * (hallD / 2 + unitD / 2 + 1))
			local flatFrame = flatCenter * CFrame.Angles(0, if side < 0 then math.pi else 0, 0)
			local unit = TowerBuilder.Units[#TowerBuilder.Units]
			unit.frame, unit.w, unit.d = flatFrame, unitW, unitD
			local accent = Color3.fromHSV((n * 0.137) % 1, 0.45, 0.75)
			local flat = Instance.new("Model")
			flat.Name = "Wohnung " .. n
			flat.Parent = root
			furnish(flat, flatFrame, unitW, unitD, accent)
		end
		lamp(root, at(-20, fy + FH - 1.4, 0), 24)
		lamp(root, at(20, fy + FH - 1.4, 0), 24)
	end

	-- roof: helipad + parapet
	local ry = total + 1.5
	local pad = box(
		root,
		"Helipad",
		Vector3.new(0.3, 40, 40),
		at(0, ry + 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(60, 62, 66),
		Enum.Material.Concrete,
		{ Shape = Enum.PartType.Cylinder }
	)
	local _ = pad
	box(root, "H1", Vector3.new(2, 0.1, 14), at(-4, ry + 0.35, 0), Color3.new(1, 1, 1))
	box(root, "H2", Vector3.new(2, 0.1, 14), at(4, ry + 0.35, 0), Color3.new(1, 1, 1))
	box(root, "H3", Vector3.new(8, 0.1, 2), at(0, ry + 0.35, 0), Color3.new(1, 1, 1))
	for _, side in { -1, 1 } do
		box(
			root,
			"Parapet",
			Vector3.new(W + 2, 4, 1),
			at(0, ry + 2, side * (D / 2 + 0.5)),
			SLAB,
			Enum.Material.Concrete
		)
		box(
			root,
			"Parapet",
			Vector3.new(1, 4, D + 2),
			at(side * (W / 2 + 0.5), ry + 2, 0),
			SLAB,
			Enum.Material.Concrete
		)
	end
	local beacon = box(
		root,
		"Beacon",
		Vector3.new(1, 1, 1),
		at(W / 2 - 2, ry + 5, D / 2 - 2),
		Color3.fromRGB(255, 30, 30),
		Enum.Material.Neon
	)
	local bl = Instance.new("PointLight")
	bl.Color = Color3.fromRGB(255, 30, 30)
	bl.Range = 30
	bl.Parent = beacon
end

return TowerBuilder
