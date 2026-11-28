--!strict
-- 🎄 Advent (Config.Advent, "test" = testing server first; rules in Shared/Advent):
--   * Adventskalender: "Advent.Get" / "Advent.Open" (one door a day, each door once,
--     claimed atomically in its own store so no second server can pay it again)
--   * Weihnachtsmarkt on the lawn behind the Parlament (built in December)
--   * workspace attribute "AdventSeason": the client hangs Christmas lights on the
--     street lamps, WorldService lets it snow more often

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Advent = require(ReplicatedStorage.Shared.Advent)
local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local Locale = require(ReplicatedStorage.Shared.Locale)
local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local DataStoreService = require(script.Parent.Sandbox).DataStoreService -- local only on the testing server
local Economy = require(script.Parent.EconomyService)
local GameLog = require(script.Parent.GameLog)
local Interaction = require(script.Parent.InteractionService)
local ParliamentBuilder = require(script.Parent.ParliamentBuilder)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local StoreService = require(script.Parent.StoreService)
local TowerBuilder = require(script.Parent.TowerBuilder)
local WorldService = require(script.Parent.WorldService)
local XPService = require(script.Parent.XPService)

local AdventService = {}

local function on(): boolean
	return Config.On(Config.Advent)
end

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName .. "_Advent")
end)
local memory: { [number]: { [string]: number } } = {} -- Studio / tests without DataStores

-- the doors this player opened: { ["1"] = time, ... }
local function opened(userId: number): { [string]: number }?
	if not store then
		return memory[userId] or {}
	end
	local ok, v = pcall(function()
		return (store :: DataStore):GetAsync("u_" .. userId)
	end)
	if not ok then
		return nil
	end
	return if typeof(v) == "table" and typeof(v.doors) == "table" then v.doors else {}
end

-- "new" = open it now · "opened" = already opened · "error" = try again
function AdventService.Claim(userId: number, door: number | string): string
	local key = tostring(door)
	if not store then
		local doors = memory[userId] or {}
		memory[userId] = doors
		if doors[key] then
			return "opened"
		end
		doors[key] = os.time()
		return "new"
	end
	local result = "error"
	local ok = pcall(function()
		(store :: DataStore):UpdateAsync("u_" .. userId, function(old: any)
			local v = if typeof(old) == "table" then old else { doors = {} }
			v.doors = if typeof(v.doors) == "table" then v.doors else {}
			if v.doors[key] then
				result = "opened"
				return nil
			end
			v.doors[key] = os.time()
			result = "new"
			return v
		end)
	end)
	return if ok then result else "error"
end

-- pays a door's reward; returns the reward as it was given (items that did not fit
-- in the bag are paid as cash: twice their price)
function AdventService.Give(player: Player, door: number): { cash: number, xp: number, items: { string } }
	local r = Advent.Rewards[door] or {}
	local cash, xp, items = r.cash or 0, r.xp or 0, {}
	for _, id in r.items or {} do
		if StoreService.Give(player, id) then
			table.insert(items, id)
		else
			local it = Items.ById[id]
			cash += math.ceil((if it then it.price else 2) * 2)
		end
	end
	local reason = "Adventskalender: Türchen " .. door
	if cash > 0 then
		Economy.Add(player, cash, reason)
	end
	if xp > 0 then
		XPService.Add(player, nil, xp, reason)
	end
	GameLog.Add("money", player, ("advent door %d: %d € %d XP %d items"):format(door, cash, xp, #items))
	return { cash = cash, xp = xp, items = items, outfit = r.outfit }
end

-- Christmas outfit ----------------------------------------------------------------------

local ownedCache: { [Player]: { [string]: boolean } } = {}

local function piecePart(
	m: Model,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	shape: Enum.PartType?,
	material: Enum.Material?
): BasePart
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = m
	return p
end

local RED = Color3.fromRGB(190, 20, 30)
local WHITE = Color3.fromRGB(250, 250, 250)
local BROWN = Color3.fromRGB(120, 80, 45)
local CYL, BALL = Enum.PartType.Cylinder, Enum.PartType.Ball
local UP = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder standing up

-- builds one piece around the head (front = -Z); all parts welded to the head
function AdventService.BuildPiece(piece: string, head: BasePart): Model?
	local s = head.Size
	local k = math.min(s.X, s.Z) / 1.2 -- 1 = a normal head
	local top = head.CFrame * CFrame.new(0, s.Y * 0.32, 0)
	local m = Instance.new("Model")
	m.Name = "Xmas_" .. piece
	if piece == "hat" then
		piecePart(m, Vector3.new(0.32, 1.32, 1.32) * k, top * UP, WHITE, CYL, Enum.Material.Snow)
		-- the red cone, leaning back, out of shrinking discs
		local cf = top * CFrame.new(0, 0.2 * k, 0)
		for i = 0, 5 do
			local d = (1.18 - i * 0.18) * k
			cf = cf * CFrame.new(0, 0.2 * k, 0) * CFrame.Angles(math.rad(-9), 0, 0) * CFrame.new(0, 0, 0.04 * k)
			piecePart(m, Vector3.new(0.26 * k, d, d), cf * UP, RED, CYL)
		end
		piecePart(m, Vector3.one * 0.38 * k, cf * CFrame.new(0, 0.25 * k, 0.05 * k), WHITE, BALL, Enum.Material.Snow)
	elseif piece == "scarf" then
		local neck = head.CFrame * CFrame.new(0, -s.Y * 0.55, 0)
		for i = 0, 11 do
			local a = i / 12 * math.pi * 2
			piecePart(
				m,
				Vector3.new(0.32, 0.3, 0.3) * k,
				neck * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.52 * k),
				if i % 2 == 0 then RED else Color3.fromRGB(30, 120, 60)
			)
		end
		-- the hanging end in front
		for j = 1, 3 do
			piecePart(
				m,
				Vector3.new(0.3, 0.32, 0.12) * k,
				neck * CFrame.new(0.28 * k, -j * 0.3 * k, -0.6 * k),
				if j % 2 == 0 then RED else Color3.fromRGB(30, 120, 60)
			)
		end
	elseif piece == "antlers" then
		for _, side in { -1, 1 } do
			local base = top * CFrame.new(side * 0.32 * k, 0, 0.05 * k)
			local main = base * CFrame.Angles(0, 0, -side * math.rad(28)) * CFrame.new(0, 0.45 * k, 0)
			piecePart(m, Vector3.new(0.9 * k, 0.14 * k, 0.14 * k), main * UP, BROWN, CYL, Enum.Material.Wood)
			for t = 1, 2 do
				local tine = main
					* CFrame.new(0, (t * 0.25 - 0.1) * k, 0)
					* CFrame.Angles(0, 0, side * math.rad(55))
					* CFrame.new(0, 0.18 * k, 0)
				piecePart(m, Vector3.new(0.4 * k, 0.11 * k, 0.11 * k), tine * UP, BROWN, CYL, Enum.Material.Wood)
			end
		end
		-- Rudolph's nose
		local nose = piecePart(
			m,
			Vector3.one * 0.3 * k,
			head.CFrame * CFrame.new(0, -s.Y * 0.05, -s.Z * 0.52),
			Color3.fromRGB(255, 30, 30),
			BALL,
			Enum.Material.Neon
		)
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 40, 40)
		glow.Range = 6
		glow.Brightness = 1.5
		glow.Parent = nose
	else
		m:Destroy()
		return nil
	end
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") then
			local w = Instance.new("WeldConstraint")
			w.Part0 = head
			w.Part1 = p
			w.Parent = p
		end
	end
	return m
end

local function wearing(player: Player): { [string]: boolean }
	local data = DataService.Get(player)
	local w = data and data.xmasWear
	return if typeof(w) == "table" then w else {}
end

function AdventService.ApplyOutfit(player: Player)
	local char = player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not char or not head then
		return
	end
	local old = char:FindFirstChild("XmasOutfit")
	if old then
		old:Destroy()
	end
	local owned = ownedCache[player] or {}
	local folder = Instance.new("Folder")
	folder.Name = "XmasOutfit"
	for piece, on in wearing(player) do
		if on and owned[piece] and Advent.Outfit[piece] then
			local m = AdventService.BuildPiece(piece, head)
			if m then
				m.Parent = folder
			end
		end
	end
	folder.Parent = char
end

-- Weihnachtsmarkt ---------------------------------------------------------------------

local WOOD = Color3.fromRGB(120, 78, 45)
local WOOD_DARK = Color3.fromRGB(85, 52, 30)
local SNOW = Color3.fromRGB(245, 248, 252)
local BULBS = {
	Color3.fromRGB(255, 200, 90),
	Color3.fromRGB(255, 60, 60),
	Color3.fromRGB(80, 200, 90),
	Color3.fromRGB(255, 230, 150),
}

local function box(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	class: string?
): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function bulb(parent: Instance, cf: CFrame, color: Color3, size: number?, light: boolean?)
	local b = box(parent, "Bulb", Vector3.one * (size or 0.6), cf, color, Enum.Material.Neon)
	b.Shape = Enum.PartType.Ball
	b.CanCollide = false
	b.CanQuery = false
	b.CastShadow = false
	if light then
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = 14
		l.Brightness = 1.2
		l.Shadows = false
		l.Parent = b
	end
end

local function sign(part: BasePart, text: string, color: Color3)
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Front
	g.CanvasSize = Vector2.new(400, 100)
	g.LightInfluence = 0
	g.Parent = part
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Fondamento
	l.TextScaled = true
	l.TextColor3 = color
	l.Text = text
	l.Parent = g
end

-- one wooden hut; cf = ground centre, the counter faces local -Z
local function hut(parent: Instance, cf: CFrame, title: string, storeKind: string?): Model
	local m = Instance.new("Model")
	m.Name = "Hütte " .. title
	m.Parent = parent
	local W, D, H = 22, 12, 10
	box(m, "Floor", Vector3.new(W, 0.6, D), cf * CFrame.new(0, 0.3, 0), WOOD_DARK, Enum.Material.WoodPlanks)
	box(m, "Back", Vector3.new(W, H, 0.6), cf * CFrame.new(0, H / 2, D / 2), WOOD, Enum.Material.WoodPlanks)
	for _, s in { -1, 1 } do
		box(m, "Side", Vector3.new(0.6, H, D), cf * CFrame.new(s * W / 2, H / 2, 0), WOOD, Enum.Material.WoodPlanks)
		-- roof: two slopes, with snow on top
		local slope = cf * CFrame.new(s * W / 4, H + 2.2, 0) * CFrame.Angles(0, 0, -s * math.rad(22))
		box(m, "Roof", Vector3.new(W / 2 + 3, 0.6, D + 3), slope, WOOD_DARK, Enum.Material.WoodPlanks)
		box(m, "RoofSnow", Vector3.new(W / 2 + 3, 0.4, D + 3), slope * CFrame.new(0, 0.5, 0), SNOW, Enum.Material.Snow)
	end
	box(m, "Gable", Vector3.new(W, 4, 0.6), cf * CFrame.new(0, H + 2, D / 2), WOOD, Enum.Material.WoodPlanks)
	box(m, "Counter", Vector3.new(W - 2, 4, 2), cf * CFrame.new(0, 2, -D / 2 + 1), WOOD, Enum.Material.Wood)
	box(m, "CounterTop", Vector3.new(W - 1, 0.4, 3), cf * CFrame.new(0, 4.2, -D / 2 + 1), WOOD_DARK, Enum.Material.Wood)
	-- the sign over the counter
	local board = box(
		m,
		"Sign",
		Vector3.new(W - 4, 2.6, 0.4),
		cf * CFrame.new(0, H - 1.2, -D / 2 - 0.4),
		Color3.fromRGB(40, 25, 15),
		Enum.Material.Wood
	)
	sign(board, title, Color3.fromRGB(255, 225, 150))
	-- fir garland with lights along the front edge
	box(
		m,
		"Garland",
		Vector3.new(W, 0.8, 0.8),
		cf * CFrame.new(0, H + 0.2, -D / 2 - 0.5),
		Color3.fromRGB(35, 90, 45),
		Enum.Material.Grass
	)
	for i = 0, 10 do
		bulb(
			m,
			cf * CFrame.new(-W / 2 + 1 + i * (W - 2) / 10, H - 0.4, -D / 2 - 0.9),
			BULBS[i % #BULBS + 1],
			0.5,
			i == 5
		)
	end
	if storeKind then
		local def = Items.Stores[storeKind]
		local marker =
			box(m, "Marker_Store", Vector3.new(2, 2, 2), cf * CFrame.new(0, 4.5, -D / 2 - 1.5), Color3.new(1, 1, 1))
		marker.Transparency = 1
		marker.CanCollide = false
		marker.CanQuery = false
		Interaction.Mark(marker, "Store", {
			Store = storeKind,
			UI = "Store",
			Arg = storeKind,
			ActionText = "Einkaufen",
			ObjectText = def and def.title or title,
		})
	end
	return m
end

-- the big tree (Dortmund's is the biggest in the world): stacked tiers, a spiral of
-- lights and a star on top
local function tree(parent: Instance, base: CFrame)
	local m = Instance.new("Model")
	m.Name = "Weihnachtsbaum"
	m.Parent = parent
	box(m, "Trunk", Vector3.new(6, 14, 6), base * CFrame.new(0, 7, 0), WOOD_DARK, Enum.Material.Wood)
	local TIERS, H0, TOP = 14, 10, 150
	for i = 0, TIERS - 1 do
		local f = i / TIERS
		local r = 34 * (1 - f) + 4
		local y = H0 + f * (TOP - H0)
		local tier = box(
			m,
			"Tier",
			Vector3.new(TOP / TIERS + 3, r * 2, r * 2),
			base * CFrame.new(0, y + TOP / TIERS / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(30, 85 + (i % 2) * 12, 45),
			Enum.Material.Grass
		)
		tier.Shape = Enum.PartType.Cylinder
	end
	-- spiral of lights
	local N = 90
	for k = 0, N - 1 do
		local f = k / N
		local y = H0 + 4 + f * (TOP - H0 - 6)
		local r = 34 * (1 - (y - H0) / (TOP - H0)) + 4.6
		local a = f * math.pi * 2 * 7
		bulb(m, base * CFrame.new(math.cos(a) * r, y, math.sin(a) * r), BULBS[k % #BULBS + 1], 1.4, k % 15 == 0)
	end
	-- star
	local star = box(
		m,
		"Star",
		Vector3.new(8, 8, 1.5),
		base * CFrame.new(0, TOP + 8, 0) * CFrame.Angles(0, 0, math.rad(45)),
		Color3.fromRGB(255, 215, 80),
		Enum.Material.Neon
	)
	star.CanCollide = false
	box(
		m,
		"Star",
		Vector3.new(8, 8, 1.5),
		base * CFrame.new(0, TOP + 8, 0),
		Color3.fromRGB(255, 215, 80),
		Enum.Material.Neon
	).CanCollide =
		false
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 215, 120)
	glow.Range = 60
	glow.Brightness = 3
	glow.Parent = star
	-- presents around the foot
	local colors = {
		Color3.fromRGB(200, 30, 40),
		Color3.fromRGB(30, 90, 170),
		Color3.fromRGB(230, 190, 40),
		Color3.fromRGB(40, 140, 70),
	}
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local s = 3 + (i % 3)
		local p = box(
			m,
			"Geschenk",
			Vector3.new(s, s, s),
			base * CFrame.new(math.cos(a) * 40, s / 2, math.sin(a) * 40) * CFrame.Angles(0, a, 0),
			colors[i % #colors + 1]
		)
		box(m, "Schleife", Vector3.new(s + 0.1, s + 0.1, 0.6), p.CFrame, Color3.fromRGB(250, 240, 220))
	end
	return m
end

local function arch(parent: Instance, cf: CFrame)
	local m = Instance.new("Model")
	m.Name = "Eingang"
	m.Parent = parent
	for _, s in { -1, 1 } do
		box(m, "Post", Vector3.new(2.5, 22, 2.5), cf * CFrame.new(s * 16, 11, 0), WOOD, Enum.Material.Wood)
		box(
			m,
			"Fir",
			Vector3.new(4, 22, 4),
			cf * CFrame.new(s * 16, 11, 0),
			Color3.fromRGB(35, 90, 45),
			Enum.Material.Grass
		).Transparency =
			0.25
	end
	local beam = box(
		m,
		"Sign",
		Vector3.new(36, 5, 1.5),
		cf * CFrame.new(0, 22, 0),
		Color3.fromRGB(40, 25, 15),
		Enum.Material.Wood
	)
	sign(beam, "Weihnachtsmarkt", Color3.fromRGB(255, 225, 150))
	local back = box(
		m,
		"SignBack",
		Vector3.new(36, 5, 0.2),
		cf * CFrame.new(0, 22, 0.9) * CFrame.Angles(0, math.pi, 0),
		Color3.fromRGB(40, 25, 15),
		Enum.Material.Wood
	)
	sign(back, "Weihnachtsmarkt", Color3.fromRGB(255, 225, 150))
	for i = 0, 12 do
		bulb(m, cf * CFrame.new(-18 + i * 3, 24.8, -0.9), BULBS[i % #BULBS + 1], 0.7, i == 6)
	end
end

-- the market area, in the Parlament's local frame: behind the building (+Z)
AdventService.Area = { x0 = -214, x1 = 214, z0 = 175, z1 = 318 }
-- parking on both sides of the market (between the market and the lawn's edge)
AdventService.Parking = { inner = 216, outer = 268, z0 = 176, z1 = 316, spot = 10, depth = 18 }

-- a small fir (for the tree hut and the flats); pivot = ground centre
local function smallTree(parent: Instance, cf: CFrame, h: number): Model
	local m = Instance.new("Model")
	m.Name = "Tannenbaum"
	m.Parent = parent
	box(
		m,
		"Stamm",
		Vector3.new(0.6, h * 0.2, 0.6) * (h / 10),
		cf * CFrame.new(0, h * 0.1, 0),
		WOOD_DARK,
		Enum.Material.Wood
	)
	for t = 0, 3 do
		local r = (h * 0.32) * (1 - t * 0.22)
		local tier = box(
			m,
			"Zweige",
			Vector3.new(h * 0.24, r * 2, r * 2),
			cf * CFrame.new(0, h * 0.2 + t * h * 0.19 + h * 0.12, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(30, 95 + t * 6, 50),
			Enum.Material.Grass
		)
		tier.Shape = Enum.PartType.Cylinder
		tier.CanCollide = false
	end
	return m
end

local function parkingLot(m: Model, at: (number, number, number?) -> CFrame, side: number, cz: number)
	local P = AdventService.Parking
	local lot = Instance.new("Model")
	lot.Name = "Parkplatz"
	lot.Parent = m
	local mid = (P.inner + P.outer) / 2
	box(
		lot,
		"Asphalt",
		Vector3.new(P.outer - P.inner, 0.3, P.z1 - P.z0),
		at(side * mid, (P.z0 + P.z1) / 2) * CFrame.new(0, 0.15, 0),
		Color3.fromRGB(55, 57, 60),
		Enum.Material.Asphalt
	)
	local white = Color3.fromRGB(240, 240, 240)
	local count = 0
	for _, row in
		{ { a = P.outer - P.depth, b = P.outer, inner = false }, { a = P.inner, b = P.inner + P.depth, inner = true } }
	do
		local cx = side * (row.a + row.b) / 2
		local z = P.z0
		while z + P.spot <= P.z1 + 0.01 do
			local zc = z + P.spot / 2
			-- the inner row leaves the way to the market's entrance free
			if not (row.inner and math.abs(zc - cz) < 16) then
				count += 1
				for _, edge in { z, z + P.spot } do
					local l =
						box(lot, "Linie", Vector3.new(P.depth, 0.05, 0.4), at(cx, edge) * CFrame.new(0, 0.33, 0), white)
					l.CanCollide = false
				end
				local spot = box(
					lot,
					"Stellplatz",
					Vector3.new(P.depth - 1, 0.05, P.spot - 1),
					at(cx, zc) * CFrame.new(0, 0.32, 0),
					Color3.fromRGB(55, 57, 60),
					Enum.Material.Asphalt
				)
				spot.Transparency = 1
				spot.CanCollide = false
			end
			z += P.spot
		end
	end
	-- "P" signs at both ends
	for _, z in { P.z0 + 2, P.z1 - 2 } do
		local x = side * (P.outer - P.depth - 8)
		box(
			lot,
			"Pfosten",
			Vector3.new(0.5, 9, 0.5),
			at(x, z) * CFrame.new(0, 4.5, 0),
			Color3.fromRGB(120, 120, 125),
			Enum.Material.Metal
		)
		local s = box(
			lot,
			"Schild",
			Vector3.new(3.6, 3.6, 0.3),
			at(x, z, if z < cz then 180 else 0) * CFrame.new(0, 9, 0),
			Color3.fromRGB(20, 80, 170)
		)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local g = Instance.new("SurfaceGui")
			g.Face = face
			g.CanvasSize = Vector2.new(100, 100)
			g.Parent = s
			local l = Instance.new("TextLabel")
			l.Size = UDim2.fromScale(1, 1)
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.GothamBlack
			l.TextScaled = true
			l.TextColor3 = Color3.new(1, 1, 1)
			l.Text = "P"
			l.Parent = g
		end
	end
	lot:SetAttribute("Spots", count)
end

function AdventService.BuildMarket(): Model?
	local site = ParliamentBuilder.Site
	local A = AdventService.Area
	local y0 = CityBuilder.GroundY(site.x, site.z) + 0.6
	local origin = CFrame.new(site.x, y0, site.z)
	local function at(x: number, z: number, yaw: number?): CFrame
		return origin * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	end
	local m = Instance.new("Model")
	m.Name = "Weihnachtsmarkt"
	local cz = (A.z0 + A.z1) / 2
	-- cobblestones with a little snow
	box(
		m,
		"Pflaster",
		Vector3.new(A.x1 - A.x0, 0.3, A.z1 - A.z0),
		at((A.x0 + A.x1) / 2, cz) * CFrame.new(0, 0.15, 0),
		Color3.fromRGB(140, 136, 130),
		Enum.Material.Cobblestone
	)
	tree(m, at(0, cz))
	-- two rows of huts facing the aisle (front = local -Z)
	local stalls = {
		{ "Punschhütte", "XmasPunsch" },
		{ "Kerzen & Licht" },
		{ "Grillhütte", "XmasGrill" },
		{ "Holzspielzeug" },
		{ "Gebrannte Mandeln", "XmasSweets" },
		{ "Glaskugeln" },
		{ "Punschhütte", "XmasPunsch" },
		{ "Krippenfiguren" },
		{ "Reibekuchen", "XmasGrill" },
		{ "Strickwaren" },
		{ "Crêpes & Süßes", "XmasSweets" },
		{ "Honig & Lebkuchen", "XmasSweets" },
		{ "Weihnachtsdeko" },
		{ "Grillhütte", "XmasGrill" },
		{ "Kakao & Punsch", "XmasPunsch" },
		{ "Weihnachtsbäume" },
	}
	local i = 0
	for _, row in { { z = A.z0 + 12, yaw = 180 }, { z = A.z1 - 12, yaw = 0 } } do
		for k = 0, 7 do
			i += 1
			local x = -189 + k * 54
			local s = stalls[i]
			local h = hut(m, at(x, row.z, row.yaw), s[1], s[2])
			if s[1] == "Weihnachtsbäume" then
				-- trees for sale beside the hut; buy one at the counter
				for _, dx in { -17, 17 } do
					smallTree(h, at(x + dx, row.z, row.yaw), 10)
				end
				local marker = box(
					h,
					"Marker_XmasTree",
					Vector3.new(2, 2, 2),
					at(x, row.z, row.yaw) * CFrame.new(0, 4.5, -7.5),
					Color3.new(1, 1, 1)
				)
				marker.Transparency = 1
				marker.CanCollide = false
				marker.CanQuery = false
				Interaction.Mark(marker, "XmasTree", {
					ActionText = ("Baum kaufen (%s)"):format(Locale.Euro(Advent.TREE_PRICE)),
					ObjectText = "Weihnachtsbaum für deine Wohnung",
					Hold = 0.6,
				})
			end
		end
	end
	-- standing tables between the huts
	for _, x in { -162, -54, 54, 162 } do
		for _, z in { cz - 22, cz + 22 } do
			box(m, "Stehtisch", Vector3.new(4, 0.5, 4), at(x, z) * CFrame.new(0, 4, 0), WOOD_DARK, Enum.Material.Wood).Shape =
				Enum.PartType.Cylinder
			box(m, "Tischbein", Vector3.new(0.6, 4, 0.6), at(x, z) * CFrame.new(0, 2, 0), WOOD_DARK, Enum.Material.Wood)
		end
	end
	-- light strings over the aisle
	for _, x in { -162, -108, 108, 162 } do -- between the huts
		for k = 0, 16 do
			local f = k / 16
			local z = A.z0 + 20 + f * (A.z1 - A.z0 - 40)
			local sag = math.sin(f * math.pi) * 3
			bulb(m, at(x, z) * CFrame.new(0, 18 - sag, 0), BULBS[k % #BULBS + 1], 0.8, k == 8)
		end
		for _, z in { A.z0 + 20, A.z1 - 20 } do
			box(m, "Mast", Vector3.new(0.8, 18, 0.8), at(x, z) * CFrame.new(0, 9, 0), WOOD_DARK, Enum.Material.Wood)
		end
	end
	-- entrances west and east
	arch(m, at(A.x0 + 4, cz, 90))
	arch(m, at(A.x1 - 4, cz, -90))
	-- parking on both sides
	local function at3(x: number, z: number, yaw: number?): CFrame
		return at(x, z, yaw)
	end
	parkingLot(m, at3, -1, cz)
	parkingLot(m, at3, 1, cz)
	m.Parent = Workspace
	return m
end

-- Weihnachtsbaum + gift cars ----------------------------------------------------------------

local flatTrees: { [Player]: Model } = {}
local treeFolder: Folder? = nil

function AdventService.HasTree(player: Player): boolean
	local data = DataService.Get(player)
	return data ~= nil and data.xmasTree == (Advent.Today())
end

-- where the tree stands in a flat (local frame of the flat: -Z = door side): the front
-- left corner, away from the door (+X), the droppers (z -4) and the wardrobe (z 0..8)
function AdventService.TreeSpot(w: number, d: number): Vector3
	return Vector3.new(-w / 2 + 6, 0.1, -d / 2 + 6)
end

function AdventService.BuildFlatTree(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Weihnachtsbaum"
	local t = smallTree(m, cf, 10)
	t.Parent = m
	box(
		m,
		"Topf",
		Vector3.new(2.4, 1.2, 2.4),
		cf * CFrame.new(0, 0.6, 0),
		Color3.fromRGB(170, 30, 40),
		Enum.Material.Fabric
	)
	for k = 0, 17 do
		local f = k / 18
		local y = 2.6 + f * 6
		local r = 3.2 * (1 - f * 0.75) + 0.2
		local a = f * math.pi * 2 * 3
		bulb(m, cf * CFrame.new(math.cos(a) * r, y, math.sin(a) * r), BULBS[k % #BULBS + 1], 0.4, k == 9)
	end
	local star = box(
		m,
		"Stern",
		Vector3.new(1.4, 1.4, 0.3),
		cf * CFrame.new(0, 10.4, 0) * CFrame.Angles(0, 0, math.rad(45)),
		Color3.fromRGB(255, 215, 80),
		Enum.Material.Neon
	)
	star.CanCollide = false
	box(
		m,
		"Stern",
		Vector3.new(1.4, 1.4, 0.3),
		cf * CFrame.new(0, 10.4, 0),
		Color3.fromRGB(255, 215, 80),
		Enum.Material.Neon
	).CanCollide =
		false
	-- presents
	for i, c in { Color3.fromRGB(30, 90, 170), Color3.fromRGB(230, 190, 40), Color3.fromRGB(40, 140, 70) } do
		box(m, "Geschenk", Vector3.new(1.2, 1.2, 1.2), cf * CFrame.new(-2 + i * 1.3, 0.6, -2.6), c)
	end
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
		end
	end
	return m
end

-- the tree in the player's flat (or none): after buying, moving in, joining
function AdventService.PlaceTree(player: Player)
	local old = flatTrees[player]
	if old then
		old:Destroy()
		flatTrees[player] = nil
	end
	local n = player:GetAttribute("Apartment")
	if not AdventService.HasTree(player) or typeof(n) ~= "number" then
		return
	end
	for _, u in TowerBuilder.Units do
		if u.number == n and u.frame and u.w and u.d then
			if not treeFolder then
				local f = Instance.new("Folder")
				f.Name = "Weihnachtsbäume"
				f.Parent = Workspace
				treeFolder = f
			end
			local spot = AdventService.TreeSpot(u.w :: number, u.d :: number)
			local m = AdventService.BuildFlatTree((u.frame :: CFrame) * CFrame.new(spot))
			m.Name = "Weihnachtsbaum " .. player.Name
			m.Parent = treeFolder
			flatTrees[player] = m
			return
		end
	end
end

-- the gift cars: only for tree owners who are online on that day (24th / 25th)
function AdventService.CheckGifts(player: Player)
	if not AdventService.HasTree(player) then
		return
	end
	local Vehicles = require(ReplicatedStorage.Shared.Vehicles) :: any
	for _, g in Advent.GiftsDue(nil, Config.Testing) do
		if Vehicles.ById[g.vehicle] and DataService.Get(player) then
			if AdventService.Claim(player.UserId, g.key) == "new" then
				local VehicleService = require(script.Parent.VehicleService) :: any
				if VehicleService.GiveVehicle(player, g.vehicle) then
					GameLog.Add("money", player, "advent gift car " .. g.vehicle)
					Remotes.Push(player, "Notify", { key = "advent_gift", args = { g.name } })
				end
			end
		end
	end
end

function AdventService.BuyTree(player: Player): string?
	local data = DataService.Get(player)
	if not data then
		return "error"
	end
	if AdventService.HasTree(player) then
		return "advent_tree_have"
	end
	if not Economy.TrySpend(player, Advent.TREE_PRICE, "Weihnachtsbaum") then
		return "no_money"
	end
	data.xmasTree = (Advent.Today())
	State.MarkDirty(player)
	AdventService.PlaceTree(player)
	Remotes.Push(player, "Notify", {
		key = if player:GetAttribute("Apartment") then "advent_tree_bought" else "advent_tree_bought_noflat",
	})
	AdventService.CheckGifts(player)
	return nil
end

-- Start -----------------------------------------------------------------------------------

function AdventService.Start()
	if not on() then
		return
	end
	local market: Model? = nil
	local wasSeason = false
	local function season()
		local inSeason = Advent.Season(nil, Config.Testing)
		Workspace:SetAttribute("AdventSeason", inSeason)
		-- December starts: it snows right away (then on most days, see WorldService)
		if inSeason and not wasSeason then
			WorldService.SetWeather("Snow")
		end
		wasSeason = inSeason
		if inSeason and not market and Workspace:FindFirstChild("Parlament") then
			local ok, m = pcall(AdventService.BuildMarket)
			market = if ok then m else nil
			if not ok then
				warn("[Advent] market failed: " .. tostring(m))
			end
		elseif not inSeason and market then
			market:Destroy()
			market = nil
		end
	end
	season()
	task.spawn(function()
		while true do
			task.wait(60) -- 1 December starts while a server runs
			season()
			-- 24 / 25 December start while you play
			for _, p in Players:GetPlayers() do
				task.spawn(AdventService.CheckGifts, p)
			end
		end
	end)

	-- the tree: bought at the market hut, stands in your flat in the Dortmund Tower
	Interaction.OnTrigger("XmasTree", function(player)
		if not Interaction.IsNear(player, "XmasTree", 16) then
			return
		end
		local err = AdventService.BuyTree(player)
		if err then
			Remotes.Push(player, "Notify", { key = err, error = true })
		end
	end)
	DataService.Loaded:Connect(function(player)
		AdventService.PlaceTree(player)
		task.spawn(AdventService.CheckGifts, player)
	end)
	local function watchFlat(p: Player)
		p:GetAttributeChangedSignal("Apartment"):Connect(function()
			AdventService.PlaceTree(p)
		end)
	end
	for _, p in Players:GetPlayers() do
		watchFlat(p)
	end
	Players.PlayerAdded:Connect(watchFlat)

	Remotes.Handle("Advent.Get", function(player)
		local doors = opened(player.UserId)
		if not doors then
			return Remotes.Fail("error")
		end
		local list = {}
		for k in doors do
			local n = tonumber(k) -- (gift cars are kept here too: "g24", "g25")
			if n then
				table.insert(list, n)
			end
		end
		local _, month, day = Advent.Today()
		ownedCache[player] = Advent.OwnedOutfit(list)
		local worn = {}
		for piece, on in wearing(player) do
			if on then
				table.insert(worn, piece)
			end
		end
		return Remotes.Ok({
			tree = AdventService.HasTree(player),
			treePrice = Locale.Euro(Advent.TREE_PRICE),
			wearing = worn,
			opened = list,
			unlocked = Advent.Unlocked(nil, Config.Testing),
			today = if month == Advent.MONTH then day else 0,
		})
	end, { rate = 4 })

	Remotes.Handle("Advent.Open", function(player, door: any)
		local n = tonumber(door)
		if not n or n ~= math.floor(n) or n < 1 or n > Advent.DOORS then
			return Remotes.Fail("bad_request")
		end
		if n > Advent.Unlocked(nil, Config.Testing) then
			return Remotes.Fail("advent_locked")
		end
		local claim = AdventService.Claim(player.UserId, n)
		if claim == "opened" then
			return Remotes.Fail("advent_opened")
		elseif claim ~= "new" then
			return Remotes.Fail("error")
		end
		local got = AdventService.Give(player, n)
		if got.outfit then
			-- a new outfit piece: put it on right away
			local owned = ownedCache[player] or {}
			owned[got.outfit] = true
			ownedCache[player] = owned
			local data = DataService.Get(player)
			if data then
				local w = if typeof(data.xmasWear) == "table" then data.xmasWear else {}
				if Advent.OnHead[got.outfit] then
					for p in Advent.OnHead do
						w[p] = nil
					end
				end
				w[got.outfit] = true
				data.xmasWear = w
				State.MarkDirty(player)
			end
			AdventService.ApplyOutfit(player)
		end
		local names = {}
		for _, id in got.items do
			local it = Items.ById[id]
			table.insert(names, if it then it.name else id)
		end
		return Remotes.Ok({
			door = n,
			cash = got.cash,
			cashText = Locale.Euro(got.cash),
			xp = got.xp,
			items = names,
			outfit = got.outfit and Advent.Outfit[got.outfit].name,
		})
	end, { rate = 3 })

	-- put an outfit piece on / take it off (hat and antlers are both on the head)
	Remotes.Handle("Advent.Wear", function(player, piece: any, on: any)
		if typeof(piece) ~= "string" or not Advent.Outfit[piece] or typeof(on) ~= "boolean" then
			return Remotes.Fail("bad_request")
		end
		if on and not (ownedCache[player] or {})[piece] then
			return Remotes.Fail("advent_not_owned")
		end
		local data = DataService.Get(player)
		if not data then
			return Remotes.Fail("error")
		end
		local w = if typeof(data.xmasWear) == "table" then data.xmasWear else {}
		if on and Advent.OnHead[piece] then
			for p in Advent.OnHead do
				w[p] = nil
			end
		end
		w[piece] = if on then true else nil
		data.xmasWear = w
		State.MarkDirty(player)
		AdventService.ApplyOutfit(player)
		return Remotes.Ok()
	end, { rate = 6 })

	-- the outfit comes back on every spawn
	local function watch(player: Player)
		task.spawn(function()
			local doors = opened(player.UserId)
			local list = {}
			for k in doors or {} do
				local n = tonumber(k)
				if n then
					table.insert(list, n)
				end
			end
			ownedCache[player] = Advent.OwnedOutfit(list)
			if player.Character then
				AdventService.ApplyOutfit(player)
			end
		end)
		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("Head", 10)
			task.wait(1) -- after the avatar's own accessories
			if player.Parent then
				AdventService.ApplyOutfit(player)
			end
		end)
	end
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		ownedCache[p] = nil
		local t = flatTrees[p]
		if t then
			t:Destroy()
			flatTrees[p] = nil
		end
	end)
end

return AdventService
