--!strict
-- Admin system (used by the phone's Admin app). Every action is checked and logged here.
--
--   Game Admin   : whole game. Global bans, global announcements, shutdown all servers,
--                  give money / XP / cars (Game Admins ONLY).
--   Server Admin : private server owner + people they appoint. Same moderation tools,
--                  but only on their own server (bans = server bans). No giving.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Jobs = require(ReplicatedStorage.Shared.Jobs)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local ChatService = require(script.Parent.ChatService)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local Remotes = require(script.Parent.Remotes)
local Roles = require(script.Parent.Roles)
local State = require(script.Parent.State)
local VehicleService = require(script.Parent.VehicleService)
local WorldService = require(script.Parent.WorldService)
local XPService = require(script.Parent.XPService)
local NewsService = require(script.Parent.NewsService)
local EventService = require(script.Parent.EventService)
local AdminTowerService = require(script.Parent.AdminTowerService)
local Boosts = require(script.Parent.Boosts)
local DropEvents = require(ReplicatedStorage.Shared.DropEvents)
local VoteService = require(script.Parent.VoteService)
local Locations = require(ReplicatedStorage.Shared.Locations)

local AdminService = {}

local logStore: DataStore? = nil
local serverBanStore: DataStore? = nil
pcall(function()
	logStore = DataStoreService:GetDataStore(Config.DataStoreName .. "_AdminLog")
	serverBanStore = DataStoreService:GetDataStore(Config.DataStoreName .. "_ServerBans")
end)

local localLog: { any } = {}
local serverBans: { [number]: { reason: string, by: string } } = {}
local shuttingDown = false

local GA = Roles.GAME_ADMIN
local SA = Roles.SERVER_ADMIN

-- Minimum rank per action.
local ACTIONS: { [string]: number } = {
	kick = SA,
	ban = SA,
	unban = SA,
	fly = SA,
	noclip = SA,
	god = SA,
	freeze = SA,
	tp_to = SA,
	bring = SA,
	detain = GA,
	release = GA,
	spectate = SA,
	spawn_vehicle = SA,
	announce = SA,
	shutdown = SA,
	time = SA,
	weather = SA,
	appoint = Roles.SERVER_OWNER,
	give_money = GA,
	give_xp = GA,
	give_vehicle = GA,
	reply = GA,
	news_post = GA,
	news_delete = GA,
	vote_start = SA,
	vote_end = SA,
	-- AA: Owner + both Co-Owner ranks
	aa_boost = Roles.SECOND_CO_OWNER,
	aa_boost_stop = Roles.SECOND_CO_OWNER,
	aa_gift = Roles.SECOND_CO_OWNER,
	aa_drop = Roles.SECOND_CO_OWNER,
	aa_drop_remove = Roles.SECOND_CO_OWNER,
	aa_music_play = Roles.SECOND_CO_OWNER,
	aa_music_stop = Roles.SECOND_CO_OWNER,
	aa_default_music = Roles.SECOND_CO_OWNER,
	aa_countdown = Roles.SECOND_CO_OWNER,
	aa_drop_event = Roles.SECOND_CO_OWNER,
	aa_droppers = Roles.SECOND_CO_OWNER,
	aa_countdown_stop = Roles.SECOND_CO_OWNER,
	aa_song_add = Roles.SECOND_CO_OWNER,
	aa_song_remove = Roles.SECOND_CO_OWNER,
}

local function log(actor: Player, action: string, detail: string, global: boolean)
	local entry = {
		t = os.time(),
		actor = actor.Name,
		actorId = actor.UserId,
		action = action,
		detail = detail,
		server = string.sub(game.JobId, 1, 8),
		private = Roles.IsPrivateServer(),
	}
	table.insert(localLog, entry)
	while #localLog > 300 do
		table.remove(localLog, 1)
	end
	print(string.format("[Admin] %s: %s %s", actor.Name, action, detail))
	if global and logStore then
		task.spawn(function()
			local day = os.date("!%Y-%m-%d") :: string
			pcall(function()
				(logStore :: DataStore):UpdateAsync("log_" .. day, function(old: any)
					local list = if typeof(old) == "table" then old else {}
					table.insert(list, entry)
					while #list > 1000 do
						table.remove(list, 1)
					end
					return list
				end)
			end)
		end)
	end
end

local function rootOf(player: Player): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoidOf(player: Player): Humanoid?
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function targetPlayer(actor: Player, args: any): (Player?, string?)
	local id = typeof(args) == "table" and Remotes.Check.Int(args.userId, 1, 1e12) or nil
	if not id then
		return nil, "bad_target"
	end
	local target = Players:GetPlayerByUserId(id)
	if not target then
		return nil, "target_offline"
	end
	if not Roles.CanTarget(actor, target) then
		return nil, "no_permission"
	end
	return target, nil
end

local function serverBanKey(): string?
	if game.PrivateServerId ~= "" then
		return "sb_" .. game.PrivateServerId
	end
	return nil
end

local function saveServerBans()
	local k = serverBanKey()
	if not k or not serverBanStore then
		return
	end
	local list = {}
	for id, info in serverBans do
		list[tostring(id)] = info
	end
	pcall(function()
		(serverBanStore :: DataStore):SetAsync(k, list)
	end)
end

local function loadServerBans()
	local k = serverBanKey()
	if not k or not serverBanStore then
		return
	end
	local ok, list = pcall(function()
		return (serverBanStore :: DataStore):GetAsync(k)
	end)
	if ok and typeof(list) == "table" then
		for id, info in list do
			local n = tonumber(id)
			if n then
				serverBans[n] = info
			end
		end
	end
end

local function resolveUserId(args: any): number?
	if typeof(args) ~= "table" then
		return nil
	end
	local id = Remotes.Check.Int(args.userId, 1, 1e12)
	if id then
		return id
	end
	local name = Remotes.Check.String(args.name, 20)
	if name then
		local ok, result = pcall(function()
			return Players:GetUserIdFromNameAsync(name)
		end)
		if ok then
			return result
		end
	end
	return nil
end

local function filterAnnouncement(actor: Player, text: any): string?
	local body = Remotes.Check.String(text, 200)
	if not body then
		return nil
	end
	return ChatService.Filter(body, actor.UserId)
end

local function doShutdownLocal(reason: string)
	if shuttingDown then
		return
	end
	shuttingDown = true
	Remotes.PushAll("Announce", { text = reason, from = "System" })
	task.wait(5)
	for _, p in Players:GetPlayers() do
		p:Kick(reason)
	end
end

-- Handlers ------------------------------------------------------------------
local handlers: { [string]: (Player, any, boolean) -> (boolean, string?, any?) } = {}

handlers.kick = function(actor, args)
	local target, err = targetPlayer(actor, args)
	if not target then
		return false, err
	end
	local reason = (typeof(args.reason) == "string" and string.sub(args.reason, 1, 120)) or "Gekickt von einem Admin"
	log(actor, "kick", target.Name .. " – " .. reason, false)
	target:Kick("Du wurdest gekickt / You were kicked: " .. reason)
	return true
end

handlers.ban = function(actor, args, isGA)
	local userId = resolveUserId(args)
	if not userId then
		return false, "bad_target"
	end
	if not Roles.CanTargetUserId(actor, userId) then
		return false, "no_permission"
	end
	local minutes = Remotes.Check.Int(args.minutes, 0, 525600 * 10) or 0
	local reason = (typeof(args.reason) == "string" and string.sub(args.reason, 1, 200)) or "Regelverstoß"
	if isGA then
		local ok, err = pcall(function()
			Players:BanAsync({
				UserIds = { userId },
				ApplyToUniverse = true,
				Duration = if minutes == 0 then -1 else minutes * 60,
				DisplayReason = reason,
				PrivateReason = "Banned by " .. actor.Name .. " (" .. actor.UserId .. ")",
				ExcludeAltAccounts = false,
			})
		end)
		if not ok then
			warn("[Admin] BanAsync failed: " .. tostring(err))
			return false, "ban_failed"
		end
		log(
			actor,
			"ban (global)",
			string.format("%d, %s, %s", userId, if minutes == 0 then "permanent" else minutes .. " min", reason),
			true
		)
	else
		serverBans[userId] = { reason = reason, by = actor.Name }
		task.spawn(saveServerBans)
		local target = Players:GetPlayerByUserId(userId)
		if target then
			target:Kick("Du wurdest von diesem Server gebannt / Banned from this server: " .. reason)
		end
		log(actor, "ban (server)", string.format("%d, %s", userId, reason), false)
	end
	return true
end

handlers.unban = function(actor, args, isGA)
	local userId = resolveUserId(args)
	if not userId then
		return false, "bad_target"
	end
	if isGA and args.global ~= false then
		local ok = pcall(function()
			Players:UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })
		end)
		if not ok then
			return false, "ban_failed"
		end
		log(actor, "unban (global)", tostring(userId), true)
	end
	if serverBans[userId] then
		serverBans[userId] = nil
		task.spawn(saveServerBans)
		log(actor, "unban (server)", tostring(userId), false)
	end
	return true
end

local function toggleSelf(attr: string)
	return function(actor: Player)
		local on = not actor:GetAttribute(attr)
		actor:SetAttribute(attr, on)
		log(actor, attr, if on then "on" else "off", false)
		return true, nil, { on = on }
	end
end
handlers.fly = toggleSelf("AdminFly")
handlers.noclip = toggleSelf("AdminNoclip")

handlers.god = function(actor, args)
	local target, err = targetPlayer(actor, args)
	if not target then
		return false, err
	end
	local on = not target:GetAttribute("God")
	target:SetAttribute("God", on)
	local hum = humanoidOf(target)
	if hum and on then
		hum.Health = hum.MaxHealth
	end
	log(actor, "god", target.Name .. (if on then " on" else " off"), false)
	return true, nil, { on = on }
end

handlers.freeze = function(actor, args)
	local target, err = targetPlayer(actor, args)
	if not target then
		return false, err
	end
	local on = not target:GetAttribute("Frozen")
	target:SetAttribute("Frozen", on)
	local root = rootOf(target)
	if root then
		root.Anchored = on
	end
	log(actor, "freeze", target.Name .. (if on then " on" else " off"), false)
	return true, nil, { on = on }
end

-- Any admin may teleport to anyone, whatever their rank.
handlers.tp_to = function(actor, args)
	local id = typeof(args) == "table" and Remotes.Check.Int(args.userId, 1, 1e12) or nil
	local target = id and Players:GetPlayerByUserId(id)
	if not target then
		return false, if id then "target_offline" else "bad_target"
	end
	local from, to = rootOf(actor), rootOf(target)
	if not from or not to then
		return false, "no_character"
	end
	local hum = humanoidOf(actor)
	if hum then
		hum.Sit = false
	end
	(actor.Character :: Model):PivotTo(to.CFrame * CFrame.new(0, 0, 4))
	log(actor, "tp_to", target.Name, false)
	return true
end

-- Any admin may bring anyone, whatever their rank (bringing is harmless).
handlers.bring = function(actor, args)
	local id = typeof(args) == "table" and Remotes.Check.Int(args.userId, 1, 1e12) or nil
	local target = id and Players:GetPlayerByUserId(id)
	if not target then
		return false, if id then "target_offline" else "bad_target"
	end
	local from, to = rootOf(target), rootOf(actor)
	if not from or not to then
		return false, "no_character"
	end
	local hum = humanoidOf(target)
	if hum then
		hum.Sit = false
	end
	(target.Character :: Model):PivotTo(to.CFrame * CFrame.new(0, 0, -4))
	log(actor, "bring", target.Name, false)
	return true
end

-- Admin Tower "Sonderraum": put a player in / let them out
handlers.detain = function(actor, args)
	local target, err = targetPlayer(actor, args)
	if not target then
		return false, err
	end
	if target == actor then
		return false, "bad_target"
	end
	AdminTowerService.Detain(target)
	log(actor, "detain", target.Name, true)
	return true
end

handlers.release = function(actor, args)
	local id = typeof(args) == "table" and Remotes.Check.Int(args.userId, 1, 1e12) or nil
	local target = id and Players:GetPlayerByUserId(id)
	if not target then
		return false, if id then "target_offline" else "bad_target"
	end
	AdminTowerService.Release(target)
	log(actor, "release", target.Name, true)
	return true
end

handlers.spectate = function(actor, args)
	local target, err = targetPlayer(actor, args)
	if not target then
		return false, err
	end
	log(actor, "spectate", target.Name, false)
	return true, nil, { userId = target.UserId }
end

handlers.spawn_vehicle = function(actor, args, isGA)
	local id = typeof(args) == "table" and args.vehicleId
	local def = typeof(id) == "string" and Vehicles.ById[id] or nil
	if not def then
		return false, "bad_item"
	end
	if def.adminLevel == "Game" and not isGA then
		return false, "no_permission"
	end
	local ok, err = VehicleService.SpawnAny(actor, def.id)
	if ok then
		log(actor, "spawn_vehicle", def.name, false)
	end
	return ok, err
end

handlers.announce = function(actor, args, isGA)
	local text = filterAnnouncement(actor, args and args.text)
	if not text then
		return false, "bad_message"
	end
	local global = isGA and args.global == true
	local packet = { text = text, from = actor.DisplayName, server = game.JobId }
	Remotes.PushAll("Announce", packet)
	if global then
		pcall(function()
			MessagingService:PublishAsync("Announce", packet)
		end)
	end
	log(actor, if global then "announce (global)" else "announce", text, global)
	return true
end

-- Votes on this server ----------------------------------------------------------
handlers.vote_start = function(actor, args)
	if typeof(args) ~= "table" or typeof(args.options) ~= "table" then
		return false, "bad_request"
	end
	local question = Remotes.Check.String(args.question, 120)
	local minutes = Remotes.Check.Int(args.minutes, 1, 120)
	if not question or not minutes then
		return false, "bad_request"
	end
	local options = {}
	for i = 1, 4 do
		local o = args.options[i]
		if typeof(o) == "string" and #o > 0 then
			local text = Remotes.Check.String(o, 40)
			if not text then
				return false, "bad_request"
			end
			table.insert(options, text)
		end
	end
	if #options < 2 then
		return false, "vote_need_two"
	end
	local fq = ChatService.Filter(question, actor.UserId)
	if not fq then
		return false, "bad_message"
	end
	for i, o in options do
		local f = ChatService.Filter(o, actor.UserId)
		if not f then
			return false, "bad_message"
		end
		options[i] = f
	end
	if not VoteService.Begin(fq, options, minutes, actor.DisplayName) then
		return false, "vote_running"
	end
	log(actor, "vote_start", fq, false)
	return true
end

handlers.vote_end = function(actor)
	if not VoteService.End() then
		return false, "no_vote"
	end
	log(actor, "vote_end", "", false)
	return true
end

-- AA events (all servers) ------------------------------------------------------------
handlers.aa_boost = function(actor, args)
	local kind = typeof(args) == "table" and Remotes.Check.OneOf(args.kind, { "cash", "xp" }) or nil
	local mult = typeof(args) == "table" and Remotes.Check.Number(args.mult, 2, 10) or nil
	local minutes = typeof(args) == "table" and Remotes.Check.Int(args.minutes, 1, 1440) or nil
	if not kind or not mult or not minutes then
		return false, "bad_request"
	end
	mult = math.floor(mult * 10 + 0.5) / 10
	if not EventService.SetBoost(kind, mult, minutes) then
		return false, "error"
	end
	log(actor, "aa_boost", string.format("%s %gx %d min", kind, mult, minutes), true)
	return true
end

handlers.aa_boost_stop = function(actor, args)
	local kind = typeof(args) == "table" and Remotes.Check.OneOf(args.kind, { "cash", "xp" }) or nil
	if not kind or not EventService.StopBoost(kind) then
		return false, "bad_request"
	end
	log(actor, "aa_boost_stop", kind, true)
	return true
end

handlers.aa_gift = function(actor, args)
	local kind = typeof(args) == "table" and args.kind or nil
	local value = EventService.CheckReward(kind, typeof(args) == "table" and args.value or nil)
	if value == nil then
		return false, "bad_request"
	end
	EventService.Gift(kind, value)
	log(actor, "aa_gift", EventService.RewardName(kind, value), true)
	return true
end

handlers.aa_drop = function(actor, args)
	if typeof(args) ~= "table" then
		return false, "bad_request"
	end
	local b = Locations.Bounds
	local x = Remotes.Check.Number(args.x, b[1], b[3])
	local z = Remotes.Check.Number(args.z, b[2], b[4])
	local minutes = Remotes.Check.Int(args.minutes, 1, 1440)
	local value = EventService.CheckReward(args.kind, args.value)
	if not x or not z or not minutes or value == nil then
		return false, "bad_request"
	end
	local ok, err = EventService.AddDrop(x, z, args.kind, value, minutes)
	if not ok then
		return false, err or "error"
	end
	log(
		actor,
		"aa_drop",
		string.format("%s at %d, %d (%d min)", EventService.RewardName(args.kind, value), x, z, minutes),
		true
	)
	return true
end

handlers.aa_drop_remove = function(actor, args)
	local id = typeof(args) == "table" and Remotes.Check.String(args.id, 16) or nil
	if not id or not EventService.RemoveDrop(id) then
		return false, "bad_request"
	end
	log(actor, "aa_drop_remove", id, true)
	return true
end

-- AA music: plays on every server --------------------------------------------------
local function audioId(v: any): number?
	local n = tonumber(if typeof(v) == "string" then string.match(v, "%d+") else v)
	if n and n >= 1 and n < 1e15 and n == math.floor(n) then
		return n
	end
	return nil
end

handlers.aa_music_play = function(actor, args)
	local id = typeof(args) == "table" and audioId(args.id) or nil
	if not id then
		return false, "bad_audio"
	end
	local volume = Remotes.Check.Number(args.volume, 0, 1) or 0.5
	local ok, err = EventService.PlayMusic(id, volume, args.loop == true)
	if not ok then
		return false, err or "error"
	end
	log(actor, "aa_music_play", tostring(id), true)
	return true
end

handlers.aa_music_stop = function(actor)
	if not EventService.StopMusic() then
		return false, "error"
	end
	log(actor, "aa_music_stop", "", true)
	return true
end

-- Countdown: date "TT.MM.JJJJ" (empty = today, or tomorrow if the time has passed)
-- and time "HH:MM", both in Berlin time.
handlers.aa_countdown = function(actor, args)
	if typeof(args) ~= "table" then
		return false, "bad_request"
	end
	local h, mi = string.match(tostring(args.time or ""), "^%s*(%d%d?)[:%.](%d%d)%s*$")
	local hour, minute = tonumber(h), tonumber(mi)
	if not hour or not minute or hour > 23 or minute > 59 then
		return false, "bad_time"
	end
	local now = os.time()
	local d, m, y = string.match(tostring(args.date or ""), "^%s*(%d%d?)%.(%d%d?)%.(%d%d%d%d)%s*$")
	local at: number
	if d then
		local day, month, year = tonumber(d) :: number, tonumber(m) :: number, tonumber(y) :: number
		if month < 1 or month > 12 or day < 1 or day > 31 then
			return false, "bad_date"
		end
		at = Boosts.FromBerlin(year, month, day, hour, minute)
	elseif string.match(tostring(args.date or ""), "%S") then
		return false, "bad_date"
	else
		local localNow = now + Boosts.BerlinOffset(now)
		local year = tonumber(os.date("!%Y", localNow)) :: number
		local month = tonumber(os.date("!%m", localNow)) :: number
		local day = tonumber(os.date("!%d", localNow)) :: number
		at = Boosts.FromBerlin(year, month, day, hour, minute)
		if at <= now then
			at += 86400 -- already passed today: tomorrow
		end
	end
	if at <= now or at > now + 366 * 86400 then
		return false, "bad_date"
	end
	local title = Remotes.Check.String(args.title, 40) or "AA"
	local filtered = ChatService.Filter(title, actor.UserId)
	if not filtered then
		return false, "bad_message"
	end
	if not EventService.SetCountdown(filtered, at) then
		return false, "error"
	end
	log(actor, "aa_countdown", filtered .. " @ " .. os.date("!%Y-%m-%d %H:%M UTC", at), true)
	return true
end

-- dropper event on every server, for `minutes` ("" = stop)
handlers.aa_drop_event = function(actor, args)
	local id = typeof(args) == "table" and args.id or nil
	if id == "" then
		if not EventService.SetDropEvent(nil) then
			return false, "error"
		end
		log(actor, "aa_drop_event_stop", "", true)
		return true
	end
	local minutes = typeof(args) == "table" and Remotes.Check.Int(args.minutes, 1, 1440) or nil
	if typeof(id) ~= "string" or not DropEvents.ById[id] or not minutes then
		return false, "bad_request"
	end
	if not EventService.SetDropEvent(id, minutes) then
		return false, "error"
	end
	log(actor, "aa_drop_event", string.format("%s %d min", id, minutes), true)
	return true
end

-- dropper tycoons in the apartments on / off (every server)
handlers.aa_droppers = function(actor, args)
	local on = typeof(args) == "table" and args.on == true
	if not EventService.SetDroppers(on) then
		return false, "error"
	end
	log(actor, if on then "aa_droppers_on" else "aa_droppers_off", "", true)
	return true
end

handlers.aa_countdown_stop = function(actor)
	if not EventService.ClearCountdown() then
		return false, "error"
	end
	log(actor, "aa_countdown_stop", "", true)
	return true
end

handlers.aa_default_music = function(actor, args)
	local on = typeof(args) == "table" and args.on == true
	if not EventService.SetDefaultMusic(on) then
		return false, "error"
	end
	log(actor, if on then "aa_default_music_start" else "aa_default_music_stop", "", true)
	return true
end

handlers.aa_song_add = function(actor, args)
	local id = typeof(args) == "table" and audioId(args.id) or nil
	if not id then
		return false, "bad_audio"
	end
	local ok, err = EventService.AddSong(id)
	if not ok then
		return false, err or "error"
	end
	log(actor, "aa_song_add", tostring(id), true)
	return true
end

handlers.aa_song_remove = function(actor, args)
	local id = typeof(args) == "table" and audioId(args.id) or nil
	if not id or not EventService.RemoveSong(id) then
		return false, "bad_request"
	end
	log(actor, "aa_song_remove", tostring(id), true)
	return true
end

-- News app (all servers)
handlers.news_post = function(actor, args)
	local title = typeof(args) == "table" and Remotes.Check.String(args.title, 60) or nil
	local text = typeof(args) == "table" and Remotes.Check.String(args.text, 600) or nil
	if not title or not text then
		return false, "bad_message"
	end
	local fTitle = ChatService.Filter(title, actor.UserId)
	local fText = ChatService.Filter(text, actor.UserId)
	if not fTitle or not fText then
		return false, "bad_message"
	end
	if not NewsService.Post(fTitle, fText, actor.DisplayName) then
		return false, "error"
	end
	log(actor, "news_post", fTitle, true)
	return true
end

handlers.news_delete = function(actor, args)
	local id = typeof(args) == "table" and Remotes.Check.String(args.id, 16) or nil
	if not id or not NewsService.Delete(id) then
		return false, "bad_request"
	end
	log(actor, "news_delete", id, true)
	return true
end

handlers.shutdown = function(actor, args, isGA)
	local global = isGA and typeof(args) == "table" and args.global == true
	local reason = "Server wird neu gestartet / Server restarting"
	log(actor, if global then "shutdown (all servers)" else "shutdown", "", global)
	if global then
		pcall(function()
			MessagingService:PublishAsync("Shutdown", { reason = reason })
		end)
	end
	task.spawn(doShutdownLocal, reason)
	return true
end

handlers.time = function(actor, args)
	local hour = typeof(args) == "table" and Remotes.Check.Number(args.hour, 0, 24) or nil
	if not hour then
		return false, "bad_request"
	end
	Lighting.ClockTime = hour
	log(actor, "time", tostring(hour), false)
	return true
end

handlers.weather = function(actor, args)
	local kind = typeof(args) == "table" and Remotes.Check.OneOf(args.kind, WorldService.WeatherTypes) or nil
	if not kind then
		return false, "bad_request"
	end
	WorldService.SetWeather(kind, true)
	log(actor, "weather", kind, false)
	return true
end

handlers.appoint = function(actor, args)
	local target, err = targetPlayer(actor, args)
	if not target then
		return false, err
	end
	local value = not Roles.IsAppointed(target.UserId)
	Roles.Appoint(target.UserId, value)
	State.MarkDirty(target)
	log(actor, "appoint server admin", target.Name .. (if value then " +" else " -"), false)
	return true, nil, { on = value }
end

handlers.give_money = function(actor, args)
	local target, err = targetPlayer(actor, args)
	if not target then
		return false, err
	end
	local amount = Remotes.Check.Int(args.amount, 1, 100000000)
	if not amount then
		return false, "bad_amount"
	end
	Economy.Add(target, amount, "Admin-Gutschrift")
	log(actor, "give_money", string.format("%s +%d €", target.Name, amount), true)
	return true
end

handlers.give_xp = function(actor, args)
	local target, err = targetPlayer(actor, args)
	if not target then
		return false, err
	end
	local amount = Remotes.Check.Int(args.amount, 1, 1000000)
	local job = typeof(args.job) == "string" and Jobs.ById[args.job] and args.job or nil
	if not amount then
		return false, "bad_amount"
	end
	XPService.Add(target, job, amount, "Admin")
	log(actor, "give_xp", string.format("%s +%d XP (%s)", target.Name, amount, job or "global"), true)
	return true
end

handlers.give_vehicle = function(actor, args)
	local target, err = targetPlayer(actor, args)
	if not target then
		return false, err
	end
	local id = args.vehicleId
	local def = typeof(id) == "string" and Vehicles.ById[id] or nil
	if not def or def.category == "Job" or def.category == "Admin" then
		return false, "bad_item"
	end
	if not VehicleService.GiveVehicle(target, def.id) then
		return false, "error"
	end
	log(actor, "give_vehicle", target.Name .. " " .. def.name, true)
	return true
end

handlers.reply = function(actor, args)
	local userId = typeof(args) == "table" and Remotes.Check.Int(args.userId, 1, 1e12) or nil
	local body = typeof(args) == "table" and Remotes.Check.String(args.text, 300) or nil
	if not userId or not body then
		return false, "bad_message"
	end
	local filtered = ChatService.Filter(body, actor.UserId)
	if not filtered then
		return false, "filter_failed"
	end
	if not ChatService.SendToUser(userId, Config.AdminChatNumber, "Admin-Team", filtered) then
		return false, "send_failed"
	end
	log(actor, "reply 23646", tostring(userId) .. ": " .. filtered, true)
	return true
end

-- Wiring ----------------------------------------------------------------------
function AdminService.Start()
	task.spawn(loadServerBans)

	Players.PlayerAdded:Connect(function(player)
		if shuttingDown then
			player:Kick("Server wird neu gestartet / Server restarting")
			return
		end
		local ban = serverBans[player.UserId]
		if ban then
			player:Kick("Du bist auf diesem Server gebannt / You are banned from this server: " .. ban.reason)
		end
	end)

	-- God mode + freeze survive respawns.
	local function onCharacter(player: Player, character: Model)
		local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not hum then
			return
		end
		hum.HealthChanged:Connect(function()
			if player:GetAttribute("God") and hum.Health < hum.MaxHealth and hum.Health > 0 then
				hum.Health = hum.MaxHealth
			end
		end)
		if player:GetAttribute("Frozen") then
			local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
			if root then
				root.Anchored = true
			end
		end
	end
	local function onPlayer(player: Player)
		Roles.Refresh(player)
		player.CharacterAdded:Connect(function(c)
			onCharacter(player, c)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end

	pcall(function()
		MessagingService:SubscribeAsync("Announce", function(packet)
			local data = packet.Data
			if typeof(data) == "table" and data.server ~= game.JobId and typeof(data.text) == "string" then
				Remotes.PushAll("Announce", { text = data.text, from = data.from, global = true })
			end
		end)
	end)
	pcall(function()
		MessagingService:SubscribeAsync("Shutdown", function(packet)
			local data = packet.Data
			task.spawn(doShutdownLocal, typeof(data) == "table" and tostring(data.reason) or "Server restarting")
		end)
	end)

	Remotes.Handle("Admin.Do", function(player, action: any, args: any)
		local minRank = typeof(action) == "string" and ACTIONS[action] or nil
		if not minRank then
			return Remotes.Fail("bad_request")
		end
		local rank = Roles.Rank(player)
		if rank < minRank then
			return Remotes.Fail("no_permission")
		end
		local ok, err, extra = handlers[action](player, args or {}, rank >= GA)
		if not ok then
			return Remotes.Fail(err or "error")
		end
		return Remotes.Ok(extra)
	end, { rate = 20 })

	Remotes.Handle("Admin.Players", function(player)
		if not Roles.IsServerAdmin(player) then
			return Remotes.Fail("no_permission")
		end
		local list = {}
		for _, p in Players:GetPlayers() do
			local data = DataService.Get(p)
			table.insert(list, {
				userId = p.UserId,
				name = p.Name,
				display = p.DisplayName,
				rank = Roles.Rank(p),
				job = data and data.job or "?",
				bank = if Roles.IsGameAdmin(player) and data then data.bank else nil,
				god = p:GetAttribute("God") == true,
				frozen = p:GetAttribute("Frozen") == true,
				appointed = Roles.IsAppointed(p.UserId),
			})
		end
		return Remotes.Ok({ players = list })
	end, { rate = 10 })

	Remotes.Handle("Admin.Logs", function(player)
		if not Roles.IsServerAdmin(player) then
			return Remotes.Fail("no_permission")
		end
		local logs = table.clone(localLog)
		if Roles.IsGameAdmin(player) and logStore then
			local day = os.date("!%Y-%m-%d") :: string
			local ok, list = pcall(function()
				return (logStore :: DataStore):GetAsync("log_" .. day)
			end)
			if ok and typeof(list) == "table" then
				local seen = {}
				for _, e in logs do
					seen[HttpService:JSONEncode(e)] = true
				end
				for _, e in list do
					if not seen[HttpService:JSONEncode(e)] then
						table.insert(logs, e)
					end
				end
			end
		end
		table.sort(logs, function(a, b)
			return a.t > b.t
		end)
		while #logs > 150 do
			table.remove(logs)
		end
		return Remotes.Ok({ logs = logs })
	end, { rate = 5 })

	Remotes.Handle("Admin.Inbox", function(player)
		if not Roles.IsGameAdmin(player) then
			return Remotes.Fail("no_permission")
		end
		return Remotes.Ok({ inbox = ChatService.AdminInbox() })
	end, { rate = 5 })
end

return AdminService
