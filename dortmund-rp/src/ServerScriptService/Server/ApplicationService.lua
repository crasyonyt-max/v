--!strict
-- Applications (Config.Applications, "test" = testing server only): players apply as
-- Admin or Official Content Creator in the "Bewerbungen" phone app (7-12 sentences:
-- why, what they would do, when they are online, their age, how they feel about the
-- game). Reviewers (Owner, Co-Owners, AA) read them in the Admin app and accept /
-- decline, with or without a reason. The applicant gets the answer as a notification
-- and as a ChatsApp message from the admin team (also when offline).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ChatService = require(script.Parent.ChatService)
local DataStoreService = require(script.Parent.Sandbox).DataStoreService -- local only on the testing server
local GameLog = require(script.Parent.GameLog)
local Remotes = require(script.Parent.Remotes)
local Roles = require(script.Parent.Roles)

local ApplicationService = {}

ApplicationService.ROLES = { admin = "Admin", creator = "Official Content Creator" }
ApplicationService.MIN_SENTENCES = 7
ApplicationService.MAX_SENTENCES = 12
ApplicationService.MAX_CHARS = 2500
ApplicationService.KEEP = 300
ApplicationService.RETRY = 24 * 3600 -- after a decision you can apply for that role again after a day

export type Application = {
	id: string,
	userId: number,
	name: string,
	role: string,
	text: string,
	t: number,
	status: string, -- "open" | "accepted" | "declined"
	reason: string?,
	by: string?,
	decided: number?,
}

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName .. "_Applications")
end)
local memory: { Application } = {} -- when there are no DataStores (Studio / tests)

-- sentences = runs of text that end in . ! or ? ("..." counts once)
function ApplicationService.CountSentences(text: string): number
	local n = 0
	for chunk in string.gmatch(text, "[^%.!%?]+[%.!%?]+") do
		if string.find(chunk, "%a") then
			n += 1
		end
	end
	return n
end

-- nil = fine, otherwise the error key
function ApplicationService.Check(role: any, text: any): string?
	if typeof(role) ~= "string" or not ApplicationService.ROLES[role] then
		return "bad_request"
	end
	if typeof(text) ~= "string" or #text > ApplicationService.MAX_CHARS then
		return "apply_too_long"
	end
	local n = ApplicationService.CountSentences(text)
	if n < ApplicationService.MIN_SENTENCES then
		return "apply_too_short"
	end
	if n > ApplicationService.MAX_SENTENCES then
		return "apply_too_long"
	end
	return nil
end

function ApplicationService.MayReview(p: Player): boolean
	return Roles.Rank(p) >= Roles.CO_OWNER or Roles.HasAA(p)
end

local function update(fn: ({ Application }) -> { Application }?): { Application }?
	if not store then
		local out = fn(memory)
		if out then
			memory = out
		end
		return memory
	end
	local result: { Application }? = nil
	local ok = pcall(function()
		(store :: DataStore):UpdateAsync("list", function(old: any)
			local list = if typeof(old) == "table" then old else {}
			local out = fn(list)
			result = out or list
			return out
		end)
	end)
	return if ok then result else nil
end

local function read(): { Application }
	if not store then
		return memory
	end
	local ok, list = pcall(function()
		return (store :: DataStore):GetAsync("list")
	end)
	return if ok and typeof(list) == "table" then list else {}
end

local function filter(text: string, userId: number): string?
	return ChatService.Filter(text, userId)
end

function ApplicationService.Start()
	if not Config.On(Config.Applications) then
		return
	end

	Remotes.Handle("Apply.Submit", function(player, role: any, text: any)
		local err = ApplicationService.Check(role, text)
		if err then
			return Remotes.Fail(err)
		end
		local clean = filter(text, player.UserId)
		if not clean then
			return Remotes.Fail("filter_failed")
		end
		local now = os.time()
		local refused: string? = nil
		local list = update(function(list)
			for _, a in list do
				if a.userId == player.UserId and a.role == role then
					if a.status == "open" then
						refused = "apply_open"
						return nil
					elseif now - (a.decided or a.t) < ApplicationService.RETRY then
						refused = "apply_wait"
						return nil
					end
				end
			end
			table.insert(list, {
				id = string.sub(HttpService:GenerateGUID(false), 1, 8),
				userId = player.UserId,
				name = player.Name,
				role = role,
				text = clean,
				t = now,
				status = "open",
			})
			while #list > ApplicationService.KEEP do
				table.remove(list, 1)
			end
			return list
		end)
		if refused then
			return Remotes.Fail(refused)
		end
		if not list then
			return Remotes.Fail("error")
		end
		GameLog.Add("admin", player, "applied as " .. ApplicationService.ROLES[role])
		-- tell the reviewers who are online
		for _, p in Players:GetPlayers() do
			if ApplicationService.MayReview(p) then
				Remotes.Push(
					p,
					"Notify",
					{ key = "apply_new", args = { player.DisplayName, ApplicationService.ROLES[role] } }
				)
			end
		end
		return Remotes.Ok()
	end, { rate = 2 })

	Remotes.Handle("Apply.Mine", function(player)
		local out = {}
		for _, a in read() do
			if a.userId == player.UserId then
				table.insert(out, { role = a.role, status = a.status, reason = a.reason, t = a.t })
			end
		end
		return Remotes.Ok({ list = out })
	end, { rate = 4 })

	Remotes.Handle("Apply.List", function(player)
		if not ApplicationService.MayReview(player) then
			return Remotes.Fail("no_permission")
		end
		local list = table.clone(read())
		table.sort(list, function(a, b)
			if (a.status == "open") ~= (b.status == "open") then
				return a.status == "open"
			end
			return a.t > b.t
		end)
		return Remotes.Ok({ list = list })
	end, { rate = 4 })

	-- accept / decline, with an optional reason (filtered)
	Remotes.Handle("Apply.Decide", function(player, id: any, accept: any, reason: any)
		if not ApplicationService.MayReview(player) then
			return Remotes.Fail("no_permission")
		end
		if typeof(id) ~= "string" or typeof(accept) ~= "boolean" then
			return Remotes.Fail("bad_request")
		end
		local why: string? = nil
		if typeof(reason) == "string" and reason ~= "" then
			why = filter(string.sub(reason, 1, 400), player.UserId)
			if not why then
				return Remotes.Fail("filter_failed")
			end
		end
		local decided: Application? = nil
		update(function(list)
			for _, a in list do
				if a.id == id and a.status == "open" then
					a.status = if accept then "accepted" else "declined"
					a.reason = why
					a.by = player.DisplayName
					a.decided = os.time()
					decided = a
					return list
				end
			end
			return nil
		end)
		local a = decided
		if not a then
			return Remotes.Fail("apply_gone")
		end
		local roleName = ApplicationService.ROLES[a.role] or a.role
		local msg = (if accept
			then "✅ Deine Bewerbung als %s wurde angenommen!"
			else "❌ Deine Bewerbung als %s wurde abgelehnt."):format(roleName) .. (if why
			then " Grund: " .. why
			else "")
		pcall(ChatService.SendToUser, a.userId, Config.AdminChatNumber, "Admin-Team", msg)
		local applicant = Players:GetPlayerByUserId(a.userId)
		if applicant then
			Remotes.Push(
				applicant,
				"Notify",
				{ key = if accept then "apply_accepted" else "apply_declined", args = { roleName }, error = not accept }
			)
		end
		GameLog.Add(
			"admin",
			player,
			("%s application of %s (%s)%s"):format(
				if accept then "accepted" else "declined",
				a.name,
				roleName,
				if why then ": " .. why else ""
			)
		)
		return Remotes.Ok()
	end, { rate = 6 })
end

return ApplicationService
