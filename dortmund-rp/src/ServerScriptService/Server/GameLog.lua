--!strict
-- The full game log: everything that happens on every server (joins, money, XP,
-- purchases, jobs, calls, messages, admin actions, bans, traffic, deaths …), saved per
-- day in a DataStore so it can be read later from any server. Only the Owner can read
-- it (Admin app → 📜 Log).
--
-- Storage: "meta_<day>" = number of chunks, "log_<day>_<n>" = up to CHUNK entries.
-- Each server collects entries and writes them every FLUSH seconds (atomic appends).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GameLog = {}

local CHUNK = 1500
local FLUSH = 20
local MAX_TEXT = 200

export type Entry = { t: number, k: string, u: number?, n: string?, x: string, s: string }

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName .. "_GameLog")
end)

local buffer: { Entry } = {}
local recent: { Entry } = {} -- this server's last entries (shown even before they are saved)
local server = string.sub(game.JobId ~= "" and game.JobId or "studio", 1, 6)

local function day(t: number): string
	return os.date("!%Y-%m-%d", t) :: string
end

-- kind: "join", "money", "xp", "admin", "call", "chat", "job", … ; who: Player or userId
function GameLog.Add(kind: string, who: any, text: string)
	local userId, name = nil, nil
	if typeof(who) == "Instance" and who:IsA("Player") then
		userId, name = who.UserId, who.Name
	elseif typeof(who) == "number" then
		userId = who
	end
	local entry: Entry = {
		t = os.time(),
		k = kind,
		u = userId,
		n = name,
		x = string.sub(tostring(text), 1, MAX_TEXT),
		s = server,
	}
	table.insert(buffer, entry)
	table.insert(recent, entry)
	while #recent > 500 do
		table.remove(recent, 1)
	end
end

local function flush()
	if not store or #buffer == 0 then
		return
	end
	local batch = buffer
	buffer = {}
	-- entries of a batch can belong to two days around midnight
	local byDay: { [string]: { Entry } } = {}
	for _, e in batch do
		local d = day(e.t)
		byDay[d] = byDay[d] or {}
		table.insert(byDay[d], e)
	end
	for d, entries in byDay do
		local ok = pcall(function()
			local ds = store :: DataStore
			for _ = 1, 4 do
				local n = 1
				ds:UpdateAsync("meta_" .. d, function(old: any)
					n = if typeof(old) == "number" then old else 1
					return n
				end)
				local full = false
				ds:UpdateAsync("log_" .. d .. "_" .. n, function(old: any)
					local list = if typeof(old) == "table" then old else {}
					if #list + #entries > CHUNK then
						full = true
						return nil
					end
					for _, e in entries do
						table.insert(list, e)
					end
					return list
				end)
				if not full then
					return
				end
				-- this chunk is full: start the next one (only once, whoever is first)
				ds:UpdateAsync("meta_" .. d, function(old: any)
					local cur = if typeof(old) == "number" then old else 1
					return if cur == n then n + 1 else cur
				end)
			end
		end)
		if not ok then
			-- keep them for the next try
			for _, e in entries do
				table.insert(buffer, e)
			end
		end
	end
end

-- Reads a day (newest first). `filter` matches name, user id, kind or text.
local cacheDay, cacheAt, cacheList = "", 0, {} :: { Entry }
function GameLog.Read(d: string, filter: string?, page: number, perPage: number): ({ Entry }, number)
	local list: { Entry }
	if d == cacheDay and os.clock() - cacheAt < 15 then
		list = cacheList
	else
		list = {}
		local seen: { [string]: boolean } = {}
		if store then
			pcall(function()
				local n = (store :: DataStore):GetAsync("meta_" .. d)
				for i = 1, (if typeof(n) == "number" then n else 1) do
					local chunk = (store :: DataStore):GetAsync("log_" .. d .. "_" .. i)
					if typeof(chunk) == "table" then
						for _, e in chunk do
							table.insert(list, e)
							seen[tostring(e.t) .. e.s .. e.x] = true
						end
					end
				end
			end)
		end
		-- plus what this server has not saved yet
		for _, e in recent do
			if day(e.t) == d and not seen[tostring(e.t) .. e.s .. e.x] then
				table.insert(list, e)
			end
		end
		table.sort(list, function(a, b)
			return a.t > b.t
		end)
		cacheDay, cacheAt, cacheList = d, os.clock(), list
	end
	local f = if filter and filter ~= "" then string.lower(filter) else nil
	local matched = list
	if f then
		matched = {}
		for _, e in list do
			local hay = string.lower(table.concat({ e.k, e.n or "", tostring(e.u or ""), e.x }, " "))
			if string.find(hay, f, 1, true) then
				table.insert(matched, e)
			end
		end
	end
	local out = {}
	for i = (page - 1) * perPage + 1, math.min(#matched, page * perPage) do
		table.insert(out, matched[i])
	end
	return out, #matched
end

function GameLog.Start()
	task.spawn(function()
		while true do
			task.wait(FLUSH)
			flush()
		end
	end)
	game:BindToClose(function()
		GameLog.Add("server", nil, "Server stopped")
		flush()
	end)
	GameLog.Add("server", nil, "Server started" .. (if game.PrivateServerId ~= "" then " (private)" else ""))
	Players.PlayerAdded:Connect(function(p)
		GameLog.Add("join", p, "joined (" .. p.DisplayName .. ")")
		p.CharacterAdded:Connect(function(c)
			local hum = c:WaitForChild("Humanoid", 10) :: Humanoid?
			if hum then
				hum.Died:Connect(function()
					GameLog.Add("death", p, "died")
				end)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(p)
		GameLog.Add("leave", p, "left")
	end)
end

return GameLog
