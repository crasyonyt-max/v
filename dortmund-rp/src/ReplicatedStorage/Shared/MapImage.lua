--!strict
-- Top-down city map (tools/render_map.py, uploaded as an image).
-- The square image starts at Locations.Bounds minX/minZ and covers `span` studs.
local Config = require(script.Parent.Config)
if Config.On(Config.BigMap) then
	-- testing server: the bigger map (ED_MAP=xl python3 tools/render_map.py)
	return {
		image = "rbxassetid://115359648537537",
		minX = -4398.7,
		minZ = -2846.4,
		span = 12122.4,
	}
end
return {
	image = "rbxassetid://95046841102055",
	minX = -3285.4,
	minZ = -1820.0,
	span = 9895.8,
}
