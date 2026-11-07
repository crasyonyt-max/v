--!strict
-- Food & drink sold in stores. Prices in € (cents allowed). Parody brand names only.
-- hunger / thirst: how much the item refills (bars go from 0 to 100).

export type Item = {
	id: string,
	name: string,
	price: number,
	hunger: number,
	thirst: number,
	color: Color3,
	size: Vector3, -- handle size of the tool you hold
	shape: string?, -- "Block" | "Cylinder" | "Ball"
}

local Items = {}

local function item(t: Item)
	return t
end

Items.List = {
	-- food
	item({
		id = "pizza_salami",
		name = "Steinofen-Pizza Salami",
		price = 3.49,
		hunger = 55,
		thirst = 0,
		color = Color3.fromRGB(214, 120, 60),
		size = Vector3.new(1.6, 0.15, 1.6),
		shape = "Cylinder",
	}),
	item({
		id = "pizza_margherita",
		name = "Pizza Margherita",
		price = 2.99,
		hunger = 50,
		thirst = 0,
		color = Color3.fromRGB(230, 170, 80),
		size = Vector3.new(1.6, 0.15, 1.6),
		shape = "Cylinder",
	}),
	item({
		id = "broetchen",
		name = "Brötchen",
		price = 0.39,
		hunger = 10,
		thirst = 0,
		color = Color3.fromRGB(205, 150, 85),
		size = Vector3.new(0.6, 0.4, 0.5),
		shape = "Ball",
	}),
	item({
		id = "belegtes_broetchen",
		name = "Belegtes Brötchen",
		price = 2.79,
		hunger = 25,
		thirst = 0,
		color = Color3.fromRGB(200, 140, 80),
		size = Vector3.new(0.8, 0.45, 0.6),
	}),
	item({
		id = "laugenbrezel",
		name = "Laugenbrezel",
		price = 0.89,
		hunger = 12,
		thirst = -3,
		color = Color3.fromRGB(130, 70, 30),
		size = Vector3.new(0.9, 0.2, 0.7),
	}),
	item({
		id = "berliner",
		name = "Berliner",
		price = 1.29,
		hunger = 14,
		thirst = 0,
		color = Color3.fromRGB(215, 160, 90),
		size = Vector3.new(0.6, 0.45, 0.6),
		shape = "Ball",
	}),
	item({
		id = "currywurst",
		name = "Currywurst mit Pommes",
		price = 5.90,
		hunger = 60,
		thirst = -5,
		color = Color3.fromRGB(190, 60, 30),
		size = Vector3.new(1.0, 0.3, 0.6),
	}),
	item({
		id = "bockwurst",
		name = "Bockwurst",
		price = 2.99,
		hunger = 30,
		thirst = 0,
		color = Color3.fromRGB(170, 80, 60),
		size = Vector3.new(0.2, 0.2, 0.9),
		shape = "Cylinder",
	}),
	item({
		id = "sandwich",
		name = "Sandwich",
		price = 2.49,
		hunger = 22,
		thirst = 0,
		color = Color3.fromRGB(230, 210, 170),
		size = Vector3.new(0.8, 0.3, 0.8),
	}),
	item({
		id = "apfel",
		name = "Apfel",
		price = 0.49,
		hunger = 6,
		thirst = 5,
		color = Color3.fromRGB(190, 30, 30),
		size = Vector3.new(0.45, 0.45, 0.45),
		shape = "Ball",
	}),
	item({
		id = "banane",
		name = "Bananen (Stück)",
		price = 0.29,
		hunger = 8,
		thirst = 0,
		color = Color3.fromRGB(250, 220, 60),
		size = Vector3.new(0.25, 0.25, 0.9),
	}),
	item({
		id = "schokoriegel",
		name = "Schokoriegel",
		price = 1.29,
		hunger = 10,
		thirst = -2,
		color = Color3.fromRGB(90, 50, 30),
		size = Vector3.new(0.25, 0.1, 0.8),
	}),
	item({
		id = "chips",
		name = "Chips",
		price = 1.79,
		hunger = 12,
		thirst = -5,
		color = Color3.fromRGB(240, 190, 40),
		size = Vector3.new(0.7, 0.9, 0.25),
	}),
	-- drinks
	item({
		id = "wasser",
		name = "Mineralwasser 1,5 l",
		price = 0.99,
		hunger = 0,
		thirst = 50,
		color = Color3.fromRGB(150, 200, 240),
		size = Vector3.new(0.35, 1.2, 0.35),
		shape = "Cylinder",
	}),
	item({
		id = "kola",
		name = "Kola 0,5 l",
		price = 1.49,
		hunger = 2,
		thirst = 35,
		color = Color3.fromRGB(120, 20, 20),
		size = Vector3.new(0.3, 0.9, 0.3),
		shape = "Cylinder",
	}),
	item({
		id = "apfelschorle",
		name = "Apfelschorle 0,5 l",
		price = 1.29,
		hunger = 2,
		thirst = 40,
		color = Color3.fromRGB(230, 170, 60),
		size = Vector3.new(0.3, 0.9, 0.3),
		shape = "Cylinder",
	}),
	item({
		id = "energy",
		name = "Energydrink",
		price = 1.99,
		hunger = 0,
		thirst = 25,
		color = Color3.fromRGB(40, 90, 200),
		size = Vector3.new(0.25, 0.65, 0.25),
		shape = "Cylinder",
	}),
	item({
		id = "kaffee",
		name = "Kaffee to go",
		price = 2.50,
		hunger = 0,
		thirst = 20,
		color = Color3.fromRGB(240, 240, 235),
		size = Vector3.new(0.35, 0.55, 0.35),
		shape = "Cylinder",
	}),
	item({
		id = "milch",
		name = "Frische Milch 1 l",
		price = 1.15,
		hunger = 8,
		thirst = 30,
		color = Color3.fromRGB(245, 245, 245),
		size = Vector3.new(0.4, 0.9, 0.4),
	}),
} :: { Item }

Items.ById = {} :: { [string]: Item }
for _, it in Items.List do
	Items.ById[it.id] = it
end

-- What each store kind sells, and its price factor (discounters are cheaper).
Items.Stores = {
	Rewo = {
		title = "REWO",
		color = Color3.fromRGB(204, 0, 0),
		factor = 1.0,
		items = {
			"pizza_salami",
			"pizza_margherita",
			"broetchen",
			"belegtes_broetchen",
			"sandwich",
			"apfel",
			"banane",
			"schokoriegel",
			"chips",
			"wasser",
			"kola",
			"apfelschorle",
			"energy",
			"milch",
		},
	},
	Lindl = {
		title = "LINDL",
		color = Color3.fromRGB(0, 80, 170),
		factor = 0.85,
		items = {
			"pizza_salami",
			"pizza_margherita",
			"broetchen",
			"apfel",
			"banane",
			"schokoriegel",
			"chips",
			"wasser",
			"kola",
			"apfelschorle",
			"energy",
			"milch",
		},
	},
	Alda = {
		title = "ALDA",
		color = Color3.fromRGB(0, 60, 140),
		factor = 0.82,
		items = {
			"pizza_salami",
			"pizza_margherita",
			"broetchen",
			"apfel",
			"banane",
			"schokoriegel",
			"chips",
			"wasser",
			"kola",
			"energy",
			"milch",
		},
	},
	Baeckerei = {
		title = "Bäckerei",
		color = Color3.fromRGB(150, 100, 50),
		factor = 1.0,
		items = { "broetchen", "belegtes_broetchen", "laugenbrezel", "berliner", "kaffee", "kola", "wasser" },
	},
	Kiosk = {
		title = "Kiosk",
		color = Color3.fromRGB(60, 120, 60),
		factor = 1.15,
		items = { "schokoriegel", "chips", "kola", "energy", "wasser", "kaffee", "sandwich" },
	},
	Arol = {
		title = "AROL Shop",
		color = Color3.fromRGB(0, 70, 160),
		factor = 1.3,
		items = { "bockwurst", "currywurst", "sandwich", "schokoriegel", "chips", "kaffee", "kola", "energy", "wasser" },
	},
}

function Items.Price(storeKind: string, itemId: string): number?
	local store = Items.Stores[storeKind]
	local it = Items.ById[itemId]
	if not store or not it or not table.find(store.items, itemId) then
		return nil
	end
	return math.floor(it.price * store.factor * 100 + 0.5) / 100
end

Items.MaxCarried = 12

return Items
