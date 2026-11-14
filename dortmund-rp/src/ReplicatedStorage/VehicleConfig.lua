--[[
	VehicleConfig (ReplicatedStorage)

	Every vehicle in the game. To add one, add ONE line to the right list below.
	Nothing else needs to change.

	Each finished entry (VehicleConfig.Get(id)) has:
	  Id           unique key, generated from Category + Name (e.g. "POLICE_MERCATOR_SPRINTOR")
	  Name         display name, also the model name in ServerStorage/Vehicles
	  Model        model name (defaults to Name; set Model = "..." to share a model)
	  Category     Dealership | Starter | Police | Fire | EMS | Notarzt | ADMC | DXL | LKW
	               | Gamepass | ServerAdmin | GameAdmin
	  Job          job key or nil
	  Price        in-game price in EUR (0 = free)
	  XPRequired   XP in that job needed to drive it (0 for non-job cars)
	  IsStarter    true for starter vehicles
	  Gamepass     { Pack, Id, Robux } or nil
	  Livery       { Colors = { Body, Stripe, Accent }, Lettering, LetteringColor, ... }
	  LightType    "none" | "blue" | "orange" | "hidden_blue"
	  Repaintable  players can repaint it (dealership, starter, gamepass cars)
	  Extras       optional parts to keep, e.g. { "WindowGrilles" }

	This module is readable by clients on purpose (shop UI). Secret data such
	as admin UserIds lives in ServerScriptService/VehicleSystem/AdminConfig.
]]

local LiveryConfig = require(script.Parent:WaitForChild("LiveryConfig"))

local VehicleConfig = {}

VehicleConfig.Settings = {
	StartingMoney = 5000, -- EUR for new players
	RepaintCost = 0, -- EUR per repaint
	SpawnDistance = 14, -- studs in front of the player
	VehiclesFolder = "Vehicles", -- ServerStorage/<this>
}

VehicleConfig.Jobs = { "Police", "Fire", "EMS", "Notarzt", "ADMC", "DXL", "LKW", "Bus" }

-------------------------------------------------------------------------------
-- DEALERSHIP: { Name, Price EUR, Paint }  (Paint names are in LiveryConfig.Paints)
-------------------------------------------------------------------------------
local DEALERSHIP = {
	{ "Dakia Sanderro", 13000, "White" },
	{ "Kio Pikanto", 15000, "Red" },
	{ "Opal Korsa", 20000, "Yellow" },
	{ "Volkswerk Pollo", 21000, "Silver" },
	{ "Opal Astro", 28000, "Blue" },
	{ "Volkswerk Golfo", 30000, "Grey" },
	{ "Skora Octava", 32000, "Green" },
	{ "Volkswerk Tiguar", 40000, "Black" },
	{ "Tesra Model Tri", 40000, "White" },
	{ "Audix A5", 47000, "DarkBlue" },
	{ "BMV 3er", 48000, "Blue" },
	{ "Mercator C-Klasse", 50000, "Silver" },
	{ "Volkswerk Golfo R", 55000, "Blue" },
	{ "Mercator E-Klasse", 60000, "Black" },
	{ "Porsha Makan", 84000, "Grey" },
	{ "BMV M3", 95000, "Green" },
	{ "Porsha Elfer Carrera", 130000, "Red" },
	{ "Mercator G-Klasse", 135000, "Black" },
	{ "Lambardini Uros", 250000, "Yellow" },
	{ "Royce-Rolland Kullinan", 380000, "BlackSilver" },
}

-- CIVILIAN STARTERS (free, each player picks one): { Name, Paint }
local CIVILIAN_STARTERS = {
	{ "Volkswerk Golfo IV", "Silver" },
	{ "Opal Korsa C", "Red" },
	{ "Fort Fiesto", "Blue" },
}

-------------------------------------------------------------------------------
-- JOB FLEETS: { Name, XPRequired, [IsStarter = true], [Lettering = "..."],
--               [Preset = "..."], [Extras = {...}], [Model = "..."] }
-------------------------------------------------------------------------------
local JOB_FLEETS = {
	{
		Job = "Police", Preset = "POLICE",
		Vehicles = {
			{ "Opal Astro Kombi", 0, IsStarter = true },
			{ "Volkswerk Golfo Variant", 250 },
			{ "Volkswerk Turan", 500 },
			{ "Fort S-Maxx", 1000 },
			{ "Mercator Vitto", 2000 },
			{ "Volkswerk Pasat Variant", 3500 },
			{ "BMV 3er Touring", 5000 },
			{ "Mercator Sprintor", 7500, Extras = { "WindowGrilles" } },
			{ "BMV 5er Touring", 10000, Lettering = "AUTOBAHNPOLIZEI" },
			{ "Audix RX6 Avant", 15000, Preset = "POLICE_UNMARKED" },
		},
	},
	{
		Job = "Fire", Preset = "FIRE",
		Vehicles = {
			{ "LF 10 Mercator Ategon", 0, IsStarter = true },
			{ "ELW 1 Mercator Sprintor", 1000, Lettering = "EINSATZLEITUNG" },
			{ "HLF 20 MAR TGM", 2500 },
			{ "DLK 23/12 Mercator Econ", 5000 },
			{ "FLF Rosenbach Panter", 10000, Preset = "AIRPORT_FIRE" },
		},
	},
	{
		Job = "EMS", Preset = "EMS",
		Vehicles = {
			{ "KTW Volkswerk Transporta", 0, IsStarter = true, Lettering = "KRANKENTRANSPORT" },
			{ "NEF Mercator E-Klasse T", 1000 },
			{ "RTW Mercator Sprintor", 2500 },
			{ "GRTW MAR TGM", 5000 },
			{ "ITW Mercator Sprintor XL", 10000, Lettering = "INTENSIVTRANSPORT" },
		},
	},
	{
		Job = "Notarzt", Preset = "NOTARZT",
		Vehicles = {
			{ "Skora Octava Kombi", 0, IsStarter = true },
			{ "Volkswerk Tiguar", 1000 },
			{ "Mercator Vitto", 2500 },
			{ "BMV 5er Touring", 5000 },
			{ "Mercator GLX", 10000, Lettering = "LEITENDER NOTARZT" },
		},
	},
	{
		Job = "ADMC", Preset = "ADMC",
		Vehicles = {
			{ "Mercator Sprintor Service Van", 0, IsStarter = true },
			{ "Volkswerk Kaddy", 0, IsStarter = true },
			{ "Volkswerk Turan", 500 },
			{ "BMV 2er Active Tourer", 1000 },
			{ "BMV X1", 2000 },
			{ "Volkswerk Transporta", 3500 },
			{ "Mercator Sprintor Tow Truck", 5000 },
			{ "MAR TGL Tow Truck", 7500 },
			{ "Mercator Arokos Heavy Recovery", 12000 },
		},
	},
	{
		Job = "DXL", Preset = "DXL",
		Vehicles = {
			{ "StreetRoller E-Van", 0, IsStarter = true },
			{ "Volkswerk Kaddy", 500 },
			{ "Mercator eSprintor", 1500 },
			{ "Volkswerk Krafter", 3000 },
			{ "MAR TGE", 6000 },
		},
	},
	{
		Job = "LKW", Preset = "LKW",
		Vehicles = {
			{ "MAR TGL 7.5t", 0, IsStarter = true },
			{ "Mercator Atekon", 1500 },
			{ "MAR TGX", 5000 },
			{ "Mercator Aktros", 10000 },
			{ "Skandia R", 15000 },
			{ "Volvar FH16", 25000 },
		},
	},
	{
		Job = "Bus", Preset = "BUS",
		Vehicles = {
			{ "Mercator Sitaro", 0, IsStarter = true },
			{ "MAR Lion's Stadt", 1000 },
			{ "Solaria Urbano Elektro", 3000, Lettering = "E-BUS DORTMUND" },
			{ "Mercator Sitaro G", 6000, Lettering = "GELENKBUS" },
		},
	},
}

-------------------------------------------------------------------------------
-- GAMEPASS PACKS: buy the pass with Robux, then the car with in-game EUR.
-- Replace GamepassId = 0 with your real IDs.  Vehicles: { Name, Price EUR, Paint }
-------------------------------------------------------------------------------
local GAMEPASS_PACKS = {
	{
		Pack = "ELECTRIC", GamepassId = 0, Robux = 299,
		Vehicles = {
			{ "Tesra Model Es Plaid", 110000, "White" },
			{ "Porsha Taikan Turbo S", 200000, "FrozenBlue" },
			{ "BMV i7", 115000, "Black" },
			{ "Mercator-AMX EQS", 160000, "Silver" },
			{ "Audix RX e-tran GT", 150000, "Grey" },
		},
	},
	{
		Pack = "HYPERCAR", GamepassId = 0, Robux = 799,
		Vehicles = {
			{ "Bugarti Chiran", 3000000, "BlueBlack" },
			{ "Koenigshaus Jesco", 3000000, "White" },
			{ "Pagano Huayro", 3000000, "CarbonSilver" },
			{ "Mercator-AMX Uno", 2700000, "Silver" },
			{ "Rimax Neverra", 2200000, "DarkBlue" },
		},
	},
	{
		Pack = "OFFROAD", GamepassId = 0, Robux = 249,
		Vehicles = {
			{ "Mercator-AMX G 63", 200000, "MatteBlack" },
			{ "Fort F-150 Raptur", 90000, "Orange" },
			{ "Land Rider Defendor 130", 80000, "OliveGreen" },
			{ "Toyara Land Kruiser", 75000, "White" },
			{ "Mercator Unimug", 250000, "ArmyGreen" },
		},
	},
	{
		Pack = "LUXURY", GamepassId = 0, Robux = 399,
		Vehicles = {
			{ "Royce-Rolland Fantom", 500000, "BlackSilver" },
			{ "Brentley Kontinental GT", 250000, "DarkGreen" },
			{ "Mercator-Maybeck S-Klasse", 220000, "BlackSilver" },
			{ "Range Rider SV", 250000, "Grey" },
			{ "Ashton Marlin DBX", 230000, "RacingGreen" },
		},
	},
	{
		Pack = "CLASSIC", GamepassId = 0, Robux = 199,
		Vehicles = {
			{ "Volkswerk Käfa", 15000, "LightBlue" },
			{ "Mercator 300 SL Flügeltürer", 1500000, "Silver" },
			{ "Porsha Elfer 1973", 150000, "Orange" },
			{ "BMV E30 M3", 100000, "White" },
			{ "Opal Mantra", 20000, "Yellow" },
		},
	},
}

-------------------------------------------------------------------------------
-- ADMIN CARS (free): { Name, Paint }
-------------------------------------------------------------------------------
local SERVER_ADMIN_CARS = { -- private server owner + admins they appoint, in that server only
	{ "Kupra Formentor VZ5", "CopperGrey" },
	{ "Audix RX3 Sportback", "Green" },
	{ "Mercator-AMX C 63 S", "Grey" },
	{ "BMV M4 Kompetition", "Yellow" },
	{ "Porsha 718 Kayman GT4 RS", "Red" },
}

local GAME_ADMIN_CARS = { -- whitelisted UserIds in AdminConfig
	{ "Mercator-AMX GT Black Series", "OrangeBlack" },
	{ "McLaurin 750S", "PapayaOrange" },
	{ "Ferroni SF90 Stradale", "Red" },
	{ "Lambardini Venino", "GreyRed" },
	{ "Koenigshaus One:1", "CarbonOrange" },
}

-------------------------------------------------------------------------------
-- Build the finished table (no need to edit below this line)
-------------------------------------------------------------------------------

local REPAINTABLE = { Dealership = true, Starter = true, Gamepass = true }
local LIVERY_FIELDS = { "Lettering", "SecondaryLettering", "LetteringColor", "Colors", "LightType" }

VehicleConfig.Vehicles = {} -- [Id] = entry
VehicleConfig.List = {} -- in config order
VehicleConfig.GamepassPacks = {} -- [Pack] = { Pack, Id, Robux }

local function makeId(category, name)
	local id = (category .. "_" .. name):upper():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
	return id
end

local function add(fields)
	local id = makeId(fields.Category, fields.Name)
	if VehicleConfig.Vehicles[id] then
		warn(("[VehicleConfig] duplicate vehicle %q in %s, skipped"):format(fields.Name, fields.Category))
		return
	end
	if not fields.Livery then
		warn(("[VehicleConfig] %q skipped: %s"):format(fields.Name, tostring(fields.LiveryError)))
		return
	end
	local entry = {
		Id = id,
		Name = fields.Name,
		Model = fields.Model or fields.Name,
		Category = fields.Category,
		Job = fields.Job,
		Price = fields.Price or 0,
		XPRequired = fields.XPRequired or 0,
		IsStarter = fields.IsStarter == true,
		Gamepass = fields.Gamepass,
		Livery = fields.Livery,
		LightType = fields.LightType or fields.Livery.LightType or "none",
		Repaintable = REPAINTABLE[fields.Category] == true,
		Extras = fields.Extras or {},
		Order = #VehicleConfig.List + 1,
	}
	if not LiveryConfig.LightTypes[entry.LightType] then
		warn(("[VehicleConfig] %q has unknown LightType %q, using none"):format(entry.Name, tostring(entry.LightType)))
		entry.LightType = "none"
	end
	VehicleConfig.Vehicles[id] = entry
	table.insert(VehicleConfig.List, entry)
end

local function painted(category, name, price, paint, extra)
	local livery, err = LiveryConfig.FromPaint(paint)
	local fields = { Name = name, Category = category, Price = price, Livery = livery, LiveryError = err, LightType = "none" }
	for k, v in pairs(extra or {}) do
		fields[k] = v
	end
	add(fields)
end

for _, row in ipairs(DEALERSHIP) do
	painted("Dealership", row[1], row[2], row[3])
end
for _, row in ipairs(CIVILIAN_STARTERS) do
	painted("Starter", row[1], 0, row[2], { IsStarter = true })
end

for _, fleet in ipairs(JOB_FLEETS) do
	for _, row in ipairs(fleet.Vehicles) do
		local overrides = {}
		for _, k in ipairs(LIVERY_FIELDS) do
			if row[k] ~= nil then
				overrides[k] = row[k]
			end
		end
		local livery, err = LiveryConfig.Resolve(row.Preset or fleet.Preset, overrides)
		add({
			Name = row[1],
			Model = row.Model,
			Category = fleet.Job,
			Job = fleet.Job,
			XPRequired = row[2],
			IsStarter = row.IsStarter,
			Livery = livery,
			LiveryError = err,
			Extras = row.Extras,
		})
	end
end

for _, pack in ipairs(GAMEPASS_PACKS) do
	local gamepass = table.freeze({ Pack = pack.Pack, Id = pack.GamepassId, Robux = pack.Robux })
	VehicleConfig.GamepassPacks[pack.Pack] = gamepass
	for _, row in ipairs(pack.Vehicles) do
		painted("Gamepass", row[1], row[2], row[3], { Gamepass = gamepass })
	end
end

-- Dortmund RP: admin cars wear the orange ADMIN livery with red sirens
-- (the paint column above is no longer used for them).
for _, list in ipairs({ { "ServerAdmin", SERVER_ADMIN_CARS }, { "GameAdmin", GAME_ADMIN_CARS } }) do
	for _, row in ipairs(list[2]) do
		local livery, err = LiveryConfig.Resolve("ADMIN")
		add({ Name = row[1], Category = list[1], Price = 0, Livery = livery, LiveryError = err })
	end
end
-- the admin bus: the Solaria of the bus job in the ADMIN livery, without siren
do
	local livery, err = LiveryConfig.Resolve("ADMIN", { LightType = "none", Lettering = "ADMIN BUS" })
	add({
		Name = "Solaria Urbano Elektro (Admin)",
		Model = "Solaria Urbano Elektro",
		Category = "GameAdmin",
		Price = 0,
		Livery = livery,
		LiveryError = err,
	})
end

function VehicleConfig.Get(id)
	return VehicleConfig.Vehicles[id]
end

function VehicleConfig.IsJob(job)
	return table.find(VehicleConfig.Jobs, job) ~= nil
end

-- All vehicles in a category (or job), in config order.
function VehicleConfig.GetByCategory(category)
	local out = {}
	for _, v in ipairs(VehicleConfig.List) do
		if v.Category == category then
			table.insert(out, v)
		end
	end
	return out
end

return VehicleConfig
