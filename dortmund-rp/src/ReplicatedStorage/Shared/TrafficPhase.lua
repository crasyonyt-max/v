--!strict
-- Traffic light timing, the same on the server (red-light check) and on every client
-- (lamp colours): worked out from the clock, so nothing has to be sent around.
-- Axis A (the bigger road) and axis B (the cross street) take turns.

local TrafficPhase = {}

TrafficPhase.GREEN = 18
TrafficPhase.YELLOW = 3
TrafficPhase.ALL_RED = 2
TrafficPhase.CYCLE = 2 * (TrafficPhase.GREEN + TrafficPhase.YELLOW + TrafficPhase.ALL_RED) -- 46 s

-- "G" | "Y" | "R" for axis A and axis B of junction `index` at time t (seconds).
function TrafficPhase.State(t: number, index: number): (string, string)
	local half = TrafficPhase.GREEN + TrafficPhase.YELLOW + TrafficPhase.ALL_RED
	local p = (t + index * 7) % TrafficPhase.CYCLE
	local function at(q: number): string
		if q < TrafficPhase.GREEN then
			return "G"
		elseif q < TrafficPhase.GREEN + TrafficPhase.YELLOW then
			return "Y"
		end
		return "R"
	end
	if p < half then
		return at(p), "R"
	end
	return "R", at(p - half)
end

return TrafficPhase
