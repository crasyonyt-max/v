--!strict
-- Owned cars, dealership, gamepass packs, job vehicles, plates, colours, fuel, lights.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Plate = require(ReplicatedStorage.Shared.Plate)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local Interaction = require(script.Parent.InteractionService)
local JobService = require(script.Parent.JobService)
local Remotes = require(script.Parent.Remotes)
local Roles = require(script.Parent.Roles)
local State = require(script.Parent.State)
local TextService = game:GetService("TextService")
local VehicleBuilder = require(script.Parent.VehicleBuilder)
local XPService = require(script.Parent.XPService)

local VehicleService = {}

local PLATE_FEE = 250
local PAINT_FEE = 500
local SELL_BACK = 0.5 -- dealer buys cars back at 50 %

local folder = Instance.new("Folder")
folder.Name = "Vehicles"
folder.Parent = Workspace

local plateStore: DataStore? = nil
pcall(function()
	plateStore = DataStoreService:GetDataStore(Config.DataStoreName .. "_Plates")
end)

local spawned: { [Player]: Model } = {}
local rng = Random.new()

local PALETTE = Vehicles.Palette

local function toColor(c: any): Color3
	if typeof(c) == "table" then
		return Color3.fromRGB(c[1] or 200, c[2] or 200, c[3] or 200)
	end
	return Color3.new(0.8, 0.8, 0.8)
end

local function fromColor(c: Color3): { number }
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

-- Plates are unique across the whole game: plate -> userId.
local function claimPlate(text: string, userId: number): boolean
	if not plateStore then
		return true
	end
	local result = false
	local ok = pcall(function()
		(plateStore :: DataStore):UpdateAsync("p_" .. text, function(old: any)
			if old == nil or old == userId then
				result = true
				return userId
			end
			result = false
			return nil
		end)
	end)
	return ok and result
end

local function releasePlate(text: string, userId: number)
	if not plateStore then
		return
	end
	pcall(function()
		local current = (plateStore :: DataStore):GetAsync("p_" .. text)
		if current == userId then
			(plateStore :: DataStore):RemoveAsync("p_" .. text)
		end
	end)
end

local function newPlate(userId: number): string
	for _ = 1, 8 do
		local text = Plate.Random(Config.DefaultCityCode, rng)
		if claimPlate(text, userId) then
			return text
		end
	end
	return Plate.Random(Config.DefaultCityCode, rng)
end

local function addOwned(player: Player, vehicleId: string)
	local data = DataService.Get(player) :: { [string]: any }
	local def = Vehicles.ById[vehicleId]
	local uid = "v" .. data.nextUid
	data.nextUid += 1
	data.vehicles[uid] = {
		id = vehicleId,
		color = fromColor(def.color),
		plate = newPlate(player.UserId),
		fuel = 100,
	}
	State.MarkDirty(player)
	return uid
end

function VehicleService.Despawn(player: Player)
	local model = spawned[player]
	if not model then
		return
	end
	spawned[player] = nil
	-- remember fuel of owned cars
	local uid = model:GetAttribute("Uid")
	local data = DataService.Get(player)
	if data and typeof(uid) == "string" and data.vehicles[uid] then
		data.vehicles[uid].fuel = math.floor((model:GetAttribute("Fuel") or 100) :: number)
	end
	model:Destroy()
end

-- Ground-level CFrame beside the player; `width` keeps big trucks clear of them.
local function spawnCFrame(player: Player, width: number): CFrame?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	-- place the car beside the player, parallel to where they look
	local right = look:Cross(Vector3.yAxis)
	local origin = root.Position + right * (width / 2 + 5) + look * 2 + Vector3.new(0, 30, 0)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { folder, character }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(origin, Vector3.new(0, -80, 0), params)
	local groundY = if hit then hit.Position.Y else root.Position.Y - 3
	local pos = Vector3.new(origin.X, groundY, origin.Z)
	return CFrame.lookAt(pos, pos + look)
end

local function spawnModel(
	player: Player,
	def: any,
	color: Color3?,
	plateText: string?,
	meta: { [string]: any }
): (boolean, string?)
	VehicleService.Despawn(player)
	local model = VehicleBuilder.Build(def, color)
	local built = model.PrimaryPart :: BasePart
	local cf = spawnCFrame(player, built.Size.X)
	if not cf then
		model:Destroy()
		return false, "no_character"
	end
	-- the model is built with the tyres touching y = 0; lift the chassis to its build height
	cf *= CFrame.new(0, built.Position.Y + 0.3, 0)
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("VehicleId", def.id)
	for k, v in meta do
		model:SetAttribute(k, v)
	end
	VehicleBuilder.SetPlate(model, plateText or Plate.Random(Config.DefaultCityCode, rng))
	model:PivotTo(cf)
	model.Parent = folder
	local chassis = model.PrimaryPart :: BasePart
	pcall(function()
		chassis:SetNetworkOwner(player)
	end)

	local seat = model:FindFirstChild("DriveSeat") :: VehicleSeat
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local humanoid = seat.Occupant
		if not humanoid then
			pcall(function()
				chassis:SetNetworkOwner(player.Parent and player or nil)
			end)
			model:SetAttribute("Brake", false)
			return
		end
		local driver = Players:GetPlayerFromCharacter(humanoid.Parent)
		local allowed = driver ~= nil
			and (
				driver == player
				or Roles.IsServerAdmin(driver)
				or (meta.Job ~= nil and JobService.Get(driver) == meta.Job)
			)
		if not allowed then
			-- not your car: get out
			task.defer(function()
				humanoid.Sit = false
				humanoid.Jump = true
			end)
			if driver then
				Remotes.Push(driver, "Notify", { key = "not_your_car", error = true })
			end
			return
		end
		pcall(function()
			chassis:SetNetworkOwner(driver)
		end)
	end)

	spawned[player] = model
	return true, nil
end

local function driverOf(player: Player): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat and seat:IsA("VehicleSeat") and seat.Name == "DriveSeat" then
		local model = seat.Parent
		if model and model:IsA("Model") and model.Parent == folder then
			return model
		end
	end
	return nil
end
VehicleService.DriverOf = driverOf

function VehicleService.SpawnAny(player: Player, vehicleId: string): (boolean, string?)
	local def = Vehicles.ById[vehicleId]
	if not def then
		return false, "bad_item"
	end
	return spawnModel(player, def, nil, nil, { Temporary = true, Job = def.job })
end

function VehicleService.GiveVehicle(player: Player, vehicleId: string): boolean
	if not Vehicles.ById[vehicleId] or not DataService.Get(player) then
		return false
	end
	addOwned(player, vehicleId)
	return true
end

function VehicleService.Start()
	Players.PlayerRemoving:Connect(VehicleService.Despawn)

	JobService.Changed:Connect(function(player)
		local model = spawned[player]
		if model and model:GetAttribute("Job") then
			VehicleService.Despawn(player)
		end
	end)

	Remotes.Handle("Vehicle.ChooseStarter", function(player, vehicleId: any)
		local data = DataService.Get(player) :: { [string]: any }
		if data.starterChosen then
			return Remotes.Fail("already_owned")
		end
		if typeof(vehicleId) ~= "string" or not table.find(Vehicles.StarterIds, vehicleId) then
			return Remotes.Fail("bad_item")
		end
		data.starterChosen = true
		addOwned(player, vehicleId)
		return Remotes.Ok()
	end, { rate = 3 })

	Remotes.Handle("Vehicle.Buy", function(player, vehicleId: any)
		local data = DataService.Get(player) :: { [string]: any }
		local def = typeof(vehicleId) == "string" and Vehicles.ById[vehicleId] or nil
		if not def or (def.category ~= "Dealer" and def.category ~= "Pack") then
			return Remotes.Fail("bad_item")
		end
		if not Interaction.IsNear(player, "Shop", 40, "UI", "Dealership") then
			return Remotes.Fail("not_near")
		end
		if def.category == "Pack" and not State.OwnsPack(player, def.pack :: string) then
			return Remotes.Fail("pack_locked")
		end
		local count = 0
		for _ in data.vehicles do
			count += 1
		end
		if count >= 40 then
			return Remotes.Fail("garage_full")
		end
		if not Economy.TrySpend(player, def.price, "Autohaus: " .. def.name) then
			return Remotes.Fail("no_money")
		end
		addOwned(player, def.id)
		return Remotes.Ok()
	end, { rate = 5 })

	Remotes.Handle("Vehicle.Sell", function(player, uid: any)
		local data = DataService.Get(player) :: { [string]: any }
		local entry = typeof(uid) == "string" and data.vehicles[uid] or nil
		if not entry then
			return Remotes.Fail("not_owned")
		end
		if not Interaction.IsNear(player, "Shop", 40, "UI", "Dealership") then
			return Remotes.Fail("not_near")
		end
		local def = Vehicles.ById[entry.id]
		local spawnedModel = spawned[player]
		if spawnedModel and spawnedModel:GetAttribute("Uid") == uid then
			VehicleService.Despawn(player)
		end
		data.vehicles[uid] = nil
		task.spawn(releasePlate, entry.plate, player.UserId)
		local value = if def then math.floor(def.price * SELL_BACK) else 0
		if value > 0 then
			Economy.Add(player, value, "Autohaus Ankauf: " .. (def and def.name or "?"))
		end
		State.MarkDirty(player)
		return Remotes.Ok({ value = value })
	end, { rate = 3 })

	Remotes.Handle("Vehicle.Spawn", function(player, uid: any)
		local data = DataService.Get(player) :: { [string]: any }
		local entry = typeof(uid) == "string" and data.vehicles[uid] or nil
		if not entry then
			return Remotes.Fail("not_owned")
		end
		local def = Vehicles.ById[entry.id]
		if not def then
			return Remotes.Fail("bad_item")
		end
		local ok, err = spawnModel(player, def, toColor(entry.color), entry.plate, { Uid = uid })
		if not ok then
			return Remotes.Fail(err or "error")
		end
		local model = spawned[player]
		model:SetAttribute("Fuel", entry.fuel or 100)
		return Remotes.Ok()
	end, { rate = 4 })

	Remotes.Handle("Vehicle.SpawnJob", function(player, vehicleId: any)
		local def = typeof(vehicleId) == "string" and Vehicles.ById[vehicleId] or nil
		if not def or def.category ~= "Job" then
			return Remotes.Fail("bad_item")
		end
		local job = JobService.Get(player)
		if def.job ~= job then
			return Remotes.Fail("wrong_job")
		end
		if XPService.JobXP(player, job) < (def.xp or 0) and not Roles.IsGameAdmin(player) then
			return Remotes.Fail("need_xp")
		end
		if not Interaction.IsNear(player, "JobGarage", 40, "JobId", job) then
			return Remotes.Fail("not_near")
		end
		local ok, err = spawnModel(player, def, nil, Plate.Random(Config.DefaultCityCode, rng), { Job = job })
		return if ok then Remotes.Ok() else Remotes.Fail(err or "error")
	end, { rate = 4 })

	Remotes.Handle("Vehicle.Despawn", function(player)
		VehicleService.Despawn(player)
		return Remotes.Ok()
	end, { rate = 5 })

	Remotes.Handle("Vehicle.SetPlate", function(player, uid: any, text: any)
		local data = DataService.Get(player) :: { [string]: any }
		local entry = typeof(uid) == "string" and data.vehicles[uid] or nil
		if not entry then
			return Remotes.Fail("not_owned")
		end
		local plateText = typeof(text) == "string" and Plate.Normalize(text) or nil
		if not plateText then
			return Remotes.Fail("bad_plate")
		end
		-- Plates are visible to everyone, so they must pass the text filter unchanged.
		local okFilter, filtered = pcall(function()
			local result = TextService:FilterStringAsync(plateText, player.UserId, Enum.TextFilterContext.PublicChat)
			return result:GetNonChatStringForBroadcastAsync()
		end)
		if not okFilter or filtered ~= plateText then
			return Remotes.Fail("bad_plate")
		end
		if data.bank < PLATE_FEE then
			return Remotes.Fail("no_money")
		end
		if not claimPlate(plateText, player.UserId) then
			return Remotes.Fail("plate_taken")
		end
		if not Economy.TrySpend(player, PLATE_FEE, "Kennzeichen " .. plateText) then
			task.spawn(releasePlate, plateText, player.UserId)
			return Remotes.Fail("no_money")
		end
		local old = entry.plate
		entry.plate = plateText
		task.spawn(releasePlate, old, player.UserId)
		local model = spawned[player]
		if model and model:GetAttribute("Uid") == uid then
			VehicleBuilder.SetPlate(model, plateText)
		end
		State.MarkDirty(player)
		return Remotes.Ok()
	end, { rate = 3 })

	Remotes.Handle("Vehicle.SetColor", function(player, uid: any, index: any)
		local data = DataService.Get(player) :: { [string]: any }
		local entry = typeof(uid) == "string" and data.vehicles[uid] or nil
		local i = Remotes.Check.Int(index, 1, #PALETTE)
		if not entry or not i then
			return Remotes.Fail("bad_request")
		end
		if not Economy.TrySpend(player, PAINT_FEE, "Lackierung") then
			return Remotes.Fail("no_money")
		end
		entry.color = table.clone(PALETTE[i])
		local model = spawned[player]
		if model and model:GetAttribute("Uid") == uid then
			VehicleBuilder.SetColor(model, toColor(entry.color))
		end
		State.MarkDirty(player)
		return Remotes.Ok()
	end, { rate = 5 })

	-- Lights / indicators / blue lights / siren. Driver only.
	Remotes.Handle("Vehicle.Control", function(player, action: any, value: any)
		local model = driverOf(player)
		if not model then
			return Remotes.Fail("not_driving")
		end
		if action == "Headlights" then
			model:SetAttribute("Headlights", not model:GetAttribute("Headlights"))
		elseif action == "Indicator" then
			local v = Remotes.Check.OneOf(value, { "", "L", "R", "H" })
			if v == nil then
				return Remotes.Fail("bad_request")
			end
			model:SetAttribute("Indicator", if model:GetAttribute("Indicator") == v then "" else v)
		elseif action == "Brake" then
			model:SetAttribute("Brake", value == true)
		elseif action == "Bluelight" or action == "Siren" then
			if not model:GetAttribute("Emergency") then
				return Remotes.Fail("not_emergency")
			end
			local on = not model:GetAttribute(action)
			model:SetAttribute(action, on)
			if action == "Siren" then
				local siren = (model.PrimaryPart :: BasePart):FindFirstChild("Siren") :: Sound?
				if siren then
					if on then
						siren:Play()
					else
						siren:Stop()
					end
				end
			end
		else
			return Remotes.Fail("bad_request")
		end
		return Remotes.Ok()
	end, { rate = 30, needsData = false })

	-- Fuel: burn while driving, refuel at Arol stations.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, model in folder:GetChildren() do
				if model:IsA("Model") and model.PrimaryPart then
					local speed = (model.PrimaryPart :: BasePart).AssemblyLinearVelocity.Magnitude
					if speed > 2 then
						local top = (model:GetAttribute("TopSpeed") or 100) :: number
						local fuel = (model:GetAttribute("Fuel") or 100) :: number
						-- a full tank lasts roughly 25 minutes at average speed
						fuel = math.max(0, fuel - (0.05 + 0.08 * speed / top))
						model:SetAttribute("Fuel", fuel)
					end
				end
			end
		end
	end)

	Interaction.OnTrigger("Refuel", function(player, marker)
		local model = spawned[player]
		if not model or not model.PrimaryPart then
			Remotes.Push(player, "Notify", { key = "no_vehicle", error = true })
			return
		end
		if ((model.PrimaryPart :: BasePart).Position - marker.Position).Magnitude > 30 then
			Remotes.Push(player, "Notify", { key = "vehicle_too_far", error = true })
			return
		end
		local fuel = (model:GetAttribute("Fuel") or 100) :: number
		local liters = math.floor((100 - fuel) * 0.5) -- 50 l tank
		if liters <= 0 then
			Remotes.Push(player, "Notify", { key = "tank_full" })
			return
		end
		local cost = math.ceil(liters * Config.FuelPricePerLiter)
		if not Economy.TrySpend(player, cost, "Arol Tankstelle") then
			Remotes.Push(player, "Notify", { key = "no_money", error = true })
			return
		end
		model:SetAttribute("Fuel", 100)
		Remotes.Push(player, "Notify", { key = "refueled", args = { liters, cost } })
	end)
end

return VehicleService
