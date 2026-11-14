--[[
	ServerAdmins (server only)

	In a player-owned private server, the owner and the admins they appoint are
	Server Admins in THAT server only. Appointed admins are saved per private
	server, so they are still there next time the owner opens it.
	Public and reserved servers have no Server Admins.

	Separate from AdminConfig (Game Admins).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local MAX_APPOINTED = 25
local MAX_RETRIES = 5

local ServerAdmins = {}

local isPrivateServer = game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0
local ownerId = game.PrivateServerOwnerId
local appointed = {} -- [userId] = true
local store = nil
if isPrivateServer then
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, "ServerAdmins_v1")
	store = ok and result or nil
end

local function withRetries(label, fn)
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(("[ServerAdmins] %s failed (%d/%d): %s"):format(label, attempt, MAX_RETRIES, tostring(result)))
		if attempt < MAX_RETRIES then
			task.wait(math.min(2 ^ attempt, 16))
		end
	end
	return false
end

local function refreshAttribute(player)
	player:SetAttribute("IsServerAdmin", ServerAdmins.IsServerAdmin(player))
	player:SetAttribute("IsServerOwner", ServerAdmins.IsOwner(player))
end

local function save()
	if not store then
		return
	end
	local list = ServerAdmins.List()
	task.spawn(withRetries, "Save", function()
		store:UpdateAsync(game.PrivateServerId, function()
			return list
		end)
	end)
end

function ServerAdmins.IsPrivateServer()
	return isPrivateServer
end

function ServerAdmins.IsOwner(player)
	return isPrivateServer and player.UserId == ownerId
end

function ServerAdmins.IsServerAdmin(player)
	return isPrivateServer and (player.UserId == ownerId or appointed[player.UserId] == true)
end

function ServerAdmins.List()
	local list = {}
	for id in pairs(appointed) do
		table.insert(list, id)
	end
	table.sort(list)
	return list
end

-- Only the private server owner may appoint or remove admins.
function ServerAdmins.Appoint(caller, userId)
	if not ServerAdmins.IsOwner(caller) then
		return false, "Only the private server owner can appoint admins."
	end
	if type(userId) ~= "number" or userId ~= userId or userId <= 0 or userId % 1 ~= 0 then
		return false, "Invalid player."
	end
	if userId == ownerId then
		return false, "You are already the owner."
	end
	if appointed[userId] then
		return false, "Already a Server Admin."
	end
	if #ServerAdmins.List() >= MAX_APPOINTED then
		return false, ("You can appoint up to %d admins."):format(MAX_APPOINTED)
	end
	appointed[userId] = true
	save()
	local target = Players:GetPlayerByUserId(userId)
	if target then
		refreshAttribute(target)
	end
	return true, "Server Admin appointed."
end

function ServerAdmins.Remove(caller, userId)
	if not ServerAdmins.IsOwner(caller) then
		return false, "Only the private server owner can remove admins."
	end
	if type(userId) ~= "number" or not appointed[userId] then
		return false, "That player is not a Server Admin."
	end
	appointed[userId] = nil
	save()
	local target = Players:GetPlayerByUserId(userId)
	if target then
		refreshAttribute(target)
	end
	return true, "Server Admin removed."
end

-- Load appointed admins for this private server.
if store then
	task.spawn(function()
		local ok, list = withRetries("Load", function()
			return store:GetAsync(game.PrivateServerId)
		end)
		if ok and type(list) == "table" then
			for _, id in ipairs(list) do
				if type(id) == "number" then
					appointed[id] = true
				end
			end
		end
		for _, plr in ipairs(Players:GetPlayers()) do
			refreshAttribute(plr)
		end
	end)
end

Players.PlayerAdded:Connect(refreshAttribute)
for _, plr in ipairs(Players:GetPlayers()) do
	refreshAttribute(plr)
end

return ServerAdmins
