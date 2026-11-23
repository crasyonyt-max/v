--!strict
-- Dropper events: set by the Owner / Co-Owners in the AA tab (every server, own duration).
-- While one runs, every drop has the event's `chance` to be worth `mult` times as much.
-- `rain` falls from the sky, `colors` drive the disco lights, `tint` colours the world.

export type DropEvent = {
	id: string,
	icon: string,
	name: string,
	mult: number,
	chance: number,
	rain: string,
	colors: { Color3 },
	tint: Color3,
	fog: Color3?,
}

local DropEvents = {}

DropEvents.List = {
	{
		id = "germany",
		icon = "🇩🇪",
		name = "Germany Event",
		mult = 5,
		chance = 0.05,
		rain = "🇩🇪",
		colors = { Color3.fromRGB(20, 20, 20), Color3.fromRGB(221, 0, 0), Color3.fromRGB(255, 206, 0) },
		tint = Color3.fromRGB(255, 235, 200),
	},
	{
		id = "tacos",
		icon = "🌮",
		name = "Raining Tacos Event",
		mult = 1.4,
		chance = 0.45,
		rain = "🌮",
		colors = { Color3.fromRGB(255, 200, 60), Color3.fromRGB(120, 200, 60), Color3.fromRGB(230, 90, 40) },
		tint = Color3.fromRGB(255, 240, 210),
	},
	{
		id = "snow",
		icon = "🥶",
		name = "Frozen Snow Event",
		mult = 2.5,
		chance = 0.27,
		rain = "❄️",
		colors = { Color3.fromRGB(160, 220, 255), Color3.fromRGB(255, 255, 255), Color3.fromRGB(80, 140, 255) },
		tint = Color3.fromRGB(200, 225, 255),
		fog = Color3.fromRGB(220, 235, 255),
	},
	{
		id = "cats",
		icon = "🐈‍⬛",
		name = "Cat Event",
		mult = 2,
		chance = 0.40,
		rain = "🐈‍⬛",
		colors = { Color3.fromRGB(180, 80, 255), Color3.fromRGB(255, 120, 200), Color3.fromRGB(40, 40, 60) },
		tint = Color3.fromRGB(235, 215, 255),
	},
	{
		id = "nuggets",
		icon = "🐔",
		name = "Chicken Nugget Event",
		mult = 3,
		chance = 0.20,
		rain = "🍗",
		colors = { Color3.fromRGB(255, 170, 40), Color3.fromRGB(255, 230, 120), Color3.fromRGB(200, 110, 30) },
		tint = Color3.fromRGB(255, 235, 190),
	},
	{
		id = "fire",
		icon = "🔥",
		name = "Fire Event",
		mult = 1.7,
		chance = 0.35,
		rain = "🔥",
		colors = { Color3.fromRGB(255, 80, 0), Color3.fromRGB(255, 180, 0), Color3.fromRGB(200, 20, 0) },
		tint = Color3.fromRGB(255, 210, 170),
		fog = Color3.fromRGB(255, 150, 90),
	},
	{
		id = "crabs",
		icon = "🦀",
		name = "Crab Event",
		mult = 1.8,
		chance = 0.37,
		rain = "🦀",
		colors = { Color3.fromRGB(255, 60, 40), Color3.fromRGB(255, 140, 100), Color3.fromRGB(60, 160, 255) },
		tint = Color3.fromRGB(255, 220, 210),
	},
	{
		id = "thanksgiving",
		icon = "🦃",
		name = "Thanksgiving Event",
		mult = 10,
		chance = 0.0005, -- 0.05 %; turkeys spawn too (Shared/Thanksgiving)
		rain = "🦃",
		colors = { Color3.fromRGB(200, 90, 20), Color3.fromRGB(240, 170, 40), Color3.fromRGB(120, 60, 20) },
		tint = Color3.fromRGB(255, 225, 190),
	},
} :: { DropEvent }

-- the chance as text, without rounding small ones to 0: 0.05 -> "5", 0.0005 -> "0,05"
function DropEvents.ChanceText(e: DropEvent): string
	local pct = e.chance * 100
	local text = if pct >= 1 and pct == math.floor(pct)
		then tostring(math.floor(pct))
		else (string.format("%.3f", pct):gsub("0+$", ""):gsub("%.$", ""))
	return (text:gsub("%.", ","))
end

DropEvents.ById = {} :: { [string]: DropEvent }
for _, e in DropEvents.List do
	DropEvents.ById[e.id] = e
end

return DropEvents
