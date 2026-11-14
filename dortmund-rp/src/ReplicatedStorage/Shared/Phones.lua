--!strict
-- Phone catalog (Handyland). Better phones = bigger screen, better camera, more wallpapers.

export type Phone = {
	id: string,
	name: string,
	brand: string,
	price: number,
	screen: number, -- screen height scale, 1 = base
	camera: number, -- 1..5 photo quality
	wallpapers: number, -- how many wallpapers are unlocked
	frame: Color3, -- bezel / body colour
	accent: Color3,
	corner: number, -- screen corner radius (px)
	foldable: boolean?, -- can be folded open (wide inner screen)
	shop: boolean, -- sold in Handyland
	adminOnly: boolean?,
	boot: string?, -- special boot animation
}

local Phones = {}

local function phone(p: Phone)
	return p
end

Phones.List = {
	phone({
		id = "poko_c85",
		name = "Poko C85 5G",
		brand = "Poko",
		price = 0,
		screen = 1.0,
		camera = 1,
		wallpapers = 2,
		frame = Color3.fromRGB(40, 40, 45),
		accent = Color3.fromRGB(255, 200, 0),
		corner = 18,
		shop = true,
	}),
	phone({
		id = "samsong_a56",
		name = "Samsong Galaxa A56",
		brand = "Samsong",
		price = 449,
		screen = 1.03,
		camera = 2,
		wallpapers = 4,
		frame = Color3.fromRGB(70, 75, 90),
		accent = Color3.fromRGB(80, 140, 255),
		corner = 22,
		shop = true,
	}),
	phone({
		id = "fairfone_6",
		name = "Fairfone 6",
		brand = "Fairfone",
		price = 599,
		screen = 1.03,
		camera = 2,
		wallpapers = 5,
		frame = Color3.fromRGB(60, 110, 90),
		accent = Color3.fromRGB(120, 220, 160),
		corner = 20,
		shop = true,
	}),
	phone({
		id = "something_3",
		name = "Something Phone (3)",
		brand = "Something",
		price = 799,
		screen = 1.05,
		camera = 3,
		wallpapers = 6,
		frame = Color3.fromRGB(230, 230, 230),
		accent = Color3.fromRGB(220, 40, 40),
		corner = 24,
		shop = true,
	}),
	phone({
		id = "aphone_17",
		name = "aPhone 17",
		brand = "Appel",
		price = 949,
		screen = 1.05,
		camera = 3,
		wallpapers = 7,
		frame = Color3.fromRGB(150, 180, 210),
		accent = Color3.fromRGB(10, 132, 255),
		corner = 30,
		shop = true,
	}),
	phone({
		id = "pixl_10_pro",
		name = "Goggle Pixl 10 Pro",
		brand = "Goggle",
		price = 1099,
		screen = 1.08,
		camera = 4,
		wallpapers = 8,
		frame = Color3.fromRGB(200, 200, 190),
		accent = Color3.fromRGB(66, 133, 244),
		corner = 28,
		shop = true,
	}),
	phone({
		id = "aphone_17_pro_max",
		name = "aPhone 17 Pro Max",
		brand = "Appel",
		price = 1449,
		screen = 1.12,
		camera = 5,
		wallpapers = 10,
		frame = Color3.fromRGB(210, 110, 40),
		accent = Color3.fromRGB(10, 132, 255),
		corner = 34,
		shop = true,
	}),
	phone({
		id = "samsong_s26_ultra",
		name = "Samsong Galaxa S26 Ultra",
		brand = "Samsong",
		price = 1449,
		screen = 1.12,
		camera = 5,
		wallpapers = 10,
		frame = Color3.fromRGB(50, 50, 60),
		accent = Color3.fromRGB(80, 140, 255),
		corner = 10,
		shop = true,
	}),
	phone({
		id = "xiaomy_15_ultra",
		name = "Xiaomy 15 Ultra",
		brand = "Xiaomy",
		price = 1499,
		screen = 1.12,
		camera = 5,
		wallpapers = 11,
		frame = Color3.fromRGB(20, 20, 20),
		accent = Color3.fromRGB(255, 105, 0),
		corner = 26,
		shop = true,
	}),
	phone({
		id = "samsong_zfold7",
		name = "Samsong Galaxa Z Fold7",
		brand = "Samsong",
		price = 2099,
		screen = 1.18,
		camera = 5,
		wallpapers = 12,
		frame = Color3.fromRGB(30, 40, 70),
		accent = Color3.fromRGB(80, 140, 255),
		corner = 14,
		shop = true,
		foldable = true,
	}),

	-- Special Game Admin phone. Never sold; granted automatically to Game Admins.
	phone({
		id = "nvdr_p1",
		name = "NVDR P1",
		brand = "NVDR",
		price = 0,
		screen = 1.18,
		camera = 5,
		wallpapers = 12,
		frame = Color3.fromRGB(8, 8, 8),
		accent = Color3.fromRGB(57, 255, 20),
		corner = 26,
		shop = false,
		adminOnly = true,
		boot = "NVDR",
	}),
} :: { Phone }

Phones.ById = {} :: { [string]: Phone }
for _, p in Phones.List do
	Phones.ById[p.id] = p
end

Phones.StarterId = "poko_c85"

-- Wallpapers: gradient pairs. Index 1..N; phones unlock the first `wallpapers` entries.
Phones.Wallpapers = {
	{ Color3.fromRGB(30, 60, 120), Color3.fromRGB(10, 15, 35) },
	{ Color3.fromRGB(40, 120, 90), Color3.fromRGB(10, 30, 25) },
	{ Color3.fromRGB(150, 50, 90), Color3.fromRGB(30, 10, 30) },
	{ Color3.fromRGB(230, 130, 40), Color3.fromRGB(60, 20, 10) },
	{ Color3.fromRGB(90, 90, 100), Color3.fromRGB(20, 20, 25) },
	{ Color3.fromRGB(0, 160, 200), Color3.fromRGB(0, 30, 60) },
	{ Color3.fromRGB(250, 210, 0), Color3.fromRGB(70, 40, 0) },
	{ Color3.fromRGB(200, 30, 30), Color3.fromRGB(40, 0, 0) },
	{ Color3.fromRGB(120, 70, 200), Color3.fromRGB(20, 10, 50) },
	{ Color3.fromRGB(240, 240, 240), Color3.fromRGB(120, 130, 150) },
	{ Color3.fromRGB(255, 90, 160), Color3.fromRGB(60, 0, 40) },
	{ Color3.fromRGB(57, 255, 20), Color3.fromRGB(0, 0, 0) }, -- NVDR green
}

return Phones
