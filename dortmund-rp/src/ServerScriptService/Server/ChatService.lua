--!strict
-- ChatsApp: player-to-player messages (any server, delivered offline via inbox)
-- and the admin hotline 23646, which reaches every Game Admin.
-- All text is filtered with TextService before anyone else sees it.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Config)
local GameLog = require(script.Parent.GameLog)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local Roles = require(script.Parent.Roles)
local State = require(script.Parent.State)

local ChatService = {}

local MAX_LEN = 300
local MAX_STORED = 100
local ADMIN_INBOX_KEY = "admin_inbox"

local inboxStore: DataStore? = nil
pcall(function()
	inboxStore = DataStoreService:GetDataStore(Config.DataStoreName .. "_Inbox")
end)

-- Filter text from `fromUserId` for display to anyone.
function ChatService.Filter(text: string, fromUserId: number): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else nil
end

local function append(data: { [string]: any }, msg: { [string]: any })
	table.insert(data.messages, msg)
	while #data.messages > MAX_STORED do
		table.remove(data.messages, 1)
	end
end

local function deliverLocal(player: Player, msg: { [string]: any })
	local data = DataService.Get(player)
	if not data then
		return false
	end
	append(data, msg)
	State.MarkDirty(player)
	Remotes.Push(player, "Message", msg)
	return true
end

-- Move everything waiting in this player's offline inbox into their profile.
local function pullInbox(player: Player)
	if not inboxStore or not DataService.IsLoaded(player) then
		return
	end
	local taken: { any } = {}
	local ok = pcall(function()
		(inboxStore :: DataStore):UpdateAsync("u_" .. player.UserId, function(old: any)
			if typeof(old) ~= "table" or #old == 0 then
				taken = {}
				return nil
			end
			taken = old
			return {}
		end)
	end)
	if ok then
		for _, msg in taken do
			deliverLocal(player, msg)
		end
	end
end

local function pushInbox(userId: number, msg: { [string]: any }): boolean
	if not inboxStore then
		return false
	end
	local ok = pcall(function()
		(inboxStore :: DataStore):UpdateAsync("u_" .. userId, function(old: any)
			local list = if typeof(old) == "table" then old else {}
			table.insert(list, msg)
			while #list > 50 do
				table.remove(list, 1)
			end
			return list
		end)
	end)
	if ok then
		pcall(function()
			MessagingService:PublishAsync("ChatsApp", { to = userId })
		end)
	end
	return ok
end

-- Sends a message to a user anywhere. `fromNumber`/`fromName` describe the sender.
function ChatService.SendToUser(toUserId: number, fromNumber: string, fromName: string, text: string): boolean
	local msg = {
		peer = fromNumber,
		peerName = fromName,
		text = text,
		t = os.time(),
		out = false,
		id = HttpService:GenerateGUID(false),
	}
	local target = Players:GetPlayerByUserId(toUserId)
	if target and deliverLocal(target, msg) then
		return true
	end
	return pushInbox(toUserId, msg)
end

-- Admin hotline inbox (shared by all Game Admins).
function ChatService.AdminInbox(): { any }
	if not inboxStore then
		return {}
	end
	local ok, list = pcall(function()
		return (inboxStore :: DataStore):GetAsync(ADMIN_INBOX_KEY)
	end)
	return if ok and typeof(list) == "table" then list else {}
end

local function toAdmins(player: Player, text: string)
	local entry = {
		id = HttpService:GenerateGUID(false),
		fromUserId = player.UserId,
		fromName = player.Name,
		number = State.PhoneNumber(player.UserId),
		text = text,
		t = os.time(),
		server = game.JobId,
	}
	if inboxStore then
		pcall(function()
			(inboxStore :: DataStore):UpdateAsync(ADMIN_INBOX_KEY, function(old: any)
				local list = if typeof(old) == "table" then old else {}
				table.insert(list, entry)
				while #list > 200 do
					table.remove(list, 1)
				end
				return list
			end)
		end)
	end
	pcall(function()
		MessagingService:PublishAsync("AdminChat", entry)
	end)
	-- Also notify Game Admins in this server immediately (MessagingService may lag).
	for _, admin in Players:GetPlayers() do
		if Roles.IsGameAdmin(admin) then
			Remotes.Push(admin, "AdminChat", entry)
		end
	end
end

function ChatService.Start()
	DataService.Loaded:Connect(function(player)
		task.spawn(pullInbox, player)
	end)

	pcall(function()
		MessagingService:SubscribeAsync("ChatsApp", function(packet)
			local data = packet.Data
			if typeof(data) == "table" and typeof(data.to) == "number" then
				local player = Players:GetPlayerByUserId(data.to)
				if player then
					pullInbox(player)
				end
			end
		end)
	end)
	pcall(function()
		MessagingService:SubscribeAsync("AdminChat", function(packet)
			local entry = packet.Data
			if typeof(entry) ~= "table" or entry.server == game.JobId then
				return
			end
			for _, admin in Players:GetPlayers() do
				if Roles.IsGameAdmin(admin) then
					Remotes.Push(admin, "AdminChat", entry)
				end
			end
		end)
	end)

	-- Safety net in case a MessagingService ping is lost.
	task.spawn(function()
		while true do
			task.wait(180)
			for _, player in Players:GetPlayers() do
				task.spawn(pullInbox, player)
				task.wait(0.5)
			end
		end
	end)

	Remotes.Handle("Chat.Send", function(player, number: any, text: any)
		local Check = Remotes.Check
		local to = Check.String(number, 20)
		local body = Check.String(text, MAX_LEN)
		if not to or not body then
			return Remotes.Fail("bad_message")
		end
		to = string.gsub(to, "[%s%-/]", "")
		local filtered = ChatService.Filter(body, player.UserId)
		if not filtered then
			return Remotes.Fail("filter_failed")
		end
		local data = DataService.Get(player) :: { [string]: any }
		local myNumber = State.PhoneNumber(player.UserId)

		GameLog.Add("chat", player, "to " .. to .. ": " .. filtered)
		if to == Config.AdminChatNumber then
			toAdmins(player, filtered)
			append(data, {
				peer = to,
				peerName = "Admin-Team",
				text = filtered,
				t = os.time(),
				out = true,
				id = HttpService:GenerateGUID(false),
			})
			State.MarkDirty(player)
			return Remotes.Ok()
		end

		local targetId = State.UserIdFromNumber(to)
		if not targetId or targetId == player.UserId then
			return Remotes.Fail("bad_number")
		end
		local targetName = "?"
		local okName, name = pcall(function()
			return Players:GetNameFromUserIdAsync(targetId)
		end)
		if not okName then
			return Remotes.Fail("bad_number")
		end
		targetName = name
		if not ChatService.SendToUser(targetId, myNumber, player.Name, filtered) then
			return Remotes.Fail("send_failed")
		end
		append(data, {
			peer = to,
			peerName = targetName,
			text = filtered,
			t = os.time(),
			out = true,
			id = HttpService:GenerateGUID(false),
		})
		State.MarkDirty(player)
		return Remotes.Ok()
	end, { rate = 8 })
end

return ChatService
