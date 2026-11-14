--!strict
-- Central game configuration. Safe to read from both server and client:
-- nothing in here is secret, and the server never trusts the client's copy.

local Config = {}

Config.GameName = "Emergency Dortmund"
Config.Version = "0.1.0"

-- OWNER: the highest rank. Nobody can kick or ban the owner.
Config.OwnerId = 10396317047

-- CO-OWNERS: everything a Game Admin can do, and they outrank Game Admins
-- (they can ban everyone except the owner; only the owner can ban them).
Config.CoOwners = {
	3559943151, -- samder_nervt
}

-- SECOND CO-OWNERS: under the Co-Owners, over the Game Admins (Game Admin powers,
-- can ban Game Admins and everyone below; no AA tab).
Config.SecondCoOwners = {
	2851688688, -- pommes5123
}

-- Background music, 24/7 on every server, one song after the other (all in sync).
-- `length` in seconds. The AA music plays instead while it runs; the AA tab can
-- pause this playlist. Roblox music library tracks (allowed in every game).
Config.DefaultMusic = {
	{ id = 9043887091, length = 137, name = "Lo-fi Chill A" },
	{ id = 1848354536, length = 97, name = "Relaxed Scene" },
}
Config.DefaultMusicVolume = 0.2 -- 0..1 (20 %)

-- AA tab for these Game Admins too (the Owner and the Co-Owners always have it)
Config.AAExtra = {}

-- GAME ADMINS (whole game). Put Roblox UserIds here.
-- The experience owner (or group owner) is ALWAYS a Game Admin automatically.
Config.GameAdmins = {
	10396317047, -- game owner
	8912131297, -- deniney26548
	3482982410, -- 0312benni
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

-- Dropper tycoon in the apartment (10 max). Cost to buy dropper i, and what it drops
-- every Config.DropInterval seconds (nerfed twice: 50-80 %, then another 80 %).
Config.DropperCosts = { 0, 1000, 3000, 10000, 100000, 200000, 400000, 800000, 1600000, 3200000 }
Config.DropperDrops = { 50, 90, 260, 800, 1500, 2400, 3000, 3500, 3800, 4000 }
Config.DropInterval = 1

-- Vehicles
Config.MaxSpawnedVehicles = 1 -- personal + job vehicles per player at once
Config.StudsPerMeter = 1 / 0.28 -- Roblox convention used for speedometers
Config.DefaultCityCode = "DO"
Config.BusFare = 5 -- € per bus ride (passenger -> bus driver)

-- Gamepass IDs. Create them on create.roblox.com -> your experience -> Monetization -> Passes,
-- then paste the IDs here. 0 = not created yet (pack is locked for everyone except Game Admins).
Config.Gamepasses = {
	Electric = 2089197396,
	Hypercar = 2089095344,
	Offroad = 2088795357,
	Luxury = 2089425357,
	Classic = 2089389319,
}
-- Money for Robux, can be bought again and again: Developer Products
-- (create.roblox.com -> your experience -> Monetization -> Developer Products).
-- id = the product id (0 = not created yet, not shown), cash = € the player gets,
-- robux = shown until Roblox reports the real price.
Config.MoneyProducts = {
	{ id = 3731400455, cash = 18000, robux = 199 },
	{ id = 3731400781, cash = 50000, robux = 299 },
	{ id = 3731401194, cash = 67911, robux = 399 },
	{ id = 3731402264, cash = 72000, robux = 432 },
	{ id = 3731402761, cash = 100000, robux = 572 },
	{ id = 3731404147, cash = 200000, robux = 1000 },
	{ id = 3731404504, cash = 500000, robux = 2000 },
	{ id = 3731407305, cash = 1000000, robux = 3723 },
	{ id = 3731407695, cash = 3000000, robux = 5723 },
	{ id = 3731408497, cash = 5000000, robux = 7273 },
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
