--!strict
-- Timetable maths for the automated Stadtbahn (server moves the trains, clients and
-- departure boards read the same timetable). Everything is a function of the
-- server clock, so every server and client agrees where each train is.
--
-- One line = a path (from TrainData) with stations. A train runs from the first to
-- the last station, waits, and comes back on the other track. Trains of a line run
-- the same timetable shifted by cycle / TRAINS.

local TrainData = require(script.Parent.TrainData)

local TrainLine = {}

TrainLine.VMAX = 70 / 3.6 / 0.28 -- 70 km/h in studs/s
TrainLine.ACC = 1.1 / 0.28 -- studs/s²
TrainLine.DWELL = 15 -- seconds at a station
TrainLine.TERMINUS = 30 -- seconds at the end of the line
TrainLine.TRAINS = 3

export type Event = {
	kind: "move" | "dwell",
	t0: number,
	dur: number,
	dir: number, -- +1 = towards the last station, -1 = back
	from: number, -- distance along the path (studs)
	to: number,
	station: number?, -- dwell: station index; move: the station it goes to
}

export type Line = {
	id: string,
	name: string,
	color: Color3,
	stations: { { name: string, s: number } },
	points: { Vector3 }, -- path points (Y = 0)
	cum: { number }, -- distance along the path at each point
	length: number,
	events: { Event },
	cycle: number,
	phase: number, -- this line's trains run this many seconds behind the first line's
	branchFrom: number, -- where its own track starts (shared before that)
}

export type State = {
	s: number,
	dir: number,
	dwelling: boolean,
	station: number?, -- dwelling: where; moving: the next station
	terminus: boolean, -- dwelling at an end of the line
}

-- time and distance-after-time on one trip (accelerate, cruise, brake)
local function tripTime(d: number): number
	local v, a = TrainLine.VMAX, TrainLine.ACC
	if d >= v * v / a then
		return d / v + v / a
	end
	return 2 * math.sqrt(d / a)
end

local function tripDistance(d: number, t: number): number
	local v, a = TrainLine.VMAX, TrainLine.ACC
	local total = tripTime(d)
	t = math.clamp(t, 0, total)
	if d < v * v / a then
		-- triangle: no cruise
		local half = total / 2
		if t <= half then
			return 0.5 * a * t * t
		end
		local r = total - t
		return d - 0.5 * a * r * r
	end
	local ta = v / a
	if t <= ta then
		return 0.5 * a * t * t
	elseif t <= total - ta then
		return 0.5 * a * ta * ta + v * (t - ta)
	end
	local r = total - t
	return d - 0.5 * a * r * r
end
TrainLine.TripTime = tripTime
TrainLine.TripDistance = tripDistance

local function build(data: any, endPad: number): Line
	local points, cum = {}, {}
	local path = data.path
	for i = 1, #path, 2 do
		table.insert(points, Vector3.new(path[i], 0, path[i + 1]))
	end
	cum[1] = 0
	for i = 2, #points do
		cum[i] = cum[i - 1] + (points[i] - points[i - 1]).Magnitude
	end
	local stations = {}
	for _, st in data.stations do
		table.insert(stations, { name = st[1], s = st[2] })
	end
	local events: { Event } = {}
	local t = 0
	local function add(e: any)
		e.t0 = t
		table.insert(events, e)
		t += e.dur
	end
	local n = #stations
	for _, dir in { 1, -1 } do
		local order = {}
		if dir == 1 then
			for i = 1, n do
				table.insert(order, i)
			end
		else
			for i = n, 1, -1 do
				table.insert(order, i)
			end
		end
		-- the start of this direction: waiting at the terminus (the far end waits
		-- longer on the shorter line, so all lines share one timetable)
		add({
			kind = "dwell",
			dur = TrainLine.TERMINUS + (if dir == -1 then endPad else 0),
			dir = dir,
			from = stations[order[1]].s,
			to = stations[order[1]].s,
			station = order[1],
		})
		for k = 2, n do
			local a, b = stations[order[k - 1]].s, stations[order[k]].s
			add({ kind = "move", dur = tripTime(math.abs(b - a)), dir = dir, from = a, to = b, station = order[k] })
			if k < n then
				add({ kind = "dwell", dur = TrainLine.DWELL, dir = dir, from = b, to = b, station = order[k] })
			end
		end
	end
	return {
		id = data.id,
		name = data.name,
		color = Color3.fromRGB(data.color[1], data.color[2], data.color[3]),
		stations = stations,
		points = points,
		cum = cum,
		length = cum[#cum],
		events = events,
		cycle = t,
		phase = 0,
		branchFrom = data.branchFrom or 0,
	}
end

-- All lines start at the same western terminus and share the track up to where
-- each one turns off. Same cycle for every line (padding at the far end) and the
-- trains of all lines interleaved: on the shared track a train comes every
-- cycle / (TRAINS * lines) seconds, never two at once.
TrainLine.Lines = {} :: { Line }
do
	local longest = 0
	for _, data in TrainData do
		longest = math.max(longest, build(data, 0).cycle)
	end
	for i, data in TrainData do
		local plain = build(data, 0)
		local line = build(data, longest - plain.cycle)
		line.phase = (i - 1) * line.cycle / (TrainLine.TRAINS * #TrainData)
		table.insert(TrainLine.Lines, line)
	end
end

-- where the train with index k (1..TRAINS) of a line is at server time t
function TrainLine.State(line: Line, k: number, t: number): State
	local tc = (t - line.phase + (k - 1) * line.cycle / TrainLine.TRAINS) % line.cycle
	for _, e in line.events do
		if tc < e.t0 + e.dur then
			local into = tc - e.t0
			if e.kind == "dwell" then
				return {
					s = e.from,
					dir = e.dir,
					dwelling = true,
					station = e.station,
					terminus = e.station == 1 or e.station == #line.stations,
				}
			end
			local d = math.abs(e.to - e.from)
			return {
				s = e.from + e.dir * tripDistance(d, into),
				dir = e.dir,
				dwelling = false,
				station = e.station,
				terminus = false,
			}
		end
	end
	local last = line.events[#line.events]
	return { s = last.to, dir = last.dir, dwelling = true, station = last.station, terminus = true }
end

-- seconds until the next train leaves station i in direction dir (and the one after)
function TrainLine.Departures(line: Line, station: number, dir: number, t: number): { number }
	local offsets = {}
	for _, e in line.events do
		if e.kind == "dwell" and e.station == station and e.dir == dir then
			table.insert(offsets, e.t0 + e.dur) -- departure
		end
	end
	local out = {}
	for k = 1, TrainLine.TRAINS do
		local tc = (t - line.phase + (k - 1) * line.cycle / TrainLine.TRAINS) % line.cycle
		for _, off in offsets do
			table.insert(out, (off - tc) % line.cycle)
		end
	end
	table.sort(out)
	return out
end

-- point + direction on the path at distance s (Y = 0)
function TrainLine.At(line: Line, s: number): (Vector3, Vector3)
	local pts, cum = line.points, line.cum
	s = math.clamp(s, 0, line.length)
	local lo, hi = 1, #pts
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if cum[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local a, b = pts[lo], pts[hi]
	local seg = cum[hi] - cum[lo]
	local f = if seg > 0 then (s - cum[lo]) / seg else 0
	local dir = if seg > 0 then (b - a) / seg else Vector3.new(0, 0, 1)
	return a:Lerp(b, f), dir
end

-- the station a train in direction dir is heading for (terminus name)
function TrainLine.Destination(line: Line, dir: number): string
	return if dir == 1 then line.stations[#line.stations].name else line.stations[1].name
end

return TrainLine
