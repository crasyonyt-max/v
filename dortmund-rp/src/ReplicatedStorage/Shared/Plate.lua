--!strict
-- German license plate validation: "DO-AB 1234" (city 1-3, letters 1-2, digits 1-4, optional E/H).

local Plate = {}

function Plate.Normalize(text: string): string?
	if typeof(text) ~= "string" or #text > 16 then
		return nil
	end
	local s = string.upper(text)
	s = string.gsub(s, "%s+", " ")
	s = string.gsub(s, "^ ", "")
	s = string.gsub(s, " $", "")
	local city, letters, digits, suffix = string.match(s, "^(%u%u?%u?)%-(%u%u?) (%d%d?%d?%d?)([EH]?)$")
	if not city then
		return nil
	end
	if string.sub(digits :: string, 1, 1) == "0" then
		return nil -- German plates never start the number with 0
	end
	return string.format("%s-%s %s%s", city :: string, letters :: string, digits :: string, suffix :: string)
end

-- Custom plates in Dortmund RP: the city is always DO. "AB 1234", "do-ab 1234" and
-- "DO-AB 1234" all become "DO-AB 1234"; any other city is refused.
function Plate.NormalizeDO(text: string): string?
	if typeof(text) ~= "string" or #text > 16 then
		return nil
	end
	local s = string.upper(text)
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "^DO%-%s*DO%-", "DO-") -- typed "DO-" although it is already shown
	if not string.find(s, "-", 1, true) then
		s = "DO-" .. s
	end
	local p = Plate.Normalize(s)
	if not p or string.sub(p, 1, 3) ~= "DO-" then
		return nil
	end
	return p
end

function Plate.Random(city: string, rng: Random): string
	local alphabet = "ABCDEFGHJKLMNPRSTUVWXYZ"
	local function letter()
		local i = rng:NextInteger(1, #alphabet)
		return string.sub(alphabet, i, i)
	end
	local letters = letter() .. (if rng:NextNumber() < 0.7 then letter() else "")
	return string.format("%s-%s %d", city, letters, rng:NextInteger(1, 9999))
end

return Plate
