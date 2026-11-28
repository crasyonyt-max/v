--!strict
-- 🎄 Advent (Config.Advent, "test" = testing server first; rules in Shared/Advent):
--   * Adventskalender: "Advent.Get" / "Advent.Open" (one door a day, each door once,
--     claimed atomically in its own store so no second server can pay it again)
--   * Weihnachtsmarkt on the lawn behind the Parlament (built in December)
--   * workspace attribute "AdventSeason": the client hangs Christmas lights on the
--     street lamps, WorldService lets it snow more often

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Advent = require(ReplicatedStorage.Shared.Advent)
local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local Locale = require(ReplicatedStorage.Shared.Locale)
local CityBuilder = require(script.Parent.CityBuilder)
local DataStoreService = require(script.Parent.Sandbox).DataStoreService -- local only on the testing server
local Economy = require(script.Parent.EconomyService)
local GameLog = require(script.Parent.GameLog)
local Interaction = require(script.Parent.InteractionService)
local ParliamentBuilder = require(script.Parent.ParliamentBuilder)
local Remotes = require(script.Parent.Remotes)
local StoreService = require(script.Parent.StoreService)
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
function AdventService.Claim(userId: number, door: number): string
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
	return { cash = cash, xp = xp, items = items }
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
local function hut(parent: Instance, cf: CFrame, title: string, storeKind: string?)
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
AdventService.Area = { x0 = -240, x1 = 240, z0 = 175, z1 = 318 }

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
		{ "Holzschnitzerei" },
	}
	local i = 0
	for _, row in { { z = A.z0 + 12, yaw = 180 }, { z = A.z1 - 12, yaw = 0 } } do
		for k = 0, 7 do
			i += 1
			local x = -210 + k * 60
			local s = stalls[i]
			hut(m, at(x, row.z, row.yaw), s[1], s[2])
		end
	end
	-- standing tables between the huts
	for _, x in { -180, -60, 60, 180 } do
		for _, z in { cz - 22, cz + 22 } do
			box(m, "Stehtisch", Vector3.new(4, 0.5, 4), at(x, z) * CFrame.new(0, 4, 0), WOOD_DARK, Enum.Material.Wood).Shape =
				Enum.PartType.Cylinder
			box(m, "Tischbein", Vector3.new(0.6, 4, 0.6), at(x, z) * CFrame.new(0, 2, 0), WOOD_DARK, Enum.Material.Wood)
		end
	end
	-- light strings over the aisle
	for _, x in { -180, -120, 120, 180 } do -- between the huts
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
	m.Parent = Workspace
	return m
end

-- Start -----------------------------------------------------------------------------------

function AdventService.Start()
	if not on() then
		return
	end
	local market: Model? = nil
	local function season()
		local inSeason = Advent.Season(nil, Config.Testing)
		Workspace:SetAttribute("AdventSeason", inSeason)
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
		end
	end)

	Remotes.Handle("Advent.Get", function(player)
		local doors = opened(player.UserId)
		if not doors then
			return Remotes.Fail("error")
		end
		local list = {}
		for k in doors do
			table.insert(list, tonumber(k))
		end
		local _, month, day = Advent.Today()
		return Remotes.Ok({
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
		})
	end, { rate = 3 })
end

return AdventService
