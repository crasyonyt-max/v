--!strict
-- Automated Stadtbahn (U43) on an elevated viaduct above its real route through the
-- city centre (Shared/TrainData from OpenStreetMap, timetable in Shared/TrainLine).
--   * stations with two side platforms, stairs prompt from the street, departure boards
--   * TrainLine.TRAINS trains per line, two cars each, moved by the server (rigid
--     AlignPosition / AlignOrientation, so clients see them smoothly)
--   * get on while the train waits at a station (free); get off at any station.
--     Jumping off between stations puts you on the next platform; at the end of the
--     line everybody gets off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TrainLine = require(ReplicatedStorage.Shared.TrainLine)
local CityBuilder = require(script.Parent.CityBuilder)
local Remotes = require(script.Parent.Remotes)

local TrainService = {}

local function now(): number
	local ok, t = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	return if ok and typeof(t) == "number" then t else os.time()
end

local HEIGHT = 26 -- deck above the street (studs)
local DECK_W = 24
local TRACK = 6 -- track centre from the viaduct centre line
local PLAT_OFF = 16.5 -- platform centre from the centre line
local PLAT_W, PLAT_L = 9, 110
local CAR_L, CAR_W, CAR_H = 46, 9, 11
local CAR_GAP = 48 -- car centre to car centre
local PILLAR_EVERY = 60

local CONCRETE = Color3.fromRGB(165, 165, 160)
local DARK = Color3.fromRGB(55, 58, 62)

type TrainRec = {
	line: TrainLine.Line,
	k: number,
	cars: { Model },
	targets: { { pos: AlignPosition, rot: AlignOrientation } },
	last: TrainLine.State?,
}
local trains: { TrainRec } = {}
local deckY: { [TrainLine.Line]: { number } } = {}
TrainService.Trains = trains

local folder = Instance.new("Folder")
folder.Name = "Stadtbahn"

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

local function label(p: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3, ppu: number?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppu or 25
	gui.LightInfluence = 0
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = bg
	l.BorderSizePixel = 0
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color
	l.Text = text
	l.RichText = true
	l.Parent = gui
	return l
end

-- deck height at distance s (interpolated between path points)
local function yAt(line: TrainLine.Line, s: number): number
	local ys = deckY[line]
	local cum = line.cum
	s = math.clamp(s, 0, line.length)
	local lo, hi = 1, #cum
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if cum[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local seg = cum[hi] - cum[lo]
	local f = if seg > 0 then (s - cum[lo]) / seg else 0
	return ys[lo] + (ys[hi] - ys[lo]) * f
end

-- frame on the viaduct at s, looking in direction dir (+X = right of travel)
local function frameAt(line: TrainLine.Line, s: number, dir: number): CFrame
	local p = TrainLine.At(line, s)
	local a = TrainLine.At(line, s - 12 * dir)
	local b = TrainLine.At(line, s + 12 * dir)
	local look = (b - a) * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, dir)
	end
	local pos = Vector3.new(p.X, yAt(line, s), p.Z)
	return CFrame.lookAt(pos, pos + look.Unit)
end
TrainService.FrameAt = frameAt

-- where a rider gets off: the platform on the side of the travel direction
local function platformSpot(line: TrainLine.Line, station: number, dir: number, along: number?): CFrame
	local st = line.stations[station]
	local f = frameAt(line, st.s + (along or 0), dir)
	return f * CFrame.new(PLAT_OFF, 4.5, 0)
end
TrainService.PlatformSpot = platformSpot

-- Viaduct ---------------------------------------------------------------------------

local function buildViaduct(line: TrainLine.Line, parent: Instance)
	-- deck heights: ground + HEIGHT, smoothed so the line has no bumps
	local raw = {}
	for i, p in line.points do
		raw[i] = CityBuilder.GroundY(p.X, p.Z) + HEIGHT
	end
	local ys = {}
	for i = 1, #raw do
		local sum, n = 0, 0
		for j = math.max(1, i - 6), math.min(#raw, i + 6) do
			sum += raw[j]
			n += 1
		end
		ys[i] = sum / n
	end
	deckY[line] = ys

	local m = Instance.new("Model")
	m.Name = "Viadukt " .. line.id
	local pts = line.points
	local nextPillar = 0
	for i = 1, #pts - 1 do
		local a = Vector3.new(pts[i].X, ys[i], pts[i].Z)
		local b = Vector3.new(pts[i + 1].X, ys[i + 1], pts[i + 1].Z)
		local len = (b - a).Magnitude
		if len < 0.05 then
			continue
		end
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(mid, b)
		box(m, "Deck", Vector3.new(DECK_W, 2, len + 1.2), cf * CFrame.new(0, -1, 0), CONCRETE, Enum.Material.Concrete)
		for _, sx in { -1, 1 } do
			box(
				m,
				"Parapet",
				Vector3.new(0.8, 2.2, len + 1.2),
				cf * CFrame.new(sx * (DECK_W / 2 - 0.4), 1.1, 0),
				CONCRETE,
				Enum.Material.Concrete
			)
			-- two tracks: rails + a ballast bed
			local tx = sx * TRACK
			box(
				m,
				"Bed",
				Vector3.new(6, 0.4, len + 1.2),
				cf * CFrame.new(tx, 0.2, 0),
				Color3.fromRGB(110, 100, 90),
				Enum.Material.Slate
			)
			for _, rx in { -1.75, 1.75 } do
				box(
					m,
					"Rail",
					Vector3.new(0.3, 0.4, len + 1.2),
					cf * CFrame.new(tx + rx, 0.6, 0),
					Color3.fromRGB(120, 120, 125),
					Enum.Material.Metal
				)
			end
		end
		-- pillars
		while nextPillar <= line.cum[i + 1] do
			local f = (nextPillar - line.cum[i]) / math.max(line.cum[i + 1] - line.cum[i], 0.01)
			local top = a:Lerp(b, math.clamp(f, 0, 1))
			local ground = CityBuilder.GroundY(top.X, top.Z)
			local h = top.Y - 2 - ground
			if h > 2 then
				box(
					m,
					"Pillar",
					Vector3.new(3.5, h, 3.5),
					CFrame.new(top.X, ground + h / 2, top.Z) * (cf - cf.Position),
					CONCRETE,
					Enum.Material.Concrete
				)
				box(
					m,
					"PillarHead",
					Vector3.new(DECK_W - 4, 2, 4),
					CFrame.new(top.X, top.Y - 3, top.Z) * (cf - cf.Position),
					CONCRETE,
					Enum.Material.Concrete
				)
			end
			nextPillar += PILLAR_EVERY
		end
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanTouch = false
		end
	end
	m.Parent = parent
	-- trees and street lights that would stick into the viaduct go
	pcall(function()
		local city = Workspace:FindFirstChild("City")
		if not city then
			return
		end
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		local list = {}
		for _, name in { "Trees", "StreetLights" } do
			local f = city:FindFirstChild(name, true)
			if f then
				table.insert(list, f)
			end
		end
		params.FilterDescendantsInstances = list
		for _, deck in m:GetChildren() do
			if deck.Name == "Deck" and deck:IsA("BasePart") then
				for _, hit in
					Workspace:GetPartBoundsInBox(
						deck.CFrame * CFrame.new(0, 2, 0),
						deck.Size + Vector3.new(4, 22, 0),
						params
					)
				do
					hit:Destroy()
				end
			end
		end
	end)
end

-- Stations ---------------------------------------------------------------------------

local stairs: { { prompt: ProximityPrompt, to: CFrame } } = {} -- wired in Start
local boards: { { line: TrainLine.Line, station: number, dir: number, text: TextLabel } } = {}

local function buildStation(line: TrainLine.Line, i: number, parent: Instance)
	local st = line.stations[i]
	local m = Instance.new("Model")
	m.Name = "U-Bahnhof " .. st.name
	for _, dir in { 1, -1 } do
		local f = frameAt(line, st.s, dir)
		local function at(x: number, y: number, z: number): CFrame
			return f * CFrame.new(x, y, z)
		end
		-- platform on the right of this direction
		box(
			m,
			"Platform",
			Vector3.new(PLAT_W, 2.5, PLAT_L),
			at(PLAT_OFF, 1.25, 0),
			Color3.fromRGB(200, 198, 192),
			Enum.Material.Concrete
		)
		box(
			m,
			"Edge",
			Vector3.new(0.6, 0.06, PLAT_L),
			at(PLAT_OFF - PLAT_W / 2 + 0.6, 2.53, 0),
			Color3.fromRGB(255, 255, 255),
			Enum.Material.SmoothPlastic
		)
		box(
			m,
			"Wall",
			Vector3.new(0.6, 8, PLAT_L),
			at(PLAT_OFF + PLAT_W / 2, 6.5, 0),
			Color3.fromRGB(150, 175, 190),
			Enum.Material.Glass,
			{ Transparency = 0.4 }
		)
		box(m, "Roof", Vector3.new(PLAT_W + 2, 0.6, PLAT_L), at(PLAT_OFF, 11, 0), DARK, Enum.Material.Metal)
		for z = -PLAT_L / 2 + 6, PLAT_L / 2 - 6, 24 do
			box(m, "RoofPost", Vector3.new(0.6, 8.5, 0.6), at(PLAT_OFF + 3.5, 6.75, z), DARK, Enum.Material.Metal)
			box(
				m,
				"Bench",
				Vector3.new(1.4, 0.4, 6),
				at(PLAT_OFF + 3, 4.1, z + 12),
				Color3.fromRGB(150, 110, 75),
				Enum.Material.Wood
			)
		end
		-- the platform sticks out of the viaduct: supports down to the street
		local groundY = CityBuilder.GroundY(f.Position.X, f.Position.Z)
		for z = -PLAT_L / 2 + 8, PLAT_L / 2 - 8, 32 do
			local h = f.Position.Y - groundY
			if h > 2 then
				box(
					m,
					"PlatformPillar",
					Vector3.new(2.5, h, 2.5),
					at(PLAT_OFF + 2, -h / 2, z),
					CONCRETE,
					Enum.Material.Concrete
				)
			end
		end
		-- glass ends
		for _, z in { -PLAT_L / 2 + 0.2, PLAT_L / 2 - 0.2 } do
			box(
				m,
				"EndWall",
				Vector3.new(PLAT_W, 3.5, 0.4),
				at(PLAT_OFF, 4.25, z),
				Color3.fromRGB(150, 175, 190),
				Enum.Material.Glass,
				{ Transparency = 0.4 }
			)
		end
		-- name sign (both sides) + departure board facing the platform
		local sign = box(
			m,
			"StationSign",
			Vector3.new(0.3, 2.2, 16),
			at(PLAT_OFF + PLAT_W / 2 - 0.6, 8.6, -20),
			Color3.fromRGB(0, 70, 160)
		)
		label(sign, Enum.NormalId.Left, "🅄  " .. st.name, Color3.new(1, 1, 1), Color3.fromRGB(0, 70, 160))
		local boardPart =
			box(m, "Board", Vector3.new(0.3, 3.6, 10), at(PLAT_OFF + PLAT_W / 2 - 0.6, 8, 18), Color3.new())
		local text =
			label(boardPart, Enum.NormalId.Left, "", Color3.fromRGB(255, 190, 40), Color3.fromRGB(10, 10, 14), 40)
		text.Font = Enum.Font.Code
		table.insert(boards, { line = line, station = i, dir = dir, text = text })

		-- access from the street: a "U" pole and a prompt that takes you up; "Ausgang" back down
		local ground = CityBuilder.GroundY(f.Position.X, f.Position.Z)
		local streetCf = CFrame.new(Vector3.new(0, ground - f.Position.Y, 0))
			* at(PLAT_OFF + PLAT_W / 2 + 5, 0, -PLAT_L / 2 + 8)
		box(m, "UPole", Vector3.new(0.5, 9, 0.5), streetCf * CFrame.new(0, 4.5, 0), DARK, Enum.Material.Metal)
		local cube =
			box(m, "USign", Vector3.new(2.6, 2.6, 2.6), streetCf * CFrame.new(0, 10, 0), Color3.fromRGB(0, 70, 160))
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
			label(cube, face, "U", Color3.new(1, 1, 1), Color3.fromRGB(0, 70, 160), 30)
		end
		local up =
			box(m, "Marker_TrainUp", Vector3.new(3, 3, 3), streetCf * CFrame.new(0, 2, 0), Color3.new(1, 1, 1), nil, {
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
			})
		local upPrompt = Instance.new("ProximityPrompt")
		upPrompt.ActionText = "Zum Bahnsteig"
		upPrompt.ObjectText = ("U%s Richtung %s"):format(line.id:sub(2), TrainLine.Destination(line, dir))
		upPrompt.HoldDuration = 0.3
		upPrompt.MaxActivationDistance = 10
		upPrompt.RequiresLineOfSight = false
		upPrompt.Parent = up
		local topSpot = at(PLAT_OFF + 1, 5.5, -PLAT_L / 2 + 10)
		table.insert(stairs, { prompt = upPrompt, to = topSpot })
		local down = box(
			m,
			"Marker_TrainDown",
			Vector3.new(3, 3, 3),
			at(PLAT_OFF + 2, 4.5, -PLAT_L / 2 + 4),
			Color3.new(1, 1, 1),
			nil,
			{
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
			}
		)
		local downPrompt = Instance.new("ProximityPrompt")
		downPrompt.ActionText = "Ausgang"
		downPrompt.ObjectText = st.name
		downPrompt.HoldDuration = 0.3
		downPrompt.MaxActivationDistance = 10
		downPrompt.RequiresLineOfSight = false
		downPrompt.Parent = down
		local streetSpot = streetCf * CFrame.new(-2, 3, 3)
		table.insert(stairs, { prompt = downPrompt, to = streetSpot })
	end
	m.Parent = parent
end

-- Trains -----------------------------------------------------------------------------

local function buildCar(
	line: TrainLine.Line,
	k: number,
	idx: number,
	origin: CFrame
): (Model, AlignPosition, AlignOrientation)
	local m = Instance.new("Model")
	m.Name = ("U%s Zug %d Wagen %d"):format(line.id:sub(2), k, idx)
	m:SetAttribute("Train", true)
	m:SetAttribute("Line", line.id)
	m:SetAttribute("TrainNo", k)
	local root = box(m, "Root", Vector3.new(CAR_W - 1, 1, CAR_L - 2), origin * CFrame.new(0, 0.5, 0), DARK)
	root.Anchored = false
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Transparency = 1
	m.PrimaryPart = root
	local function part(
		name: string,
		size: Vector3,
		offset: CFrame,
		color: Color3,
		material: Enum.Material?,
		transparency: number?
	): Part
		local p = box(m, name, size, origin * offset, color, material, {
			Anchored = false,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Massless = true,
			Transparency = transparency or 0,
		})
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
		return p
	end
	local white = Color3.fromRGB(235, 235, 232)
	part("Floor", Vector3.new(CAR_W, 0.6, CAR_L), CFrame.new(0, 1.2, 0), Color3.fromRGB(70, 70, 75))
	part("Skirt", Vector3.new(CAR_W - 0.6, 1.4, CAR_L - 4), CFrame.new(0, 0.3, 0), DARK)
	part("Roof", Vector3.new(CAR_W, 0.8, CAR_L), CFrame.new(0, CAR_H, 0), white)
	for _, sx in { -1, 1 } do
		part("Lower", Vector3.new(0.4, 3.4, CAR_L), CFrame.new(sx * CAR_W / 2, 2.9, 0), line.color)
		part(
			"Window",
			Vector3.new(0.3, 4.6, CAR_L - 1),
			CFrame.new(sx * CAR_W / 2, 6.9, 0),
			Color3.fromRGB(40, 55, 65),
			Enum.Material.Glass,
			0.45
		)
		part("Upper", Vector3.new(0.4, 1.4, CAR_L), CFrame.new(sx * CAR_W / 2, 9.9, 0), white)
	end
	-- cab ends (the train runs both ways: car 1 at the front end, car 2 at the back end)
	local endZ = if idx == 1 then -CAR_L / 2 else CAR_L / 2
	part("Cab", Vector3.new(CAR_W, 9.6, 0.6), CFrame.new(0, 6, endZ), line.color)
	local led = part(
		"Destination",
		Vector3.new(CAR_W - 2, 1.2, 0.2),
		CFrame.new(0, 9.8, endZ + (if idx == 1 then -0.4 else 0.4)),
		Color3.new()
	)
	local ledText = label(
		led,
		if idx == 1 then Enum.NormalId.Front else Enum.NormalId.Back,
		"",
		Color3.fromRGB(255, 170, 30),
		Color3.new(),
		40
	)
	ledText.Font = Enum.Font.Arcade
	ledText.Name = "DestText"
	part(
		"Windshield",
		Vector3.new(CAR_W - 1.5, 3.6, 0.2),
		CFrame.new(0, 6.4, endZ + (if idx == 1 then -0.4 else 0.4)),
		Color3.fromRGB(30, 40, 50),
		Enum.Material.Glass,
		0.2
	)
	part("Coupler", Vector3.new(CAR_W, 9.6, 0.6), CFrame.new(0, 6, -endZ), Color3.fromRGB(40, 40, 44))
	-- seats: 2 + 2 per row, facing forward
	local n = 0
	for z = -CAR_L / 2 + 6, CAR_L / 2 - 6, 4.6 do
		for _, x in { -3.2, -1.5, 1.5, 3.2 } do
			n += 1
			part(
				"SeatBack",
				Vector3.new(1.6, 2.4, 0.3),
				CFrame.new(x, 3.4, z + 0.9),
				line.color:Lerp(Color3.new(0, 0, 0), 0.3)
			)
			local seat = Instance.new("Seat")
			seat.Name = "Seat" .. n
			seat.Size = Vector3.new(1.6, 0.3, 1.6)
			seat.CFrame = origin * CFrame.new(x, 2.1, z)
			seat.Color = line.color:Lerp(Color3.new(0, 0, 0), 0.3)
			seat.CanCollide = false
			seat.CanTouch = false
			seat.Massless = true
			seat.Parent = m
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = seat
			w.Parent = seat
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "EnterPrompt"
			prompt.ActionText = "Einsteigen"
			prompt.ObjectText = "U" .. line.id:sub(2)
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Enabled = false
			prompt.Parent = seat
		end
	end
	local att = Instance.new("Attachment")
	att.Name = "Drive"
	att.Parent = root
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.RigidityEnabled = true
	ap.Position = root.CFrame.Position
	ap.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.RigidityEnabled = true
	ao.CFrame = root.CFrame - root.CFrame.Position
	ao.Parent = root
	return m, ap, ao
end

-- car cframes for a train state: car 1 at the higher-distance end, on the track to the
-- right of the travel direction
local function carFrames(line: TrainLine.Line, state: TrainLine.State): { CFrame }
	local out = {}
	for idx = 1, 2 do
		local s = state.s + (if idx == 1 then CAR_GAP / 2 else -CAR_GAP / 2)
		local f = frameAt(line, s, 1) -- car 1 always faces +s; dir -1 trains run backwards on the other track
		local offset = if state.dir == 1 then TRACK else -TRACK
		out[idx] = f * CFrame.new(offset, 0.6, 0)
	end
	return out
end
TrainService.CarFrames = carFrames

local function playerOn(seat: Seat): Player?
	local hum = seat.Occupant
	return hum and Players:GetPlayerFromCharacter(hum.Parent)
end

-- take every rider out and put them on the platform (end of the line)
local function emptyTrain(rec: TrainRec, station: number, dir: number)
	for _, car in rec.cars do
		for _, seat in car:GetChildren() do
			if seat:IsA("Seat") then
				local p = playerOn(seat)
				local weld = seat:FindFirstChild("SeatWeld")
				if p and weld then
					weld:Destroy()
					local c = p.Character
					if c then
						c:PivotTo(platformSpot(rec.line, station, dir, math.random(-30, 30)))
					end
					Remotes.Push(p, "Notify", { key = "train_end_of_line" })
				end
			end
		end
	end
end

local function step()
	local t = now()
	for _, rec in trains do
		local state = TrainLine.State(rec.line, rec.k, t)
		local last = rec.last
		-- arrived at the end of the line: everybody off (before the train turns round)
		if state.terminus and last and not last.terminus and state.station then
			emptyTrain(rec, state.station, last.dir)
		end
		local frames = carFrames(rec.line, state)
		local teleport = last and last.dir ~= state.dir
		for idx, car in rec.cars do
			local target = rec.targets[idx]
			target.pos.Position = frames[idx].Position
			target.rot.CFrame = frames[idx] - frames[idx].Position
			if teleport then
				car:PivotTo(frames[idx])
			end
		end
		if not last or last.dwelling ~= state.dwelling or last.station ~= state.station or last.dir ~= state.dir then
			local dest = TrainLine.Destination(rec.line, state.dir)
			local stationName = if state.station then rec.line.stations[state.station].name else ""
			for _, car in rec.cars do
				car:SetAttribute("Dir", state.dir)
				car:SetAttribute("Dest", dest)
				car:SetAttribute("AtStation", state.dwelling)
				car:SetAttribute("Station", stationName)
				car:SetAttribute("StationIndex", state.station or 0)
				for _, seat in car:GetChildren() do
					local prompt = seat:IsA("Seat") and seat:FindFirstChild("EnterPrompt")
					if prompt and prompt:IsA("ProximityPrompt") then
						prompt.Enabled = state.dwelling and seat.Occupant == nil
					end
				end
				local led = car:FindFirstChild("Destination")
				local text = led and led:FindFirstChild("DestText", true)
				if text and text:IsA("TextLabel") then
					text.Text = "U" .. rec.line.id:sub(2) .. "  " .. dest
				end
			end
		end
		rec.last = state
	end
end
TrainService.Step = step

local function boardText(line: TrainLine.Line, station: number, dir: number, t: number): string
	local deps = TrainLine.Departures(line, station, dir, t)
	if #deps == 0 then
		return "  Endstation\n  Bitte nicht einsteigen"
	end
	local dest = TrainLine.Destination(line, dir)
	local rows = {}
	for i = 1, math.min(2, #deps) do
		local secs = deps[i]
		local when = if secs < 30 then "sofort" else math.ceil(secs / 60) .. " min"
		table.insert(rows, ("  U%s %-16s %s"):format(line.id:sub(2), dest, when))
	end
	return table.concat(rows, "\n")
end
TrainService.BoardText = boardText

function TrainService.Build()
	for _, line in TrainLine.Lines do
		buildViaduct(line, folder)
		for i = 1, #line.stations do
			buildStation(line, i, folder)
		end
		for k = 1, TrainLine.TRAINS do
			local rec: TrainRec = { line = line, k = k, cars = {}, targets = {}, last = nil }
			local state = TrainLine.State(line, k, now())
			local frames = carFrames(line, state)
			for idx = 1, 2 do
				local car, ap, ao = buildCar(line, k, idx, frames[idx])
				ap.Position = frames[idx].Position
				ao.CFrame = frames[idx] - frames[idx].Position
				rec.cars[idx] = car
				rec.targets[idx] = { pos = ap, rot = ao }
				car.Parent = folder
			end
			table.insert(trains, rec)
		end
	end
	folder.Parent = Workspace
end

function TrainService.Start()
	for _, st in stairs do
		st.prompt.Triggered:Connect(function(player)
			local c = player.Character
			if c then
				c:PivotTo(st.to)
			end
		end)
	end
	for _, rec in trains do
		for _, car in rec.cars do
			local root = car.PrimaryPart :: BasePart
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
			for _, s in car:GetChildren() do
				if not s:IsA("Seat") then
					continue
				end
				local seat = s :: Seat
				local prompt = seat:FindFirstChild("EnterPrompt") :: ProximityPrompt
				prompt.Triggered:Connect(function(player)
					local c = player.Character
					local hum = c and c:FindFirstChildOfClass("Humanoid")
					if
						hum
						and hum.Health > 0
						and not hum.SeatPart
						and not seat.Occupant
						and car:GetAttribute("AtStation")
					then
						seat:Sit(hum)
					end
				end)
				local lastHum: Humanoid? = nil
				seat:GetPropertyChangedSignal("Occupant"):Connect(function()
					local hum = seat.Occupant
					prompt.Enabled = hum == nil and car:GetAttribute("AtStation") == true
					if hum then
						lastHum = hum
						return
					end
					-- got off: onto this station's platform, or the next one if still moving
					local character = lastHum and lastHum.Parent
					lastHum = nil
					local state = rec.last
					if not character or not character:IsA("Model") or not state or not state.station then
						return
					end
					local spot = platformSpot(
						rec.line,
						state.station,
						state.dir,
						if state.dwelling then math.random(-20, 20) else 0
					)
					task.defer(function()
						character:PivotTo(spot)
					end)
				end)
			end
		end
	end
	RunService.Heartbeat:Connect(step)
	-- departure boards
	task.spawn(function()
		while true do
			local t = now()
			for _, b in boards do
				b.text.Text = boardText(b.line, b.station, b.dir, t)
			end
			task.wait(1)
		end
	end)
end

return TrainService
