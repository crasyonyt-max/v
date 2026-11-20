--!strict
-- v0.4 houses: what you can buy at the Immobilienmakler. You own a house TYPE;
-- on every server it is built on a free plot of the Wohngebiet (housing estate).
-- Sizes in studs (1 stud = 0.28 m): w = width along the street, d = depth.

local Houses = {}

export type HouseType = {
	id: string,
	name: string,
	price: number,
	w: number,
	d: number,
	floors: number,
	roof: string, -- "gable" | "flat" | "hip"
	wall: Color3,
	trim: Color3,
	roofColor: Color3,
	material: Enum.Material,
	garage: boolean?,
	pool: boolean?,
	terrace: boolean?,
	info: string,
}

Houses.List = {
	{
		id = "reihenhaus",
		name = "Reihenhaus",
		price = 200000,
		w = 26,
		d = 34,
		floors = 2,
		roof = "gable",
		wall = Color3.fromRGB(176, 92, 66),
		trim = Color3.fromRGB(235, 232, 225),
		roofColor = Color3.fromRGB(90, 45, 35),
		material = Enum.Material.Brick,
		info = "2 Etagen · Wohnzimmer, Küche, 2 Zimmer, Bad",
	},
	{
		id = "doppelhaus",
		name = "Doppelhaushälfte",
		price = 350000,
		w = 30,
		d = 36,
		floors = 2,
		roof = "gable",
		wall = Color3.fromRGB(232, 222, 196),
		trim = Color3.fromRGB(70, 70, 75),
		roofColor = Color3.fromRGB(60, 60, 66),
		material = Enum.Material.Plaster,
		info = "2 Etagen · Garten",
	},
	{
		id = "bungalow",
		name = "Bungalow",
		price = 500000,
		w = 46,
		d = 36,
		floors = 1,
		roof = "flat",
		wall = Color3.fromRGB(240, 240, 236),
		trim = Color3.fromRGB(50, 50, 55),
		roofColor = Color3.fromRGB(80, 80, 84),
		material = Enum.Material.Plaster,
		terrace = true,
		info = "Alles auf einer Etage · Terrasse",
	},
	{
		id = "einfamilienhaus",
		name = "Einfamilienhaus",
		price = 800000,
		w = 38,
		d = 40,
		floors = 2,
		roof = "gable",
		wall = Color3.fromRGB(246, 238, 220),
		trim = Color3.fromRGB(120, 80, 50),
		roofColor = Color3.fromRGB(150, 60, 40),
		material = Enum.Material.Plaster,
		garage = true,
		info = "2 Etagen · Garage",
	},
	{
		id = "landhaus",
		name = "Landhaus",
		price = 1200000,
		w = 44,
		d = 40,
		floors = 2,
		roof = "hip",
		wall = Color3.fromRGB(196, 160, 112),
		trim = Color3.fromRGB(245, 240, 230),
		roofColor = Color3.fromRGB(70, 50, 40),
		material = Enum.Material.WoodPlanks,
		garage = true,
		info = "Holzhaus · 2 Etagen · Garage",
	},
	{
		id = "stadtvilla",
		name = "Stadtvilla",
		price = 2000000,
		w = 44,
		d = 44,
		floors = 2,
		roof = "hip",
		wall = Color3.fromRGB(250, 250, 248),
		trim = Color3.fromRGB(40, 40, 46),
		roofColor = Color3.fromRGB(40, 40, 46),
		material = Enum.Material.Plaster,
		garage = true,
		terrace = true,
		info = "Große Räume · Terrasse · Garage",
	},
	{
		id = "modernevilla",
		name = "Moderne Villa",
		price = 3500000,
		w = 54,
		d = 42,
		floors = 2,
		roof = "flat",
		wall = Color3.fromRGB(238, 238, 238),
		trim = Color3.fromRGB(30, 30, 34),
		roofColor = Color3.fromRGB(60, 60, 64),
		material = Enum.Material.Concrete,
		garage = true,
		terrace = true,
		info = "Glasfronten · Dachterrasse · Doppelgarage",
	},
	{
		id = "luxusvilla",
		name = "Luxusvilla mit Pool",
		price = 5000000,
		w = 56,
		d = 40,
		floors = 3,
		roof = "flat",
		wall = Color3.fromRGB(245, 242, 235),
		trim = Color3.fromRGB(150, 120, 70),
		roofColor = Color3.fromRGB(70, 70, 74),
		material = Enum.Material.Marble,
		garage = true,
		pool = true,
		terrace = true,
		info = "3 Etagen · Pool · Dachterrasse · Doppelgarage",
	},
} :: { HouseType }

Houses.ById = {} :: { [string]: HouseType }
for _, h in Houses.List do
	Houses.ById[h.id] = h
end

Houses.FLOOR_H = 12 -- studs per storey
Houses.PLOT_W = 80 -- house + garage side by side
Houses.PLOT_D = 74
Houses.SELL_BACK = 0.5 -- selling gives half the price back
Houses.MAX_FURNITURE = 150

-- roles in a house
Houses.Roles = { "coowner", "guest" }

return Houses
