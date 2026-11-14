--!strict
-- Vehicle catalog: one motorbike for everyone. All names are parody names.
-- Civilians ride it in their own paint colour; on duty (job garage) it comes in
-- the job livery. `id` values are saved in player data: never rename an id.
--
-- category: "Starter" (the free bike everyone owns) | "CarStarter" (one free car to pick)
--           | "Dealer" | "Pack" (gamepass + price) | "Job" | "Admin"
-- speed: top speed in km/h, accel: 0-100 feel (1 = slow, 3 = very fast)

export type Vehicle = {
	id: string,
	name: string,
	category: string,
	price: number,
	body: string,
	speed: number,
	accel: number,
	power: number?, -- PS (cars: Shared/CarPerformance)
	color: Color3,
	job: string?,
	xp: number?,
	pack: string?,
	adminLevel: string?, -- "Server" | "Game"
	emergency: boolean?,
	livery: string?, -- "Police" | "Fire" | "Rescue" | "ADMC" | "DXL" | "LKW" | "Admin"
	note: string?,
	car: string?, -- VehicleConfig id (cars); nil = motorbike
	repaintable: boolean?,
}

local Vehicles = {}
local list: { Vehicle } = {}

Vehicles.BikeId = "motorrad"
Vehicles.BikeName = "Ruhrmoto R 700"

table.insert(list, {
	id = Vehicles.BikeId,
	name = Vehicles.BikeName,
	category = "Starter",
	price = 0,
	body = "bike",
	speed = 190,
	accel = 1.8,
	color = Color3.fromRGB(180, 20, 20),
})

local function job(jobId: string, livery: string, title: string, color: Color3, emergency: boolean)
	table.insert(list, {
		id = "motorrad_" .. string.lower(jobId),
		name = Vehicles.BikeName .. " " .. title,
		category = "Job",
		job = jobId,
		xp = 0,
		price = 0,
		body = "bike",
		speed = 200,
		accel = 2.0,
		color = color,
		livery = livery,
		emergency = emergency,
	})
end

job("Police", "Police", "Polizei", Color3.fromRGB(0, 58, 150), true)
job("Fire", "Fire", "Feuerwehr", Color3.fromRGB(200, 20, 20), true)
job("Rettungsdienst", "Rescue", "Rettungsdienst", Color3.fromRGB(242, 242, 242), true)
job("Notarzt", "Rescue", "Notarzt", Color3.fromRGB(242, 242, 242), true)
job("ADMC", "ADMC", "ADMC Pannenhilfe", Color3.fromRGB(250, 205, 0), false)
job("DXL", "DXL", "DXL Kurier", Color3.fromRGB(255, 204, 0), false)
job("LKW", "LKW", "Spedition", Color3.fromRGB(40, 90, 60), false)

table.insert(list, {
	id = "motorrad_admin",
	name = Vehicles.BikeName .. " Admin",
	category = "Admin",
	adminLevel = "Server",
	livery = "Admin",
	price = 0,
	body = "bike",
	speed = 260,
	accel = 2.8,
	color = Color3.fromRGB(255, 115, 0),
})

-- CARS (RealisticCars + VehicleConfig/LiveryConfig in ReplicatedStorage) -------------
-- Every car of VehicleConfig becomes an entry here; `car` is its VehicleConfig id.
local VehicleConfig = require(script.Parent.Parent:WaitForChild("VehicleConfig")) :: any
local CarPerformance = require(script.Parent.CarPerformance)
local JOB_OF = { EMS = "Rettungsdienst" } -- their job names -> ours
local PACK_OF =
	{ ELECTRIC = "Electric", HYPERCAR = "Hypercar", OFFROAD = "Offroad", LUXURY = "Luxury", CLASSIC = "Classic" }
Vehicles.CarStarterIds = {} :: { string }
for _, v in VehicleConfig.List do
	local entry: Vehicle = {
		id = v.Id,
		name = v.Name,
		category = "Dealer",
		price = v.Price,
		body = "car",
		speed = (CarPerformance.Get(v.Model)) or 0,
		accel = 1,
		power = select(2, CarPerformance.Get(v.Model)),
		color = v.Livery.Colors.Body or Color3.fromRGB(200, 200, 200),
		car = v.Id,
		emergency = v.LightType ~= "none",
		repaintable = v.Repaintable,
	}
	if v.Category == "Starter" then
		entry.category = "CarStarter"
		table.insert(Vehicles.CarStarterIds, v.Id)
	elseif v.Category == "Gamepass" then
		entry.category = "Pack"
		entry.pack = PACK_OF[v.Gamepass.Pack] or v.Gamepass.Pack
	elseif v.Category == "ServerAdmin" or v.Category == "GameAdmin" then
		entry.category = "Admin"
		entry.adminLevel = if v.Category == "GameAdmin" then "Game" else "Server"
	elseif v.Job then
		entry.category = "Job"
		entry.job = JOB_OF[v.Job] or v.Job
		entry.xp = v.XPRequired
	end
	table.insert(list, entry)
end
Vehicles.PackOrder = { "Electric", "Hypercar", "Offroad", "Luxury", "Classic" }

Vehicles.List = list
Vehicles.ById = {} :: { [string]: Vehicle }
for _, v in list do
	assert(Vehicles.ById[v.id] == nil, "Duplicate vehicle id " .. v.id)
	Vehicles.ById[v.id] = v
end

-- Paint colours offered in the Garage app (index is sent to the server).
Vehicles.Palette = {
	{ 235, 235, 235 },
	{ 25, 25, 28 },
	{ 170, 172, 175 },
	{ 90, 92, 96 },
	{ 180, 20, 20 },
	{ 30, 60, 140 },
	{ 0, 140, 200 },
	{ 40, 110, 70 },
	{ 250, 205, 0 },
	{ 230, 120, 20 },
	{ 110, 40, 140 },
	{ 120, 90, 60 },
}

-- Prices of the cars that were removed: owners get this back once (see VehicleService).
Vehicles.LegacyPrices = {
	amx_eqs = 160000,
	amx_g63 = 200000,
	amx_uno = 2700000,
	ashton_dbx = 230000,
	audix_a5 = 47000,
	audix_etran = 150000,
	bmv_3er = 48000,
	bmv_e30_m3 = 100000,
	bmv_i7 = 115000,
	bmv_m3 = 95000,
	brentley_kontinental = 250000,
	bugarti_chiran = 3000000,
	dakia_sanderro = 13000,
	fort_raptur = 90000,
	kio_pikanto = 15000,
	koenigshaus_jesco = 3000000,
	lambardini_uros = 250000,
	landrider_defendor = 80000,
	maybeck_s = 220000,
	mercator_300sl = 1500000,
	mercator_c = 50000,
	mercator_e = 60000,
	mercator_g = 135000,
	mercator_unimug = 250000,
	opal_astro = 28000,
	opal_korsa = 20000,
	opal_mantra = 20000,
	pagano_huayro = 3000000,
	porsha_elfer = 130000,
	porsha_elfer73 = 150000,
	porsha_makan = 84000,
	porsha_taikan = 200000,
	rangerider_sv = 250000,
	rimax_neverra = 2200000,
	royce_fantom = 500000,
	royce_kullinan = 380000,
	skora_octava = 32000,
	tesra_model_es = 110000,
	tesra_model_tri = 40000,
	toyara_kruiser = 75000,
	vk_golfo = 30000,
	vk_golfo_r = 55000,
	vk_kaefa = 15000,
	vk_pollo = 21000,
	vk_tiguar = 40000,
} :: { [string]: number }

function Vehicles.ForJob(jobId: string): { Vehicle }
	local out = {}
	for _, v in list do
		if v.category == "Job" and v.job == jobId then
			table.insert(out, v)
		end
	end
	table.sort(out, function(a, b)
		if (a.xp or 0) ~= (b.xp or 0) then
			return (a.xp or 0) < (b.xp or 0)
		end
		if (a.car == nil) ~= (b.car == nil) then
			return a.car == nil -- the bike first
		end
		return a.id < b.id
	end)
	return out
end

function Vehicles.ByCategory(category: string): { Vehicle }
	local out = {}
	for _, v in list do
		if v.category == category then
			table.insert(out, v)
		end
	end
	return out
end

-- "322 km/h · 1020 PS" (empty when unknown)
function Vehicles.Stats(v: Vehicle): string
	if not v.speed or v.speed <= 0 then
		return ""
	end
	return v.speed .. " km/h" .. (if v.power then " · " .. v.power .. " PS" else "")
end

return Vehicles
