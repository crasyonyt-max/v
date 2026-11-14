--!strict
-- Votes on EVERY server (started by Game Admins in the Admin app's Server tab).
-- The vote lives in a DataStore; every server adds its own tally there every few
-- seconds and shows the sum of all servers. Everyone votes once per vote (also when
-- switching servers: remembered in the player's data). After the time is up the
-- result stays on screen for a little while.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local VoteService = {}

local KEY = "current"
local TOPIC = "Votes"
local SYNC = 4 -- seconds between tally syncs
local SHOW_RESULT = 20 -- seconds the final result stays visible

type Vote = {
	id: string,
	question: string,
	options: { string },
	ends: number,
	by: string,
	counts: { [string]: { number } }, -- server -> tally
}

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName .. "_Votes")
end)
local SERVER = if game.JobId ~= "" then game.JobId else "studio"

local current: Vote? = nil
local mine: { number } = {} -- this server's tally for the current vote
local dirty = false
local lastPushed = ""

local function clean(v: any): Vote?
	if typeof(v) ~= "table" or typeof(v.id) ~= "string" or typeof(v.options) ~= "table" then
		return nil
	end
	if typeof(v.ends) ~= "number" or os.time() > v.ends + SHOW_RESULT then
		return nil
	end
	return {
		id = v.id,
		question = tostring(v.question),
		options = v.options,
		ends = v.ends,
		by = tostring(v.by or ""),
		counts = if typeof(v.counts) == "table" then v.counts else {},
	}
end

-- totals over all servers (this server's own tally is always the newest)
local function totals(v: Vote): { number }
	local out = {}
	for i = 1, #v.options do
		out[i] = mine[i] or 0
	end
	for server, tally in v.counts do
		if server ~= SERVER and typeof(tally) == "table" then
			for i = 1, #v.options do
				out[i] += tonumber(tally[i]) or 0
			end
		end
	end
	return out
end

local function public(): { [string]: any }?
	local v = current
	if not v then
		return nil
	end
	local counts = totals(v)
	local total = 0
	for _, c in counts do
		total += c
	end
	return {
		id = v.id,
		question = v.question,
		options = v.options,
		counts = counts,
		total = total,
		ends = v.ends,
		by = v.by,
		done = os.time() >= v.ends,
	}
end

local function myChoice(player: Player): number?
	local data = DataService.Get(player)
	local v = current
	if data and v and data.votedIn == v.id then
		return tonumber(data.votedChoice)
	end
	return nil
end

local function push(force: boolean?)
	local p = public()
	local json = HttpService:JSONEncode(p or {})
	if not force and json == lastPushed then
		return
	end
	lastPushed = json
	for _, player in Players:GetPlayers() do
		Remotes.Push(player, "Vote", { vote = p, mine = myChoice(player) })
	end
end

-- (true, value) or (false) when the DataStore could not be read
local function read(): (boolean, any)
	if not store then
		return false, nil
	end
	local ok, v = pcall(function()
		local okOpt, options = pcall(function()
			local o = Instance.new("DataStoreGetOptions")
			o.UseCache = false
			return o
		end)
		return (store :: DataStore):GetAsync(KEY, if okOpt then options else nil)
	end)
	return ok, v
end

-- takes the stored vote (new vote = new tally)
local function adopt(v: Vote?)
	if v and (not current or (current :: Vote).id ~= v.id) then
		mine = {}
		dirty = false
	end
	current = v
end

-- writes this server's tally into the shared vote
local function sync()
	local v = current
	if not store or not v or not dirty then
		return
	end
	dirty = false
	local tally = table.clone(mine)
	local id = v.id
	local ok = pcall(function()
		(store :: DataStore):UpdateAsync(KEY, function(old: any)
			if typeof(old) ~= "table" or old.id ~= id then
				return nil -- another vote by now
			end
			old.counts = if typeof(old.counts) == "table" then old.counts else {}
			old.counts[SERVER] = tally
			return old
		end)
	end)
	if not ok then
		dirty = true
	end
end

local function publish()
	pcall(function()
		MessagingService:PublishAsync(TOPIC, { server = SERVER })
	end)
end

-- question / options must already be filtered.
function VoteService.Begin(question: string, options: { string }, minutes: number, by: string): boolean
	local running = false
	local vote = {
		id = string.sub(HttpService:GenerateGUID(false), 1, 8),
		question = question,
		options = options,
		ends = os.time() + math.floor(minutes * 60),
		by = by,
		counts = {},
	}
	if store then
		local ok = pcall(function()
			(store :: DataStore):UpdateAsync(KEY, function(old: any)
				local o = clean(old)
				if o and os.time() < o.ends then
					running = true
					return nil
				end
				return vote
			end)
		end)
		if not ok then
			return false
		end
	elseif current and os.time() < (current :: Vote).ends then
		running = true
	end
	if running then
		return false
	end
	adopt(vote)
	push(true)
	publish()
	return true
end

function VoteService.End(): boolean
	local v = current
	if not v or os.time() >= v.ends then
		return false
	end
	local now = os.time()
	if store then
		pcall(function()
			(store :: DataStore):UpdateAsync(KEY, function(old: any)
				if typeof(old) ~= "table" or old.id ~= v.id then
					return nil
				end
				old.ends = now
				return old
			end)
		end)
	end
	v.ends = now
	push(true)
	publish()
	return true
end

function VoteService.IsRunning(): boolean
	return current ~= nil and os.time() < (current :: Vote).ends
end

function VoteService.Start()
	task.spawn(function()
		local ok, v = read()
		if ok then
			adopt(clean(v))
			push(true)
		end
	end)
	pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(message)
			local data = message.Data
			if typeof(data) == "table" and data.server == SERVER then
				return
			end
			local ok, v = read()
			if ok then
				adopt(clean(v))
				push(true)
			end
		end)
	end)
	-- every few seconds: send our tally, fetch everyone's, show the sum
	task.spawn(function()
		while true do
			task.wait(SYNC)
			if current then
				sync()
				local ok, v = read()
				if ok then
					adopt(clean(v)) -- nil once the vote is over (or replaced)
				elseif current and os.time() > (current :: Vote).ends + SHOW_RESULT then
					current = nil
				end
				push()
			end
		end
	end)
	-- a new player sees the running vote
	Players.PlayerAdded:Connect(function(player)
		task.wait(3)
		if current then
			Remotes.Push(player, "Vote", { vote = public(), mine = myChoice(player) })
		end
	end)

	Remotes.Handle("Vote.Get", function(player)
		return Remotes.Ok({ vote = public(), mine = myChoice(player) })
	end, { rate = 6, needsData = false })

	Remotes.Handle("Vote.Cast", function(player, index: any)
		local v = current
		if not v or os.time() >= v.ends then
			return Remotes.Fail("no_vote")
		end
		local i = Remotes.Check.Int(index, 1, #v.options)
		if not i then
			return Remotes.Fail("bad_request")
		end
		local data = DataService.Get(player) :: { [string]: any }
		if data.votedIn == v.id then
			return Remotes.Fail("already_voted")
		end
		data.votedIn = v.id
		data.votedChoice = i
		State.MarkDirty(player)
		mine[i] = (mine[i] or 0) + 1
		dirty = true
		push(true)
		return Remotes.Ok()
	end, { rate = 4 })
end

return VoteService
