--!strict
-- v0.4: builds one house (Shared/Houses type) on a plot. Plot frame: origin = plot
-- centre on the ground, -Z = towards the street. Real walls with window openings,
-- a front door, floors with stairs, room walls, roof, garden, path, hedge, mailbox,
-- and per type garage / terrace / pool.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Houses = require(ReplicatedStorage.Shared.Houses)

local HouseBuilder = {}

local FH = Houses.FLOOR_H
local T = 1 -- wall thickness
local GLASS = Color3.fromRGB(150, 185, 205)
local FLOOR_WOOD = Color3.fromRGB(170, 130, 90)
local CEILING = Color3.fromRGB(245, 245, 242)
local INNER = Color3.fromRGB(238, 234, 226)

export type Built = {
	model: Model,
	door: BasePart,
	inside: CFrame, -- just inside the front door
	outside: CFrame, -- on the path in front of the door
	bounds: { cf: CFrame, size: Vector3 }, -- where furniture may go
	nameLabel: TextLabel,
	mailbox: BasePart, -- "Haus verwalten" (owner + co-owners)
	floorTops: { number }, -- local Y of each floor (for furniture snapping)
}

local function part(
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

local function sign(p: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3): TextLabel
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
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color
	l.Text = text
	l.Parent = gui
	return l
end

-- A straight wall from a to b (house frame, on floor height y0) with windows; an
-- optional door opening at `doorAt` (distance from a). Returns nothing.
local function wall(
	m: Instance,
	at: (number, number, number) -> CFrame,
	a: Vector2,
	b: Vector2,
	y0: number,
	color: Color3,
	material: Enum.Material,
	windows: boolean,
	doorAt: number?,
	glassFront: boolean?
)
	local dir = b - a
	local len = dir.Magnitude
	if len < 0.5 then
		return
	end
	local u = dir / len
	local yaw = math.atan2(-u.Y, u.X) -- the part's X axis along the wall
	local function piece(
		from: number,
		to: number,
		ylo: number,
		yhi: number,
		c: Color3,
		mat: Enum.Material,
		glass: boolean
	)
		if to - from < 0.05 or yhi - ylo < 0.05 then
			return
		end
		local mid = a + u * ((from + to) / 2)
		part(
			m,
			if glass then "Window" else "Wall",
			Vector3.new(to - from, yhi - ylo, if glass then 0.3 else T),
			at(mid.X, y0 + (ylo + yhi) / 2, mid.Y) * CFrame.Angles(0, yaw, 0),
			c,
			mat,
			if glass then { Transparency = 0.45, Reflectance = 0.1 } else nil
		)
	end
	if glassFront then
		-- modern: one big glass front between two solid ends
		piece(0, 2, 0, FH, color, material, false)
		piece(len - 2, len, 0, FH, color, material, false)
		if doorAt then
			piece(2, doorAt - 3, 0, FH, GLASS, Enum.Material.Glass, true)
			piece(doorAt + 3, len - 2, 0, FH, GLASS, Enum.Material.Glass, true)
			piece(doorAt - 3, doorAt + 3, 9, FH, color, material, false)
		else
			piece(2, len - 2, 0, FH, GLASS, Enum.Material.Glass, true)
		end
		return
	end
	local cells = math.max(1, math.floor(len / 10))
	local cw = len / cells
	for i = 0, cells - 1 do
		local c0, c1 = i * cw, (i + 1) * cw
		local mid = (c0 + c1) / 2
		if doorAt and doorAt >= c0 and doorAt < c1 then
			piece(c0, doorAt - 3, 0, FH, color, material, false)
			piece(doorAt + 3, c1, 0, FH, color, material, false)
			piece(doorAt - 3, doorAt + 3, 9, FH, color, material, false)
		elseif windows and cw >= 7 then
			local half = math.min(2.6, (cw - 3) / 2)
			piece(c0, mid - half, 0, FH, color, material, false)
			piece(mid + half, c1, 0, FH, color, material, false)
			piece(mid - half, mid + half, 0, 3.5, color, material, false)
			piece(mid - half, mid + half, 3.5, 8.5, GLASS, Enum.Material.Glass, true)
			piece(mid - half, mid + half, 8.5, FH, color, material, false)
		else
			piece(c0, c1, 0, FH, color, material, false)
		end
	end
end

local function lamp(m: Instance, cf: CFrame)
	local p =
		part(m, "CeilingLamp", Vector3.new(2.4, 0.3, 2.4), cf, Color3.fromRGB(250, 248, 240), Enum.Material.Neon, {
			CanCollide = false,
		})
	local l = Instance.new("PointLight")
	l.Range = 22
	l.Brightness = 0.6
	l.Color = Color3.fromRGB(255, 236, 210)
	l.Parent = p
end

function HouseBuilder.Build(def: Houses.HouseType, plot: CFrame, ownerName: string?): Built
	local m = Instance.new("Model")
	m.Name = def.name
	local PW, PD = Houses.PLOT_W, Houses.PLOT_D
	local w, d = def.w, def.d
	-- the house stands 10 studs behind the street edge of the plot; with a garage the
	-- house moves to one side and the garage stands next to it (both on the plot)
	local hz = -PD / 2 + 10 + d / 2
	local gw = if def.id == "modernevilla" or def.id == "luxusvilla" then 16 else 14
	local total = w + (if def.garage then 2 + gw else 0)
	local hx = -total / 2 + w / 2
	local function at(x: number, y: number, z: number): CFrame
		return plot * CFrame.new(x + hx, y, z + hz)
	end
	local function plotAt(x: number, y: number, z: number): CFrame
		return plot * CFrame.new(x, y, z)
	end

	-- garden: lawn, path to the door, hedge on the sides and the back, mailbox
	part(m, "Lawn", Vector3.new(PW, 0.2, PD), plotAt(0, 0.1, 0), Color3.fromRGB(96, 150, 70), Enum.Material.Grass)
	part(
		m,
		"Path",
		Vector3.new(5, 0.25, 10),
		plotAt(hx, 0.13, -PD / 2 + 5),
		Color3.fromRGB(170, 165, 155),
		Enum.Material.Slate
	)
	for _, sx in { -1, 1 } do
		part(
			m,
			"Hedge",
			Vector3.new(1.6, 4, PD - 6),
			plotAt(sx * (PW / 2 - 0.8), 2, 3),
			Color3.fromRGB(50, 105, 50),
			Enum.Material.Grass
		)
	end
	part(
		m,
		"Hedge",
		Vector3.new(PW, 4, 1.6),
		plotAt(0, 2, PD / 2 - 0.8),
		Color3.fromRGB(50, 105, 50),
		Enum.Material.Grass
	)
	part(
		m,
		"MailboxPost",
		Vector3.new(0.4, 4, 0.4),
		plotAt(hx + 4.5, 2, -PD / 2 + 1.5),
		Color3.fromRGB(50, 50, 55),
		Enum.Material.Metal
	)
	local box = part(
		m,
		"Mailbox",
		Vector3.new(2.2, 1.6, 1.4),
		plotAt(hx + 4.5, 4.6, -PD / 2 + 1.5),
		Color3.fromRGB(240, 200, 30)
	)
	local nameLabel = sign(box, Enum.NormalId.Front, ownerName or "", Color3.new(0, 0, 0), Color3.fromRGB(240, 200, 30))

	-- floors (slabs) and ceilings; stairs along the left wall, hole above them
	local stairX0, stairX1 = -w / 2 + T, -w / 2 + T + 4.5
	local stairZ0 = -d / 2 + 7
	local steps = 16
	local run = 1.35
	local stairZ1 = stairZ0 + steps * run
	local floorTops = {}
	for f = 0, def.floors - 1 do
		local y = f * FH
		floorTops[f + 1] = y + 0.5
		if f == 0 then
			part(m, "Floor", Vector3.new(w, 1, d), at(0, 0, 0), FLOOR_WOOD, Enum.Material.WoodPlanks)
		else
			-- slab with a hole for the stairs from below
			local holeW = stairX1 - stairX0
			part(
				m,
				"Floor",
				Vector3.new(w - holeW - T, 1, d),
				at((stairX1 + w / 2) / 2, y, 0),
				FLOOR_WOOD,
				Enum.Material.WoodPlanks
			)
			part(
				m,
				"Floor",
				Vector3.new(holeW + T, 1, stairZ0 + d / 2),
				at((-w / 2 + stairX1) / 2, y, (-d / 2 + stairZ0) / 2),
				FLOOR_WOOD,
				Enum.Material.WoodPlanks
			)
			part(
				m,
				"Floor",
				Vector3.new(holeW + T, 1, d / 2 - stairZ1),
				at((-w / 2 + stairX1) / 2, y, (stairZ1 + d / 2) / 2),
				FLOOR_WOOD,
				Enum.Material.WoodPlanks
			)
		end
		-- outer walls: front with the door on the ground floor, windows everywhere
		local modern = def.roof == "flat" and (def.id == "modernevilla" or def.id == "luxusvilla")
		local hw, hd = w / 2, d / 2
		wall(
			m,
			at,
			Vector2.new(-hw, -hd + T / 2),
			Vector2.new(hw, -hd + T / 2),
			y + 0.5,
			def.wall,
			def.material,
			true,
			if f == 0 then hw else nil,
			modern
		)
		wall(
			m,
			at,
			Vector2.new(-hw, hd - T / 2),
			Vector2.new(hw, hd - T / 2),
			y + 0.5,
			def.wall,
			def.material,
			true,
			nil,
			modern and f == 0
		)
		wall(
			m,
			at,
			Vector2.new(-hw + T / 2, -hd + T),
			Vector2.new(-hw + T / 2, hd - T),
			y + 0.5,
			def.wall,
			def.material,
			true
		)
		wall(
			m,
			at,
			Vector2.new(hw - T / 2, -hd + T),
			Vector2.new(hw - T / 2, hd - T),
			y + 0.5,
			def.wall,
			def.material,
			true
		)
		-- inner room walls with a doorway: ground floor kitchen on the right,
		-- upper floors bedroom / bath at the back
		if f == 0 then
			local x = w / 2 - math.max(12, w * 0.3)
			wall(
				m,
				at,
				Vector2.new(x, -hd + T),
				Vector2.new(x, hd - T),
				y + 0.5,
				INNER,
				Enum.Material.SmoothPlastic,
				false,
				d * 0.35
			)
		else
			wall(
				m,
				at,
				Vector2.new(stairX1 + 2, 2),
				Vector2.new(hw - T, 2),
				y + 0.5,
				INNER,
				Enum.Material.SmoothPlastic,
				false,
				5
			)
			wall(
				m,
				at,
				Vector2.new(w * 0.15, 2),
				Vector2.new(w * 0.15, hd - T),
				y + 0.5,
				INNER,
				Enum.Material.SmoothPlastic,
				false,
				4
			)
		end
		lamp(m, at(-w / 4, y + FH + 0.1, 0))
		lamp(m, at(w / 4, y + FH + 0.1, 0))
		-- stairs up to the next floor
		if f < def.floors - 1 then
			for s = 0, steps - 1 do
				part(
					m,
					"Step",
					Vector3.new(stairX1 - stairX0, 0.75, run),
					at((stairX0 + stairX1) / 2, y + 0.5 + (s + 0.5) * 0.75, stairZ0 + (s + 0.5) * run),
					Color3.fromRGB(150, 110, 75),
					Enum.Material.Wood
				)
			end
			part(
				m,
				"Railing",
				Vector3.new(0.3, 3, stairZ1 - stairZ0),
				at(stairX1 + 0.15, y + FH + 2, (stairZ0 + stairZ1) / 2),
				Color3.fromRGB(60, 60, 64),
				Enum.Material.Metal
			)
		end
	end
	local top = def.floors * FH
	-- ceiling of the top floor + roof
	part(m, "Ceiling", Vector3.new(w, 1, d), at(0, top + 0.5, 0), CEILING)
	if def.roof == "flat" then
		part(m, "Roof", Vector3.new(w + 1, 0.6, d + 1), at(0, top + 1.3, 0), def.roofColor, Enum.Material.Concrete)
		for _, sx in { -1, 1 } do
			part(
				m,
				"Parapet",
				Vector3.new(0.8, 3, d + 1),
				at(sx * (w / 2 + 0.1), top + 2.9, 0),
				def.trim,
				Enum.Material.Concrete
			)
		end
		for _, sz in { -1, 1 } do
			part(
				m,
				"Parapet",
				Vector3.new(w + 1, 3, 0.8),
				at(0, top + 2.9, sz * (d / 2 + 0.1)),
				def.trim,
				Enum.Material.Concrete
			)
		end
	else
		local rh = if def.roof == "hip" then 7 else 10
		local ov = 1.5
		for _, side in { -1, 1 } do
			local wedge = Instance.new("WedgePart")
			wedge.Name = "Roof"
			wedge.Anchored = true
			wedge.Size = Vector3.new(w + ov * 2, rh, d / 2 + ov)
			wedge.CFrame = at(0, top + 1 + rh / 2, side * (d / 4 + ov / 2))
				* CFrame.Angles(0, if side == 1 then math.pi else 0, 0)
			wedge.Color = def.roofColor
			wedge.Material = Enum.Material.Slate
			wedge.Parent = m
		end
	end

	-- front door (the server decides who can open it, see HouseService)
	local door = part(m, "Door", Vector3.new(6, 9, 0.6), at(0, 5, -d / 2 + T / 2), def.trim, Enum.Material.Wood)
	part(
		m,
		"DoorStep",
		Vector3.new(8, 0.6, 3),
		at(0, 0.3, -d / 2 - 1.5),
		Color3.fromRGB(150, 150, 150),
		Enum.Material.Concrete
	)
	part(
		m,
		"HouseNumberLight",
		Vector3.new(1, 1, 0.2),
		at(4.5, 9, -d / 2 - 0.1),
		Color3.fromRGB(255, 240, 200),
		Enum.Material.Neon
	)

	-- extras next to / behind the house
	if def.garage then
		local gx = w / 2 + 2 + gw / 2 -- right next to the house
		do
			-- a real garage you can drive into: back + side walls, roof, floor, the
			-- roller door rolled up under the roof
			local gz, gd, gh = -d / 2 + 11, 22, 10
			part(
				m,
				"GarageFloor",
				Vector3.new(gw, 0.4, gd),
				at(gx, 0.2, gz),
				Color3.fromRGB(150, 150, 155),
				Enum.Material.Concrete
			)
			part(m, "GarageBack", Vector3.new(gw, gh, 0.8), at(gx, gh / 2, gz + gd / 2 - 0.4), def.wall, def.material)
			for _, sx in { -1, 1 } do
				part(
					m,
					"GarageSide",
					Vector3.new(0.8, gh, gd),
					at(gx + sx * (gw / 2 - 0.4), gh / 2, gz),
					def.wall,
					def.material
				)
			end
			part(m, "Garage", Vector3.new(gw, 1.6, 0.8), at(gx, gh - 0.8, gz - gd / 2 + 0.4), def.wall, def.material)
			part(
				m,
				"GarageRoof",
				Vector3.new(gw + 1, 0.6, gd + 1),
				at(gx, gh + 0.3, gz),
				def.roofColor,
				Enum.Material.Concrete
			)
			part(
				m,
				"GarageDoor",
				Vector3.new(gw - 2, 0.6, 3),
				at(gx, gh - 2, gz - gd / 2 + 2),
				Color3.fromRGB(200, 200, 205),
				Enum.Material.DiamondPlate
			)
			local light = part(
				m,
				"GarageLight",
				Vector3.new(2, 0.2, 2),
				at(gx, gh - 0.2, gz),
				Color3.fromRGB(250, 248, 240),
				Enum.Material.Neon
			)
			light.CanCollide = false
			local l = Instance.new("PointLight")
			l.Range = 16
			l.Brightness = 0.5
			l.Parent = light
			part(
				m,
				"Driveway",
				Vector3.new(gw - 2, 0.25, 10),
				plotAt(hx + gx, 0.13, -PD / 2 + 5),
				Color3.fromRGB(120, 120, 125),
				Enum.Material.Concrete
			)
		end
	end
	local backZ = d / 2
	if def.terrace then
		part(
			m,
			"Terrace",
			Vector3.new(w, 0.8, 8),
			at(0, 0.4, backZ + 4),
			Color3.fromRGB(150, 110, 70),
			Enum.Material.WoodPlanks
		)
		backZ += 8
	end
	if def.pool then
		local pz = backZ + 8
		local pw, pd = math.min(30, w - 6), 12
		if hz + pz + pd / 2 < PD / 2 - 2 then
			part(
				m,
				"PoolEdge",
				Vector3.new(pw + 3, 0.6, pd + 3),
				at(0, 0.3, pz),
				Color3.fromRGB(235, 232, 225),
				Enum.Material.Marble
			)
			part(
				m,
				"Pool",
				Vector3.new(pw, 0.4, pd),
				at(0, 0.55, pz),
				Color3.fromRGB(40, 150, 220),
				Enum.Material.Glass,
				{
					Transparency = 0.25,
					CanCollide = false,
				}
			)
		end
	end

	m.PrimaryPart = door
	return {
		model = m,
		door = door,
		inside = at(0, 3.5, -d / 2 + 4),
		outside = at(0, 3.5, -d / 2 - 5) * CFrame.Angles(0, math.pi, 0),
		bounds = { cf = at(0, top / 2 + 0.5, 0), size = Vector3.new(w - 2 * T - 0.2, top, d - 2 * T - 0.2) },
		nameLabel = nameLabel,
		mailbox = box,
		floorTops = floorTops,
	}
end

return HouseBuilder
