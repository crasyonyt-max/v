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
	},
}

local fakeGame = {
	GetService = function(_, name: string)
		if name == "ReplicatedStorage" or name == "ServerScriptService" or name == "ServerStorage" then
			return pathProxy({ name })
		end
		if fakeServices[name] then
			return fakeServices[name]
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
	eq(Locale.T("en", "paycheck", "250 €"), "Paycheck received: 250 €")
	eq(Locale.T("de", "unknown_key"), "unknown_key")
end)

local Vehicles = requirePath(RS.Shared.Vehicles)
local VehicleBuilder = requirePath(Server.VehicleBuilder)
test("vehicle catalog", function()
	eq(#Vehicles.ByCategory("Dealer"), 20, "dealer cars")
	eq(#Vehicles.ByCategory("Starter"), 3, "starters")
	eq(#Vehicles.ByCategory("Pack"), 25, "pack cars")
	eq(#Vehicles.ByCategory("Admin"), 10, "admin cars")
	for _, job in { "Police", "Fire", "Rettungsdienst", "Notarzt", "ADMC", "DXL", "LKW" } do
		local list = Vehicles.ForJob(job)
		assert(#list > 0 and (list[1].xp or 0) == 0, job .. " needs a 0 XP starter")
	end
	for _, v in Vehicles.List do
		assert(VehicleBuilder.BodyTypes[v.body], v.id .. " has unknown body " .. v.body)
		assert(v.category ~= "Pack" or table.find(Vehicles.PackOrder, v.pack), v.id .. " bad pack")
	end
	eq(Vehicles.ById.lambardini_uros.price, 250000)
	eq(Vehicles.ById.bugarti_chiran.price, 3000000)
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

test("config", function()
	local Config = requirePath(RS.Shared.Config)
	eq(Config.AdminChatNumber, "23646")
	eq(Config.AdminPhoneId, "nvdr_p1")
end)

-- Every vehicle builds -----------------------------------------------------------
for _, v in Vehicles.List do
	test("build " .. v.id, function()
		local model = VehicleBuilder.Build(v)
		assert(model.PrimaryPart, "no primary part")
		assert(model:FindFirstChild("DriveSeat"), "no driver seat")
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
		if v.emergency and v.livery ~= "Unmarked" then
			assert(model:FindFirstChild("Bluelight"), "emergency car without blue lights")
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
	eq(kinds.JobGarage, 7, "job garages")
	assert((kinds.Refuel or 0) >= 3, "petrol stations")
	local uis = {}
	for _, m in tagged.Interaction do
		local ui = m:GetAttribute("UI")
		if ui then
			uis[ui] = true
		end
	end
	assert(uis.Handyland and uis.Dealership, "shops missing")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
