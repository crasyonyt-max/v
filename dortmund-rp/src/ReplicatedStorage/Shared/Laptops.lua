--!strict
-- v0.4 laptops (Handyland, tab "Laptops"). Opened from the 🎒 bag: all phone apps on
-- a big landscape screen. Parody brands only.

local Laptops = {}

export type Laptop = { id: string, name: string, price: number, body: Color3, accent: Color3, info: string }

Laptops.List = {
	{
		id = "lenova_think",
		name = "Lenova ThinkBuch 14",
		price = 899,
		body = Color3.fromRGB(30, 30, 32),
		accent = Color3.fromRGB(220, 30, 40),
		info = '14" · Office',
	},
	{
		id = "samsong_book",
		name = "Samsong Galaxi Buch 4",
		price = 1199,
		body = Color3.fromRGB(70, 80, 100),
		accent = Color3.fromRGB(60, 120, 230),
		info = '15,6" · leicht',
	},
	{
		id = "pear_air",
		name = "Pear BookAir 13",
		price = 1299,
		body = Color3.fromRGB(205, 208, 212),
		accent = Color3.fromRGB(250, 250, 250),
		info = '13,6" · dünn & leise',
	},
	{
		id = "dalle_xpz",
		name = "Dalle XPZ 15",
		price = 1799,
		body = Color3.fromRGB(190, 192, 196),
		accent = Color3.fromRGB(20, 20, 24),
		info = '15" · OLED',
	},
	{
		id = "azuz_rogg",
		name = "Azuz ROGG Strix",
		price = 2499,
		body = Color3.fromRGB(25, 25, 30),
		accent = Color3.fromRGB(230, 30, 60),
		info = '17" · Gaming · RGB',
	},
	{
		id = "pear_pro",
		name = "Pear BookPro 16",
		price = 2999,
		body = Color3.fromRGB(60, 62, 66),
		accent = Color3.fromRGB(220, 220, 225),
		info = '16" · Profi',
	},
} :: { Laptop }

Laptops.ById = {} :: { [string]: Laptop }
for _, l in Laptops.List do
	Laptops.ById[l.id] = l
end

return Laptops
