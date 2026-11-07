--!strict
-- Player data with session locking, autosave and safe shutdown.
-- All data is plain JSON (no Color3 etc.), so it can be saved directly.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Phones = require(ReplicatedStorage.Shared.Phones)

local DataService = {}

local LOCK_TIMEOUT = 30 * 60 -- a lock older than this is considered dead
local AUTOSAVE = 120

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
end)

type Profile = {
	data: { [string]: any },
	canSave: boolean,
	lastSave: number,
}

local profiles: { [Player]: Profile } = {}
local loadedEvent = Instance.new("BindableEvent")
DataService.Loaded = loadedEvent.Event -- (player, data)

local function template(): { [string]: any }
	return {
		v = 1,
		bank = Config.StartingBank,
		cash = 0,
		xp = 0,
		job = "Unemployed",
		jobXP = {},
		vehicles = {}, -- [uid] = { id, color = {r,g,b}, plate, fuel }
		nextUid = 1,
		starterChosen = false,
		phones = { Phones.StarterId },
		phone = Phones.StarterId,
		wallpaper = 1,
		language = "de",
		messages = {}, -- { peer, peerName, text, t, out }
		tx = {}, -- bank transactions { amount, reason, t }
		stats = { joins = 0, playtime = 0 },
		_lock = nil,
	}
end

-- Fill in fields added in later versions without touching existing values.
local function reconcile(data: { [string]: any }, tpl: { [string]: any })
	for k, v in tpl do
		if data[k] == nil then
			data[k] = v
		elseif typeof(v) == "table" and typeof(data[k]) == "table" and next(v) ~= nil and #v == 0 then
			reconcile(data[k], v)
		end
	end
end

local function key(userId: number): string
	return "u_" .. userId
end

local function tryLoad(userId: number, force: boolean): ({ [string]: any }?, string?)
	if not store then
		return nil, "no_store"
	end
	local result: { [string]: any }? = nil
	local blocked = false
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(userId), function(old: any)
			local data = if typeof(old) == "table" then old else template()
			local lock = data._lock
			if
				not force
				and typeof(lock) == "table"
				and lock.job ~= game.JobId
				and os.time() - (tonumber(lock.t) or 0) < LOCK_TIMEOUT
			then
				blocked = true
				return nil -- cancel: another server still has this player
			end
			blocked = false
			data._lock = { job = game.JobId, t = os.time() }
			result = data
			return data
		end)
	end)
	if not ok then
		return nil, tostring(err)
	end
	if blocked then
		return nil, "locked"
	end
	return result, nil
end

function DataService.Load(player: Player)
	local data: { [string]: any }? = nil
	local canSave = true
	for attempt = 1, 6 do
		local result, err = tryLoad(player.UserId, attempt == 6)
		if result then
			data = result
			break
		end
		if err == "no_store" or (RunService:IsStudio() and err ~= "locked") then
			break
		end
		warn(string.format("[Data] load %s attempt %d failed: %s", player.Name, attempt, tostring(err)))
		task.wait(if err == "locked" then 5 else 2)
		if player.Parent ~= Players then
			return
		end
	end

	if not data then
		if RunService:IsStudio() then
			-- Studio without API access: play with fresh data that is never saved.
			data = template()
			canSave = false
			warn("[Data] Using unsaved test data for " .. player.Name)
		else
			player:Kick(
				"Deine Daten konnten nicht geladen werden. Bitte versuche es gleich noch einmal.\nYour data could not be loaded, please rejoin."
			)
			return
		end
	end
	local loaded = data :: { [string]: any }

	reconcile(loaded, template())
	loaded.stats.joins += 1

	if player.Parent ~= Players then
		-- Left while loading: release the lock we just took.
		if canSave then
			loaded._lock = nil
			pcall(function()
				(store :: DataStore):SetAsync(key(player.UserId), loaded)
			end)
		end
		return
	end

	profiles[player] = { data = loaded, canSave = canSave, lastSave = os.clock() }
	loadedEvent:Fire(player, loaded)
end

function DataService.Get(player: Player): { [string]: any }?
	local p = profiles[player]
	return if p then p.data else nil
end

function DataService.IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

function DataService.Save(player: Player, release: boolean)
	local p = profiles[player]
	if not p or not p.canSave or not store then
		return
	end
	local data = p.data
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(player.UserId), function(old: any)
			if typeof(old) == "table" and typeof(old._lock) == "table" and old._lock.job ~= game.JobId then
				-- Another server force-loaded this player; never overwrite its newer data.
				return nil
			end
			data._lock = if release then nil else { job = game.JobId, t = os.time() }
			return data
		end)
	end)
	if not ok then
		warn("[Data] save failed for " .. player.Name .. ": " .. tostring(err))
	end
	p.lastSave = os.clock()
end

local function onLeave(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	DataService.Save(player, true)
	profiles[player] = nil
end

function DataService.Start()
	Players.PlayerAdded:Connect(function(player)
		DataService.Load(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(DataService.Load, player)
	end
	Players.PlayerRemoving:Connect(onLeave)

	task.spawn(function()
		while true do
			task.wait(10)
			for player, p in profiles do
				p.data.stats.playtime += 10
				if os.clock() - p.lastSave >= AUTOSAVE then
					task.spawn(DataService.Save, player, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				onLeave(player)
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
