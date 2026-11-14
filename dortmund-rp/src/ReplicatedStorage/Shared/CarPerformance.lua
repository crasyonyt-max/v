--!strict
-- Every car's own top speed (km/h) and power (PS). The body type (RealisticCars
-- Configs: Sedan, Supercar, Truck ...) still decides gearbox, weight and grip; the
-- power scales the engine's torque and the top speed is an electronic limiter.
-- Keyed by model name (VehicleConfig "Model", which defaults to the car's name).

local CarPerformance = {}

CarPerformance.Cars = {
	-- Autohaus
	["Dakia Sanderro"] = { 175, 90 },
	["Kio Pikanto"] = { 160, 67 },
	["Opal Korsa"] = { 190, 100 },
	["Volkswerk Pollo"] = { 187, 95 },
	["Opal Astro"] = { 210, 130 },
	["Volkswerk Golfo"] = { 215, 150 },
	["Skora Octava"] = { 220, 150 },
	["Volkswerk Tiguar"] = { 205, 150 },
	["Tesra Model Tri"] = { 225, 325 },
	["Audix A5"] = { 240, 204 },
	["BMV 3er"] = { 250, 184 },
	["Mercator C-Klasse"] = { 246, 204 },
	["Volkswerk Golfo R"] = { 250, 320 },
	["Mercator E-Klasse"] = { 250, 258 },
	["Porsha Makan"] = { 232, 265 },
	["BMV M3"] = { 290, 510 },
	["Porsha Elfer Carrera"] = { 293, 385 },
	["Mercator G-Klasse"] = { 210, 330 },
	["Lambardini Uros"] = { 305, 650 },
	["Royce-Rolland Kullinan"] = { 250, 571 },
	-- free starter cars
	["Volkswerk Golfo IV"] = { 185, 100 },
	["Opal Korsa C"] = { 170, 75 },
	["Fort Fiesto"] = { 180, 85 },
	-- Electric pack
	["Tesra Model Es Plaid"] = { 322, 1020 },
	["Porsha Taikan Turbo S"] = { 260, 761 },
	["BMV i7"] = { 240, 544 },
	["Mercator-AMX EQS"] = { 250, 658 },
	["Audix RX e-tran GT"] = { 250, 646 },
	-- Hypercar pack
	["Bugarti Chiran"] = { 420, 1500 },
	["Koenigshaus Jesco"] = { 440, 1600 },
	["Pagano Huayro"] = { 383, 730 },
	["Mercator-AMX Uno"] = { 352, 1063 },
	["Rimax Neverra"] = { 412, 1914 },
	-- Offroad pack
	["Mercator-AMX G 63"] = { 220, 585 },
	["Fort F-150 Raptur"] = { 180, 450 },
	["Land Rider Defendor 130"] = { 191, 400 },
	["Toyara Land Kruiser"] = { 175, 309 },
	["Mercator Unimug"] = { 90, 231 },
	-- Luxury pack
	["Royce-Rolland Fantom"] = { 250, 571 },
	["Brentley Kontinental GT"] = { 335, 659 },
	["Mercator-Maybeck S-Klasse"] = { 250, 612 },
	["Range Rider SV"] = { 250, 615 },
	["Ashton Marlin DBX"] = { 291, 550 },
	-- Classic pack
	["Volkswerk Käfa"] = { 115, 34 },
	["Mercator 300 SL Flügeltürer"] = { 260, 215 },
	["Porsha Elfer 1973"] = { 230, 190 },
	["BMV E30 M3"] = { 235, 200 },
	["Opal Mantra"] = { 190, 110 },
	-- admin cars
	["Kupra Formentor VZ5"] = { 250, 390 },
	["Audix RX3 Sportback"] = { 250, 400 },
	["Mercator-AMX C 63 S"] = { 280, 510 },
	["BMV M4 Kompetition"] = { 290, 530 },
	["Porsha 718 Kayman GT4 RS"] = { 315, 500 },
	["Mercator-AMX GT Black Series"] = { 325, 730 },
	["McLaurin 750S"] = { 332, 750 },
	["Ferroni SF90 Stradale"] = { 340, 1000 },
	["Lambardini Venino"] = { 355, 750 },
	["Koenigshaus One:1"] = { 440, 1360 },
	-- Polizei
	["Opal Astro Kombi"] = { 200, 130 },
	["Volkswerk Golfo Variant"] = { 210, 150 },
	["Volkswerk Turan"] = { 200, 150 },
	["Fort S-Maxx"] = { 205, 190 },
	["Mercator Vitto"] = { 190, 190 },
	["Volkswerk Pasat Variant"] = { 230, 200 },
	["BMV 3er Touring"] = { 250, 258 },
	["Mercator Sprintor"] = { 160, 190 },
	["BMV 5er Touring"] = { 250, 340 },
	["Audix RX6 Avant"] = { 280, 600 },
	-- Feuerwehr
	["LF 10 Mercator Ategon"] = { 110, 290 },
	["ELW 1 Mercator Sprintor"] = { 160, 190 },
	["HLF 20 MAR TGM"] = { 105, 290 },
	["DLK 23/12 Mercator Econ"] = { 100, 300 },
	["FLF Rosenbach Panter"] = { 135, 1400 },
	-- Rettungsdienst / Notarzt
	["KTW Volkswerk Transporta"] = { 160, 150 },
	["NEF Mercator E-Klasse T"] = { 250, 258 },
	["RTW Mercator Sprintor"] = { 150, 190 },
	["GRTW MAR TGM"] = { 100, 290 },
	["ITW Mercator Sprintor XL"] = { 145, 190 },
	["Skora Octava Kombi"] = { 230, 190 },
	["Mercator GLX"] = { 250, 367 },
	-- ADMC
	["Mercator Sprintor Service Van"] = { 160, 150 },
	["Volkswerk Kaddy"] = { 175, 122 },
	["BMV 2er Active Tourer"] = { 220, 178 },
	["BMV X1"] = { 225, 204 },
	["Volkswerk Transporta"] = { 180, 150 },
	["Mercator Sprintor Tow Truck"] = { 140, 190 },
	["MAR TGL Tow Truck"] = { 100, 250 },
	["Mercator Arokos Heavy Recovery"] = { 90, 530 },
	-- DXL
	["StreetRoller E-Van"] = { 85, 68 },
	["Mercator eSprintor"] = { 120, 204 },
	["Volkswerk Krafter"] = { 160, 177 },
	["MAR TGE"] = { 160, 177 },
	-- LKW
	["MAR TGL 7.5t"] = { 90, 250 },
	["Mercator Atekon"] = { 90, 300 },
	["MAR TGX"] = { 90, 510 },
	["Mercator Aktros"] = { 90, 530 },
	["Skandia R"] = { 90, 650 },
	["Volvar FH16"] = { 90, 750 },
	-- Bus
	["Mercator Sitaro"] = { 80, 354 },
	["MAR Lion's Stadt"] = { 80, 360 },
	["Solaria Urbano Elektro"] = { 80, 340 },
	["Mercator Sitaro G"] = { 80, 394 },
} :: { [string]: { number } }

-- top speed (km/h), power (PS) or nil for a car that is not listed
function CarPerformance.Get(model: string): (number?, number?)
	local row = CarPerformance.Cars[model]
	if not row then
		return nil, nil
	end
	return row[1], row[2]
end

return CarPerformance
