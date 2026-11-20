--!strict
-- v0.4 "imagine" orders: pay now, delivered later (standard 5 min, express 1 min).
-- Orders are saved with the player (server time), so they also arrive after a
-- rejoin on another server. Food goes into the bag (waits while the bag is full),
-- furniture into the furniture storage, laptops / phones become yours.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Imagine = require(ReplicatedStorage.Shared.Imagine)
local Items = require(ReplicatedStorage.Shared.Items)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local GameLog = require(script.Parent.GameLog)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local StoreService = require(script.Parent.StoreService)

local OrderService = {}

export type Order = { n: number, key: string, eta: number, express: boolean, waiting: boolean? }

local function owns(data: { [string]: any }, p: Imagine.Product): boolean
	if p.kind == "laptop" then
		return table.find(data.laptops or {}, p.id) ~= nil
	elseif p.kind == "phone" then
		return table.find(data.phones or {}, p.id) ~= nil
	end
	return false
end

local function ordered(data: { [string]: any }, key: string): boolean
	for _, o in data.orders or {} do
		if o.key == key then
			return true
		end
	end
	return false
end

-- hands the product over; false = can't right now (bag full)
function OrderService.Deliver(player: Player?, data: { [string]: any }, p: Imagine.Product): boolean
	if p.kind == "item" then
		if #data.inventory >= Items.MaxCarried then
			return false
		end
		if player then
			return StoreService.Give(player, p.id)
		end
		table.insert(data.inventory, p.id)
		return true
	elseif p.kind == "furniture" then
		data.furniture = data.furniture or {}
		data.furniture[p.id] = (data.furniture[p.id] or 0) + 1
		return true
	elseif p.kind == "laptop" then
		data.laptops = data.laptops or {}
		if not table.find(data.laptops, p.id) then
			table.insert(data.laptops, p.id)
		end
		data.laptop = data.laptop or p.id
		return true
	elseif p.kind == "phone" then
		if not table.find(data.phones, p.id) then
			table.insert(data.phones, p.id)
		end
		return true
	end
	return false
end

-- delivers everything that is due; returns how many arrived
function OrderService.Tick(player: Player?, data: { [string]: any }, now: number): number
	local arrived = 0
	local keep = {}
	for _, o in data.orders or {} do
		local p = Imagine.ByKey[o.key]
		if not p then
			continue -- product no longer sold: dropped
		end
		if o.eta <= now then
			if OrderService.Deliver(player, data, p) then
				arrived += 1
				if player then
					-- say where it went (the bag, the furniture storage, or it is yours now)
					Remotes.Push(player, "Notify", { key = "imagine_arrived_" .. p.kind, args = { p.name } })
				end
				continue
			elseif not o.waiting then
				o.waiting = true
				if player then
					Remotes.Push(player, "Notify", { key = "imagine_bag_full", args = { p.name }, error = true })
				end
			end
		end
		table.insert(keep, o)
	end
	data.orders = keep
	return arrived
end

function OrderService.Start()
	if not Config.V04 then
		return
	end
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.time()
			for _, player in Players:GetPlayers() do
				local data = DataService.Get(player)
				if data and data.orders and #data.orders > 0 then
					if OrderService.Tick(player, data, now) > 0 then
						State.MarkDirty(player)
					end
				end
			end
		end
	end)

	Remotes.Handle("Imagine.Order", function(player, key: any, express: any)
		local p = typeof(key) == "string" and Imagine.ByKey[key] or nil
		local data = DataService.Get(player)
		if not p or not data then
			return Remotes.Fail("bad_item")
		end
		data.orders = data.orders or {}
		if #data.orders >= Imagine.MAX_OPEN then
			return Remotes.Fail("imagine_too_many")
		end
		if (p.kind == "laptop" or p.kind == "phone") and (owns(data, p) or ordered(data, p.key)) then
			return Remotes.Fail("already_owned")
		end
		local fast = express == true
		local total = p.price + (if fast then Imagine.EXPRESS_FEE else 0)
		if not Economy.TrySpend(player, total, "imagine: " .. p.name) then
			return Remotes.Fail("no_money")
		end
		data.nextOrder = (tonumber(data.nextOrder) or 0) + 1
		table.insert(data.orders, {
			n = data.nextOrder,
			key = p.key,
			eta = os.time() + (if fast then Imagine.EXPRESS_SECONDS else Imagine.STANDARD_SECONDS),
			express = fast,
		})
		State.MarkDirty(player)
		GameLog.Add("money", player, ("imagine order %s (%.2f €)"):format(p.key, total))
		return Remotes.Ok()
	end, { rate = 10 })

	Remotes.Handle("Imagine.Orders", function(player)
		local data = DataService.Get(player)
		if not data then
			return Remotes.Fail("error")
		end
		local now = os.time()
		local list = {}
		for _, o in data.orders or {} do
			local p = Imagine.ByKey[o.key]
			if p then
				table.insert(list, {
					n = o.n,
					name = p.name,
					express = o.express,
					left = math.max(0, o.eta - now),
					waiting = o.waiting == true,
				})
			end
		end
		return Remotes.Ok({ orders = list })
	end, { rate = 10 })
end

return OrderService
