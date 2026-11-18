--!strict
-- Certificates shown on the digital ID (Personalausweis). Game Admins give them in
-- the admin app ("ID" tab); `owner = true` ones only the Owner may give or take away.
-- W4 bans the player automatically; kicks / bans add the "previously" ones.

local Certificates = {}

export type Cert = { code: string, name: string, owner: boolean, kind: string, color: Color3 }

local GOLD = Color3.fromRGB(212, 160, 40)
local BLUE = Color3.fromRGB(30, 110, 210)
local PURPLE = Color3.fromRGB(140, 60, 200)
local RED = Color3.fromRGB(200, 40, 40)
local ORANGE = Color3.fromRGB(230, 120, 20)
local GREY = Color3.fromRGB(110, 110, 120)

Certificates.List = {
	{ code = "VAT8388NDO", name = "Official Trusted Admin", owner = false, kind = "trust", color = BLUE },
	{ code = "VOTR289DO9F", name = "Official Trusted Owner Rank", owner = true, kind = "trust", color = GOLD },
	{ code = "VIPR8D79OAC2", name = "Official Admin Certified VIP", owner = false, kind = "vip", color = PURPLE },
	{ code = "VIPRE77OOC2", name = "Official Owner Certified VIP", owner = true, kind = "vip", color = GOLD },
	{
		code = "OCC2ED8TRCC",
		name = "Emergency Dortmund Content Creator",
		owner = false,
		kind = "creator",
		color = Color3.fromRGB(230, 40, 120),
	},
	{ code = "F9SK88I2L9PWS", name = "Admin Flagged Player", owner = false, kind = "flag", color = ORANGE },
	{ code = "F78W72L8D9LE", name = "Owner Flagged Player", owner = true, kind = "flag", color = RED },
	{ code = "W77WJP827E", name = "Wanted by ED Team", owner = false, kind = "flag", color = RED },
	{ code = "PBPSN8S7W72", name = "Previously Banned Player", owner = false, kind = "record", color = GREY },
	{ code = "PKP27SK8WI2O", name = "Previously Kicked Player", owner = false, kind = "record", color = GREY },
	{ code = "W1", name = "First warning", owner = false, kind = "warn", color = Color3.fromRGB(240, 200, 30) },
	{ code = "W2", name = "Second warning", owner = false, kind = "warn", color = ORANGE },
	{ code = "W3", name = "Third warning", owner = false, kind = "warn", color = RED },
	{
		code = "W4",
		name = "Automatically banned player due to warnings",
		owner = false,
		kind = "warn",
		color = Color3.fromRGB(120, 0, 0),
	},
} :: { Cert }

Certificates.ByCode = {} :: { [string]: Cert }
for _, c in Certificates.List do
	Certificates.ByCode[c.code] = c
end

Certificates.BANNED = "PBPSN8S7W72"
Certificates.KICKED = "PKP27SK8WI2O"
Certificates.WARN_BAN = "W4"

-- ID number like a German Personalausweis (9 characters, no vowels), always the
-- same for one player
local ALPHABET = "CFGHJKLMNPRTVWXYZ0123456789"
function Certificates.IdNumber(userId: number): string
	local x = (userId * 2654435761 + 97) % 4294967296
	local out = { "L" }
	for _ = 1, 8 do
		local i = x % #ALPHABET + 1
		table.insert(out, ALPHABET:sub(i, i))
		x = (x // #ALPHABET) * 31 + 7 + userId % 13
		x %= 4294967296
	end
	return table.concat(out)
end

return Certificates
