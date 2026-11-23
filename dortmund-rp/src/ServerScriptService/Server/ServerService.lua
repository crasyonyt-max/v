--!strict
-- v0.4 Servers: every server has an 8-character code; private servers (bought for
-- Robux, a Developer Product) can be named and made public; public servers are
-- listed in the Servers app; anyone can join any server with its code.
--
--   normal server   : NO code; listed under "Public Servers", joined by its JobId
--   private server  : a reserved server (TeleportService:ReserveServer) with a fixed
--                     8-character code (public or private), owner / name / public saved
--                     in the "_PServers" DataStore
--
-- Running servers announce themselves in a MemoryStore sorted map every 30 s.

local DataStoreService = require(script.Parent.Sandbox).DataStoreService -- local only on the testing server
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local GameLog = require(script.Parent.GameLog)
local Remotes = require(script.Parent.Remotes)
local Roles = require(script.Parent.Roles)

local ServerService = {}

local CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" -- no 0/O, 1/I
local CODE_LENGTH = 8
local ANNOUNCE_EVERY = 30
local ANNOUNCE_TTL = 120
local NAME_MAX = 32

export type PServer = {
	id: string, -- PrivateServerId
	accessCode: string,
	code: string,
	owner: number,
	ownerName: string,
	name: string,
	public: boolean,
	created: number,
}

local store: DataStore? = nil
local liveMap: MemoryStoreSortedMap? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName .. "_PServers")
end)
pcall(function()
	if not Config.Testing then -- the testing server isn't in the server list
		liveMap = MemoryStoreService:GetSortedMap("LiveServers")
	end
end)

-- this server
local info = {
	code = "",
	name = "Emergency Dortmund",
	kind = "public", -- "public" (normal) | "private"
	public = true, -- listed in "Public Servers"
	owner = 0,
	psid = "",
}
ServerService.Info = info

function ServerService.NewCode(random: Random?): string
	local rng = random or Random.new()
	local out = {}
	for i = 1, CODE_LENGTH do
		local k = rng:NextInteger(1, #CODE_CHARS)
		out[i] = string.sub(CODE_CHARS, k, k)
	end
	return table.concat(out)
end

function ServerService.CleanCode(code: any): string?
	if typeof(code) ~= "string" then
		return nil
	end
	local c = string.upper((code:gsub("[%s%-]", "")))
	if #c ~= CODE_LENGTH or c:find("[^" .. CODE_CHARS .. "]") then
		return nil
	end
	return c
end

local function filterName(player: Player, text: any): string?
	local name = Remotes.Check.String(text, NAME_MAX)
	if not name then
		return nil
	end
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(name, player.UserId, Enum.TextFilterContext.PublicChat)
			:GetNonChatStringForBroadcastAsync()
	end)
	return if ok and typeof(result) == "string" then result else nil
end

local function load(psid: string): PServer?
	if not store then
		return nil
	end
	local ok, data = pcall(function()
		return (store :: DataStore):GetAsync("ps_" .. psid)
	end)
	return if ok and typeof(data) == "table" then data :: any else nil
end

local function save(ps: PServer): boolean
	if not store then
		return false
	end
	local ds = store :: DataStore
	for attempt = 1, 3 do
		-- (two separate statements: a line starting with "(" would be read as a call
		-- on the line before – that was the bug that lost the first purchases)
		local ok, err = pcall(function()
			ds:SetAsync("ps_" .. ps.id, ps)
			ds:SetAsync("code_" .. ps.code, ps.id)
		end)
		if ok then
			return true
		end
		warn("[Servers] save failed: " .. tostring(err))
		task.wait(attempt * 2)
	end
	return false
end

-- where a code leads: a running server (MemoryStore) or a private server (DataStore)
local function resolve(code: string): { [string]: any }?
	if string.sub(code, 1, 4) == "job_" then
		-- a normal server from the list (no code): its live entry
		if not liveMap then
			return nil
		end
		local ok, entry = pcall(function()
			return (liveMap :: MemoryStoreSortedMap):GetAsync(code)
		end)
		return if ok and typeof(entry) == "table" then entry else nil
	end
	-- codes only lead to private servers (saved in the DataStore)
	if store then
		local ok, psid = pcall(function()
			return (store :: DataStore):GetAsync("code_" .. code)
		end)
		if ok and typeof(psid) == "string" then
			local ps = load(psid)
			if ps then
				return { code = code, kind = "private", psid = ps.id, name = ps.name }
			end
		end
	end
	return nil
end

local function teleport(player: Player, entry: { [string]: any }): (boolean, string?)
	if (entry.code ~= nil and entry.code == info.code) or entry.jobId == game.JobId then
		return false, "server_already_here"
	end
	local options = Instance.new("TeleportOptions")
	if entry.kind == "private" then
		local ps = load(entry.psid)
		if not ps then
			return false, "server_unknown"
		end
		options.ReservedServerAccessCode = ps.accessCode
	elseif typeof(entry.jobId) == "string" then
		options.ServerInstanceId = entry.jobId
	else
		return false, "server_unknown"
	end
	options:SetTeleportData({ via = "code", code = entry.code })
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not ok then
		warn("[Servers] teleport failed: " .. tostring(err))
		return false, "server_teleport_failed"
	end
	GameLog.Add("server", player, "joins server " .. tostring(entry.code))
	return true, nil
end

-- a new private server for this player (after the Robux purchase, or free for the
-- Owner and Co-Owners)
function ServerService.Create(player: Player): (PServer?, string?)
	local data = DataService.Get(player)
	if not data then
		return nil, "error"
	end
	local ok, accessCode, psid = false, nil, nil
	for attempt = 1, 3 do
		ok, accessCode, psid = pcall(function()
			return TeleportService:ReserveServer(game.PlaceId)
		end)
		if ok and typeof(accessCode) == "string" and typeof(psid) == "string" then
			break
		end
		GameLog.Add("server", player, ("ReserveServer failed (try %d): %s"):format(attempt, tostring(accessCode)))
		task.wait(attempt * 2)
	end
	if not ok or typeof(accessCode) ~= "string" or typeof(psid) ~= "string" then
		warn("[Servers] ReserveServer failed: " .. tostring(accessCode))
		return nil, "server_create_failed"
	end
	local ps: PServer = {
		id = psid,
		accessCode = accessCode,
		code = ServerService.NewCode(),
		owner = player.UserId,
		ownerName = player.Name,
		name = player.DisplayName .. "s Server",
		public = false,
		created = os.time(),
	}
	if not save(ps) then
		GameLog.Add("server", player, "private server could not be saved")
		return nil, "server_create_failed"
	end
	data.servers = data.servers or {}
	table.insert(data.servers, psid)
	DataService.Save(player, false)
	GameLog.Add("server", player, "created private server " .. ps.code)
	return ps, nil
end

local function mine(player: Player): { PServer }
	local data = DataService.Get(player)
	local out = {}
	for _, psid in (data and data.servers) or {} do
		local ps = load(psid)
		if ps and ps.owner == player.UserId then
			table.insert(out, ps)
		end
	end
	return out
end

local function publicView(ps: PServer): { [string]: any }
	return { id = ps.id, code = ps.code, name = ps.name, public = ps.public, created = ps.created }
end

local function setAttributes()
	Workspace:SetAttribute("ServerCode", info.code)
	Workspace:SetAttribute("ServerName", info.name)
	Workspace:SetAttribute("ServerKind", info.kind)
	Workspace:SetAttribute("ServerPublic", info.public)
	Workspace:SetAttribute("ServerOwnerId", info.owner)
end

-- key in the live list: the code of a private server, "job_<JobId>" for normal ones
function ServerService.ListKey(): string
	return if info.code ~= "" then info.code else "job_" .. game.JobId
end

-- tell everyone this server exists (list + code lookup)
local function announce()
	if not liveMap then
		return
	end
	local entry = {
		key = ServerService.ListKey(),
		code = if info.code ~= "" then info.code else nil,
		name = info.name,
		kind = info.kind,
		public = info.public,
		psid = if info.psid ~= "" then info.psid else nil,
		jobId = game.JobId,
		players = #Players:GetPlayers(),
		max = Players.MaxPlayers,
		t = os.time(),
	}
	pcall(function()
		(liveMap :: MemoryStoreSortedMap):SetAsync(ServerService.ListKey(), entry, ANNOUNCE_TTL)
	end)
end

-- which server is this? (reserved private server: its record; otherwise a fresh code)
local function identify()
	if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
		local ps = load(game.PrivateServerId)
		if ps then
			info.kind = "private"
			info.code = ps.code
			info.name = ps.name
			info.public = ps.public
			info.owner = ps.owner
			info.psid = ps.id
			Roles.SetReservedOwner(ps.owner)
			return
		end
	end
	info.code = "" -- normal servers have no code (only private servers do)
	info.name = if Config.Testing then "🧪 Testserver" else "Emergency Dortmund"
	if game.PrivateServerId ~= "" then
		-- a Roblox VIP server: private, not listed
		info.kind = "private"
		info.public = false
		info.owner = game.PrivateServerOwnerId
	end
end

function ServerService.Start()
	if not Config.V04 then
		return
	end
	identify()
	setAttributes()
	task.spawn(function()
		while true do
			-- a private server picks up name / public changes made from elsewhere
			if info.psid ~= "" then
				local ps = load(info.psid)
				if ps then
					info.name, info.public = ps.name, ps.public
					setAttributes()
				end
			end
			announce()
			task.wait(ANNOUNCE_EVERY)
		end
	end)
	game:BindToClose(function()
		if liveMap then
			pcall(function()
				(liveMap :: MemoryStoreSortedMap):RemoveAsync(ServerService.ListKey())
			end)
		end
	end)

	Remotes.Handle("Servers.Info", function()
		return Remotes.Ok({
			code = if info.code ~= "" then info.code else nil,
			name = info.name,
			kind = info.kind,
			public = info.public,
			owner = info.owner,
			players = #Players:GetPlayers(),
			max = Players.MaxPlayers,
			productId = Config.PrivateServerProductId,
		})
	end, { rate = 10, needsData = false })

	Remotes.Handle("Servers.List", function()
		if not liveMap then
			return Remotes.Ok({ servers = {} })
		end
		local ok, items = pcall(function()
			return (liveMap :: MemoryStoreSortedMap):GetRangeAsync(Enum.SortDirection.Ascending, 200)
		end)
		if not ok then
			return Remotes.Fail("error")
		end
		local out = {}
		for _, item in items do
			local e = item.value
			if typeof(e) == "table" and e.public and os.time() - (tonumber(e.t) or 0) < ANNOUNCE_TTL then
				table.insert(out, {
					key = e.key or e.code,
					code = e.code,
					name = e.name,
					kind = e.kind,
					players = e.players,
					max = e.max,
					here = e.jobId == game.JobId,
				})
			end
		end
		-- RP servers (private + public) first, then by players
		table.sort(out, function(a, b)
			if (a.kind == "private") ~= (b.kind == "private") then
				return a.kind == "private"
			end
			return (a.players or 0) > (b.players or 0)
		end)
		return Remotes.Ok({ servers = out })
	end, { rate = 6, needsData = false })

	Remotes.Handle("Servers.Join", function(player, code: any)
		-- from the list a normal server comes as "job_<JobId>", otherwise a code
		local c = if typeof(code) == "string"
				and string.sub(code, 1, 4) == "job_"
				and #code < 80
			then code
			else ServerService.CleanCode(code)
		if not c then
			return Remotes.Fail("server_bad_code")
		end
		local entry = resolve(c)
		if not entry then
			return Remotes.Fail("server_unknown")
		end
		local ok, err = teleport(player, entry)
		return if ok then Remotes.Ok() else Remotes.Fail(err or "error")
	end, { rate = 3 })

	Remotes.Handle("Servers.Mine", function(player)
		local list = {}
		for _, ps in mine(player) do
			table.insert(list, publicView(ps))
		end
		return Remotes.Ok({ servers = list, free = Roles.Rank(player) >= Roles.CO_OWNER })
	end, { rate = 6 })

	-- Owner / Co-Owners: a private server without buying one
	Remotes.Handle("Servers.CreateFree", function(player)
		if Roles.Rank(player) < Roles.CO_OWNER then
			return Remotes.Fail("no_permission")
		end
		local ps, err = ServerService.Create(player)
		return if ps then Remotes.Ok({ server = publicView(ps) }) else Remotes.Fail(err or "error")
	end, { rate = 1 })

	local function owned(player: Player, psid: any): PServer?
		if typeof(psid) ~= "string" then
			return nil
		end
		local data = DataService.Get(player)
		if not data or not table.find(data.servers or {}, psid) then
			return nil
		end
		local ps = load(psid)
		return if ps and ps.owner == player.UserId then ps else nil
	end

	Remotes.Handle("Servers.Rename", function(player, psid: any, name: any)
		local ps = owned(player, psid)
		if not ps then
			return Remotes.Fail("no_permission")
		end
		local clean = filterName(player, name)
		if not clean then
			return Remotes.Fail("server_bad_name")
		end
		ps.name = clean
		if not save(ps) then
			return Remotes.Fail("error")
		end
		if ps.id == info.psid then
			info.name = clean
			setAttributes()
			announce()
		end
		return Remotes.Ok({ server = publicView(ps) })
	end, { rate = 3 })

	Remotes.Handle("Servers.SetPublic", function(player, psid: any, on: any)
		local ps = owned(player, psid)
		if not ps or typeof(on) ~= "boolean" then
			return Remotes.Fail("no_permission")
		end
		ps.public = on
		if not save(ps) then
			return Remotes.Fail("error")
		end
		if ps.id == info.psid then
			info.public = on
			setAttributes()
			announce()
		end
		return Remotes.Ok({ server = publicView(ps) })
	end, { rate = 3 })

	Remotes.Handle("Servers.Open", function(player, psid: any)
		local ps = owned(player, psid)
		if not ps then
			return Remotes.Fail("no_permission")
		end
		local ok, err = teleport(player, { code = ps.code, kind = "private", psid = ps.id })
		return if ok then Remotes.Ok() else Remotes.Fail(err or "error")
	end, { rate = 3 })
end

return ServerService
