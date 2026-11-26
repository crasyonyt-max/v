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
	-- V1.0: only real-body cars (the blocky ones are retired): admin = bike, One:1 RS,
	-- M3 G80, Setro admin bus + their 3 owner versions; 14 civil cars at the Autohaus
	local v10 = requirePath(RS.Shared.Config).RealCars
	eq(#Vehicles.ByCategory("Admin"), if v10 then 7 else 23, "admin bike + admin cars + admin bus + owner ones")
	eq(#Vehicles.ByCategory("Dealer"), if v10 then 14 else 20, "dealership cars")
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
	eq(kinds.JobStart, 8, "job start markers (one per job)")
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
	eq(kinds.JobGarage, 8, "job garages")
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
	eq(#DropEvents.List, 8, "7 events + Thanksgiving")
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
			assert(model:GetAttribute("TopSpeed") and model:GetAttribute("Power"), "own top speed + power")
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

test("buses: seats, doors, displays; admin bus free + no siren", function()
	local VehicleConfig = requirePath(RS.VehicleConfig)
	local storage = roblox.Instance.new("Folder")
	local oldStorage = fakeServices.ServerStorage
	fakeServices.ServerStorage = storage
	cache["ServerScriptService/Server/Cars/VehicleModelGenerator"] = nil
	local Generator = requirePath(pathProxy({ "ServerScriptService", "Server", "Cars", "VehicleModelGenerator" }))
	fakeServices.ServerStorage = oldStorage
	-- ranks: 8912131297 is a Game Admin, everyone else a normal player
	local any = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
	local fakes = {
		Roles = {
			IsServerAdmin = function(p)
				return p.UserId == 8912131297
			end,
		},
		EconomyService = any,
		Remotes = any,
		XPService = any,
		GameLog = any,
	}
	for name, fake in fakes do
		overrides["ServerScriptService/Server/" .. name] = fake
	end
	cache["ServerScriptService/Server/BusService"] = nil
	local BusService = requirePath(Server.BusService)
	for name in fakes do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	cache["ServerScriptService/Server/BusService"] = nil
	local buses, admin = 0, nil
	for _, v in VehicleConfig.List do
		if Generator.RuleFor(v).Type ~= "Bus" then
			continue
		end
		buses += 1
		local model = Generator.Get(v):Clone()
		local free = v.Category == "GameAdmin" or v.Category == "Owner"
		assert(BusService.Build(model, free, v.LivingRoom), v.Name .. " equipped")
		eq(model:GetAttribute("Bus"), true)
		local seats, doors, displays = 0, 0, 0
		for _, c in model:GetChildren() do
			if c.ClassName == "Seat" then
				seats += 1
				local prompt = c:FindFirstChild("EnterPrompt")
				assert(prompt and prompt.Enabled == false, "boarding only with open doors")
			elseif c.Name:match("^Door%d_") then
				doors += 1
			elseif c.Name:match("^Line") then
				displays += 1
			end
		end
		if v.LivingRoom then
			-- owner bus: living room (sofa + armchair to sit on), no seat rows
			local sofa = false
			for _, c in model:GetChildren() do
				sofa = sofa or c.Name == "sofa"
				assert(not c.Name:match("^Seat%d"), v.Name .. ": no passenger seat rows")
			end
			assert(sofa, v.Name .. ": sofa in the living room")
			eq(seats, 4, v.Name .. ": 3 sofa places + armchair")
		else
			assert(seats >= 12, v.Name .. ": passenger seats " .. seats)
		end
		eq(doors, 4, v.Name .. ": two double doors")
		eq(displays, 3, v.Name .. ": front, side, rear display")
		if free then
			if v.Category == "GameAdmin" then
				admin = v
			end
			eq(model:GetAttribute("FreeRide"), true, "admin bus is free")
			local normal = { UserId = 1234, Name = "Normal" } :: any
			local gameAdmin = { UserId = 8912131297, Name = "deniney26548" } :: any
			eq(BusService.MayBoard(model, normal), false, "normal player can't ride the admin bus")
			eq(BusService.MayBoard(model, gameAdmin), true, "admins can")
		else
			eq(BusService.MayBoard(model, { UserId = 1234 } :: any), true, "normal bus: everyone")
		end
		model:Destroy()
	end
	eq(
		buses,
		if requirePath(RS.Shared.Config).RealCars then 3 else 6,
		"job buses + admin bus + owner bus (+ V1.0 Setro: job, admin, owner)"
	)
	assert(admin, "admin bus exists")
	eq(admin.LightType, "none", "admin bus: no siren")
	eq(admin.Livery.Colors.Body:ToHex():upper(), "FF7300", "admin bus: orange ADMIN livery")
	local Jobs = requirePath(RS.Shared.Jobs)
	assert(Jobs.ById.Bus, "bus driver job")
	eq(#Vehicles.ForJob("Bus"), if requirePath(RS.Shared.Config).RealCars then 1 else 4, "buses in the bus job garage")
end)

test("train timetable: smooth, both ways, all stations", function()
	local TrainLine = requirePath(RS.Shared.TrainLine)
	local line = TrainLine.Lines[1]
	assert(line and #line.stations >= 5, "U43 with stations")
	assert(line.cycle > 300 and line.cycle < 1500, "cycle " .. line.cycle)
	-- trip maths: full distance at the end, continuous
	local d = 1800
	eq(math.floor(TrainLine.TripDistance(d, TrainLine.TripTime(d)) + 0.5), d)
	-- simulate one train for a whole cycle: never jumps (except turning at the ends), stops everywhere
	local seen = {}
	local last = TrainLine.State(line, 1, 0)
	for t = 0.5, line.cycle, 0.5 do
		local st = TrainLine.State(line, 1, t)
		if st.dir == last.dir then
			assert(math.abs(st.s - last.s) <= TrainLine.VMAX * 0.5 + 0.01, "no jump at t=" .. t)
		end
		assert(
			st.s >= line.stations[1].s - 0.01 and st.s <= line.stations[#line.stations].s + 0.01,
			"stays between the ends"
		)
		if st.dwelling and st.station then
			seen[st.station .. ":" .. st.dir] = true
		end
		last = st
	end
	for i = 2, #line.stations - 1 do
		assert(seen[i .. ":1"] and seen[i .. ":-1"], line.stations[i].name .. " served both ways")
	end
	-- U43 + U44: same cycle, same shared stations, and never two trains close on one track
	local u43, u44 = TrainLine.Lines[1], TrainLine.Lines[2]
	assert(u44 and u44.id == "U44", "U44 line")
	eq(u43.cycle, u44.cycle, "one timetable")
	for i = 1, 4 do
		eq(u44.stations[i].s, u43.stations[i].s, "shared station " .. u43.stations[i].name)
	end
	eq(u44.stations[#u44.stations].name, "Borsigplatz", "U44 ends at Borsigplatz")
	local closest = math.huge
	for t = 0, u43.cycle, 1 do
		local pos = {}
		for _, l in TrainLine.Lines do
			for k = 1, TrainLine.TRAINS do
				local st = TrainLine.State(l, k, t)
				local p = TrainLine.At(l, st.s)
				table.insert(pos, { p = p, dir = st.dir, l = l, s = st.s })
			end
		end
		for a = 1, #pos do
			for b = a + 1, #pos do
				local A, B = pos[a], pos[b]
				-- same track: same direction, and both on the shared part or on the same line
				local shared = A.s < math.max(A.l.branchFrom, B.l.branchFrom)
					and B.s < math.max(A.l.branchFrom, B.l.branchFrom)
				if A.dir == B.dir and (A.l == B.l or shared) then
					closest = math.min(closest, (A.p - B.p).Magnitude)
				end
			end
		end
	end
	assert(closest > 150, "trains on one track keep their distance, closest " .. closest)
	print(string.format("  trains: cycle %.0f s, closest on one track %.0f studs", u43.cycle, closest))
	local deps = TrainLine.Departures(line, 2, 1, 100)
	eq(#deps, TrainLine.TRAINS, "one departure per train")
	assert(deps[1] >= 0 and deps[1] < line.cycle / TrainLine.TRAINS + 1, "next train within the interval")
end)

test("every car has its own speed", function()
	local VehicleConfig = requirePath(RS.VehicleConfig)
	local Perf = requirePath(RS.Shared.CarPerformance)
	local Tuning = requirePath(RS.RealisticCars.CarTuning)
	local Configs = requirePath(RS.RealisticCars.Configs)
	local missing = {}
	for _, v in VehicleConfig.List do
		if not Perf.Get(v.Model) then
			table.insert(missing, v.Model)
		end
	end
	eq(#missing, 0, "no speed for: " .. table.concat(missing, ", "))
	-- same body type, different cars: different engines
	local chiran = Tuning.Get("Supercar", 1500, 420)
	local neverra = Tuning.Get("Supercar", 1914, 412)
	assert(chiran.engine.torque[3][2] < neverra.engine.torque[3][2], "more PS = more torque")
	eq(chiran.topSpeed, 420)
	eq(Configs.Cars.Supercar.topSpeed, nil, "the base type stays untouched")
	local korsa = Tuning.Get("Hatchback", 75, 170)
	local golfR = Tuning.Get("Hatchback", 320, 250)
	assert(korsa.engine.torque[3][2] < golfR.engine.torque[3][2], "Korsa C weaker than Golfo R")
	eq(Tuning.Get("Hatchback", 75, 170), korsa, "cached")
	-- braking: every car gets the brake assist, buses + trucks stronger brakes and steering
	assert(korsa.brakeAssist and korsa.brakeAssist > 0, "brake assist")
	local bus = Tuning.Get("Bus", 354, 80)
	assert(bus.brakes.maxTorque > Configs.Cars.Bus.brakes.maxTorque, "bus brakes stronger")
	assert(bus.steering.speedFactor < Configs.Cars.Bus.steering.speedFactor, "bus steers better at speed")
	eq(Configs.Cars.Bus.brakeAssist, nil, "base config untouched")
	eq(bus.body, Configs.Cars.Bus.body, "the body stays as built")
	local Vehicles = requirePath(RS.Shared.Vehicles)
	local shown = Vehicles.Stats(Vehicles.ByCategory("Dealer")[1])
	assert(shown:find("km/h") and shown:find("PS"), "shown in the Autohaus: " .. shown)
end)

test("Robux money: rebuyable, every receipt paid once", function()
	local Config = requirePath(RS.Shared.Config)
	local player = { UserId = 77, Name = "Buyer" } :: any
	local data = { bank = 0, receipts = {} }
	local paid, saveOk = 0, true
	local any = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
	local fakes = {
		DataService = {
			Get = function()
				return data
			end,
			Save = function()
				return saveOk
			end,
		},
		EconomyService = {
			Add = function(_, amount)
				paid += amount
				data.bank += amount
				return true
			end,
		},
		Remotes = any,
		GameLog = any,
		ServerService = any,
	}
	for name, fake in fakes do
		overrides["ServerScriptService/Server/" .. name] = fake
	end
	local oldPlayers = fakeServices.Players
	fakeServices.Players = {
		GetPlayerByUserId = function(_, id)
			return if id == 77 then player else nil
		end,
	}
	cache["ServerScriptService/Server/PurchaseService"] = nil
	local Purchase = requirePath(Server.PurchaseService)
	for name in fakes do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	fakeServices.Players = oldPlayers
	cache["ServerScriptService/Server/PurchaseService"] = nil

	local product = Config.MoneyProducts[2]
	local oldId = product.id
	product.id = 123456
	local r1 = { PlayerId = 77, ProductId = 123456, PurchaseId = "A" }
	eq(Purchase.Process(r1), "PurchaseGranted")
	eq(Purchase.Process(r1), "PurchaseGranted", "same receipt again (Roblox retry)")
	eq(paid, product.cash, "paid once")
	eq(Purchase.Process({ PlayerId = 77, ProductId = 123456, PurchaseId = "B" }), "PurchaseGranted")
	eq(paid, product.cash * 2, "bought again = paid again")
	saveOk = false
	eq(Purchase.Process({ PlayerId = 77, ProductId = 123456, PurchaseId = "C" }), "NotProcessedYet", "not saved yet")
	saveOk = true
	eq(Purchase.Process({ PlayerId = 77, ProductId = 123456, PurchaseId = "C" }), "PurchaseGranted")
	eq(paid, product.cash * 3, "the retry after a failed save does not pay twice")
	eq(Purchase.Process({ PlayerId = 5, ProductId = 123456, PurchaseId = "D" }), "NotProcessedYet", "player not here")
	eq(Purchase.Process({ PlayerId = 77, ProductId = 999, PurchaseId = "E" }), "NotProcessedYet", "unknown product")
	product.id = oldId
end)

test("ID: certificates, owner-only ones, W4, numbers", function()
	local Certificates = requirePath(RS.Shared.Certificates)
	eq(#Certificates.List, 14, "14 certificates")
	for _, code in { "VOTR289DO9F", "VIPRE77OOC2", "F78W72L8D9LE" } do
		eq(Certificates.ByCode[code].owner, true, code .. " is an owner certificate")
	end
	eq(Certificates.ByCode.VAT8388NDO.owner, false)
	local a, b = Certificates.IdNumber(3482982410), Certificates.IdNumber(8912131297)
	eq(#a, 9, "9 characters like a Personalausweis")
	eq(a, Certificates.IdNumber(3482982410), "always the same for one player")
	assert(a ~= b, "different players, different numbers")

	-- permissions (fake ranks: 1 = Owner, 2 = Game Admin, 3 = normal player)
	local ranks = { [1] = 6, [2] = 3, [3] = 0 }
	local any = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
	local fakes = {
		Roles = {
			OWNER = 6,
			IsGameAdmin = function(p)
				return (ranks[p.UserId] or 0) >= 3
			end,
			Rank = function(p)
				return ranks[p.UserId] or 0
			end,
			CanTargetUserId = function(p, id)
				return (ranks[p.UserId] or 0) > (ranks[id] or 0)
			end,
		},
		DataService = any,
		GameLog = any,
		JobService = {
			Get = function(p)
				return p.job or "Unemployed"
			end,
		},
		Remotes = any,
	}
	for name, fake in fakes do
		overrides["ServerScriptService/Server/" .. name] = fake
	end
	local oldDS = fakeServices.DataStoreService
	fakeServices.DataStoreService = {
		GetDataStore = function()
			error("no datastores in tests")
		end,
	}
	local oldPlayers = fakeServices.Players
	fakeServices.Players = {
		GetPlayerByUserId = function()
			return nil
		end,
	}
	cache["ServerScriptService/Server/IDService"] = nil
	local ID = requirePath(Server.IDService)
	fakeServices.Players = oldPlayers
	for name in fakes do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	fakeServices.DataStoreService = oldDS
	cache["ServerScriptService/Server/IDService"] = nil
	local owner, admin, normal =
		{ UserId = 1, Name = "Owner" }, { UserId = 2, Name = "Admin" }, { UserId = 3, Name = "N" }
	eq((ID.MayChange(admin, 3, "VAT8388NDO")), true, "admin gives a normal certificate")
	eq(select(2, ID.MayChange(admin, 3, "VIPRE77OOC2")), "id_owner_only", "admin can't give owner certificates")
	eq((ID.MayChange(owner, 3, "VIPRE77OOC2")), true, "the owner can")
	eq((ID.MayChange(normal, 3, "W1")), false, "players can't give certificates")
	eq((ID.MayChange(admin, 1, "W1")), false, "no warnings for the owner from an admin")
	eq((ID.MayChange(admin, 3, "NOPE")), false, "unknown code")
	-- give + view (memory store): listed in certificate order
	assert(ID.Give(owner, 3, "W1"))
	assert(ID.Give(owner, 3, "VAT8388NDO"))
	local v = ID.View(ID.Load(3))
	eq(v.certs[1].code, "VAT8388NDO", "shown in list order")
	eq(v.certs[2].code, "W1")
	eq(v.residence, "Dortmund")
	assert(ID.Remove(owner, 3, "W1"))
	eq(#ID.View(ID.Load(3)).certs, 1, "removed")
	-- police: only on duty
	eq(ID.MayInspect({ UserId = 3 } :: any, { UserId = 4 } :: any), false, "normal players can't see other IDs")
	eq(ID.MayInspect(admin :: any, { UserId = 4 } :: any), true, "admins can")
end)

test("Kofferraum: limits by body, ID can't go in", function()
	local Trunk = requirePath(RS.Shared.Trunk)
	local VehicleConfig = requirePath(RS.VehicleConfig)
	local storage = roblox.Instance.new("Folder")
	local oldStorage = fakeServices.ServerStorage
	fakeServices.ServerStorage = storage
	cache["ServerScriptService/Server/Cars/VehicleModelGenerator"] = nil
	local Generator = requirePath(pathProxy({ "ServerScriptService", "Server", "Cars", "VehicleModelGenerator" }))
	fakeServices.ServerStorage = oldStorage
	local function limit(model)
		for _, v in VehicleConfig.List do
			if v.Model == model then
				return Trunk.LimitFor(Generator.RuleFor(v).Type)
			end
		end
		error("no car " .. model)
	end
	if requirePath(RS.Shared.Config).RealCars then
		eq(limit("Koenigshaus One:1 RS"), 14)
		eq(limit("BMV 330i F30"), 45)
		eq(limit("Mercator Sprintor Werkstatt"), 500)
		eq(limit("Mercator Sprintor RTW"), 500, "job cars too")
		eq(limit("Setro Stadtbus"), 5)
	else
		eq(limit("Koenigshaus Jesco"), 14)
		eq(limit("Koenigshaus One:1"), 14)
		eq(limit("Kupra Formentor VZ5"), 50)
		eq(limit("BMV M4 Kompetition"), 45)
		eq(limit("Mercator Sprintor"), 500)
		eq(limit("RTW Mercator Sprintor"), 500, "job cars too")
		eq(limit("Mercator Sitaro"), 5)
	end
	eq(Trunk.LimitFor("Motorbike"), 10, "motorbike")
	local any = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
	for _, name in { "DataService", "Remotes", "State", "StoreService" } do
		overrides["ServerScriptService/Server/" .. name] = any
	end
	cache["ServerScriptService/Server/TrunkService"] = nil
	local TS = requirePath(Server.TrunkService)
	for _, name in { "DataService", "Remotes", "State", "StoreService" } do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	cache["ServerScriptService/Server/TrunkService"] = nil
	local Items = requirePath(RS.Shared.Items)
	local item = Items.List[1].id
	local data = { inventory = { item, item }, trunks = {} }
	eq(select(2, TS.Put(data, "v1", 1, "id_card")), "trunk_not_item", "the ID can't go in")
	assert(TS.Put(data, "v1", 1, item), "first item in")
	eq(select(2, TS.Put(data, "v1", 1, item)), "trunk_full", "limit")
	assert(TS.Take(data, "v1", item), "take out")
	eq(#data.trunks.v1, 0)
end)

test("owner cars: blue OWNER livery, Owner + Co-Owner only", function()
	local VehicleConfig = requirePath(RS.VehicleConfig)
	local n = 0
	for _, v in VehicleConfig.List do
		if v.Category == "Owner" then
			n += 1
			eq(v.Livery.Colors.Body:ToHex():upper(), "0A5CFF", v.Name .. " blue")
			local bus = v.Model == "Solaria Urbano Elektro" or v.Model == "Setro Stadtbus"
			eq(v.Livery.Lettering, if bus then "OWNER BUS" else "OWNER")
			if bus then
				eq(v.LightType, "none", v.Name .. ": no siren")
			end
		end
	end
	eq(n, if requirePath(RS.Shared.Config).RealCars then 3 else 11, "every admin car + the bus as owner versions")
	for _, v in Vehicles.ByCategory("Admin") do
		if v.name:find("%(Owner%)") then
			eq(v.adminLevel, "Owner", v.name)
		end
	end
end)

test("v0.4: server codes, houses, furniture, laptops", function()
	local any = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
	for _, name in { "Roles", "DataService", "Remotes", "GameLog" } do
		overrides["ServerScriptService/Server/" .. name] = any
	end
	cache["ServerScriptService/Server/ServerService"] = nil
	local Servers = requirePath(Server.ServerService)
	for _, name in { "Roles", "DataService", "Remotes", "GameLog" } do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	cache["ServerScriptService/Server/ServerService"] = nil
	local fakeRng = {
		NextInteger = function(_, a, b)
			return math.random(a, b)
		end,
	} :: any
	local code = Servers.NewCode(fakeRng)
	eq(#code, 8, "8 characters")
	eq(Servers.CleanCode(code:lower()), code, "lower case works")
	eq(Servers.CleanCode(code:sub(1, 4) .. "-" .. code:sub(5)), code, "with a dash")
	eq(Servers.CleanCode("ABC"), nil, "too short")
	-- regression: two statements starting with "(" ran together into one call
	-- ("(store):SetAsync(...)(store):SetAsync(...)") and lost the first purchases
	local fs = require("@lune/fs")
	local function scan(dir: string)
		for _, name in fs.readDir(dir) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				if name ~= "RealisticCars" and name ~= "CityData" then
					scan(path)
				end
			elseif name:match("%.lua$") then
				local text = fs.readFile(path)
				assert(not text:find("%)%(%w+ :: "), path .. ": a call chained onto the line before")
			end
		end
	end
	scan("src")
	eq(Servers.CleanCode("ABCD0O1I"), nil, "no 0 / O / 1 / I")

	local Houses = requirePath(RS.Shared.Houses)
	eq(#Houses.List, 8, "8 house types")
	eq(Houses.List[1].price, 200000, "from 200.000 €")
	eq(Houses.List[#Houses.List].price, 5000000, "to 5.000.000 €")
	local HouseBuilder = requirePath(Server.HouseBuilder)
	for _, h in Houses.List do
		local built = HouseBuilder.Build(h, roblox.CFrame.new(), "Tester")
		assert(built.door and built.mailbox, h.name .. ": door + mailbox")
		local garage = built.model:FindFirstChild("Garage")
		if h.garage then
			assert(garage, h.name .. " has its garage")
			local gp = garage.CFrame.Position
			assert(math.abs(gp.X) + garage.Size.X / 2 <= Houses.PLOT_W / 2 - 1, h.name .. ": garage on the plot")
			local house = built.bounds
			assert(
				gp.X - garage.Size.X / 2 >= house.cf.Position.X + house.size.X / 2,
				h.name .. ": garage next to the house, not inside"
			)
		else
			eq(garage, nil, h.name .. " has no garage")
		end
		local c = built.bounds.cf.Position
		assert(
			math.abs(c.X) + built.bounds.size.X / 2 <= Houses.PLOT_W / 2
				and math.abs(c.Z) + built.bounds.size.Z / 2 <= Houses.PLOT_D / 2,
			h.name .. " fits its plot"
		)
		built.model:Destroy()
	end

	local Furniture = requirePath(RS.Shared.Furniture)
	assert(#Furniture.List >= 20, "furniture catalog")
	for _, it in Furniture.List do
		local m = Furniture.Build(it.id)
		assert(m and m.PrimaryPart, it.id .. " builds")
		m:Destroy()
	end
	assert(Furniture.ById[Furniture.FREE_BED], "free bed exists")
	local half = roblox.Vector3.new(37, 0, 36)
	eq(Furniture.Fits("bed_single", 0, 0.5, 0, 0, half, 40), true, "bed in the middle")
	eq(Furniture.Fits("bed_single", 35, 0.5, 0, 0, half, 40), false, "bed through the hedge")
	eq(Furniture.Fits("sofa", 33, 0.5, 0, 90, half, 40), true, "turned sofa fits at the side")
	eq(Furniture.Fits("sofa", 0, 0 / 0, 0, 0, half, 40), false, "NaN refused")

	local Laptops = requirePath(RS.Shared.Laptops)
	assert(#Laptops.List >= 5, "laptops")
end)

test("v0.4 imagine: catalog, delivery after the time, waits when the bag is full", function()
	local Imagine = requirePath(RS.Shared.Imagine)
	local Items = requirePath(RS.Shared.Items)
	assert(#Imagine.List > 40, "products from all shops")
	local keys = {}
	for _, p in Imagine.List do
		assert(not keys[p.key], "unique key " .. p.key)
		keys[p.key] = true
	end
	local any = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
	local fakes = { "DataService", "EconomyService", "GameLog", "Remotes", "State", "StoreService" }
	for _, name in fakes do
		overrides["ServerScriptService/Server/" .. name] = any
	end
	cache["ServerScriptService/Server/OrderService"] = nil
	local Orders = requirePath(Server.OrderService)
	for _, name in fakes do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	cache["ServerScriptService/Server/OrderService"] = nil
	local food = Items.List[1].id
	local data = {
		inventory = {},
		phones = {},
		orders = {
			{ n = 1, key = "item:" .. food, eta = 100, express = false },
			{ n = 2, key = "furniture:sofa", eta = 100, express = false },
			{ n = 3, key = "laptop:pear_air", eta = 500, express = true },
		},
	}
	eq(Orders.Tick(nil, data, 50), 0, "nothing before the time")
	eq(Orders.Tick(nil, data, 100), 2, "food + sofa arrive")
	eq(data.inventory[1], food, "food in the bag")
	eq(data.furniture.sofa, 1, "sofa in the furniture storage")
	eq(#data.orders, 1, "laptop still on the way")
	eq(Orders.Tick(nil, data, 500), 1, "laptop arrives")
	eq(data.laptop, "pear_air", "laptop is yours")
	-- full bag: the parcel waits
	for i = 1, Items.MaxCarried do
		data.inventory[i] = food
	end
	data.orders = { { n = 4, key = "item:" .. food, eta = 0, express = false } }
	eq(Orders.Tick(nil, data, 10), 0, "bag full")
	eq(#data.orders, 1, "waits")
	eq(data.orders[1].waiting, true)
	table.remove(data.inventory)
	eq(Orders.Tick(nil, data, 11), 1, "arrives once there is room")
end)

test("bigger map (XL): only on the testing server, same sites, more city", function()
	local Config = requirePath(RS.Shared.Config)
	local function fresh(name)
		cache["ReplicatedStorage/Shared/" .. name] = nil
		return requirePath(pathProxy({ "ReplicatedStorage", "Shared", name }))
	end
	local base = fresh("Locations")
	local baseStops, baseLights = #fresh("BusStopData"), #fresh("TrafficData").lights
	eq(base.Bounds[1], -3285.4, "the game keeps its map")
	Config.Testing = true
	local xl = fresh("Locations")
	local xlStops, xlLights = #fresh("BusStopData"), #fresh("TrafficData").lights
	local img = fresh("MapImage")
	Config.Testing = false
	fresh("Locations")
	fresh("BusStopData")
	fresh("TrafficData")
	fresh("MapImage")
	assert(xl ~= base and xl.Bounds[1] < base.Bounds[1], "testing server: bigger map")
	local area = function(b)
		return (b[3] - b[1]) * (b[4] - b[2])
	end
	local grow = area(xl.Bounds) / area(base.Bounds)
	assert(grow > 1.45 and grow < 1.55, ("50 %% bigger, got %.1f %%"):format((grow - 1) * 100))
	assert(xl.Bounds[4] > base.Bounds[4], "also further south")
	for k, site in base.Sites do
		local o = xl.Sites[k]
		assert(o and o.x == site.x and o.z == site.z and o.yaw == site.yaw, k .. " stays where it is")
	end
	for k, j in base.Jobs do
		eq(xl.Jobs[k].marker[1], j.marker[1], k .. " station marker")
	end
	assert(#xl.Stores > #base.Stores, "more markets")
	assert(xlStops > baseStops and xlLights > baseLights, "more bus stops and traffic lights")
	eq(img.minX, xl.Bounds[1], "AA map image matches the bigger map")
	assert(img.image ~= "rbxassetid://95046841102055", "own map image")
end)

test("testing server: saves and messages stay in the server", function()
	local real = { p1 = { bank = 100 } }
	local wrote = false
	fakeServices.DataStoreService = {
		GetDataStore = function()
			return {
				GetAsync = function(_, k)
					return real[k]
				end,
				SetAsync = function()
					wrote = true
				end,
				UpdateAsync = function()
					wrote = true
				end,
				RemoveAsync = function()
					wrote = true
				end,
			}
		end,
	}
	cache["ServerScriptService/Server/Sandbox"] = nil
	local Sandbox = requirePath(Server.Sandbox)
	eq(Sandbox.Active, false, "main game: real services")
	local Config = requirePath(RS.Shared.Config)
	eq(Config.Testing, false, "not the testing server")
	eq(Config.On("test"), false, "test-only switch is off in the game")
	eq(Config.On(true), true)
	Config.Testing = true
	eq(Config.On("test"), true, "test-only switch is on on the testing server")
	eq(Config.On(false), false)
	Config.Testing = false
	local ds = Sandbox._local.DataStoreService:GetDataStore("x")
	eq(ds:GetAsync("p1").bank, 100, "reads the real save")
	ds:UpdateAsync("p1", function(old)
		old.bank = 5000
		return old
	end)
	eq(ds:GetAsync("p1").bank, 5000, "sees its own change")
	eq(real.p1.bank, 100, "real save untouched")
	ds:SetAsync("ban_7", { reason = "test" })
	ds:RemoveAsync("p1")
	eq(ds:GetAsync("p1"), nil, "removed here")
	eq(wrote, false, "nothing written to the real DataStore")
	local got = nil
	local ms = Sandbox._local.MessagingService
	ms:SubscribeAsync("AAEvents", function(m)
		got = m.Data
	end)
	ms:PublishAsync("AAEvents", { boost = 3 })
	assert(got and got.boost == 3, "events reach this server's own listeners")
	fakeServices.DataStoreService = nil
end)

test("Thanksgiving: event, turkeys, oven", function()
	local DropEvents = requirePath(RS.Shared.DropEvents)
	local TG = requirePath(RS.Shared.Thanksgiving)
	local Items = requirePath(RS.Shared.Items)
	local Furniture = requirePath(RS.Shared.Furniture)
	local Imagine = requirePath(RS.Shared.Imagine)
	local e = DropEvents.ById[TG.EVENT]
	assert(e, "event in the AA list")
	eq(e.mult, 10, "10x")
	eq(e.chance, 0.0005, "0.05 %")
	eq(DropEvents.ChanceText(e), "0,05", "shown as 0,05 %, not 0 %")
	eq(DropEvents.ChanceText(DropEvents.ById.germany), "5")
	eq(DropEvents.ChanceText(DropEvents.ById.tacos), "45")
	eq(TG.SPAWN_MIN, 1)
	eq(TG.SPAWN_MAX, 10)
	eq(TG.SPAWN_EVERY, 120, "every 2 minutes")
	assert(Items.ById[TG.ALIVE] and Items.ById[TG.ALIVE].noEat, "live turkey can't be eaten")
	assert(Items.ById[TG.BAKED] and Items.ById[TG.BAKED].hunger > 0, "roast can be eaten")
	for _, p in Imagine.List do
		assert(p.id ~= TG.ALIVE and p.id ~= TG.BAKED, "turkeys can't be ordered")
	end
	local oven = Furniture.Build(TG.OVEN)
	assert(oven and oven:FindFirstChild("Glow"), "oven with an inside light")
	for _, baked in { false, true } do
		local t = TG.BuildTurkey(baked)
		assert(t.PrimaryPart and t.PrimaryPart.Name == "Body", "turkey model")
		for _, d in t:GetDescendants() do
			if d:IsA("BasePart") then
				local c = d.Color
				assert(
					not (c.R > 0.6 and c.G < 0.1 and c.B < 0.1 and d.Name ~= "Wattle" and d.Name ~= "Feather"),
					"no blood: " .. d.Name
				)
			end
		end
	end
	local src = fs.readFile("src/ServerScriptService/Server/AdminService.lua")
	assert(src:find("Check.Number(args.mult, 2, 100)", 1, true), "boosts up to 100x")
end)

test("V1.0: real-body cars, crime rules, weapons", function()
	local Config = requirePath(RS.Shared.Config)
	-- cars: with V1.0 on, every Creator Store body has its job / civil / admin versions
	Config.V10 = true
	Config.RealCars = true
	cache["ReplicatedStorage/VehicleConfig"] = nil
	local VC = requirePath(RS.VehicleConfig)
	local Bodies = requirePath(pathProxy({ "ServerStorage", "ToolboxBodies" }))
	local Perf = requirePath(RS.Shared.CarPerformance)
	local byBody: { [number]: { any } } = {}
	for _, v in VC.List do
		if v.Toolbox then
			assert(Bodies[v.Toolbox], v.Name .. ": body data")
			assert(v.CarType, v.Name .. ": physics type")
			assert(Perf.Get(v.Model), v.Name .. ": speed + power")
			assert(v.Livery, v.Name .. ": livery")
			byBody[v.Toolbox] = byBody[v.Toolbox] or {}
			table.insert(byBody[v.Toolbox], v)
		end
	end
	local bodies = 0
	for _ in Bodies do
		bodies += 1
	end
	eq(bodies, 17, "17 cleaned bodies")
	for id, info in Bodies do
		assert(info.assetId and info.assetId ~= 0, id .. ": uploaded to the group")
	end
	for id, list in byBody do
		local civil, admin = false, false
		for _, v in list do
			civil = civil or v.Category == "Dealership"
			admin = admin or v.Category == "GameAdmin" or v.Category == "ServerAdmin"
		end
		if id == 97903463217450 or id == 18912299148 or id == 9837028915 then
			eq(civil, false, "One:1 / M3 / Setro bus not for sale")
			eq(admin, true, "One:1 / M3 / Setro bus admin versions")
		else
			eq(civil, true, list[1].Model .. " also civil")
		end
	end
	local police = 0
	for _, v in VC.List do
		if v.Toolbox and v.Category == "Police" then
			police += 1
			eq(v.LightType, if v.Model == "Audix RS7 Sportbak" then "hidden_blue" else "blue", v.Name)
		end
	end
	eq(police, 4, "4 new police cars")
	-- the retired blocky cars: their prices are kept for the one-time refund
	local retired = 0
	for id, price in VC.RetiredPrices do
		retired += 1
		assert(typeof(price) == "number", id)
		eq(VC.Get(id), nil, id .. " is gone")
	end
	eq(retired, 23, "20 Autohaus + 3 starter cars retired")
	for _, job in VC.Jobs do
		local free = false
		for _, v in VC.List do
			free = free or (v.Category == job and v.XPRequired == 0)
		end
		assert(free, job .. ": a car from 0 XP")
	end
	-- archived (Config.RealCars = false): the blocky cars are back, the real-body
	-- ones are gone and their prices are kept for the refund
	Config.RealCars = false
	cache["ReplicatedStorage/VehicleConfig"] = nil
	local VA = requirePath(RS.VehicleConfig)
	for _, v in VA.List do
		eq(v.Toolbox, nil, v.Name .. ": no real-body car while archived")
	end
	eq(next(VA.RetiredPrices), nil, "blocky cars not retired")
	local archivedN = 0
	for id, price in VA.ArchivedPrices do
		archivedN += 1
		assert(typeof(price) == "number", id)
		eq(VA.Get(id), nil, id .. " archived")
	end
	assert(archivedN >= 14, "civil real-body prices kept for the refund")
	for _, job in VA.Jobs do
		local free = false
		for _, v in VA.List do
			free = free or (v.Category == job and v.XPRequired == 0)
		end
		assert(free, job .. ": a blocky car from 0 XP")
	end
	Config.V10 = false
	cache["ReplicatedStorage/VehicleConfig"] = nil

	-- crime rules (fake jobs / money)
	local jobs: { [any]: string } = {}
	local bank: { [any]: number } = {}
	local any = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
	local fakes = {
		JobService = {
			Get = function(p)
				return jobs[p] or "Unemployed"
			end,
		},
		EconomyService = {
			Balance = function(p)
				return bank[p] or 0
			end,
			TrySpend = function(p, n)
				bank[p] = (bank[p] or 0) - n
				return true
			end,
			Add = function(p, n)
				bank[p] = (bank[p] or 0) + n
				return true
			end,
			Earn = function(p, n)
				bank[p] = (bank[p] or 0) + n
				return n
			end,
		},
		GameLog = any,
		Remotes = any,
		XPService = any,
		DataService = any,
		InteractionService = any,
		PrisonService = {
			Cells = {},
			Inside = function()
				return true
			end,
		},
	}
	for name, fake in fakes do
		overrides["ServerScriptService/Server/" .. name] = fake
	end
	cache["ServerScriptService/Server/CrimeService"] = nil
	cache["ServerScriptService/Server/WeaponService"] = nil
	local Crime = requirePath(Server.CrimeService)
	overrides["ServerScriptService/Server/CrimeService"] = Crime
	local Weapon = requirePath(Server.WeaponService)
	overrides["ServerScriptService/Server/CrimeService"] = nil
	for name in fakes do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	cache["ServerScriptService/Server/CrimeService"] = nil
	cache["ServerScriptService/Server/WeaponService"] = nil
	local function fakePlayer(name)
		local attrs = {}
		return {
			Name = name,
			DisplayName = name,
			UserId = #name,
			Parent = true,
			SetAttribute = function(_, k, v)
				attrs[k] = v
			end,
			GetAttribute = function(_, k)
				return attrs[k]
			end,
		} :: any
	end
	Config.V10 = true
	local robber, cop, other = fakePlayer("Robber"), fakePlayer("Cop"), fakePlayer("Other")
	jobs[cop] = "Police"
	eq(Crime.IsCivil(robber), true)
	eq(Crime.IsCivil(cop), false, "police are not civilians")
	eq(Crime.IsCriminal(robber), false)
	Crime.Crime(robber, "test")
	eq(Crime.IsCriminal(robber), true, "crime -> wanted")
	local first = Crime.Wanted[robber].untilT
	assert(first - os.time() >= Config.CriminalSeconds - 1, "5 minutes")
	Crime.Wanted[robber].untilT = os.time() + 252 -- 4:12 left
	Crime.Crime(robber, "again")
	assert(Crime.Wanted[robber].untilT - os.time() >= Config.CriminalSeconds - 1, "new crime -> 5:00 again")
	-- weapons: police only hurt wanted people, everyone else commits a crime
	eq(Weapon.MayHurt(cop, other), false, "police can't shoot innocent people")
	eq(Weapon.MayHurt(cop, robber), true, "police can shoot criminals")
	eq(Weapon.MayHurt(other, cop), true, "civilians can (it is a crime)")
	eq(Weapon.MayHurt(other, other), false, "not yourself")
	-- arrest: prison, stolen money gone, reward for the officer
	bank[robber] = 5000
	Crime.Wanted[robber].stolen = 2000
	Crime.Jail(robber, cop)
	eq(Crime.IsCriminal(robber), false, "no longer wanted")
	eq(Crime.IsJailed(robber), true, "in prison")
	eq(bank[robber], 3000, "stolen money taken")
	eq(bank[cop], Config.ArrestReward, "officer reward")
	eq(Weapon.MayHurt(other, robber), false, "prisoners can't be hurt")
	Config.V10 = false

	local Weapons = requirePath(RS.Shared.Weapons)
	assert(Weapons.ById.service_pistol and Weapons.ById.pistol, "two weapons")
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
			local bus = v.Model == "Solaria Urbano Elektro" or v.Model == "Setro Stadtbus"
			eq(v.LightType, if bus then "none" else "red", v.Name .. " lights (bus: no siren)")
			eq(v.Livery.Lettering, if bus then "ADMIN BUS" else "ADMIN", v.Name .. " lettering")
			eq(v.Livery.Colors.Body:ToHex():upper(), "FF7300", v.Name .. " orange")
		end
	end
	eq(n, if requirePath(RS.Shared.Config).RealCars then 3 else 11, "admin cars + admin bus")
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
	local Trains = requirePath(Server.TrainService)
	for _, name in { "EconomyService", "State" } do
		overrides["ServerScriptService/Server/" .. name] = stub
	end
	local realPlayers = fakeServices.Players
	fakeServices.Players = {
		GetPlayerByUserId = function()
			return nil
		end,
		GetPlayers = function()
			return {}
		end,
	}
	local HouseSvc = requirePath(Server.HouseService)
	fakeServices.Players = realPlayers
	local FurnitureSvc = requirePath(Server.FurnitureService)
	for _, name in { "EconomyService", "State" } do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	for _, name in { "Remotes", "Roles", "DataService" } do
		overrides["ServerScriptService/Server/" .. name] = nil
	end
	Mall.Build()
	Garages.Build()
	Plates.Build()
	local ws = env.workspace
	-- bus stops from OSM: built, and found again near their position
	local Stops = requirePath(Server.BusStopService)
	local BusStopData = requirePath(RS.Shared.BusStopData)
	Stops.Build()
	-- v0.4: housing estate + Swedea (switched on just for this test)
	local Config = requirePath(RS.Shared.Config)
	Config.V04 = true
	HouseSvc.Build()
	FurnitureSvc.Build()
	assert(ws:FindFirstChild("Wohngebiet"), "estate built")
	eq(#HouseSvc.Plots, 16, "16 plots")
	assert(ws:FindFirstChild("Swedea"), "Swedea built")
	local record = {
		owner = 77,
		ownerName = "Tester",
		type = "luxusvilla",
		members = {},
		furniture = {},
		bought = 0,
	}
	assert(HouseSvc.Create(record), "house record")
	eq(HouseSvc.Create(record), false, "only one house per player")
	local plot = HouseSvc.Spawn(record)
	assert(plot and plot.built, "house on a plot")
	eq(HouseSvc.RoleOf(record, 77), "owner")
	eq(HouseSvc.CanEnter(record, 5), false, "strangers stay outside")
	local saved = HouseSvc.Edit(77, function(r)
		r.members["5"] = { role = "guest", name = "Gast" }
		table.insert(r.furniture, { id = "sofa", x = 0, y = 0.6, z = 0, r = 0 })
	end)
	assert(saved, "edit saved")
	eq(HouseSvc.CanEnter(saved, 5), true, "guest may enter")
	eq(HouseSvc.CanBuild(saved, 5), false, "guest may not furnish")
	FurnitureSvc.Render(77)
	local furn = plot.built.model:FindFirstChild("Furniture")
	assert(furn and #furn:GetChildren() == 1, "placed sofa shown")
	Config.V04 = false
	-- Parlament: off in the game ("test"), built when switched on
	local Parliament = requirePath(Server.ParliamentBuilder)
	eq(Parliament.Build(), nil, "only on the testing server")
	Config.Parliament = true
	local parl = Parliament.Build()
	Config.Parliament = "test"
	assert(parl and parl.Parent == ws, "parliament built")
	local inside, outside = parl:FindFirstChild("Inside"), parl:FindFirstChild("Outside")
	local function flagsIn(root)
		local set = {}
		for _, d in root:GetDescendants() do
			if d:IsA("Model") and d.Name:sub(1, 5) == "Flag_" then
				set[d.Name:sub(6)] = (set[d.Name:sub(6)] or 0) + 1
			end
		end
		return set
	end
	local fin = flagsIn(inside)
	for _, id in { "NL", "DK", "DE", "BE", "FR", "EU" } do
		eq(fin[id], 1, id .. " flag inside")
	end
	for id in flagsIn(outside) do
		assert(id == "DE" or id == "EU", "outside only Germany + EU, not " .. id)
	end
	assert((parl:GetAttribute("Seats") or 0) > 150, "seats in the plenary hall")
	-- the entrance is open: nothing solid in the doorway (local 0, 10..40, -150)
	for _, d in parl:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide and d.Name ~= "Floor" and d.Name ~= "Plinth" and d.Name ~= "Podium" then
			local rel = parl:FindFirstChild("Outside").Lawn.CFrame:PointToObjectSpace(d.CFrame.Position)
			local hs = d.Size / 2
			local blocks = math.abs(rel.X) < 12 + hs.X
				and rel.Y - hs.Y < 30
				and rel.Y + hs.Y > 14
				and math.abs(rel.Z + 150) < 4 + hs.Z
			assert(not blocks, "doorway blocked by " .. d.Name)
		end
	end
	parl:Destroy()
	-- V1.0 prison
	local Prison = requirePath(Server.PrisonService)
	Config.V10 = true
	Prison.Build()
	Config.V10 = false
	assert(ws:FindFirstChild("JVA Dortmund"), "prison built")
	eq(#Prison.Cells, 8, "8 cells")
	eq(Prison.Inside(Prison.Cells[1].Position), true, "cells are inside the walls")
	eq(Prison.Inside((Prison.Exit :: any).Position), false, "the exit is outside")
	-- Stadtbahn: viaduct, stations, trains
	local TrainLine = requirePath(RS.Shared.TrainLine)
	Trains.Build()
	local sb = ws:FindFirstChild("Stadtbahn")
	assert(sb, "stadtbahn built")
	local line = TrainLine.Lines[1]
	local stations, cars = 0, 0
	for _, c in sb:GetChildren() do
		if c.Name:match("^U%-Bahnhof") then
			stations += 1
		elseif c:GetAttribute("Train") then
			cars += 1
		end
	end
	local names = {}
	for _, l in TrainLine.Lines do
		for _, st in l.stations do
			names[st.name] = true
		end
	end
	local unique = 0
	for _ in names do
		unique += 1
	end
	eq(stations, unique, "one station per stop (shared stations once)")
	eq(cars, TrainLine.TRAINS * 2 * #TrainLine.Lines, "two cars per train")
	-- Reinoldikirche (shared): its board lists both lines eastbound
	for _, b in Trains.Boards do
		if
			#b.serves == 2
			and b.dir == 1
			and b.serves[1].line.stations[b.serves[1].station].name == "Reinoldikirche"
		then
			local text = Trains.BoardTextFor(b.serves, 1, 0)
			assert(text:find("U43") and text:find("U44"), "both lines on the board: " .. text)
		end
	end
	-- a train at a station stands next to the platform of its direction
	for _, dir in { 1, -1 } do
		local st = line.stations[3]
		local frames = Trains.CarFrames(line, { s = st.s, dir = dir, dwelling = true, station = 3, terminus = false })
		local plat = Trains.PlatformSpot(line, 3, dir)
		local mid = (frames[1].Position + frames[2].Position) / 2
		local d = ((plat.Position - mid) * roblox.Vector3.new(1, 0, 1)).Magnitude
		assert(d > 8 and d < 14, "platform beside the train: " .. d)
	end
	Trains.Step()
	assert(
		string.find(Trains.BoardText(line, 2, 1, 0), "min") or string.find(Trains.BoardText(line, 2, 1, 0), "sofort"),
		"board"
	)
	assert(string.find(Trains.BoardText(line, #line.stations, 1, 0), "Endstation"), "end of the line board")
	local stopFolder = ws:FindFirstChild("BusStops")
	assert(stopFolder, "bus stops built")
	assert(#BusStopData >= 50, "bus stops around the city: " .. #BusStopData)
	eq(#stopFolder:GetChildren(), #BusStopData, "one shelter per stop")
	local first = Stops.Stops[1]
	eq(Stops.Nearest(first.pos + roblox.Vector3.new(10, 0, 5), 45), first, "bus at the stop")
	eq(Stops.Nearest(first.pos + roblox.Vector3.new(400, 0, 400), 45) == first, false, "far away: not this stop")
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
