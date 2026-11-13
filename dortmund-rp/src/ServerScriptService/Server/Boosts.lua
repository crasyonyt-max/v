--!strict
-- Current cash / XP multipliers (set by EventService, read by Economy and XPService).
-- Also the automatic weekly event: Saturday 18:00 German time, 2x cash + 2x XP, 30 min.

local Boosts = {}

local cash, xp = 1, 1
local cashEnds, xpEnds = 0, 0

function Boosts.Set(c: number, cEnds: number, x: number, xEnds: number)
	cash, cashEnds, xp, xpEnds = c, cEnds, x, xEnds
end

function Boosts.Cash(): number
	return cash
end

function Boosts.XP(): number
	return xp
end

function Boosts.Ends(): (number, number)
	return cashEnds, xpEnds
end

-- days since 1970-01-01 for a calendar date (proleptic Gregorian)
local function daysFromCivil(y: number, m: number, d: number): number
	y -= if m <= 2 then 1 else 0
	local era = (if y >= 0 then y else y - 399) // 400
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = (153 * mp + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end

Boosts.DaysFromCivil = daysFromCivil

-- Berlin wall-clock time -> UTC timestamp (handles CET / CEST).
function Boosts.FromBerlin(y: number, m: number, d: number, h: number, mi: number): number
	local wall = daysFromCivil(y, m, d) * 86400 + h * 3600 + mi * 60
	local guess = wall - 3600
	return wall - Boosts.BerlinOffset(guess)
end

local function lastSunday(y: number, m: number): number -- days since epoch
	local nextMonth = if m == 12 then daysFromCivil(y + 1, 1, 1) else daysFromCivil(y, m + 1, 1)
	local last = nextMonth - 1
	local weekday = (last + 4) % 7 -- 0 = Sunday (1970-01-01 was a Thursday)
	return last - weekday
end

-- Germany: CET (UTC+1), summer time CEST (UTC+2) from the last Sunday in March
-- 01:00 UTC to the last Sunday in October 01:00 UTC.
function Boosts.BerlinOffset(t: number): number
	local year = tonumber(os.date("!%Y", t)) :: number
	local startT = lastSunday(year, 3) * 86400 + 3600
	local endT = lastSunday(year, 10) * 86400 + 3600
	return if t >= startT and t < endT then 7200 else 3600
end

Boosts.WEEKLY_MULT = 2
Boosts.WEEKLY_START = 18 * 3600 -- 18:00
Boosts.WEEKLY_LENGTH = 30 * 60

-- If the weekly event is running at UTC time t: the UTC time it ends, else nil.
function Boosts.WeeklyEnds(t: number): number?
	local localT = t + Boosts.BerlinOffset(t)
	local days = localT // 86400
	local weekday = (days + 4) % 7 -- 6 = Saturday
	local sec = localT - days * 86400
	if weekday == 6 and sec >= Boosts.WEEKLY_START and sec < Boosts.WEEKLY_START + Boosts.WEEKLY_LENGTH then
		return t + (Boosts.WEEKLY_START + Boosts.WEEKLY_LENGTH - sec)
	end
	return nil
end

return Boosts
