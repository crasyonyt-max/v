--!strict
-- Vehicle catalog. All names are parody names (no real brands).
-- `id` values are saved in player data: never rename an existing id.
--
-- category: "Dealer" | "Starter" | "Job" | "Pack" | "Admin"
-- body: shape used by the procedural VehicleBuilder (see VehicleBuilder.BodyTypes)
-- speed: top speed in km/h, accel: 0-100 feel (1 = slow, 3 = very fast)

export type Vehicle = {
	id: string,
	name: string,
	category: string,
	price: number,
	body: string,
	speed: number,
	accel: number,
	color: Color3,
	job: string?,
	xp: number?,
	pack: string?,
	adminLevel: string?, -- "Server" | "Game"
	emergency: boolean?,
	livery: string?, -- "Police" | "Fire" | "Rescue" | "ADMC" | "DXL"
	tow: boolean?,
	note: string?,
}

local Vehicles = {}
local list: { Vehicle } = {}

local function add(v: Vehicle)
	table.insert(list, v)
end

local WHITE = Color3.fromRGB(235, 235, 235)
local SILVER = Color3.fromRGB(170, 172, 175)
local BLACK = Color3.fromRGB(25, 25, 28)
local RED = Color3.fromRGB(180, 20, 20)
local BLUE = Color3.fromRGB(30, 60, 140)
local YELLOW = Color3.fromRGB(250, 205, 0)
local GREY = Color3.fromRGB(90, 92, 96)

local function dealer(
	id: string,
	name: string,
	price: number,
	body: string,
	speed: number,
	accel: number,
	color: Color3
)
	add({
		id = id,
		name = name,
		category = "Dealer",
		price = price,
		body = body,
		speed = speed,
		accel = accel,
		color = color,
	})
end

-- 4. CAR DEALERSHIP --------------------------------------------------------
dealer("dakia_sanderro", "Dakia Sanderro", 13000, "hatch", 175, 1.0, Color3.fromRGB(200, 120, 40))
dealer("kio_pikanto", "Kio Pikanto", 15000, "hatch_small", 165, 1.0, Color3.fromRGB(200, 30, 60))
dealer("opal_korsa", "Opal Korsa", 20000, "hatch", 190, 1.2, YELLOW)
dealer("vk_pollo", "Volkswerk Pollo", 21000, "hatch", 195, 1.2, BLUE)
dealer("opal_astro", "Opal Astro", 28000, "hatch", 210, 1.4, SILVER)
dealer("vk_golfo", "Volkswerk Golfo", 30000, "hatch", 215, 1.5, WHITE)
dealer("skora_octava", "Skora Octava", 32000, "sedan", 220, 1.5, Color3.fromRGB(40, 110, 70))
dealer("vk_tiguar", "Volkswerk Tiguar", 40000, "suv", 210, 1.5, GREY)
dealer("tesra_model_tri", "Tesra Model Tri", 40000, "sedan", 225, 2.2, WHITE)
dealer("audix_a5", "Audix A5", 47000, "coupe", 240, 1.8, BLACK)
dealer("bmv_3er", "BMV 3er", 48000, "sedan", 240, 1.8, BLUE)
dealer("mercator_c", "Mercator C-Klasse", 50000, "sedan", 245, 1.8, SILVER)
dealer("vk_golfo_r", "Volkswerk Golfo R", 55000, "hatch", 270, 2.3, Color3.fromRGB(30, 80, 200))
dealer("mercator_e", "Mercator E-Klasse", 60000, "sedan_long", 250, 1.9, BLACK)
dealer("porsha_makan", "Porsha Makan", 84000, "suv", 260, 2.2, RED)
dealer("bmv_m3", "BMV M3", 95000, "sedan", 290, 2.6, Color3.fromRGB(60, 170, 60))
dealer("porsha_elfer", "Porsha Elfer Carrera", 130000, "coupe_sport", 300, 2.7, YELLOW)
dealer("mercator_g", "Mercator G-Klasse", 135000, "offroad", 210, 1.8, BLACK)
dealer("lambardini_uros", "Lambardini Uros", 250000, "suv", 305, 2.8, Color3.fromRGB(240, 140, 0))
dealer("royce_kullinan", "Royce-Rolland Kullinan", 380000, "suv_long", 250, 1.9, Color3.fromRGB(40, 30, 60))

-- STARTER CARS (choose 1 free) ---------------------------------------------
add({
	id = "vk_golfo4",
	name = "Volkswerk Golfo IV (2002)",
	category = "Starter",
	price = 0,
	body = "hatch",
	speed = 185,
	accel = 1.1,
	color = SILVER,
})
add({
	id = "opal_korsa_c",
	name = "Opal Korsa C (2004)",
	category = "Starter",
	price = 0,
	body = "hatch_small",
	speed = 170,
	accel = 1.0,
	color = Color3.fromRGB(150, 20, 30),
})
add({
	id = "fort_fiesto",
	name = "Fort Fiesto (2008)",
	category = "Starter",
	price = 0,
	body = "hatch_small",
	speed = 175,
	accel = 1.0,
	color = Color3.fromRGB(30, 100, 180),
})

-- 5. JOB VEHICLES (unlocked by job XP, free to spawn) ----------------------
local function job(
	jobId: string,
	id: string,
	name: string,
	xp: number,
	body: string,
	speed: number,
	livery: string,
	emergency: boolean,
	extra: { [string]: any }?
)
	local v: Vehicle = {
		id = id,
		name = name,
		category = "Job",
		price = 0,
		body = body,
		speed = speed,
		accel = 1.5,
		color = WHITE,
		job = jobId,
		xp = xp,
		livery = livery,
		emergency = emergency,
	}
	if extra then
		for k, val in extra do
			(v :: any)[k] = val
		end
	end
	add(v)
end

-- Police
job("Police", "pol_astro_kombi", "Opal Astro Kombi", 0, "kombi", 200, "Police", true)
job("Police", "pol_golfo_variant", "Volkswerk Golfo Variant", 250, "kombi", 210, "Police", true)
job("Police", "pol_turan", "Volkswerk Turan", 500, "mpv", 200, "Police", true)
job("Police", "pol_smaxx", "Fort S-Maxx", 1000, "mpv", 210, "Police", true)
job("Police", "pol_vitto", "Mercator Vitto", 2000, "van", 190, "Police", true)
job("Police", "pol_pasat_variant", "Volkswerk Pasat Variant", 3500, "kombi_long", 230, "Police", true)
job("Police", "pol_3er_touring", "BMV 3er Touring", 5000, "kombi", 240, "Police", true)
job("Police", "pol_sprintor_riot", "Mercator Sprintor (Gruppenwagen)", 7500, "bigvan", 160, "Police", true)
job("Police", "pol_5er_touring", "BMV 5er Touring (Autobahn)", 10000, "kombi_long", 260, "Police", true)
job(
	"Police",
	"pol_rx6_zivil",
	"Audix RX6 Avant (Zivil)",
	15000,
	"kombi_long",
	280,
	"Police",
	true,
	{ livery = "Unmarked", color = Color3.fromRGB(40, 45, 55), accel = 2.6 }
)

-- Fire
job("Fire", "fw_lf10", "LF 10 Mercator Ategon", 0, "truck", 110, "Fire", true, { color = RED })
job("Fire", "fw_elw1", "ELW 1 Mercator Sprintor", 1000, "bigvan", 160, "Fire", true, { color = RED })
job("Fire", "fw_hlf20", "HLF 20 MAR TGM", 2500, "truck", 105, "Fire", true, { color = RED })
job("Fire", "fw_dlk", "DLK 23/12 Mercator Econ", 5000, "truck_ladder", 100, "Fire", true, { color = RED })
job("Fire", "fw_flf_panter", "FLF Rosenbach Panter", 10000, "truck_airport", 120, "Fire", true, { color = RED })

-- Rettungsdienst (DRH)
job("Rettungsdienst", "rd_ktw", "KTW Volkswerk Transporta", 0, "van", 170, "Rescue", true)
job("Rettungsdienst", "rd_nef", "NEF Mercator E-Klasse T", 1000, "kombi_long", 240, "Rescue", true)
job("Rettungsdienst", "rd_rtw", "RTW Mercator Sprintor", 2500, "rtw", 150, "Rescue", true)
job("Rettungsdienst", "rd_grtw", "GRTW MAR TGM", 5000, "truck_box", 110, "Rescue", true)
job("Rettungsdienst", "rd_itw", "ITW Mercator Sprintor XL", 10000, "rtw", 145, "Rescue", true)

-- Notarzt (NEF)
job("Notarzt", "na_octava", "Skora Octava Kombi", 0, "kombi", 220, "Rescue", true)
job("Notarzt", "na_tiguar", "Volkswerk Tiguar", 1000, "suv", 210, "Rescue", true)
job("Notarzt", "na_vitto", "Mercator Vitto", 2500, "van", 190, "Rescue", true)
job("Notarzt", "na_5er", "BMV 5er Touring", 5000, "kombi_long", 250, "Rescue", true)
job("Notarzt", "na_glx_lna", 'Mercator GLX "Leitender Notarzt"', 10000, "suv_long", 240, "Rescue", true)

-- Roadside Assistance (ADMC)
job("ADMC", "admc_sprintor", "Mercator Sprintor Servicewagen", 0, "bigvan", 160, "ADMC", false, { color = YELLOW })
job("ADMC", "admc_kaddy", "Volkswerk Kaddy", 0, "van_small", 180, "ADMC", false, { color = YELLOW })
job("ADMC", "admc_turan", "Volkswerk Turan", 500, "mpv", 200, "ADMC", false, { color = YELLOW })
job("ADMC", "admc_2er_at", "BMV 2er Active Tourer", 1000, "mpv", 210, "ADMC", false, { color = YELLOW })
job("ADMC", "admc_x1", "BMV X1", 2000, "suv", 215, "ADMC", false, { color = YELLOW })
job("ADMC", "admc_transporta", "Volkswerk Transporta", 3500, "van", 175, "ADMC", false, { color = YELLOW })
job(
	"ADMC",
	"admc_sprintor_tow",
	"Mercator Sprintor Abschlepper",
	5000,
	"tow_small",
	150,
	"ADMC",
	false,
	{ color = YELLOW, tow = true }
)
job("ADMC", "admc_tgl_tow", "MAR TGL Abschlepper", 7500, "tow", 120, "ADMC", false, { color = YELLOW, tow = true })
job(
	"ADMC",
	"admc_arokos",
	"Mercator Arokos Bergefahrzeug",
	12000,
	"tow_heavy",
	100,
	"ADMC",
	false,
	{ color = YELLOW, tow = true }
)

-- Parcel Delivery (DXL)
job("DXL", "dxl_streetroller", "StreetRoller E-Van", 0, "van_small", 90, "DXL", false, { color = YELLOW })
job("DXL", "dxl_kaddy", "Volkswerk Kaddy", 500, "van_small", 170, "DXL", false, { color = YELLOW })
job("DXL", "dxl_esprintor", "Mercator eSprintor", 1500, "bigvan", 130, "DXL", false, { color = YELLOW })
job("DXL", "dxl_krafter", "Volkswerk Krafter", 3000, "bigvan", 150, "DXL", false, { color = YELLOW })
job("DXL", "dxl_tge", "MAR TGE Kastenwagen", 6000, "bigvan", 150, "DXL", false, { color = YELLOW })

-- Truck Driver (LKW)
job("LKW", "lkw_tgl", "MAR TGL 7,5t", 0, "truck_box", 100, "None", false, { color = WHITE })
job("LKW", "lkw_atekon", "Mercator Atekon", 1500, "truck_box", 100, "None", false, { color = SILVER })
job("LKW", "lkw_tgx", "MAR TGX Sattelzug", 5000, "semi", 90, "None", false, { color = WHITE })
job("LKW", "lkw_aktros", "Mercator Aktros Sattelzug", 10000, "semi", 90, "None", false, { color = BLACK })
job("LKW", "lkw_skandia_r", "Skandia R Sattelzug", 15000, "semi", 90, "None", false, { color = RED })
job("LKW", "lkw_volvar_fh16", "Volvar FH16 Schwerlast", 25000, "semi", 90, "None", false, { color = BLUE })

-- 6. GAMEPASS PACKS (Robux unlock + in-game price) -------------------------
local function pack(
	packId: string,
	id: string,
	name: string,
	price: number,
	body: string,
	speed: number,
	accel: number,
	color: Color3
)
	add({
		id = id,
		name = name,
		category = "Pack",
		pack = packId,
		price = price,
		body = body,
		speed = speed,
		accel = accel,
		color = color,
	})
end

pack("Electric", "tesra_model_es", "Tesra Model Es Plaid", 110000, "sedan_long", 320, 3.0, RED)
pack(
	"Electric",
	"porsha_taikan",
	"Porsha Taikan Turbo S",
	200000,
	"sedan_sport",
	260,
	3.0,
	Color3.fromRGB(120, 160, 190)
)
pack("Electric", "bmv_i7", "BMV i7", 115000, "sedan_long", 240, 2.2, BLACK)
pack("Electric", "amx_eqs", "Mercator-AMX EQS", 160000, "sedan_long", 250, 2.6, SILVER)
pack("Electric", "audix_etran", "Audix RX e-tran GT", 150000, "sedan_sport", 250, 2.8, GREY)

pack("Hypercar", "bugarti_chiran", "Bugarti Chiran", 3000000, "super", 420, 3.0, BLUE)
pack("Hypercar", "koenigshaus_jesco", "Koenigshaus Jesco", 3000000, "super", 430, 3.0, WHITE)
pack("Hypercar", "pagano_huayro", "Pagano Huayro", 3000000, "super", 380, 2.9, Color3.fromRGB(200, 150, 40))
pack("Hypercar", "amx_uno", "Mercator-AMX Uno", 2700000, "super", 350, 2.9, SILVER)
pack("Hypercar", "rimax_neverra", "Rimax Neverra", 2200000, "super", 410, 3.0, Color3.fromRGB(20, 120, 120))

pack("Offroad", "amx_g63", "Mercator-AMX G 63", 200000, "offroad", 240, 2.3, BLACK)
pack("Offroad", "fort_raptur", "Fort F-150 Raptur", 90000, "pickup", 180, 1.9, Color3.fromRGB(70, 80, 90))
pack(
	"Offroad",
	"landrider_defendor",
	"Land Rider Defendor 130",
	80000,
	"offroad_long",
	190,
	1.6,
	Color3.fromRGB(110, 120, 90)
)
pack("Offroad", "toyara_kruiser", "Toyara Land Kruiser", 75000, "offroad", 175, 1.5, WHITE)
pack("Offroad", "mercator_unimug", "Mercator Unimug", 250000, "unimug", 90, 1.2, Color3.fromRGB(230, 120, 0))

pack("Luxury", "royce_fantom", "Royce-Rolland Fantom", 500000, "sedan_xl", 250, 1.9, Color3.fromRGB(20, 20, 40))
pack(
	"Luxury",
	"brentley_kontinental",
	"Brentley Kontinental GT",
	250000,
	"coupe_sport",
	330,
	2.5,
	Color3.fromRGB(30, 70, 50)
)
pack("Luxury", "maybeck_s", "Mercator-Maybeck S-Klasse", 220000, "sedan_xl", 250, 2.0, SILVER)
pack("Luxury", "rangerider_sv", "Range Rider SV", 250000, "suv_long", 260, 2.1, WHITE)
pack("Luxury", "ashton_dbx", "Ashton Marlin DBX", 230000, "suv", 290, 2.4, Color3.fromRGB(60, 70, 80))

pack("Classic", "vk_kaefa", "Volkswerk Käfa", 15000, "beetle", 115, 0.6, Color3.fromRGB(110, 170, 200))
pack("Classic", "mercator_300sl", "Mercator 300 SL Flügeltürer", 1500000, "coupe_sport", 250, 1.4, SILVER)
pack("Classic", "porsha_elfer73", "Porsha Elfer 1973", 150000, "coupe_sport", 240, 1.6, Color3.fromRGB(230, 120, 20))
pack("Classic", "bmv_e30_m3", "BMV E30 M3", 100000, "sedan", 235, 1.7, RED)
pack("Classic", "opal_mantra", "Opal Mantra", 20000, "coupe", 190, 1.1, YELLOW)

-- 7. ADMIN CARS (spawn only, never sold) -----------------------------------
local function admin(level: string, id: string, name: string, body: string, speed: number, color: Color3)
	add({
		id = id,
		name = name,
		category = "Admin",
		adminLevel = level,
		livery = "Admin",
		price = 0,
		body = body,
		speed = speed,
		accel = 2.8,
		color = color,
	})
end

admin("Server", "kupra_formentor_vz5", "Kupra Formentor VZ5", "suv", 250, Color3.fromRGB(80, 90, 100))
admin("Server", "audix_rx3", "Audix RX3 Sportback", "hatch", 290, Color3.fromRGB(30, 110, 60))
admin("Server", "amx_c63s", "Mercator-AMX C 63 S", "sedan", 290, BLACK)
admin("Server", "bmv_m4", "BMV M4 Kompetition", "coupe_sport", 290, Color3.fromRGB(0, 140, 200))
admin("Server", "porsha_kayman", "Porsha 718 Kayman GT4 RS", "coupe_sport", 315, Color3.fromRGB(230, 230, 230))

admin("Game", "amx_gt_black", "Mercator-AMX GT Black Series", "coupe_sport", 325, Color3.fromRGB(240, 120, 0))
admin("Game", "mclaurin_750s", "McLaurin 750S", "super", 332, Color3.fromRGB(255, 120, 0))
admin("Game", "ferroni_sf90", "Ferroni SF90 Stradale", "super", 340, RED)
admin("Game", "lambardini_venino", "Lambardini Venino", "super", 355, Color3.fromRGB(40, 200, 60))
admin("Game", "koenigshaus_one1", "Koenigshaus One:1", "super", 440, Color3.fromRGB(10, 10, 12))

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

Vehicles.StarterIds = { "vk_golfo4", "opal_korsa_c", "fort_fiesto" }
Vehicles.PackOrder = { "Electric", "Hypercar", "Offroad", "Luxury", "Classic" }

function Vehicles.ForJob(jobId: string): { Vehicle }
	local out = {}
	for _, v in list do
		if v.category == "Job" and v.job == jobId then
			table.insert(out, v)
		end
	end
	table.sort(out, function(a, b)
		return (a.xp or 0) < (b.xp or 0)
	end)
	return out
end

function Vehicles.ByCategory(category: string, pack: string?): { Vehicle }
	local out = {}
	for _, v in list do
		if v.category == category and (pack == nil or v.pack == pack) then
			table.insert(out, v)
		end
	end
	return out
end

return Vehicles
