--!strict
-- Central game configuration. Safe to read from both server and client:
-- nothing in here is secret, and the server never trusts the client's copy.

local Config = {}

Config.GameName = "Emergency Dortmund"
Config.Version = "0.1.0"

-- GAME ADMINS (whole game). Put Roblox UserIds here.
-- The experience owner (or group owner) is ALWAYS a Game Admin automatically.
Config.GameAdmins = {
	10396317047, -- game owner
	8912131297, -- deniney26548
}

-- Special Game Admin phone. Only Game Admins can own / equip it.
Config.AdminPhoneId = "nvdr_p1"

-- ChatsApp number that delivers messages to every Game Admin (online + inbox).
Config.AdminChatNumber = "23646"

-- Emergency numbers -> jobs that receive the call.
Config.EmergencyNumbers = {
	["110"] = { "Police" },
	["112"] = { "Fire", "Rettungsdienst", "Notarzt" },
}

-- Economy
Config.StartingBank = 2500
Config.PaycheckInterval = 600 -- seconds between paychecks
Config.MaxTransfer = 1000000
Config.FuelPricePerLiter = 1.79

-- Vehicles
Config.MaxSpawnedVehicles = 1 -- personal + job vehicles per player at once
Config.StudsPerMeter = 1 / 0.28 -- Roblox convention used for speedometers
Config.DefaultCityCode = "DO"

-- Gamepass IDs. Create them on create.roblox.com -> your experience -> Monetization -> Passes,
-- then paste the IDs here. 0 = not created yet (pack is locked for everyone except Game Admins).
Config.Gamepasses = {
	Electric = 0,
	Hypercar = 0,
	Offroad = 0,
	Luxury = 0,
	Classic = 0,
}
Config.GamepassRobux = {
	Electric = 299,
	Hypercar = 799,
	Offroad = 249,
	Luxury = 399,
	Classic = 199,
}

-- Audio asset IDs (0 = none yet). Uploaded later via Open Cloud.
Config.Sounds = {
	Martinshorn = 0,
	NvdrBoot = 0,
	Ringtone = 0,
	Notification = 0,
}

-- Emergency calls
Config.CallCooldown = 120 -- seconds a caller must wait between calls
Config.CallArriveDistance = 40 -- studs from the caller's location to complete a call
Config.CallMinTravel = 120 -- responder must have been this far away when accepting
Config.CallXP = 50
Config.CallBonus = 150 -- € bonus for completing a call

-- World
Config.DayLengthMinutes = 48 -- real minutes per in-game day

-- DataStores (change the suffix to wipe all data)
Config.DataStoreName = "DortmundRP_Players_v1"

return Config
