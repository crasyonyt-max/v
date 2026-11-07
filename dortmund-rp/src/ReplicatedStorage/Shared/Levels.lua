--!strict
-- XP curve shared by the global level and job levels.

local Levels = {}

-- XP needed to go from `level` to `level + 1`.
function Levels.Required(level: number): number
	return math.floor(100 * level ^ 1.4)
end

-- Returns level, xp into current level, xp needed for next level.
function Levels.FromTotal(total: number): (number, number, number)
	local level = 1
	local remaining = total
	while remaining >= Levels.Required(level) and level < 500 do
		remaining -= Levels.Required(level)
		level += 1
	end
	return level, remaining, Levels.Required(level)
end

return Levels
