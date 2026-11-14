--[[
	PlayerDataAdapter (server only)

	Saves per player with DataStore: Money, JobXP, OwnedVehicles, CustomColors,
	StarterClaimed.
	  * Loads with retries. If loading fails in a live game, the player is
	    kicked so an empty profile never overwrites their real save.
	  * Autosaves every few minutes, saves on leave, and saves everyone on
	    server shutdown (BindToClose).
	  * The current job is session state (not saved). Your job system sets it with
	    PlayerDataAdapter.SetCurrentJob(player, "Police") and clears it with nil.

	Values are mirrored to player attributes (Money, XP_Police, CurrentJob, ...)
	so client UI can read them. Clients can't change the server's copy.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local VehicleConfig = require(ReplicatedStorage:WaitForChild("VehicleConfig"))
local LiveryConfig = require(ReplicatedStorage:WaitForChild("LiveryConfig"))

local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 180
local MAX_RETRIES = 5
local SHUTDOWN_TIMEOUT = 25

local Adapter = {}
local profiles = {} -- [player] = { data, saving, noSave }
local loadedSignal = Instance.new("BindableEvent")
Adapter.Loaded = loadedSignal.Event -- fires (player) when data is ready

local storeOk, store = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
if not storeOk then
	warn("[PlayerData] DataStore unavailable: " .. tostring(store))
	store = nil
end

local function template()
	return {
		Version = 1,
		Money = VehicleConfig.Settings.StartingMoney,
		JobXP = {}, -- [job] = number
		OwnedVehicles = {}, -- [vehicleId] = true
		CustomColors = {}, -- [vehicleId] = { Body = "RRGGBB", ... }
		StarterClaimed = false, -- or the claimed vehicle Id
	}
end

local function reconcile(data)
	local fresh = template()
	if type(data) ~= "table" then
		return fresh
	end
	for k, v in pairs(fresh) do
		if type(data[k]) ~= type(v) then
			-- StarterClaimed may be a string (vehicle id)
			if not (k == "StarterClaimed" and type(data[k]) == "string") then
				data[k] = v
			end
		end
	end
	return data
end

local function withRetries(label, fn)
	local lastErr
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(("[PlayerData] %s failed (%d/%d): %s"):format(label, attempt, MAX_RETRIES, tostring(result)))
		if attempt < MAX_RETRIES then
			task.wait(math.min(2 ^ attempt, 16))
		end
	end
	return false, lastErr
end

local function key(player)
	return "u_" .. player.UserId
end

local function publish(player)
	local p = profiles[player]
	if not p then
		return
	end
	player:SetAttribute("Money", p.data.Money)
	for _, job in ipairs(VehicleConfig.Jobs) do
		player:SetAttribute("XP_" .. job, p.data.JobXP[job] or 0)
	end
	player:SetAttribute("StarterClaimed", p.data.StarterClaimed ~= false)
end

local function load(player)
	local ok, data
	if store then
		ok, data = withRetries("Load " .. player.UserId, function()
			return store:GetAsync(key(player))
		end)
	end
	if not player.Parent then
		return
	end
	local noSave = false
	if not ok then
		if RunService:IsStudio() then
			warn("[PlayerData] Using temporary data in Studio (enable Studio API access to test saving). Nothing will be saved.")
			noSave = true
			data = nil
		else
			player:Kick("Your save data could not be loaded. Please rejoin in a moment.")
			return
		end
	end
	profiles[player] = { data = reconcile(data), saving = false, noSave = noSave }
	publish(player)
	player:SetAttribute("DataLoaded", true)
	loadedSignal:Fire(player)
end

local function save(player)
	local p = profiles[player]
	if not p or p.noSave or not store then
		return true
	end
	while p.saving do
		task.wait(0.1)
	end
	p.saving = true
	local snapshot = p.data
	local ok = withRetries("Save " .. player.UserId, function()
		store:UpdateAsync(key(player), function()
			return snapshot
		end)
	end)
	p.saving = false
	return ok
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

function Adapter.IsLoaded(player)
	return profiles[player] ~= nil
end

function Adapter.WaitForData(player, timeout)
	local deadline = os.clock() + (timeout or 15)
	while not profiles[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player] ~= nil
end

local function data(player)
	local p = profiles[player]
	return p and p.data
end

-- Money ------------------------------------------------------------------
function Adapter.GetMoney(player)
	local d = data(player)
	return d and d.Money or 0
end

function Adapter.AddMoney(player, amount)
	local d = data(player)
	if not d or type(amount) ~= "number" or amount ~= amount then
		return false
	end
	d.Money = math.max(0, math.floor(d.Money + amount))
	publish(player)
	return true
end

-- Takes money only if the player has enough. Returns true on success.
function Adapter.TrySpend(player, amount)
	local d = data(player)
	if not d or type(amount) ~= "number" or amount < 0 or d.Money < amount then
		return false
	end
	d.Money -= amount
	publish(player)
	return true
end

-- Job XP -----------------------------------------------------------------
function Adapter.GetJobXP(player, job)
	local d = data(player)
	return d and d.JobXP[job] or 0
end

function Adapter.AddJobXP(player, job, amount)
	local d = data(player)
	if not d or not VehicleConfig.IsJob(job) or type(amount) ~= "number" or amount ~= amount then
		return false
	end
	d.JobXP[job] = math.max(0, math.floor((d.JobXP[job] or 0) + amount))
	publish(player)
	return true
end

-- Current job (session only) ---------------------------------------------
function Adapter.GetCurrentJob(player)
	return player:GetAttribute("CurrentJob")
end

function Adapter.SetCurrentJob(player, job)
	if job ~= nil and not VehicleConfig.IsJob(job) then
		warn("[PlayerData] Unknown job: " .. tostring(job))
		return false
	end
	player:SetAttribute("CurrentJob", job)
	return true
end

-- Vehicles ---------------------------------------------------------------
function Adapter.OwnsVehicle(player, vehicleId)
	local d = data(player)
	return d ~= nil and d.OwnedVehicles[vehicleId] == true
end

function Adapter.GrantVehicle(player, vehicleId)
	local d = data(player)
	if not d or not VehicleConfig.Get(vehicleId) then
		return false
	end
	d.OwnedVehicles[vehicleId] = true
	return true
end

function Adapter.GetOwnedVehicles(player)
	local d = data(player)
	local list = {}
	if d then
		for id in pairs(d.OwnedVehicles) do
			if VehicleConfig.Get(id) then
				table.insert(list, id)
			end
		end
	end
	return list
end

function Adapter.HasClaimedStarter(player)
	local d = data(player)
	return d == nil or d.StarterClaimed ~= false
end

function Adapter.SetStarterClaimed(player, vehicleId)
	local d = data(player)
	if d then
		d.StarterClaimed = vehicleId
		publish(player)
	end
end

-- Custom colors ----------------------------------------------------------
-- Returns { Body = Color3, ... } or nil.
function Adapter.GetCustomColors(player, vehicleId)
	local d = data(player)
	local saved = d and d.CustomColors[vehicleId]
	if not saved then
		return nil
	end
	local colors = {}
	for _, slot in ipairs(LiveryConfig.RepaintableSlots) do
		local hexValue = saved[slot]
		if type(hexValue) == "string" then
			local ok, color = pcall(Color3.fromHex, hexValue)
			if ok then
				colors[slot] = color
			end
		end
	end
	return next(colors) and colors or nil
end

-- colors: { Body = Color3, ... } merged into existing; nil resets to factory paint.
function Adapter.SetCustomColors(player, vehicleId, colors)
	local d = data(player)
	if not d then
		return false
	end
	if colors == nil then
		d.CustomColors[vehicleId] = nil
		return true
	end
	local saved = d.CustomColors[vehicleId] or {}
	for _, slot in ipairs(LiveryConfig.RepaintableSlots) do
		local c = colors[slot]
		if typeof(c) == "Color3" then
			saved[slot] = c:ToHex()
		end
	end
	d.CustomColors[vehicleId] = saved
	return true
end

-- Save on demand (e.g. after a big purchase). Yields.
function Adapter.Save(player)
	return save(player)
end

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------

Players.PlayerAdded:Connect(load)
for _, plr in ipairs(Players:GetPlayers()) do
	task.spawn(load, plr)
end

Players.PlayerRemoving:Connect(function(player)
	save(player)
	profiles[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for player in pairs(profiles) do
			task.spawn(save, player)
		end
	end
end)

game:BindToClose(function()
	local pending = 0
	for player in pairs(profiles) do
		pending += 1
		task.spawn(function()
			save(player)
			pending -= 1
		end)
	end
	local deadline = os.clock() + SHUTDOWN_TIMEOUT
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

return Adapter
