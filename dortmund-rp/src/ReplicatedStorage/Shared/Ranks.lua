--!strict
-- Update 2: job ranks from the job's XP. Every rank above the first adds 5 % to the
-- paycheck. Police and fire use real German ranks, the other jobs general ones.

local Ranks = {}

Ranks.XP = { 0, 1000, 3000, 7000, 15000, 30000 }
Ranks.BONUS = 0.05 -- paycheck bonus per rank above the first

local NAMES: { [string]: { string } } = {
	Police = {
		"Polizeimeisteranwärter",
		"Polizeimeister",
		"Polizeiobermeister",
		"Polizeikommissar",
		"Polizeioberkommissar",
		"Polizeihauptkommissar",
	},
	Fire = {
		"Brandmeisteranwärter",
		"Brandmeister",
		"Oberbrandmeister",
		"Hauptbrandmeister",
		"Brandinspektor",
		"Brandamtmann",
	},
	Rettungsdienst = {
		"Rettungshelfer",
		"Rettungssanitäter",
		"Notfallsanitäter",
		"Praxisanleiter",
		"Wachleiter",
		"Rettungsdienstleiter",
	},
	Notarzt = { "Assistenzarzt", "Notarzt", "Facharzt", "Oberarzt", "Leitender Notarzt", "Chefarzt" },
	Bus = { "Fahrschüler", "Busfahrer", "Linienfahrer", "Erfahrener Fahrer", "Lehrfahrer", "Verkehrsmeister" },
	Taxi = { "Aushilfe", "Taxifahrer", "Stammfahrer", "Erfahrener Fahrer", "Schichtleiter", "Taxiunternehmer" },
}
local GENERAL = { "Azubi", "Mitarbeiter", "Erfahrener Mitarbeiter", "Teamleiter", "Meister", "Chef" }

-- rank number (1-6) and its name for a job and its XP
function Ranks.For(jobId: string, xp: number): (number, string)
	local r = 1
	for i, need in Ranks.XP do
		if xp >= need then
			r = i
		end
	end
	local names = NAMES[jobId] or GENERAL
	return r, names[r]
end

-- XP needed for the next rank (nil = top rank)
function Ranks.NextXP(xp: number): number?
	for _, need in Ranks.XP do
		if xp < need then
			return need
		end
	end
	return nil
end

return Ranks
