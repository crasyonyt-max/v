--!strict
-- Proper job stations on cleared real sites (Locations.Sites): an enterable main building
-- (reception with NPC, locker room where you start / end your shift, offices, police cells)
-- and a garage hall whose bays are where service vehicles spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Jobs = require(ReplicatedStorage.Shared.Jobs)
local Locations = require(ReplicatedStorage.Shared.Locations)
local CityBuilder = require(script.Parent.CityBuilder)
local Interaction = require(script.Parent.InteractionService)
local StoreBuilder = require(script.Parent.StoreBuilder)

local StationBuilder = {}

-- jobId -> list of bay CFrames (car faces out of the garage)
StationBuilder.Bays = {} :: { [string]: { CFrame } }
-- jobs that have a proper station (the plain street markers are skipped for them)
StationBuilder.Jobs = {} :: { [string]: boolean }

local CONCRETE = Color3.fromRGB(214, 210, 202)
local FLOOR = Color3.fromRGB(196, 196, 192)
local ASPHALT = Color3.fromRGB(70, 72, 76)

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

local function sign(part: BasePart, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
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

local function lamp(parent: Instance, cf: CFrame, range: number)
	local p = box(
		parent,
		"Lamp",
		Vector3.new(5, 0.2, 1.2),
		cf,
		Color3.fromRGB(255, 252, 242),
		Enum.Material.Neon,
		{ CanCollide = false }
	)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = 1.1
	l.Shadows = false
	l.Parent = p
end

local function mark(
	parent: Instance,
	kind: string,
	cf: CFrame,
	color: Color3,
	attrs: { [string]: any },
	visible: boolean
)
	local p = box(
		parent,
		"Marker_" .. kind,
		Vector3.new(0.15, 6, 6),
		cf * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		Enum.Material.Neon,
		{
			Shape = Enum.PartType.Cylinder,
			Transparency = if visible then 0.45 else 1,
			CanCollide = false,
			CanQuery = false,
		}
	)
	Interaction.Mark(p, kind, attrs)
end

-- Walls of a room box with an optional door gap in the front (-Z) wall.
local function room(
	parent: Instance,
	base: CFrame,
	w: number,
	d: number,
	h: number,
	color: Color3,
	doorW: number?,
	doorX: number?
)
	local t = 0.8
	box(parent, "Wall", Vector3.new(w, h, t), base * CFrame.new(0, h / 2, d / 2 - t / 2), color, Enum.Material.Concrete)
	box(
		parent,
		"Wall",
		Vector3.new(t, h, d),
		base * CFrame.new(-w / 2 + t / 2, h / 2, 0),
		color,
		Enum.Material.Concrete
	)
	box(parent, "Wall", Vector3.new(t, h, d), base * CFrame.new(w / 2 - t / 2, h / 2, 0), color, Enum.Material.Concrete)
	if doorW then
		local dx = doorX or 0
		local leftW = (w / 2 + dx) - doorW / 2
		local rightW = (w / 2 - dx) - doorW / 2
		if leftW > 0.1 then
			box(
				parent,
				"Wall",
				Vector3.new(leftW, h, t),
				base * CFrame.new(-w / 2 + leftW / 2, h / 2, -d / 2 + t / 2),
				color,
				Enum.Material.Concrete
			)
		end
		if rightW > 0.1 then
			box(
				parent,
				"Wall",
				Vector3.new(rightW, h, t),
				base * CFrame.new(w / 2 - rightW / 2, h / 2, -d / 2 + t / 2),
				color,
				Enum.Material.Concrete
			)
		end
		box(
			parent,
			"Lintel",
			Vector3.new(doorW, h - 9, t),
			base * CFrame.new(dx, 9 + (h - 9) / 2, -d / 2 + t / 2),
			color,
			Enum.Material.Concrete
		)
	else
		box(
			parent,
			"Wall",
			Vector3.new(w, h, t),
			base * CFrame.new(0, h / 2, -d / 2 + t / 2),
			color,
			Enum.Material.Concrete
		)
	end
end

type StationDef = {
	key: string,
	title: string,
	accent: Color3,
	doorColor: Color3,
	jobs: { { id: string, bays: number } },
	police: boolean?,
	staff: string?,
	bayW: number?,
	-- job-specific furniture: (model, garage frame, garage width, garage depth)
	extras: ((Model, CFrame, number, number) -> ())?,
}

local function build(root: Instance, site: any, def: StationDef)
	local m = Instance.new("Model")
	m.Name = def.title
	m.Parent = root
	local W, D = site.width, site.depth
	local yaw = CFrame.Angles(0, math.rad(site.yaw), 0)
	local frontPoint = (CFrame.new(site.x, 0, site.z) * yaw * CFrame.new(0, 0, -D / 2 - 6)).Position
	local y = CityBuilder.GroundY(frontPoint.X, frontPoint.Z) + 0.05
	local base = CFrame.new(site.x, y, site.z) * yaw
	local function at(x: number, yy: number, z: number): CFrame
		return base * CFrame.new(x, yy, z)
	end

	-- yard
	box(m, "Yard", Vector3.new(W, 0.6, D), at(0, -0.3, 0), ASPHALT, Enum.Material.Asphalt)
	box(
		m,
		"Fence",
		Vector3.new(W, 7, 0.4),
		at(0, 3.5, D / 2 - 0.2),
		Color3.fromRGB(90, 95, 100),
		Enum.Material.DiamondPlate,
		{ Transparency = 0.3 }
	)

	-- main building (front left): ground floor enterable, upper floors solid
	local bw, bd, H = W * 0.42, D * 0.55, 15
	local bx, bz = -W / 2 + bw / 2 + 4, -D / 2 + bd / 2 + 8
	local bBase = at(bx, 0, bz)
	box(m, "Floor", Vector3.new(bw, 0.4, bd), bBase * CFrame.new(0, 0.2, 0), FLOOR, Enum.Material.Marble)
	room(m, bBase * CFrame.new(0, 0.4, 0), bw, bd, H, CONCRETE, 8, 0)
	box(m, "Ceiling", Vector3.new(bw, 0.8, bd), bBase * CFrame.new(0, H + 0.4, 0), Color3.fromRGB(235, 235, 232))
	box(
		m,
		"UpperFloors",
		Vector3.new(bw, 26, bd),
		bBase * CFrame.new(0, H + 0.8 + 13, 0),
		CONCRETE,
		Enum.Material.Concrete
	)
	for row = 0, 2 do
		box(
			m,
			"Windows",
			Vector3.new(bw + 0.2, 3, bd + 0.2),
			bBase * CFrame.new(0, H + 5 + row * 8, 0),
			Color3.fromRGB(70, 90, 110),
			Enum.Material.Glass,
			{ CanCollide = false }
		)
	end
	local fascia =
		box(m, "Sign", Vector3.new(bw * 0.8, 4, 0.6), bBase * CFrame.new(0, H - 2.5, -bd / 2 - 0.4), def.accent)
	sign(fascia, def.title, Color3.new(1, 1, 1))
	-- interior: reception at the front, locker room right, offices / cells at the back
	box(
		m,
		"Reception",
		Vector3.new(14, 3.6, 2.4),
		bBase * CFrame.new(-bw / 4, 2.2, -bd / 2 + 12),
		Color3.fromRGB(120, 125, 135)
	)
	StoreBuilder.Npc(
		m,
		def.staff or (if def.police then "Wachtmeister" else "Wachabteilung"),
		bBase * CFrame.new(-bw / 4, 0.4, -bd / 2 + 15) * CFrame.Angles(0, math.pi, 0),
		def.accent
	)
	-- inner wall splitting front (lobby) and back (offices) with a doorway
	local inner = bBase * CFrame.new(0, 0.4, bd * 0.1)
	box(
		m,
		"InnerWall",
		Vector3.new(bw / 2 - 5, H, 0.6),
		inner * CFrame.new(-bw / 4 - 2.5, H / 2, 0),
		CONCRETE,
		Enum.Material.Concrete
	)
	box(
		m,
		"InnerWall",
		Vector3.new(bw / 2 - 5, H, 0.6),
		inner * CFrame.new(bw / 4 + 2.5, H / 2, 0),
		CONCRETE,
		Enum.Material.Concrete
	)
	-- locker room (right front)
	for i = 0, 5 do
		box(
			m,
			"Locker",
			Vector3.new(2.4, 7, 2),
			bBase * CFrame.new(bw / 2 - 2.2, 4, -bd / 2 + 6 + i * 2.6),
			Color3.fromRGB(90, 100, 120),
			Enum.Material.Metal
		)
	end
	box(
		m,
		"Bench",
		Vector3.new(2, 1.6, 12),
		bBase * CFrame.new(bw / 2 - 8, 1.2, -bd / 2 + 12),
		Color3.fromRGB(150, 110, 70),
		Enum.Material.Wood
	)
	for i, j in def.jobs do
		local job = Jobs.ById[j.id]
		local lz = -bd / 2 + 6 + (i - 1) * 9
		mark(
			m,
			"JobStart",
			bBase * CFrame.new(bw / 2 - 12, 0.45, lz),
			job.color,
			{ JobId = j.id, ActionText = "Dienst antreten", ObjectText = Jobs.Name(j.id, "de") },
			true
		)
	end
	mark(
		m,
		"JobEnd",
		bBase * CFrame.new(bw / 2 - 12, 0.45, -bd / 2 + 6 + #def.jobs * 9),
		Color3.fromRGB(120, 120, 120),
		{ ActionText = "Dienst beenden", ObjectText = def.title },
		true
	)
	-- offices
	for i = 0, 2 do
		local ox = -bw / 2 + 8 + i * 12
		box(
			m,
			"Desk",
			Vector3.new(6, 2.8, 3),
			bBase * CFrame.new(ox, 1.8, bd * 0.3),
			Color3.fromRGB(170, 140, 100),
			Enum.Material.Wood
		)
		box(
			m,
			"Screen",
			Vector3.new(2, 1.4, 0.2),
			bBase * CFrame.new(ox, 3.9, bd * 0.3 + 0.8),
			Color3.fromRGB(20, 20, 24),
			Enum.Material.Glass
		)
	end
	if def.police then
		-- two holding cells at the back right
		for i = 0, 1 do
			local cx = bw / 2 - 7 - i * 12
			local cz = bd / 2 - 7
			box(
				m,
				"CellWall",
				Vector3.new(0.6, H, 12),
				bBase * CFrame.new(cx - 6, 0.4 + H / 2, cz),
				CONCRETE,
				Enum.Material.Concrete
			)
			for b = 0, 10 do
				box(
					m,
					"CellBar",
					Vector3.new(0.25, 10, 0.25),
					bBase * CFrame.new(cx - 5 + b * 1.0, 5.4, cz - 6),
					Color3.fromRGB(70, 70, 75),
					Enum.Material.Metal
				)
			end
			box(
				m,
				"CellBunk",
				Vector3.new(7, 1.2, 3),
				bBase * CFrame.new(cx, 1.6, cz + 3.5),
				Color3.fromRGB(120, 120, 125),
				Enum.Material.Metal
			)
		end
	end
	for i = 0, 2 do
		lamp(m, bBase * CFrame.new(-bw / 3 + i * bw / 3, H - 0.5, -bd / 4), 30)
		lamp(m, bBase * CFrame.new(-bw / 3 + i * bw / 3, H - 0.5, bd / 4), 30)
	end

	-- garage hall (front right) with bay doors facing the street
	local totalBays = 0
	for _, j in def.jobs do
		totalBays += j.bays
	end
	local bayW = def.bayW or 16
	local gw, gd, gh = math.min(W * 0.52, totalBays * bayW + 4), D * 0.6, 20
	local gx, gz = W / 2 - gw / 2 - 4, -D / 2 + gd / 2 + 8
	local gBase = at(gx, 0, gz)
	box(
		m,
		"GarageFloor",
		Vector3.new(gw, 0.4, gd),
		gBase * CFrame.new(0, 0.2, 0),
		Color3.fromRGB(150, 152, 155),
		Enum.Material.Concrete
	)
	local t = 0.8
	box(
		m,
		"GarageWall",
		Vector3.new(gw, gh, t),
		gBase * CFrame.new(0, gh / 2, gd / 2 - t / 2),
		CONCRETE,
		Enum.Material.Concrete
	)
	box(
		m,
		"GarageWall",
		Vector3.new(t, gh, gd),
		gBase * CFrame.new(-gw / 2 + t / 2, gh / 2, 0),
		CONCRETE,
		Enum.Material.Concrete
	)
	box(
		m,
		"GarageWall",
		Vector3.new(t, gh, gd),
		gBase * CFrame.new(gw / 2 - t / 2, gh / 2, 0),
		CONCRETE,
		Enum.Material.Concrete
	)
	box(
		m,
		"GarageRoof",
		Vector3.new(gw + 1, 1, gd + 1),
		gBase * CFrame.new(0, gh + 0.5, 0),
		Color3.fromRGB(110, 112, 116)
	)
	local pillarW = (gw - totalBays * (bayW - 2)) / (totalBays + 1)
	local doorH = 16
	box(
		m,
		"Header",
		Vector3.new(gw, gh - doorH, t),
		gBase * CFrame.new(0, doorH + (gh - doorH) / 2, -gd / 2 + t / 2),
		CONCRETE,
		Enum.Material.Concrete
	)
	local bayIndex = 0
	local x0 = -gw / 2
	for _, j in def.jobs do
		StationBuilder.Bays[j.id] = StationBuilder.Bays[j.id] or {}
		StationBuilder.Jobs[j.id] = true
		local job = Jobs.ById[j.id]
		for _ = 1, j.bays do
			local left = x0 + pillarW + bayIndex * (bayW - 2 + pillarW)
			local center = left + (bayW - 2) / 2
			box(
				m,
				"Pillar",
				Vector3.new(pillarW, doorH, t),
				gBase * CFrame.new(left - pillarW / 2, doorH / 2, -gd / 2 + t / 2),
				CONCRETE,
				Enum.Material.Concrete
			)
			-- rolled-up door + coloured frame
			box(
				m,
				"DoorRoll",
				Vector3.new(bayW - 2, 1.4, 1.2),
				gBase * CFrame.new(center, doorH - 0.7, -gd / 2 + 0.8),
				def.doorColor,
				Enum.Material.Metal
			)
			box(
				m,
				"BayLine",
				Vector3.new(0.3, 0.05, gd - 6),
				gBase * CFrame.new(left - pillarW / 2, 0.43, 2),
				Color3.fromRGB(240, 220, 60),
				nil,
				{ CanCollide = false }
			)
			lamp(m, gBase * CFrame.new(center, gh - 0.6, 0), 34)
			table.insert(StationBuilder.Bays[j.id], gBase * CFrame.new(center, 0.45, 2) * CFrame.Angles(0, 0, 0))
			local _ = job
			bayIndex += 1
		end
	end
	box(
		m,
		"Pillar",
		Vector3.new(pillarW, doorH, t),
		gBase * CFrame.new(gw / 2 - pillarW / 2, doorH / 2, -gd / 2 + t / 2),
		CONCRETE,
		Enum.Material.Concrete
	)
	-- vehicle prompt inside the hall (opens the service vehicle list for your job)
	for i, j in def.jobs do
		local job = Jobs.ById[j.id]
		mark(m, "JobGarage", gBase * CFrame.new(-gw / 2 + 5, 0.45, gd / 2 - 6 - (i - 1) * 8), job.color, {
			JobId = j.id,
			UI = "JobGarage",
			Arg = j.id,
			ActionText = "Dienstfahrzeug",
			ObjectText = Jobs.Name(j.id, "de"),
		}, true)
	end

	if def.extras then
		def.extras(m, gBase, gw, gd)
	end

	-- flag poles at the entrance
	for i = -1, 1 do
		local p = at(-W / 2 + 6 + i * 4, 0, -D / 2 + 3)
		box(
			m,
			"Flagpole",
			Vector3.new(0.4, 22, 0.4),
			p * CFrame.new(0, 11, 0),
			Color3.fromRGB(200, 200, 205),
			Enum.Material.Metal
		)
		box(
			m,
			"Flag",
			Vector3.new(0.1, 3, 5),
			p * CFrame.new(0, 19.5, 2.6),
			if i == 0 then def.accent else Color3.fromRGB(240, 240, 240),
			Enum.Material.Fabric
		)
	end
end

-- Job-specific furniture along the back of the garage hall (cars spawn in the front part).
local BROWN = Color3.fromRGB(176, 128, 80)

local function rack(m: Model, cf: CFrame, len: number, height: number, levels: number, goods: Color3)
	box(
		m,
		"RackPost",
		Vector3.new(0.4, height, 0.4),
		cf * CFrame.new(-len / 2, height / 2, 0),
		Color3.fromRGB(230, 120, 30),
		Enum.Material.Metal
	)
	box(
		m,
		"RackPost",
		Vector3.new(0.4, height, 0.4),
		cf * CFrame.new(len / 2, height / 2, 0),
		Color3.fromRGB(230, 120, 30),
		Enum.Material.Metal
	)
	for i = 1, levels do
		local y = i * height / (levels + 0.5)
		box(
			m,
			"RackBeam",
			Vector3.new(len, 0.3, 3.2),
			cf * CFrame.new(0, y, 0),
			Color3.fromRGB(40, 90, 170),
			Enum.Material.Metal
		)
		for k = 0, math.floor(len / 3.4) - 1 do
			box(
				m,
				"Goods",
				Vector3.new(2.8, 2.2, 2.6),
				cf * CFrame.new(-len / 2 + 2 + k * 3.4, y + 1.25, 0),
				goods:Lerp(Color3.new(1, 1, 1), (k % 3) * 0.08),
				Enum.Material.Cardboard,
				{ CanCollide = false }
			)
		end
	end
end

local function admcExtras(m: Model, g: CFrame, gw: number, gd: number)
	local back = gd / 2 - 9
	-- two car lifts at the back of the workshop
	for _, x in { -gw / 4, gw / 4 } do
		local lift = g * CFrame.new(x, 0.4, back)
		for _, sx in { -1, 1 } do
			box(
				m,
				"LiftPost",
				Vector3.new(1, 12, 1),
				lift * CFrame.new(sx * 5.5, 6, 0),
				Color3.fromRGB(200, 30, 30),
				Enum.Material.Metal
			)
			box(
				m,
				"LiftArm",
				Vector3.new(4.5, 0.4, 0.6),
				lift * CFrame.new(sx * 3.5, 3.5, -2),
				Color3.fromRGB(60, 60, 64),
				Enum.Material.Metal
			)
			box(
				m,
				"LiftArm",
				Vector3.new(4.5, 0.4, 0.6),
				lift * CFrame.new(sx * 3.5, 3.5, 2),
				Color3.fromRGB(60, 60, 64),
				Enum.Material.Metal
			)
		end
		box(
			m,
			"LiftBeam",
			Vector3.new(12, 0.8, 1),
			lift * CFrame.new(0, 12.4, 0),
			Color3.fromRGB(200, 30, 30),
			Enum.Material.Metal
		)
	end
	-- tool chests, tyre stacks, compressor
	for i = 0, 3 do
		box(
			m,
			"ToolChest",
			Vector3.new(4, 4, 2),
			g * CFrame.new(-gw / 2 + 4 + i * 5, 2.4, gd / 2 - 2),
			Color3.fromRGB(200, 30, 30),
			Enum.Material.Metal
		)
	end
	for i = 0, 4 do
		for k = 0, 3 do
			box(
				m,
				"Tyre",
				Vector3.new(0.9, 2.6, 2.6),
				g * CFrame.new(gw / 2 - 3, 0.85 + k * 0.92, -gd / 2 + 26 + i * 3) * CFrame.Angles(0, 0, math.pi / 2),
				Color3.fromRGB(25, 25, 27),
				Enum.Material.Rubber,
				{ Shape = Enum.PartType.Cylinder }
			)
		end
	end
	box(
		m,
		"Compressor",
		Vector3.new(3, 3, 5),
		g * CFrame.new(gw / 2 - 3, 1.9, gd / 2 - 6),
		Color3.fromRGB(240, 200, 0),
		Enum.Material.Metal
	)
end

local function dxlExtras(m: Model, g: CFrame, gw: number, gd: number)
	local back = gd / 2 - 4
	for i = -1, 1 do
		rack(m, g * CFrame.new(i * gw / 3.2, 0.4, back), gw / 3.6, 12, 3, BROWN)
	end
	-- conveyor belt with parcels
	box(
		m,
		"Conveyor",
		Vector3.new(gw * 0.7, 2.6, 2.4),
		g * CFrame.new(0, 1.7, back - 9),
		Color3.fromRGB(60, 62, 66),
		Enum.Material.Metal
	)
	box(
		m,
		"Belt",
		Vector3.new(gw * 0.7, 0.15, 2),
		g * CFrame.new(0, 3.05, back - 9),
		Color3.fromRGB(20, 20, 20),
		Enum.Material.Rubber
	)
	for i = 0, math.floor(gw * 0.7 / 4) - 1 do
		box(
			m,
			"Parcel",
			Vector3.new(1.8, 1.2, 1.4),
			g * CFrame.new(-gw * 0.35 + 2 + i * 4, 3.7, back - 9),
			BROWN,
			Enum.Material.Cardboard,
			{ CanCollide = false }
		)
	end
	for i = 0, 3 do
		box(
			m,
			"Pallet",
			Vector3.new(4, 0.5, 4),
			g * CFrame.new(-gw / 2 + 5 + i * 6, 0.65, back - 16),
			Color3.fromRGB(190, 160, 110),
			Enum.Material.Wood
		)
		box(
			m,
			"ParcelStack",
			Vector3.new(3.6, 3.2, 3.6),
			g * CFrame.new(-gw / 2 + 5 + i * 6, 2.5, back - 16),
			BROWN,
			Enum.Material.Cardboard
		)
	end
end

local function lkwExtras(m: Model, g: CFrame, gw: number, gd: number)
	local back = gd / 2 - 4
	for i = -2, 2 do
		rack(m, g * CFrame.new(i * gw / 5.2, 0.4, back), gw / 5.6, 16, 4, Color3.fromRGB(150, 120, 90))
	end
	-- forklift
	local f = g * CFrame.new(gw / 2 - 10, 0.4, back - 14)
	box(
		m,
		"ForkliftBody",
		Vector3.new(3.6, 3, 5.5),
		f * CFrame.new(0, 2, 0),
		Color3.fromRGB(240, 180, 0),
		Enum.Material.Metal
	)
	box(
		m,
		"ForkliftMast",
		Vector3.new(3, 8, 0.5),
		f * CFrame.new(0, 4.5, -3),
		Color3.fromRGB(40, 40, 42),
		Enum.Material.Metal
	)
	for _, sx in { -1, 1 } do
		box(
			m,
			"Fork",
			Vector3.new(0.4, 0.2, 4),
			f * CFrame.new(sx * 0.9, 0.7, -5),
			Color3.fromRGB(40, 40, 42),
			Enum.Material.Metal
		)
	end
	for i = 0, 5 do
		box(
			m,
			"Pallet",
			Vector3.new(4, 0.5, 4),
			g * CFrame.new(-gw / 2 + 6 + i * 6, 0.65, back - 14),
			Color3.fromRGB(190, 160, 110),
			Enum.Material.Wood
		)
		box(
			m,
			"Freight",
			Vector3.new(3.6, 3.6, 3.6),
			g * CFrame.new(-gw / 2 + 6 + i * 6, 2.7, back - 14),
			Color3.fromRGB(150 + i * 10, 120, 90),
			Enum.Material.Cardboard
		)
	end
end

function StationBuilder.Build()
	local root = Instance.new("Folder")
	root.Name = "Stations"
	root.Parent = Workspace
	local sites = (Locations :: any).Sites or {}
	if sites.Police then
		build(root, sites.Police, {
			key = "Police",
			title = "POLIZEI",
			accent = Color3.fromRGB(0, 58, 150),
			doorColor = Color3.fromRGB(0, 58, 150),
			jobs = { { id = "Police", bays = 4 } },
			police = true,
		})
	end
	if sites.FireRescue then
		build(root, sites.FireRescue, {
			key = "FireRescue",
			title = "Feuer- und Rettungswache 1",
			accent = Color3.fromRGB(200, 20, 20),
			doorColor = Color3.fromRGB(200, 20, 20),
			jobs = { { id = "Fire", bays = 3 }, { id = "Rettungsdienst", bays = 2 }, { id = "Notarzt", bays = 1 } },
		})
	end
	if sites.ADMC then
		build(root, sites.ADMC, {
			key = "ADMC",
			title = "ADMC Stützpunkt",
			accent = Color3.fromRGB(250, 205, 0),
			doorColor = Color3.fromRGB(250, 205, 0),
			jobs = { { id = "ADMC", bays = 4 } },
			staff = "Werkstattmeister",
			bayW = 18,
			extras = admcExtras,
		})
	end
	if sites.DXL then
		build(root, sites.DXL, {
			key = "DXL",
			title = "DXL Paketzentrum",
			accent = Color3.fromRGB(210, 20, 30),
			doorColor = Color3.fromRGB(255, 204, 0),
			jobs = { { id = "DXL", bays = 5 } },
			staff = "Lagerist",
			bayW = 16,
			extras = dxlExtras,
		})
	end
	if sites.LKW then
		build(root, sites.LKW, {
			key = "LKW",
			title = "Spedition Dortmund",
			accent = Color3.fromRGB(60, 120, 70),
			doorColor = Color3.fromRGB(200, 200, 205),
			jobs = { { id = "LKW", bays = 4 } },
			staff = "Disponent",
			bayW = 24,
			extras = lkwExtras,
		})
	end
end

return StationBuilder
