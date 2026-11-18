--!strict
-- Kofferraum: the driver of their own car moves carried items (food & drinks) into
-- the trunk and back. The ID card is not an item and can't go in. The trunk is
-- saved with the player: own cars per car, job / admin cars per vehicle type.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Trunk = require(ReplicatedStorage.Shared.Trunk)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local StoreService = require(script.Parent.StoreService)

local TrunkService = {}

-- the car this player drives, if it is their own spawn
local function myCar(player: Player): Model?
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local model = seat and seat.Parent
	if not seat or not model or not model:IsA("Model") or model:GetAttribute("OwnerId") ~= player.UserId then
		return nil
	end
	local isCar = seat.Name == "DriverSeat" and model:GetAttribute("CarType") ~= nil
	local isBike = seat.Name == "DriveSeat" and model:GetAttribute("Bike") == true
	return if isCar or isBike then model else nil
end

local function bodyOf(model: Model): string?
	return if model:GetAttribute("Bike") then "Motorbike" else model:GetAttribute("CarType")
end

function TrunkService.KeyFor(model: Model): string
	local uid = model:GetAttribute("Uid")
	if typeof(uid) == "string" then
		return uid
	end
	return "car:" .. tostring(model:GetAttribute("VehicleId"))
end

local function contents(data: { [string]: any }, k: string): { string }
	data.trunks = data.trunks or {}
	local list = data.trunks[k]
	if typeof(list) ~= "table" then
		list = {}
		data.trunks[k] = list
	end
	return list
end

local function snapshot(data: { [string]: any }, model: Model): { [string]: any }
	return {
		items = table.clone(contents(data, TrunkService.KeyFor(model))),
		limit = Trunk.LimitFor(bodyOf(model)),
		carried = table.clone(data.inventory),
		maxCarried = Items.MaxCarried,
		car = model.Name,
	}
end

-- pure rules (also used by the tests)
function TrunkService.Put(data: { [string]: any }, k: string, limit: number, itemId: string): (boolean, string?)
	if not Items.ById[itemId] then
		return false, "trunk_not_item" -- e.g. the ID card
	end
	if not table.find(data.inventory, itemId) then
		return false, "bad_request"
	end
	local list = contents(data, k)
	if #list >= limit then
		return false, "trunk_full"
	end
	table.insert(list, itemId)
	return true, nil
end

function TrunkService.Take(data: { [string]: any }, k: string, itemId: string): (boolean, string?)
	local list = contents(data, k)
	local index = table.find(list, itemId)
	if not index then
		return false, "bad_request"
	end
	if #data.inventory >= Items.MaxCarried then
		return false, "inventory_full"
	end
	table.remove(list, index)
	return true, nil
end

function TrunkService.Start()
	Remotes.Handle("Trunk.Open", function(player)
		local model = myCar(player)
		local data = DataService.Get(player)
		if not model or not data then
			return Remotes.Fail("trunk_driver_only")
		end
		return Remotes.Ok(snapshot(data, model))
	end, { rate = 10 })

	Remotes.Handle("Trunk.Put", function(player, itemId: any)
		local model = myCar(player)
		local data = DataService.Get(player)
		if not model or not data or typeof(itemId) ~= "string" then
			return Remotes.Fail("trunk_driver_only")
		end
		local ok, err = TrunkService.Put(data, TrunkService.KeyFor(model), Trunk.LimitFor(bodyOf(model)), itemId)
		if not ok then
			return Remotes.Fail(err or "error")
		end
		StoreService.Take(player, itemId)
		State.MarkDirty(player)
		return Remotes.Ok(snapshot(data, model))
	end, { rate = 20 })

	Remotes.Handle("Trunk.Take", function(player, itemId: any)
		local model = myCar(player)
		local data = DataService.Get(player)
		if not model or not data or typeof(itemId) ~= "string" then
			return Remotes.Fail("trunk_driver_only")
		end
		local ok, err = TrunkService.Take(data, TrunkService.KeyFor(model), itemId)
		if not ok then
			return Remotes.Fail(err or "error")
		end
		if not StoreService.Give(player, itemId) then
			-- bag full after all: back into the trunk
			table.insert(contents(data, TrunkService.KeyFor(model)), itemId)
			return Remotes.Fail("inventory_full")
		end
		State.MarkDirty(player)
		return Remotes.Ok(snapshot(data, model))
	end, { rate = 20 })
end

return TrunkService
