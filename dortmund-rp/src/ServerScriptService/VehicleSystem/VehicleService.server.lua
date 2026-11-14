--[[
	VehicleService (server Script)

	Creates ReplicatedStorage/VehicleRemotes. Every request is checked here on
	the server; the client only asks.

	RemoteFunctions (all return { Success = bool, Message = string, ... }):
	  GetPlayerVehicleData()                 -> money, XP, owned cars, job, admin flags
	  PurchaseVehicle(vehicleId)
	  ClaimStarter(vehicleId)
	  SpawnVehicle(vehicleId)
	  DespawnVehicle()
	  RepaintVehicle(vehicleId, { Body = Color3, Stripe = Color3, Accent = Color3 } | "reset")
	  AppointServerAdmin(userId) / RemoveServerAdmin(userId) / GetServerAdmins()
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local VehicleConfig = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local LiveryConfig = require(ReplicatedStorage:WaitForChild("LiveryConfig"))
local PlayerData = require(script.Parent.PlayerDataAdapter)
local Access = require(script.Parent.VehicleAccess)
local LiveryApplier = require(script.Parent.LiveryApplier)
local ServerAdmins = require(script.Parent.ServerAdmins)
local ModelGenerator = require(script.Parent.VehicleModelGenerator)

local Settings = VehicleConfig.Settings
local COOLDOWN = 0.5 -- seconds between requests per player

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "VehicleRemotes"

local spawnedFolder = workspace:FindFirstChild("SpawnedVehicles") or Instance.new("Folder")
spawnedFolder.Name = "SpawnedVehicles"
spawnedFolder.Parent = workspace

local function vehiclesFolder()
	return ServerStorage:FindFirstChild(Settings.VehiclesFolder)
end

-- Build drivable placeholder models for vehicles that have no model yet.
ModelGenerator.GenerateMissing()

-- One startup warning listing every vehicle whose model is still missing.
do
	local folder = vehiclesFolder()
	local missing = {}
	for _, v in ipairs(VehicleConfig.List) do
		local model = folder and folder:FindFirstChild(v.Model)
		if not (model and model:IsA("Model")) and not table.find(missing, v.Model) then
			table.insert(missing, v.Model)
		end
	end
	if #missing > 0 then
		warn(("[VehicleService] %d vehicle model(s) not found in ServerStorage/%s yet; they will be skipped until added:\n  %s")
			:format(#missing, Settings.VehiclesFolder, table.concat(missing, "\n  ")))
	end
end

local function reply(success, message, extra)
	local out = { Success = success, Message = message }
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- Rate limit + one request at a time per player.
local lastRequest, busy = {}, {}
local function guarded(handler)
	return function(player, ...)
		local now = os.clock()
		if busy[player] or (lastRequest[player] and now - lastRequest[player] < COOLDOWN) then
			return reply(false, "Please wait a moment.")
		end
		lastRequest[player] = now
		busy[player] = true
		local ok, result = pcall(handler, player, ...)
		busy[player] = nil
		if not ok then
			warn("[VehicleService] " .. tostring(result))
			return reply(false, "Something went wrong, please try again.")
		end
		return result
	end
end

local function remote(name, handler)
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.OnServerInvoke = guarded(handler)
	rf.Parent = remotes
end

local function getVehicle(id)
	return type(id) == "string" and VehicleConfig.Get(id) or nil
end

-------------------------------------------------------------------------------
-- Spawning
-------------------------------------------------------------------------------

local spawned = {} -- [player] = model

local function despawn(player)
	local model = spawned[player]
	spawned[player] = nil
	if model then
		model:Destroy()
	end
end

local function spawnCFrame(player, model)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	local target = hrp.Position + flat * Settings.SpawnDistance

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, spawnedFolder }
	local hit = workspace:Raycast(target + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0), params)
	local groundY = hit and hit.Position.Y or hrp.Position.Y - 3

	-- Put the bottom of the model on the ground, facing sideways to the player.
	local boxCFrame, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local pivotAboveBottom = pivot.Position.Y - (boxCFrame.Position.Y - size.Y / 2)
	local pos = Vector3.new(target.X, groundY + pivotAboveBottom + 0.3, target.Z)
	local side = flat:Cross(Vector3.yAxis)
	return CFrame.lookAt(pos, pos + side)
end

local function spawnVehicle(player, vehicle)
	local folder = vehiclesFolder()
	local template = folder and folder:FindFirstChild(vehicle.Model)
	if not (template and template:IsA("Model")) then
		warn(("[VehicleService] Model %q for %s missing in ServerStorage/%s, skipped")
			:format(vehicle.Model, vehicle.Id, Settings.VehiclesFolder))
		return reply(false, "This vehicle isn't available yet.")
	end

	local model = template:Clone()
	local cf = spawnCFrame(player, model)
	if not cf then
		model:Destroy()
		return reply(false, "You need a character to spawn a vehicle.")
	end
	despawn(player)

	model.Name = vehicle.Name
	model:SetAttribute("VehicleId", vehicle.Id)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("Job", vehicle.Job)
	CollectionService:AddTag(model, "SpawnedVehicle")
	LiveryApplier.ApplyVehicle(model, vehicle, vehicle.Repaintable and PlayerData.GetCustomColors(player, vehicle.Id) or nil)
	model:PivotTo(cf)
	model.Parent = spawnedFolder
	spawned[player] = model
	model.Destroying:Connect(function()
		if spawned[player] == model then
			spawned[player] = nil
		end
	end)
	return reply(true, vehicle.Name .. " spawned.")
end

-- Leaving the job removes that job's vehicle.
local function watchJob(player)
	player:GetAttributeChangedSignal("CurrentJob"):Connect(function()
		local model = spawned[player]
		local job = model and model:GetAttribute("Job")
		if job and job ~= PlayerData.GetCurrentJob(player) then
			despawn(player)
		end
	end)
end
Players.PlayerAdded:Connect(watchJob)
for _, plr in ipairs(Players:GetPlayers()) do
	watchJob(plr)
end

Players.PlayerRemoving:Connect(function(player)
	despawn(player)
	lastRequest[player] = nil
	busy[player] = nil
end)

-------------------------------------------------------------------------------
-- Remotes
-------------------------------------------------------------------------------

remote("GetPlayerVehicleData", function(player)
	if not PlayerData.WaitForData(player, 10) then
		return reply(false, "Your data is still loading.")
	end
	local xp = {}
	for _, job in ipairs(VehicleConfig.Jobs) do
		xp[job] = PlayerData.GetJobXP(player, job)
	end
	return reply(true, "OK", {
		Money = PlayerData.GetMoney(player),
		JobXP = xp,
		CurrentJob = PlayerData.GetCurrentJob(player),
		OwnedVehicles = PlayerData.GetOwnedVehicles(player),
		StarterClaimed = PlayerData.HasClaimedStarter(player),
		IsServerAdmin = Access.IsServerAdmin(player),
		IsGameAdmin = Access.IsGameAdmin(player),
		SpawnedVehicleId = spawned[player] and spawned[player]:GetAttribute("VehicleId") or nil,
	})
end)

remote("PurchaseVehicle", function(player, vehicleId)
	local vehicle = getVehicle(vehicleId)
	if not vehicle then
		return reply(false, "Unknown vehicle.")
	end
	local ok, reason = Access.CanBuy(player, vehicle)
	if not ok then
		return reply(false, reason)
	end
	if not PlayerData.TrySpend(player, vehicle.Price) then
		return reply(false, "Not enough money.")
	end
	PlayerData.GrantVehicle(player, vehicle.Id)
	task.spawn(PlayerData.Save, player)
	return reply(true, ("You bought the %s for %d EUR."):format(vehicle.Name, vehicle.Price), {
		Money = PlayerData.GetMoney(player),
	})
end)

remote("ClaimStarter", function(player, vehicleId)
	local vehicle = getVehicle(vehicleId)
	if not vehicle then
		return reply(false, "Unknown vehicle.")
	end
	local ok, reason = Access.CanClaimStarter(player, vehicle)
	if not ok then
		return reply(false, reason)
	end
	PlayerData.GrantVehicle(player, vehicle.Id)
	PlayerData.SetStarterClaimed(player, vehicle.Id)
	task.spawn(PlayerData.Save, player)
	return reply(true, ("The %s is yours!"):format(vehicle.Name))
end)

remote("SpawnVehicle", function(player, vehicleId)
	local vehicle = getVehicle(vehicleId)
	if not vehicle then
		return reply(false, "Unknown vehicle.")
	end
	local ok, reason = Access.CanSpawn(player, vehicle)
	if not ok then
		return reply(false, reason)
	end
	return spawnVehicle(player, vehicle)
end)

remote("DespawnVehicle", function(player)
	if not spawned[player] then
		return reply(false, "You have no vehicle out.")
	end
	despawn(player)
	return reply(true, "Vehicle parked.")
end)

remote("RepaintVehicle", function(player, vehicleId, colors)
	local vehicle = getVehicle(vehicleId)
	if not vehicle then
		return reply(false, "Unknown vehicle.")
	end
	local ok, reason = Access.CanRepaint(player, vehicle)
	if not ok then
		return reply(false, reason)
	end

	local clean = nil
	if colors ~= "reset" then
		if type(colors) ~= "table" then
			return reply(false, "Invalid colors.")
		end
		clean = {}
		for _, slot in ipairs(LiveryConfig.RepaintableSlots) do
			local c = colors[slot]
			if c ~= nil then
				if typeof(c) ~= "Color3" then
					return reply(false, "Invalid color for " .. slot .. ".")
				end
				clean[slot] = c
			end
		end
		if next(clean) == nil then
			return reply(false, "Pick at least one color.")
		end
	end

	if Settings.RepaintCost > 0 and not PlayerData.TrySpend(player, Settings.RepaintCost) then
		return reply(false, "Not enough money for a repaint.")
	end
	PlayerData.SetCustomColors(player, vehicle.Id, clean)

	local model = spawned[player]
	if model and model:GetAttribute("VehicleId") == vehicle.Id then
		LiveryApplier.ApplyVehicle(model, vehicle, PlayerData.GetCustomColors(player, vehicle.Id))
	end
	return reply(true, clean and "Repainted." or "Factory paint restored.", { Money = PlayerData.GetMoney(player) })
end)

remote("AppointServerAdmin", function(player, userId)
	local ok, message = ServerAdmins.Appoint(player, userId)
	return reply(ok, message)
end)

remote("RemoveServerAdmin", function(player, userId)
	local ok, message = ServerAdmins.Remove(player, userId)
	return reply(ok, message)
end)

remote("GetServerAdmins", function(player)
	if not ServerAdmins.IsServerAdmin(player) then
		return reply(false, "Only Server Admins can see this.")
	end
	return reply(true, "OK", { Admins = ServerAdmins.List(), OwnerUserId = game.PrivateServerOwnerId })
end)

remotes.Parent = ReplicatedStorage
