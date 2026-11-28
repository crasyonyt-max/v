--!strict
-- 🎄 Advent (Config.Advent, testing server first):
--   * Adventskalender: one door a day from 1 to 24 December (German time). A missed
--     door can still be opened later, until 31 December. Every door once per player
--     (claimed atomically, also across servers).
--   * Weihnachtsmarkt behind the Parlament: wooden huts with Kinderpunsch, Kakao,
--     Bratwurst, Reibekuchen, gebrannte Mandeln, Lebkuchenherzen ...; a giant tree.
--   * Christmas lights in the city, snow on most December days.
-- On the testing server every door can be opened right away (to test the rewards).

local Advent = {}

Advent.MONTH = 12
Advent.DOORS = 24
Advent.LAST_DAY = 31 -- missed doors can be opened until then
Advent.UTC_OFFSET = 3600 -- German winter time (CET)

export type Reward = { cash: number?, xp: number?, items: { string }?, outfit: string? }

-- Christmas outfit: pieces built from parts on your avatar (everyone sees them).
-- You get each piece behind its door; wear them in the Advent app.
Advent.Outfit = {
	hat = { door = 6, name = "Weihnachtsmütze", icon = "🎅", order = 1 },
	scarf = { door = 13, name = "Weihnachtsschal", icon = "🧣", order = 2 },
	antlers = { door = 20, name = "Rentiergeweih + rote Nase", icon = "🦌", order = 3 },
}
-- pieces that sit on the head and can't be worn together
Advent.OnHead = { hat = true, antlers = true }

-- door -> reward (6 = Nikolaus, 24 = Heiligabend: the big one)
Advent.Rewards = {
	[1] = { cash = 500 },
	[2] = { items = { "kinderpunsch", "lebkuchenherz" } },
	[3] = { xp = 300 },
	[4] = { cash = 750 },
	[5] = { items = { "gebrannte_mandeln", "kakao" }, xp = 150 },
	[6] = { cash = 2500, items = { "lebkuchenherz" }, outfit = "hat" }, -- Nikolaus
	[7] = { xp = 400 },
	[8] = { cash = 900 },
	[9] = { items = { "bratwurst", "kinderpunsch" } },
	[10] = { cash = 1000, xp = 200 },
	[11] = { xp = 500 },
	[12] = { items = { "reibekuchen", "kakao", "crepe" } },
	[13] = { cash = 1250, outfit = "scarf" },
	[14] = { xp = 600, items = { "schmalzkuchen" } },
	[15] = { cash = 1500 },
	[16] = { items = { "gebrannte_mandeln", "lebkuchenherz", "kinderpunsch" } },
	[17] = { xp = 750 },
	[18] = { cash = 1750, xp = 250 },
	[19] = { items = { "bratwurst", "reibekuchen", "kakao" } },
	[20] = { cash = 2000, outfit = "antlers" },
	[21] = { xp = 1000 },
	[22] = { cash = 2500, items = { "crepe" } },
	[23] = { xp = 1250, cash = 1000 },
	[24] = { cash = 10000, xp = 2500, items = { "lebkuchenherz", "gebrannte_mandeln", "kinderpunsch" } }, -- Heiligabend
} :: { [number]: Reward }

-- the outfit pieces the opened doors give
function Advent.OwnedOutfit(opened: { number }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, d in opened do
		local r = Advent.Rewards[d]
		if r and r.outfit then
			set[r.outfit] = true
		end
	end
	return set
end

-- the German date now: year, month, day
function Advent.Today(now: number?): (number, number, number)
	local t = os.date("!*t", (now or os.time()) + Advent.UTC_OFFSET) :: any
	return t.year, t.month, t.day
end

-- the highest door that may be opened now (0 = none, outside December)
function Advent.Unlocked(now: number?, testing: boolean?): number
	if testing then
		return Advent.DOORS
	end
	local _, month, day = Advent.Today(now)
	if month ~= Advent.MONTH or day > Advent.LAST_DAY then
		return 0
	end
	return math.min(day, Advent.DOORS)
end

-- is it December (market, lights, snow)?
function Advent.Season(now: number?, testing: boolean?): boolean
	if testing then
		return true
	end
	local _, month = Advent.Today(now)
	return month == Advent.MONTH
end

-- the doors in a shuffled but fixed order (like a real calendar): grid position -> door
Advent.Layout = {
	7,
	15,
	1,
	22,
	10,
	4,
	18,
	3,
	12,
	24,
	20,
	9,
	13,
	6,
	21,
	2,
	16,
	11,
	5,
	19,
	8,
	14,
	23,
	17,
}

return Advent
