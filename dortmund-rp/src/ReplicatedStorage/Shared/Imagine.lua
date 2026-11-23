--!strict
-- v0.4 "imagine": the online shop app. Everything from the other shops in one
-- place, delivered after a while (standard 5 min free, express 1 min).
-- Keys look like "item:pizza_salami", "furniture:sofa", "laptop:pear_air", "phone:x".

local Furniture = require(script.Parent.Furniture)
local Items = require(script.Parent.Items)
local Laptops = require(script.Parent.Laptops)
local Phones = require(script.Parent.Phones)

local Imagine = {}

export type Product = {
	key: string,
	kind: string, -- "item" | "furniture" | "laptop" | "phone"
	id: string,
	name: string,
	info: string,
	price: number,
	category: string,
	color: Color3,
}

Imagine.STANDARD_SECONDS = 300
Imagine.EXPRESS_SECONDS = 60
Imagine.EXPRESS_FEE = 4.99
Imagine.MAX_OPEN = 10

Imagine.Categories = { "Essen & Trinken", "Möbel", "Elektronik" }

Imagine.List = {} :: { Product }
for _, it in Items.List do
	if it.event then
		continue -- event items (Thanksgiving turkeys) can't be ordered
	end
	table.insert(Imagine.List, {
		key = "item:" .. it.id,
		kind = "item",
		id = it.id,
		name = it.name,
		info = (if it.hunger > 0 then "🍔 +" .. it.hunger .. " " else "")
			.. (if it.thirst > 0 then "💧 +" .. it.thirst else ""),
		price = it.price,
		category = "Essen & Trinken",
		color = it.color,
	})
end
for _, f in Furniture.List do
	table.insert(Imagine.List, {
		key = "furniture:" .. f.id,
		kind = "furniture",
		id = f.id,
		name = f.name .. " · " .. f.kind,
		info = "Swedea · " .. f.category,
		price = f.price,
		category = "Möbel",
		color = f.color,
	})
end
for _, l in Laptops.List do
	table.insert(Imagine.List, {
		key = "laptop:" .. l.id,
		kind = "laptop",
		id = l.id,
		name = l.name,
		info = "Laptop · " .. l.info,
		price = l.price,
		category = "Elektronik",
		color = l.body,
	})
end
for _, p in Phones.List do
	if (p :: any).shop and (p :: any).price > 0 then
		table.insert(Imagine.List, {
			key = "phone:" .. p.id,
			kind = "phone",
			id = p.id,
			name = p.name,
			info = "Smartphone",
			price = (p :: any).price,
			category = "Elektronik",
			color = (p :: any).accent or Color3.fromRGB(60, 60, 60),
		})
	end
end

Imagine.ByKey = {} :: { [string]: Product }
for _, p in Imagine.List do
	Imagine.ByKey[p.key] = p
end

return Imagine
