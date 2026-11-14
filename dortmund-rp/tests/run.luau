-- Headless tests, run with Lune from dortmund-rp/:  lune run tests/run.luau
-- Loads the real game modules with a small fake `game`/`script` so we can check
-- pure logic (plates, levels, money format, catalogs) and that every vehicle and
-- the map build without wrong class or property names.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(a: any, b: any, msg: string?)
	if a ~= b then
		error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
	end
end

-- Fake instance paths -------------------------------------------------------------
local PATH = {}
local function pathProxy(parts: { string })
	return setmetatable({ [PATH] = parts }, {
		__index = function(self, key)
			if key == "Parent" then
				local p = table.clone(parts)
				table.remove(p)
				return pathProxy(p)
			elseif key == "WaitForChild" or key == "FindFirstChild" then
				return function(_, child)
					return self[child]
				end
			elseif key == "Name" then
				return parts[#parts]
			elseif key == "IsA" then
				return function(_, class)
					return class == "ModuleScript" and fs.isFile("src/" .. table.concat(parts, "/") .. ".lua")
				end
			elseif key == "GetChildren" then
				return function()
					local out = {}
					for _, entry in fs.readDir("src/" .. table.concat(parts, "/")) do
						local name = string.gsub(entry, "%.lua$", "")
						local p = table.clone(parts)
						table.insert(p, name)
						table.insert(out, pathProxy(p))
					end
					return out
				end
			end
			local p = table.clone(parts)
			table.insert(p, key)
			return pathProxy(p)
		end,
	})
end

local function fileFor(parts: { string }): string?
	local base = "src/" .. table.concat(parts, "/")
	for _, suffix in { ".lua", ".server.lua", ".client.lua" } do
		if fs.isFile(base .. suffix) then
			return base .. suffix
		end
	end
	return nil
end

-- Real Lune DataModel for services that hold instances.
local dataModel = roblox.Instance.new("DataModel")
local tagged: { [string]: { any } } = {}
local fakeServices = {
	CollectionService = {
		AddTag = function(_, inst, tag)
			tagged[tag] = tagged[tag] or {}
			table.insert(tagged[tag], inst)
		end,
		GetTagged = function(_, tag)
			return tagged[tag] or {}
		end,
		HasTag = function(_, inst, tag)
			return table.find(tagged[tag] or {}, inst) ~= nil
		end,
		RemoveTag = function(_, inst, tag)
			local list = tagged[tag] or {}
			local i = table.find(list, inst)
			if i then
				table.remove(list, i)
			end
		end,
		GetInstanceAddedSignal = function()
			return { Connect = function() end }
		end,
	},
}

local fakeGame = {
	GetService = function(_, name: string)
		if fakeServices[name] then
			return fakeServices[name]
		end
		if name == "ReplicatedStorage" or name == "ServerScriptService" or name == "ServerStorage" then
			return pathProxy({ name })
		end
		return dataModel:GetService(name)
	end,
}

local overrides: { [string]: any } = {}
local cache: { [string]: any } = {}
local env

local function requirePath(target: any)
	local parts = rawget(target, PATH)
	assert(parts, "require of non-path")
	local key = table.concat(parts, "/")
	if overrides[key] ~= nil then
		return overrides[key]
	end
	if cache[key] ~= nil then
		return cache[key]
	end
	local file = fileFor(parts)
	assert(file, "module not found: " .. key)
	local moduleEnv = table.clone(env)
	moduleEnv.script = pathProxy(parts)
	local chunk = luau.load(fs.readFile(file), { debugName = file, environment = moduleEnv })
	local result = chunk()
	cache[key] = result
	return result
end

env = {
	game = fakeGame,
	task = require("@lune/task"),
	workspace = dataModel:GetService("Workspace"),
	require = requirePath,
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	BrickColor = roblox.BrickColor,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	PhysicalProperties = roblox.PhysicalProperties,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	NumberRange = roblox.NumberRange,
	Random = {
		new = function(seed)
			local s = seed or 1
			return {
				NextInteger = function(_, a, b)
					s = (s * 1103515245 + 12345) % 2147483648
					return a + s % (b - a + 1)
				end,
				NextNumber = function()
					s = (s * 1103515245 + 12345) % 2147483648
					return s / 2147483648
				end,
			}
		end,
	},
}

local RS = pathProxy({ "ReplicatedStorage" })
fakeServices.ServerStorage = pathProxy({ "ServerStorage" })
local Server = pathProxy({ "ServerScriptService", "Server" })

-- Every Enum.X.Y used anywhere in src/ must exist ----------------------------------
test("all enums exist", function()
	local bad = {}
	local function scan(dir: string)
		for _, entry in fs.readDir(dir) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				scan(path)
			elseif string.sub(entry, -4) == ".lua" then
				for enumName, item in string.gmatch(fs.readFile(path), "Enum%.(%a+)%.([%w_]+)") do
					local ok = pcall(function()
						return (roblox.Enum :: any)[enumName][item]
					end)
					if not ok then
						table.insert(bad, path .. ": Enum." .. enumName .. "." .. item)
					end
				end
			end
		end
	end
	scan("src")
	assert(#bad == 0, "unknown enums:\n  " .. table.concat(bad, "\n  "))
end)

-- Shared modules -------------------------------------------------------------------
local Plate = requirePath(RS.Shared.Plate)
test("plates", function()
	eq(Plate.Normalize("do-ab 1234"), "DO-AB 1234", "lowercase")
	eq(Plate.Normalize("  DO-A 7  "), "DO-A 7", "trim")
	eq(Plate.Normalize("DO-AB 123E"), "DO-AB 123E", "e-plate")
	eq(Plate.Normalize("DO-AB 0123"), nil, "leading zero")
	eq(Plate.Normalize("DOAB 1234"), nil, "missing dash")
	eq(Plate.Normalize("DO-ABC 1"), nil, "3 letters")
	eq(Plate.Normalize("DO-AB 12345"), nil, "5 digits")
	local rng = env.Random.new(3)
	for _ = 1, 200 do
		local p = Plate.Random("DO", rng)
		assert(Plate.Normalize(p) == p, "random plate invalid: " .. p)
	end
end)

local Levels = requirePath(RS.Shared.Levels)
test("levels", function()
	eq((Levels.FromTotal(0)), 1, "start level")
	eq((Levels.FromTotal(Levels.Required(1))), 2, "first level up")
	local l, into, need = Levels.FromTotal(Levels.Required(1) + 5)
	eq(l, 2)
	eq(into, 5)
	eq(need, Levels.Required(2))
end)

local Locale = requirePath(RS.Shared.Locale)
test("euro format", function()
	eq(Locale.Euro(0), "0 €")
	eq(Locale.Euro(999), "999 €")
	eq(Locale.Euro(1000), "1.000 €")
	eq(Locale.Euro(3000000), "3.000.000 €")
	eq(Locale.Euro(-12500), "-12.500 €")
	eq(Locale.Euro(3.49), "3,49 €")
	eq(Locale.Euro(1234.5), "1.234,50 €")
	eq(Locale.Euro(0.99), "0,99 €")
	eq(Locale.T("en", "paycheck", "250 €"), "Paycheck received: 250 €")
	eq(Locale.T("de", "unknown_key"), "unknown_key")
end)

local Vehicles = requirePath(RS.Shared.Vehicles)
local VehicleBuilder = requirePath(Server.VehicleBuilder)
test("vehicle catalog: one motorbike", function()
	eq(#Vehicles.ByCategory("Starter"), 1, "one civilian bike")
	eq(Vehicles.ByCategory("Starter")[1].id, Vehicles.BikeId)
	eq(#Vehicles.ByCategory("Admin"), 11, "admin bike + 10 admin cars")
	eq(#Vehicles.ByCategory("Dealer"), 20, "dealership cars")
	eq(#Vehicles.ByCategory("CarStarter"), 3, "starter cars to pick from")
	eq(#Vehicles.ByCategory("Pack"), 25, "gamepass pack cars")
	for _, job in { "Police", "Fire", "Rettungsdienst", "Notarzt", "ADMC", "DXL", "LKW" } do
		local list = Vehicles.ForJob(job)
		assert(#list > 1, job .. ": bike + cars")
		eq(list[1].body, "bike", job .. ": the bike comes first")
		eq(list[1].xp or 0, 0, job .. " bike free")
		assert(VehicleBuilder.Schemes[list[1].livery], job .. " has no livery")
	end
	for _, v in Vehicles.List do
		assert(v.body == "bike" or v.car, v.id .. " is neither bike nor car")
		if v.category == "Pack" then
			assert(table.find(Vehicles.PackOrder, v.pack), v.id .. " has an unknown pack " .. tostring(v.pack))
		end
	end
	-- every job has its bike first, then its cars by XP
	eq(Vehicles.ForJob("Rettungsdienst")[1].id, "motorrad_rettungsdienst")
	assert(#Vehicles.ForJob("Rettungsdienst") > 1, "rescue cars (EMS) mapped to Rettungsdienst")
	-- refunds for the removed cars
	eq(Vehicles.LegacyPrices.lambardini_uros, 250000)
	eq(Vehicles.LegacyPrices.bugarti_chiran, 3000000)
	eq(Vehicles.LegacyPrices.vk_golfo4, nil, "free starter cars are not refunded")
end)

test("weekly event: Saturday 18:00 German time, 30 min", function()
	local Boosts = requirePath(Server.Boosts)
	-- 14 Nov 2026 is a Saturday (CET = UTC+1); 13 Jun 2026 too (CEST = UTC+2)
	local nov = 1794675600 -- 2026-11-14 17:00 UTC
	local jun = 1781366400 -- 2026-06-13 16:00 UTC
	eq(os.date("!%Y-%m-%d %H:%M", nov), "2026-11-14 17:00")
	eq(os.date("!%Y-%m-%d %H:%M", jun), "2026-06-13 16:00")
	eq(Boosts.WeeklyEnds(nov), nov + 1800, "winter start")
	eq(Boosts.WeeklyEnds(nov + 1799), nov + 1800, "winter last second")
	eq(Boosts.WeeklyEnds(nov + 1800), nil, "winter over")
	eq(Boosts.WeeklyEnds(nov - 1), nil, "not yet")
	eq(Boosts.WeeklyEnds(nov - 86400), nil, "Friday")
	eq(Boosts.WeeklyEnds(jun), jun + 1800, "summer start")
	eq(Boosts.WeeklyEnds(jun + 3600), nil, "19:00 CEST")
end)

test("every UI text key exists", function()
	local missing = {}
	local function walk(dir)
		for _, name in fs.readDir(dir) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				walk(path)
			elseif string.match(name, "%.lua$") then
				for key in string.gmatch(fs.readFile(path), 'Store%.T%("([%w_]+)"') do
					if string.sub(key, -1) ~= "_" and Locale.T("de", key) == key then
						table.insert(missing, key .. " (" .. name .. ")")
					end
				end
			end
		end
	end
	walk("src")
	eq(#missing, 0, "missing texts: " .. table.concat(missing, ", "))
end)

test("phones", function()
	local Phones = requirePath(RS.Shared.Phones)
	local shop = 0
	for _, p in Phones.List do
		if p.shop then
			shop += 1
		end
		assert(p.wallpapers <= #Phones.Wallpapers, p.id .. " wallpapers")
	end
	eq(shop, 10, "shop phones")
	eq(Phones.ById.poko_c85.price, 0)
	eq(Phones.ById.samsong_zfold7.price, 2099)
	assert(Phones.ById.nvdr_p1.adminOnly and not Phones.ById.nvdr_p1.shop, "NVDR P1 must be admin only")
end)

test("store catalog", function()
	local Items = requirePath(RS.Shared.Items)
	for kind, store in Items.Stores do
		for _, id in store.items do
			assert(Items.ById[id], kind .. " sells unknown item " .. id)
			assert(Items.Price(kind, id), "no price")
		end
	end
	eq(Items.Price("Rewo", "pizza_salami"), 3.49, "Rewo pizza")
	assert(Items.Price("Lindl", "pizza_salami") < 3.49, "discounter cheaper")
	eq(Items.Price("Rewo", "currywurst"), nil, "not sold there")
end)

test("config", function()
	local Config = requirePath(RS.Shared.Config)
	eq(Config.AdminChatNumber, "23646")
	eq(Config.AdminPhoneId, "nvdr_p1")
end)

-- Car refund: paid once, never again (even if the cars come back) ---------------
test("car refund is paid only once", function()
	local stores = {}
	fakeServices.DataStoreService = {
		GetDataStore = function(_, name)
			stores[name] = stores[name] or {}
			local mem = stores[name]
			return {
				UpdateAsync = function(_, key, fn)
					local new = fn(mem[key])
					if new ~= nil then
						mem[key] = new
					end
					return new
				end,
				GetAsync = function(_, key)
					return mem[key]
				end,
				RemoveAsync = function(_, key)
					mem[key] = nil
				end,
			}
		end,
	}
	local data
	local function add(amount, reason)
		data.bank += amount
		table.insert(data.tx, { amount = amount, reason = reason, t = 0 })
		return true
	end
	local stub = function()
		return setmetatable({}, {
			__index = function()
				return function() end
			end,
		})
	end
	overrides["ServerScriptService/Server/DataService"] = {
		Get = function()
			return data
		end,
		Save = function() end,
	}
	overrides["ServerScriptService/Server/EconomyService"] = {
		Add = function(_, amount, reason)
			return add(amount, reason)
		end,
		TrySpend = function(_, amount, reason)
			return add(-amount, reason)
		end,
	}
	overrides["ServerScriptService/Server/Remotes"] = stub()
	overrides["ServerScriptService/Server/State"] = stub()
	overrides["ServerScriptService/Server/InteractionService"] = stub()
	overrides["ServerScriptService/Server/JobService"] = stub()
	overrides["ServerScriptService/Server/Roles"] = stub()
	overrides["ServerScriptService/Server/StationBuilder"] = stub()
	overrides["ServerScriptService/Server/XPService"] = stub()
	local VS = requirePath(Server.VehicleService)
	-- the stubs are only for VehicleService: later tests use the real modules
	for _, name in
		{
			"DataService",
			"EconomyService",
			"Remotes",
			"State",
			"InteractionService",
			"JobService",
			"Roles",
			"StationBuilder",
			"XPService",
		}
	do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	fakeServices.DataStoreService = nil
	local player = { UserId = 42, Name = "Tester", Parent = nil }
	local function oldSave()
		return {
			bank = 1000,
			tx = {},
			nextUid = 3,
			vehicles = {
				v1 = { id = "lambardini_uros", plate = "DO-A 1" },
				v2 = { id = "vk_golfo4", plate = "DO-A 2" },
			},
		}
	end
	data = oldSave()
	VS._migrate(player, data)
	eq(data.bank, 251000, "first join: full refund")
	local n = 0
	for _, e in data.vehicles do
		n += 1
		eq(e.id, Vehicles.BikeId, "only the bike is left")
	end
	eq(n, 1, "one bike")
	-- the cars come back (failed save / old server): no second refund
	data = oldSave()
	VS._migrate(player, data)
	eq(data.bank, 1000, "no second refund")
	data.vehicles.v9 = { id = "bmv_m3", plate = "DO-A 9" }
	VS._migrate(player, data)
	eq(data.bank, 1000, "no refund on a later join")
	assert(data.vehicles.v9 == nil, "old car removed")
	-- someone already paid three times before the fix: two get taken back
	data = {
		bank = 800000,
		tx = {
			{ amount = 250000, reason = "Erstattung Fahrzeuge", t = 1 },
			{ amount = 250000, reason = "Erstattung Fahrzeuge", t = 2 },
			{ amount = 250000, reason = "Erstattung Fahrzeuge", t = 3 },
		},
		nextUid = 2,
		vehicles = { v1 = { id = Vehicles.BikeId, plate = "DO-B 1" } },
	}
	player.UserId = 43
	VS._migrate(player, data)
	eq(data.bank, 300000, "duplicates taken back")
	VS._migrate(player, data)
	eq(data.bank, 300000, "correction runs once")
end)

-- AA events: boosts, gifts once per player, pickups -------------------------------
test("AA events", function()
	local stores = {}
	fakeServices.DataStoreService = {
		GetDataStore = function(_, name)
			stores[name] = stores[name] or {}
			local mem = stores[name]
			return {
				UpdateAsync = function(_, key, fn)
					local new = fn(mem[key])
					if new ~= nil then
						mem[key] = new
					end
				end,
				GetAsync = function(_, key)
					return mem[key]
				end,
			}
		end,
	}
	local n = 0
	fakeServices.HttpService = {
		GenerateGUID = function()
			n += 1
			return string.format("%08d-x", n)
		end,
		JSONEncode = function(_, v)
			return tostring(v)
		end,
	}
	fakeServices.MessagingService = {
		PublishAsync = function() end,
		SubscribeAsync = function() end,
	}
	fakeServices.MarketplaceService = {
		GetProductInfo = function(_, id)
			if id == 1837849285 then
				return { AssetTypeId = 3, Name = "Event Song" }
			end
			return { AssetTypeId = 10, Name = "A model" }
		end,
	}
	local data = { bank = 0, tx = {}, inventory = {} }
	local got = {}
	local fakePlayer = { UserId = 7, Name = "P" }
	fakeServices.Players = {
		GetPlayers = function()
			return { fakePlayer }
		end,
	}
	local stub = function()
		return setmetatable({}, {
			__index = function()
				return function() end
			end,
		})
	end
	overrides["ServerScriptService/Server/DataService"] = {
		Get = function()
			return data
		end,
	}
	overrides["ServerScriptService/Server/EconomyService"] = {
		Add = function(_, amount, reason)
			data.bank += amount
			table.insert(got, reason)
			return true
		end,
	}
	overrides["ServerScriptService/Server/XPService"] = stub()
	overrides["ServerScriptService/Server/PhoneService"] = stub()
	overrides["ServerScriptService/Server/StoreService"] = stub()
	overrides["ServerScriptService/Server/Remotes"] = stub()
	local dropEvent, droppersOn = nil, true
	overrides["ServerScriptService/Server/DropEventService"] = {
		Set = function(id)
			dropEvent = id
		end,
	}
	overrides["ServerScriptService/Server/DropperService"] = {
		SetEnabled = function(on)
			droppersOn = on
		end,
	}
	local Boosts = requirePath(Server.Boosts)
	local Events = requirePath(Server.EventService)
	for _, name in
		{
			"DataService",
			"EconomyService",
			"XPService",
			"PhoneService",
			"StoreService",
			"Remotes",
			"DropEventService",
			"DropperService",
		}
	do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	fakeServices.DataStoreService, fakeServices.HttpService = nil, nil
	fakeServices.MessagingService, fakeServices.Players = nil, nil
	fakeServices.MarketplaceService = nil

	-- rewards are checked
	eq(Events.CheckReward("cash", 500), 500)
	eq(Events.CheckReward("cash", -5), nil, "negative cash")
	eq(Events.CheckReward("cash", 1e9), nil, "too much cash")
	eq(Events.CheckReward("item", "pizza_salami"), "pizza_salami")
	eq(Events.CheckReward("item", "nope"), nil)
	eq(Events.CheckReward("phone", "nvdr_p1"), nil, "admin phone can't be given")
	eq(Events.CheckReward("rocket", 1), nil)

	-- boosts
	assert(Events.SetBoost("cash", 3, 10), "set boost")
	eq(Boosts.Cash(), 3, "3x cash")
	local snap = Events.Snapshot()
	eq(snap.cash.m, 3)
	assert(snap.cash.ends > os.time() + 590, "10 minutes")
	assert(Events.StopBoost("cash"), "stop")
	eq(Boosts.Cash(), Boosts.WeeklyEnds(os.time()) and 2 or 1, "boost stopped")

	-- gift: once per player, even if the message arrives twice
	Events.Gift("cash", 250)
	require("@lune/task").wait(0.1)
	eq(data.bank, 250, "gift paid")
	eq(#data.eventClaims, 1)

	-- pickups (max 10 at once)
	for i = 1, 10 do
		assert(Events.AddDrop(100 + i, 200, "cash", 50, 5), "drop " .. i)
	end
	local ok, err = Events.AddDrop(1, 1, "cash", 50, 5)
	eq(ok, false, "11th drop refused")
	eq(err, "too_many_drops")
	eq(#Events.Snapshot().drops, 10)
	local id = Events.Snapshot().drops[1].id
	assert(Events.RemoveDrop(id), "remove")
	eq(#Events.Snapshot().drops, 9)

	-- music: only real audio ids, saved list without duplicates
	local okMusic, errMusic = Events.PlayMusic(555, 0.5, true)
	eq(okMusic, false, "a model is not music")
	eq(errMusic, "not_audio")
	assert(Events.PlayMusic(1837849285, 0.8, true), "play")
	eq(Events.Snapshot().music.name, "Event Song")
	eq(Events.Snapshot().music.vol, 0.8)
	assert(Events.StopMusic(), "stop")
	eq(Events.Snapshot().music, nil, "stopped")
	assert(Events.AddSong(1837849285), "add song")
	assert(Events.AddSong(1837849285), "adding twice is fine")
	eq(#Events.Snapshot().songs, 1, "no duplicates")
	assert(Events.RemoveSong(1837849285), "remove song")
	eq(#Events.Snapshot().songs, 0)

	-- 24/7 default music: on unless paused
	eq(Events.Snapshot().defaultOff, false, "default music on")
	assert(Events.SetDefaultMusic(false), "pause")
	eq(Events.Snapshot().defaultOff, true, "paused")
	assert(Events.SetDefaultMusic(true), "start")
	eq(Events.Snapshot().defaultOff, false, "on again")

	-- dropper events + dropper switch reach every server's services
	assert(Events.SetDropEvent("crabs", 10), "drop event")
	eq(dropEvent, "crabs")
	eq(Events.Snapshot().dropEvent.id, "crabs")
	assert(Events.SetDropEvent(nil), "stop drop event")
	eq(dropEvent, nil)
	assert(Events.SetDroppers(false), "droppers off")
	eq(droppersOn, false)
	eq(Events.Snapshot().droppersOff, true)
	assert(Events.SetDroppers(true), "droppers on")
	eq(droppersOn, true)

	-- countdown: shown until a few minutes after it hits zero
	assert(Events.SetCountdown("AA", os.time() + 3600), "countdown")
	eq(Events.Snapshot().countdown.title, "AA")
	assert(Events.ClearCountdown(), "clear")
	eq(Events.Snapshot().countdown, nil)
	local Bo = requirePath(Server.Boosts)
	eq(os.date("!%Y-%m-%d %H:%M", Bo.FromBerlin(2026, 11, 13, 19, 0)), "2026-11-13 18:00", "19:00 CET")
	eq(os.date("!%Y-%m-%d %H:%M", Bo.FromBerlin(2026, 7, 1, 19, 0)), "2026-07-01 17:00", "19:00 CEST")
end)

-- Every bike builds ---------------------------------------------------------------
for _, v in Vehicles.List do
	if v.car then
		continue -- cars are built by RealisticCars (own test below)
	end
	test("build " .. v.id, function()
		local model = VehicleBuilder.Build(v)
		assert(model.PrimaryPart, "no primary part")
		local seat = model:FindFirstChild("DriveSeat")
		assert(seat, "no driver seat")
		assert(math.abs(seat.CFrame.Position.X) < 0.01, "rider sits in the middle")
		local motors, steers = 0, 0
		for _, d in model:GetDescendants() do
			if d.ClassName == "HingeConstraint" then
				if d.Name == "Motor" then
					motors += 1
					assert(d.MotorMaxTorque > 0, "zero torque")
				elseif d.Name == "Steer" then
					steers += 1
				end
			end
		end
		eq(motors, 4, "motors")
		eq(steers, 2, "steering")
		assert(model.PrimaryPart:FindFirstChild("Stabilizer"), "no stabiliser")
		-- rear-wheel drive: the front only rolls, so it can't pull the bike into a spin
		local function torque(w)
			return model:FindFirstChild(w):FindFirstChild("Motor"):GetAttribute("BaseTorque")
		end
		assert(torque("WheelFL") < torque("WheelRL") * 0.2, "front wheel must not drive")
		assert(model.PrimaryPart:FindFirstChild("Upright"), "wheelie needs the Upright attachment")
		-- the visible wheels spin with the physics wheels, the fork steers with the knuckle
		local wheelFL, wheelRL = model:FindFirstChild("WheelFL"), model:FindFirstChild("WheelRL")
		local tyres, forks = 0, 0
		for _, d in model:GetDescendants() do
			if d.ClassName == "WeldConstraint" then
				if d.Part1.Name == "Tyre" then
					assert(d.Part0 == wheelFL or d.Part0 == wheelRL, "tyre not on a wheel")
					tyres += 1
				elseif d.Part1.Name == "Fork" or d.Part1.Name == "Handlebar" then
					eq(d.Part0.Name, "Knuckle", "fork must steer")
					forks += 1
				end
			end
		end
		eq(tyres, 2, "two visible tyres")
		eq(forks, 3, "fork legs + handlebar")
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local p = d.CFrame.Position
				assert(p.Y > -0.1 and p.Y < 6, string.format("%s at y=%.1f", d.Name, p.Y))
				assert(math.abs(p.Z) < 4.2 and math.abs(p.X) < 1.6, d.Name .. " sticks out")
				if d ~= model.PrimaryPart and d.Name ~= "Knuckle" and not string.match(d.Name, "^Wheel") then
					assert(d.Massless and not d.CanCollide, d.Name .. " must be massless decoration")
				end
			end
		end
		if v.emergency then
			assert(model:FindFirstChild("Bluelight"), "emergency bike without blue lights")
			assert(model.PrimaryPart:FindFirstChild("Siren"), "no siren")
		else
			assert(not model:FindFirstChild("Bluelight"), "blue lights on a non-emergency bike")
		end
		if v.livery then
			assert(model:FindFirstChild("TopCase"), "livery top case")
		else
			local painted = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("Paint") then
					painted += 1
				end
			end
			assert(painted >= 5, "civilian paint parts")
			local c = roblox.Color3.fromRGB(0, 140, 200)
			VehicleBuilder.SetColor(model, c)
			eq((model:FindFirstChild("Tank") :: any).Color, c, "repaint")
		end
		VehicleBuilder.SetPlate(model, "DO-AB 1234")
		eq(model:GetAttribute("Plate"), "DO-AB 1234")
		model:Destroy()
	end)
end

-- Map builds -----------------------------------------------------------------------
overrides["ServerScriptService/Server/InteractionService"] = {
	Mark = function(part, kind, attrs)
		part:SetAttribute("Interaction", kind)
		for k, val in attrs do
			part:SetAttribute(k, val)
		end
		fakeServices.CollectionService:AddTag(part, "Interaction")
	end,
}
test("triangle prisms hit their corners", function()
	local CityBuilder = requirePath(Server.CityBuilder)
	local V2 = roblox.Vector2
	local rngT = env.Random.new(7)
	for _ = 1, 200 do
		local function rp()
			return V2.new(rngT:NextInteger(-500, 500) / 3, rngT:NextInteger(-500, 500) / 3)
		end
		local a, b, c = rp(), rp(), rp()
		local area = math.abs((b - a).X * (c - a).Y - (b - a).Y * (c - a).X) / 2
		if area > 20 then
			local holder = roblox.Instance.new("Folder")
			CityBuilder._triPrism(
				holder,
				a,
				b,
				c,
				0,
				10,
				roblox.Color3.new(1, 1, 1),
				roblox.Enum.Material.Concrete,
				true
			)
			local covered = 0
			for _, w in holder:GetChildren() do
				local sz = w.Size
				-- wedge cross-section corners: bottom-front, bottom-back (right angle), top-back
				for _, lp in
					{
						roblox.Vector3.new(0, -sz.Y / 2, -sz.Z / 2),
						roblox.Vector3.new(0, -sz.Y / 2, sz.Z / 2),
						roblox.Vector3.new(0, sz.Y / 2, sz.Z / 2),
					}
				do
					local wp = w.CFrame * lp
					local p = V2.new(wp.X, wp.Z)
					local best = math.min((p - a).Magnitude, (p - b).Magnitude, (p - c).Magnitude)
					if best < 0.01 then
						covered += 1
					end
				end
				assert(math.abs(w.CFrame.RightVector.Y) > 0.999, "wedge not vertical")
				eq(w.CFrame.Position.Y, 5, "prism height centre")
			end
			-- each of the 2 wedges has 2 real triangle corners (+ the foot point)
			eq(covered, 4, "wedge corners on triangle")
			local sum = 0
			for _, w in holder:GetChildren() do
				sum += w.Size.Y * w.Size.Z / 2
			end
			assert(math.abs(sum - area) < 0.05, "area mismatch " .. sum .. " vs " .. area)
		end
	end
end)

test("real city + map", function()
	local CityBuilder = requirePath(Server.CityBuilder)
	CityBuilder.GroundY = function()
		return 0.2 -- no raycasts in Lune
	end
	local MapBuilder = requirePath(Server.MapBuilder)
	local t0 = os.clock()
	MapBuilder.Build()
	local city = dataModel:GetService("Workspace"):FindFirstChild("City")
	assert(city, "no city")
	local counts = {}
	local total = 0
	for _, f in city:GetChildren() do
		counts[f.Name] = #f:GetChildren()
		total += counts[f.Name]
	end
	print(
		string.format(
			"  city: %d parts in %.1fs  (buildings %d, roads %d, pavements %d, markings %d, trees %d, lights %d)",
			total,
			os.clock() - t0,
			counts.Buildings,
			counts.Roads,
			counts.Pavements,
			counts.Markings,
			counts.Trees,
			counts.StreetLights
		)
	)
	assert(counts.Buildings > 20000, "too few building parts")
	local kinds: { [string]: number } = {}
	for _, m in tagged.Interaction or {} do
		local k = m:GetAttribute("Interaction")
		kinds[k] = (kinds[k] or 0) + 1
	end
	eq(kinds.JobStart, 7, "job start markers (one per job)")
	eq(kinds.AptDoor, 32, "32 apartment doors in the tower")
	eq(kinds.Elevator, 17, "elevator on every floor + lobby")
	local TowerBuilder = requirePath(Server.TowerBuilder)
	eq(#TowerBuilder.Units, 32, "tower units")
	local StationBuilder = requirePath(Server.StationBuilder)
	eq(#StationBuilder.Bays.Police, 4, "police garage bays")
	eq(#StationBuilder.Bays.Fire, 3, "fire bays")
	assert(StationBuilder.Jobs.Rettungsdienst and StationBuilder.Jobs.Notarzt, "rescue shares the fire station")
	eq(#(StationBuilder.Bays.ADMC or {}), 4, "ADMC bays")
	eq(#(StationBuilder.Bays.DXL or {}), 5, "DXL bays")
	eq(#(StationBuilder.Bays.LKW or {}), 4, "LKW bays")
	eq(kinds.JobGarage, 7, "job garages")
	assert((kinds.Refuel or 0) >= 3, "petrol stations")
	local uis = {}
	for _, m in tagged.Interaction do
		local ui = m:GetAttribute("UI")
		if ui then
			uis[ui] = true
		end
	end
	assert(uis.Handyland and uis.Dealership, "shops: Handyland and Autohaus")

	local StoreBuilder = requirePath(Server.StoreBuilder)
	StoreBuilder.Build()
	local stores = dataModel:GetService("Workspace"):FindFirstChild("Stores")
	local Locations = requirePath(RS.Shared.Locations)
	local built, markers = 0, 0
	for _, m in stores:GetChildren() do
		if m:FindFirstChild("Checkout") then
			built += 1
		end
	end
	for _, m in tagged.Interaction do
		if m:GetAttribute("Interaction") == "Store" then
			markers += 1
		end
	end
	eq(built, #Locations.Stores, "every store has a checkout")
	assert(markers >= #Locations.Stores, "every store has a cashier prompt")
	print(string.format("  stores: %d walk-in shops", built))
end)

-- v0.2: dropper events, traffic, droppers ---------------------------------------------
test("dropper events: each drop has the event's chance", function()
	local DropEvents = requirePath(RS.Shared.DropEvents)
	eq(#DropEvents.List, 7, "7 events")
	eq(DropEvents.ById.germany.mult, 5)
	eq(DropEvents.ById.germany.chance, 0.05)
	eq(DropEvents.ById.tacos.mult, 1.4)
	local stub = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
	overrides["ServerScriptService/Server/Remotes"] = stub
	cache["ServerScriptService/Server/DropEventService"] = nil
	local Service = requirePath(Server.DropEventService)
	overrides["ServerScriptService/Server/Remotes"] = nil
	local r = env.Random.new(3)
	eq(Service.Hit(r), 1, "no event: no multiplier")
	Service.Set("tacos", os.time() + 60)
	eq(Service.Current(), "tacos")
	local hits = 0
	for _ = 1, 5000 do
		local mult, hit = Service.Hit(r)
		if hit then
			hits += 1
			eq(mult, 1.4)
		end
	end
	assert(math.abs(hits / 5000 - 0.45) < 0.03, "about 45 % of drops hit: " .. hits)
	Service.Set(nil)
	eq(Service.Current(), nil, "stopped")
end)

test("traffic lights: never green both ways", function()
	local Phase = requirePath(RS.Shared.TrafficPhase)
	local greenA, greenB = 0, 0
	for t = 0, Phase.CYCLE * 3, 0.5 do
		local a, b = Phase.State(t, 5)
		assert(not (a ~= "R" and b ~= "R"), "both axes open at " .. t)
		greenA += if a == "G" then 1 else 0
		greenB += if b == "G" then 1 else 0
	end
	assert(math.abs(greenA - greenB) <= 1, "fair green time")
	local Data = requirePath(RS.Shared.TrafficData)
	assert(#Data.lights > 100, "traffic lights from OSM")
	assert(#Data.cameras > 20, "speed cameras from OSM")
end)

test("Fahr-XP exchange drops the last digit", function()
	local stub = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
	for _, name in { "DataService", "EconomyService", "Remotes", "State" } do
		overrides["ServerScriptService/Server/" .. name] = stub
	end
	local Traffic = requirePath(Server.TrafficService)
	for _, name in { "DataService", "EconomyService", "Remotes", "State" } do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	local euros, rest = Traffic._exchange(1234)
	eq(euros, 123)
	eq(rest, 4)
	eq(Traffic._exchange(9), 0)
end)

test("dropper tycoon in the apartment", function()
	local Config = requirePath(RS.Shared.Config)
	eq(#Config.DropperCosts, 10, "10 droppers")
	eq(Config.DropperCosts[1], 0, "first is free")
	eq(Config.DropperCosts[2], 1000)
	eq(Config.DropperCosts[5], 100000)
	eq(Config.DropperCosts[6], 200000, "then x2")
	eq(Config.DropperCosts[10], 3200000)
	eq(Config.DropperDrops[1], 50, "first drops 50")
	eq(Config.DropperDrops[10], 4000, "dropper 10: 4000 per second (nerfed)")
	for i = 2, 10 do
		assert(Config.DropperDrops[i] > Config.DropperDrops[i - 1], "every dropper drops more")
	end
	eq(Config.DropInterval, 1, "every second")
	local Tower = requirePath(Server.TowerBuilder)
	assert(Tower.Units[1].frame, "flat frame")

	local data = { bank = 5000, tx = {}, droppers = 0, dropCash = 0 }
	overrides["ServerScriptService/Server/DataService"] = {
		Get = function()
			return data
		end,
	}
	overrides["ServerScriptService/Server/EconomyService"] = {
		TrySpend = function(_, amount)
			if data.bank < amount then
				return false
			end
			data.bank -= amount
			return true
		end,
		Add = function(_, amount)
			data.bank += amount
			return true
		end,
	}
	local stub = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
	overrides["ServerScriptService/Server/Remotes"] = stub
	overrides["ServerScriptService/Server/State"] = stub
	cache["ServerScriptService/Server/DropperService"] = nil
	cache["ServerScriptService/Server/DropEventService"] = nil
	local Droppers = requirePath(Server.DropperService)
	for _, name in { "DataService", "EconomyService", "Remotes", "State" } do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	local player = {
		UserId = 5,
		GetAttribute = function(_, k)
			return if k == "Apartment" then 1 else nil
		end,
	}
	Droppers._build(player)
	local t = Droppers._tycoon(player)
	assert(t, "tycoon built")
	eq(data.droppers, 1, "free first dropper")
	assert(t.model:FindFirstChild("Dropper1"), "dropper 1")
	assert(t.model:FindFirstChild("BuyPad"), "buy pad")
	assert(t.model:FindFirstChild("Collector"), "collector")
	-- buy dropper 2 (1000), 3 (3000), then 4 is too expensive
	assert(Droppers.Buy(player), "buy 2")
	assert(Droppers.Buy(player), "buy 3")
	eq(data.bank, 1000)
	local ok, err = Droppers.Buy(player)
	eq(ok, false)
	eq(err, "no_money")
	eq(data.droppers, 3)
	assert(t.model:FindFirstChild("Dropper3"), "dropper 3 built")
	-- collecting moves the collector money to the bank
	data.dropCash = 1500
	eq(Droppers.Collect(player), 1500)
	eq(data.bank, 2500)
	eq(data.dropCash, 0)
	-- all droppers stay inside the flat
	local frame = Tower.Units[1].frame
	for _, d in t.model:GetDescendants() do
		if d:IsA("BasePart") then
			local lp = frame:PointToObjectSpace(d.CFrame.Position)
			assert(
				math.abs(lp.X) < Tower.Units[1].w / 2 and math.abs(lp.Z) < Tower.Units[1].d / 2,
				d.Name .. " outside the flat"
			)
		end
	end
end)

test("admin tower: site and offices", function()
	local Locations = requirePath(RS.Shared.Locations)
	assert(Locations.Sites.AdminTower, "admin tower site")
	local stub = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
	for _, name in { "DataService", "Remotes", "Roles" } do
		overrides["ServerScriptService/Server/" .. name] = stub
	end
	local Tower = requirePath(Server.AdminTowerService)
	for _, name in { "DataService", "Remotes", "Roles" } do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	local ids = Tower.AdminIds()
	eq(ids[1], 10396317047, "owner first")
	eq(ids[2], 3559943151, "then samder_nervt")
	eq(#ids, 5, "five admins, no doubles")
	assert(#ids <= 6, "one office each")
	Tower.Build()
	local model = env.workspace:FindFirstChild("Admin Tower")
	assert(model, "built")
	local pcs, cells = 0, 0
	for _, d in model:GetDescendants() do
		if d.Name == "PC" then
			pcs += 1
		elseif d.Name == "CellDoor" then
			cells += 1
		end
	end
	eq(pcs, 7, "6 office PCs + meeting room")
	eq(cells, 1, "one Sonderraum")
	for _, spot in { "Outside", "Lobby", "Offices", "Meeting", "Holding", "HoldingHall" } do
		assert(Tower.Spot(spot), "spot " .. spot)
	end
end)

test("full game log: add, filter, pages", function()
	local Log = requirePath(Server.GameLog)
	Log.Add("money", 98765, "+500.00 € Dropper")
	Log.Add("chat", 98765, "to 23646: hilfe")
	for i = 1, 150 do
		Log.Add("xp", 7, "+50 XP Verkehr #" .. i)
	end
	local today = os.date("!%Y-%m-%d") :: string
	local all, total = Log.Read(today, nil, 1, 100)
	eq(#all, 100, "first page")
	assert(total >= 152, "everything is there")
	local chats, n = Log.Read(today, "23646", 1, 100)
	eq(n, 1, "filter finds the message")
	eq(chats[1].k, "chat")
	local _, n2 = Log.Read(today, "98765", 1, 100)
	eq(n2, 2, "filter by user id")
	local page2 = Log.Read(today, "xp", 2, 100)
	eq(#page2, 50, "second page")
end)

test("votes are shared by all servers", function()
	local mem = {}
	fakeServices.DataStoreService = {
		GetDataStore = function()
			return {
				UpdateAsync = function(_, key, fn)
					local new = fn(mem[key])
					if new ~= nil then
						mem[key] = new
					end
				end,
				GetAsync = function(_, key)
					return mem[key]
				end,
			}
		end,
	}
	fakeServices.MessagingService = { PublishAsync = function() end, SubscribeAsync = function() end }
	fakeServices.Players = {
		GetPlayers = function()
			return {}
		end,
	}
	fakeServices.HttpService = {
		GenerateGUID = function()
			return "abcdef12-0000"
		end,
		JSONEncode = function(_, v)
			return tostring(v)
		end,
	}
	local stub = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
	overrides["ServerScriptService/Server/Remotes"] = stub
	overrides["ServerScriptService/Server/State"] = stub
	overrides["ServerScriptService/Server/DataService"] = stub
	cache["ServerScriptService/Server/VoteService"] = nil
	local Votes = requirePath(Server.VoteService)
	for _, name in { "Remotes", "State", "DataService" } do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	fakeServices.DataStoreService, fakeServices.MessagingService = nil, nil
	fakeServices.HttpService, fakeServices.Players = nil, nil

	assert(Votes.Begin("Pizza?", { "Ja", "Nein" }, 5, "Tester"), "vote started")
	assert(Votes.IsRunning(), "running")
	eq(Votes.Begin("Noch eine?", { "A", "B" }, 5, "Tester"), false, "only one vote at a time")
	assert(mem.current and mem.current.question == "Pizza?", "saved for all servers")
	assert(Votes.End(), "ended")
	eq(Votes.IsRunning(), false)
	assert(mem.current.ends <= os.time(), "end saved too")
end)

test("every car builds and gets its livery", function()
	local VehicleConfig = requirePath(RS.VehicleConfig)
	local storage = roblox.Instance.new("Folder")
	local oldStorage = fakeServices.ServerStorage
	fakeServices.ServerStorage = storage
	cache["ServerScriptService/Server/Cars/VehicleModelGenerator"] = nil
	local Generator = requirePath(pathProxy({ "ServerScriptService", "Server", "Cars", "VehicleModelGenerator" }))
	local Applier = requirePath(pathProxy({ "ServerScriptService", "Server", "Cars", "LiveryApplier" }))
	fakeServices.ServerStorage = oldStorage
	local built, failed = 0, {}
	for _, v in VehicleConfig.List do
		local ok, err = pcall(function()
			local template = Generator.Get(v)
			assert(template, "no model")
			local model = template:Clone()
			assert(model.PrimaryPart and model:FindFirstChild("DriverSeat"), "chassis + driver seat")
			Applier.ApplyVehicle(model, v, nil)
			model:Destroy()
		end)
		if ok then
			built += 1
		else
			table.insert(failed, v.Id .. ": " .. tostring(err))
		end
	end
	eq(#failed, 0, table.concat(failed, "\n"))
	print(string.format("  cars: %d built", built))
end)

test("custom plates: city is always DO", function()
	local Plate = requirePath(RS.Shared.Plate)
	eq(Plate.NormalizeDO("AB 123"), "DO-AB 123")
	eq(Plate.NormalizeDO("do-ab 123"), "DO-AB 123")
	eq(Plate.NormalizeDO("DO-DO-AB 12"), "DO-AB 12", "DO typed twice")
	eq(Plate.NormalizeDO("AB 1234"), nil, "max three digits")
	eq(Plate.NormalizeDO("B-AB 123"), nil, "other city refused")
	eq(Plate.NormalizeDO("DO-AB 012"), nil, "no leading zero")
	eq(Plate.NormalizeDO("ABC 123"), nil, "max two letters")
end)

test("admin cars: orange livery with red sirens", function()
	local VehicleConfig = requirePath(RS.VehicleConfig)
	local n = 0
	for _, v in VehicleConfig.List do
		if v.Category == "ServerAdmin" or v.Category == "GameAdmin" then
			n += 1
			eq(v.LightType, "red", v.Name .. " red lights")
			eq(v.Livery.Lettering, "ADMIN", v.Name .. " lettering")
			eq(v.Livery.Colors.Body:ToHex():upper(), "FF7300", v.Name .. " orange")
		end
	end
	eq(n, 10, "10 admin cars")
end)

test("mall, underground garages and plate service", function()
	local stub = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
	for _, name in { "Remotes", "Roles", "DataService" } do
		overrides["ServerScriptService/Server/" .. name] = stub
	end
	local Mall = requirePath(Server.MallBuilder)
	local Garages = requirePath(Server.GarageService)
	local Plates = requirePath(Server.PlateService)
	for _, name in { "Remotes", "Roles", "DataService" } do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	Mall.Build()
	Garages.Build()
	Plates.Build()
	local ws = env.workspace
	local mall = ws:FindFirstChild("Dortmund Mall")
	assert(mall, "mall built")
	local stores, special = 0, {}
	for _, d in mall:GetDescendants() do
		if d.Name == "Marker_Store" then
			stores += 1
		elseif d.Name == "Marker_Shop" then
			special[d:GetAttribute("UI")] = true
		end
	end
	eq(stores, 14, "14 food shops in the mall")
	assert(special.Dealership and special.Handyland, "Autohaus + Handyland branch")
	eq(#Mall.Spots, 3, "lifts on floors 1-3 (+ ground floor 0)")
	for _, name in { "Tiefgarage Dortmund Tower", "Tiefgarage Admin Tower" } do
		local g = ws:FindFirstChild(name)
		assert(g, name)
		local bays = 0
		for _, d in g:GetChildren() do
			if d.Name == "BayLine" then
				bays += 1
			end
		end
		eq(bays, 16, name .. " bays")
		assert(g:FindFirstChild("Marker_GarageIn") and g:FindFirstChild("Marker_GarageOut"), name .. " gates")
	end
	assert(ws:FindFirstChild("Kennzeichen-Service"), "ADMC plate service")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
