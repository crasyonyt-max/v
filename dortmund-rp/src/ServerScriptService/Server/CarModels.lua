--!strict
-- Which catalog vehicles use a cleaned Creator Store body (see ServerStorage.ToolboxCars),
-- and the real-world length (m) the body is scaled to. Height and width follow the model's
-- own proportions, so a hypercar always stays lower than a van.
-- Vehicles not listed here use the generated bodies (VehicleBuilder).

local SANDERO = 12765708197
local HATCH = 1268658815
local SEDAN = 16536903413
local ESTATE = 9809341494
local SUV = 117276253886376
local SUV_L = 18169494881
local OFFROAD = 18171159918
local COUPE = 4872481462
local HYPER_A = 14484304958
local HYPER_B = 17057409668
local HYPER_C = 16641418932
local SPORTS = 1327624473
local FIRE_LF = 6173263330
local LIMO = 5233465872
local CLASSIC = 16100723406
local PICKUP = 3499202310

return {
	-- small hatchbacks
	dakia_sanderro = { SANDERO, 4.07 },
	kio_pikanto = { SANDERO, 3.60 },
	opal_korsa = { SANDERO, 4.06 },
	opal_korsa_c = { SANDERO, 3.84 },
	fort_fiesto = { SANDERO, 3.95 },
	vk_pollo = { SANDERO, 4.05 },
	-- compact hatchbacks
	opal_astro = { HATCH, 4.37 },
	vk_golfo = { HATCH, 4.28 },
	vk_golfo_r = { HATCH, 4.29 },
	vk_golfo4 = { HATCH, 4.15 },
	audix_rx3 = { HATCH, 4.33 },
	-- sedans
	skora_octava = { SEDAN, 4.69 },
	tesra_model_tri = { SEDAN, 4.69 },
	bmv_3er = { SEDAN, 4.71 },
	mercator_c = { SEDAN, 4.75 },
	mercator_e = { SEDAN, 4.95 },
	amx_c63s = { SEDAN, 4.75 },
	tesra_model_es = { SEDAN, 5.02 },
	amx_eqs = { SEDAN, 5.22 },
	audix_etran = { SEDAN, 4.99 },
	porsha_taikan = { SEDAN, 4.96 },
	bmv_e30_m3 = { SEDAN, 4.35 },
	-- estates (police / NEF get their livery on top)
	pol_astro_kombi = { ESTATE, 4.70 },
	pol_golfo_variant = { ESTATE, 4.63 },
	pol_pasat_variant = { ESTATE, 4.77 },
	pol_3er_touring = { ESTATE, 4.71 },
	pol_5er_touring = { ESTATE, 4.96 },
	pol_rx6_zivil = { ESTATE, 4.94 },
	rd_nef = { ESTATE, 4.95 },
	na_octava = { ESTATE, 4.69 },
	na_5er = { ESTATE, 4.96 },
	-- SUVs
	vk_tiguar = { SUV, 4.51 },
	porsha_makan = { SUV, 4.73 },
	na_tiguar = { SUV, 4.51 },
	admc_x1 = { SUV, 4.50 },
	kupra_formentor_vz5 = { SUV, 4.45 },
	lambardini_uros = { SUV_L, 5.11 },
	royce_kullinan = { SUV_L, 5.34 },
	na_glx_lna = { SUV_L, 5.13 },
	rangerider_sv = { SUV_L, 5.25 },
	ashton_dbx = { SUV_L, 5.04 },
	-- off-roaders
	mercator_g = { OFFROAD, 4.82 },
	amx_g63 = { OFFROAD, 4.87 },
	toyara_kruiser = { OFFROAD, 4.99 },
	landrider_defendor = { OFFROAD, 5.36 },
	-- coupés / sports cars
	audix_a5 = { COUPE, 4.70 },
	opal_mantra = { COUPE, 4.40 },
	bmv_m4 = { COUPE, 4.79 },
	bmv_m3 = { SPORTS, 4.80 },
	porsha_elfer = { SPORTS, 4.52 },
	porsha_elfer73 = { SPORTS, 4.16 },
	brentley_kontinental = { SPORTS, 4.85 },
	porsha_kayman = { SPORTS, 4.45 },
	amx_gt_black = { SPORTS, 4.55 },
	-- hypercars (all around 1.2 m tall after scaling)
	koenigshaus_jesco = { HYPER_A, 4.61 },
	koenigshaus_one1 = { HYPER_A, 4.50 },
	bugarti_chiran = { HYPER_A, 4.54 },
	pagano_huayro = { HYPER_B, 4.60 },
	ferroni_sf90 = { HYPER_B, 4.71 },
	mclaurin_750s = { HYPER_B, 4.57 },
	lambardini_venino = { HYPER_C, 5.02 },
	rimax_neverra = { HYPER_C, 4.75 },
	amx_uno = { HYPER_C, 4.76 },
	-- luxury
	royce_fantom = { LIMO, 5.76 },
	maybeck_s = { LIMO, 5.47 },
	bmv_i7 = { LIMO, 5.39 },
	-- classics
	vk_kaefa = { CLASSIC, 4.10 },
	mercator_300sl = { CLASSIC, 4.50 },
	-- pickups
	fort_raptur = { PICKUP, 5.91 },
	-- fire brigade (model keeps its own German red / white livery)
	fw_lf10 = { FIRE_LF, 7.50 },
	fw_hlf20 = { FIRE_LF, 8.80 },
}
