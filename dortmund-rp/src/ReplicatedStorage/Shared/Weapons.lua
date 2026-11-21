--!strict
-- V1.0 weapons. Police on duty carry the service pistol; civilians can buy a pistol
-- at the black market (Schwarzmarkt). Shooting is checked by the server.

local Weapons = {}

export type Weapon = {
	id: string,
	name: string,
	damage: number,
	rate: number, -- seconds between shots
	mag: number,
	reload: number, -- seconds
	range: number, -- studs
}

Weapons.List = {
	{ id = "service_pistol", name = "Dienstpistole P99", damage = 25, rate = 0.3, mag = 15, reload = 1.8, range = 320 },
	{ id = "pistol", name = "Pistole", damage = 20, rate = 0.4, mag = 12, reload = 2.2, range = 260 },
} :: { Weapon }

Weapons.ById = {} :: { [string]: Weapon }
for _, w in Weapons.List do
	Weapons.ById[w.id] = w
end

return Weapons
