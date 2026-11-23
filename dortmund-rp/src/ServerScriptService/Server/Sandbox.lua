--!strict
-- DataStoreService / MessagingService for the game's services. In the main game they
-- are the real ones. The admin testing server is one reserved server of this game; its
-- PrivateServerId is saved (TestServerService) and checked here when the server starts.
-- There (Config.Testing) nothing leaves the server: DataStores read the real saves but every write stays in this server's memory
-- (gone when it closes), and messages only reach this server's own subscribers.
-- So a ban there only kicks, an event only runs there, money there is not saved.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Sandbox = {}

Sandbox.STORE = Config.DataStoreName .. "_TestServer" -- key "server" = { id, code }

-- is this server the testing server? (a reserved server whose id is the saved one)
local function detect(): boolean
	local ok, result = pcall(function()
		if game.PrivateServerId == "" or game.PrivateServerOwnerId ~= 0 then
			return false
		end
		local rec = game:GetService("DataStoreService"):GetDataStore(Sandbox.STORE):GetAsync("server")
		return typeof(rec) == "table" and rec.id == game.PrivateServerId
	end)
	return ok and result == true
end

Sandbox.Active = detect()
if Sandbox.Active then
	Config.Testing = true
	workspace:SetAttribute("TestServer", true) -- for the clients
end

local DELETED = newproxy(false) -- marks a key removed in this server

local function copy(v: any): any
	if typeof(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end

-- a DataStore: reads fall through to the real one, writes stay here
local function localStore(real: DataStore?): any
	local mem: { [string]: any } = {}
	local store = {}
	local function read(key: string): any
		local v = mem[key]
		if v == DELETED then
			return nil
		elseif v ~= nil then
			return copy(v)
		end
		if real then
			local ok, got = pcall(function()
				return (real :: DataStore):GetAsync(key)
			end)
			if ok then
				return copy(got) -- never change the real value
			end
		end
		return nil
	end
	function store.GetAsync(_self, key: string): any
		return read(key)
	end
	function store.SetAsync(_self, key: string, value: any)
		mem[key] = if value == nil then DELETED else copy(value)
	end
	function store.UpdateAsync(_self, key: string, fn: (any, any) -> any): any
		local new = fn(read(key), nil)
		if new ~= nil then
			mem[key] = copy(new)
		end
		return new
	end
	function store.RemoveAsync(_self, key: string): any
		local old = read(key)
		mem[key] = DELETED
		return old
	end
	function store.IncrementAsync(_self, key: string, delta: number?): number
		local n = (tonumber(read(key)) or 0) + (delta or 1)
		mem[key] = n
		return n
	end
	function store.ListKeysAsync(_self, ...): any
		-- lists the real keys (read only)
		if real then
			return (real :: DataStore):ListKeysAsync(...)
		end
		error("no store")
	end
	return store
end

local stores: { [string]: any } = {}
local fakeDS = {}
function fakeDS.GetDataStore(_self, name: string, scope: string?): any
	local key = name .. "\0" .. (scope or "")
	if not stores[key] then
		local ok, real = pcall(function()
			return game:GetService("DataStoreService"):GetDataStore(name, scope)
		end)
		stores[key] = localStore(if ok then real else nil)
	end
	return stores[key]
end

local subscribers: { [string]: { (any) -> () } } = {}
local fakeMS = {}
function fakeMS.PublishAsync(_self, topic: string, data: any)
	for _, fn in subscribers[topic] or {} do
		task.spawn(fn, { Data = copy(data), Sent = os.time() })
	end
end
function fakeMS.SubscribeAsync(_self, topic: string, fn: (any) -> ()): any
	subscribers[topic] = subscribers[topic] or {}
	table.insert(subscribers[topic], fn)
	return {
		Disconnect = function()
			local list = subscribers[topic]
			local i = list and table.find(list, fn)
			if i then
				table.remove(list, i)
			end
		end,
	}
end

-- main game: the real services (looked up on every call)
local realDS = {}
function realDS.GetDataStore(_self, name: string, scope: string?): any
	return game:GetService("DataStoreService"):GetDataStore(name, scope)
end
function realDS.GetOrderedDataStore(_self, name: string, scope: string?): any
	return game:GetService("DataStoreService"):GetOrderedDataStore(name, scope)
end
local realMS = {}
function realMS.PublishAsync(_self, topic: string, data: any)
	return game:GetService("MessagingService"):PublishAsync(topic, data)
end
function realMS.SubscribeAsync(_self, topic: string, fn: (any) -> ()): any
	return game:GetService("MessagingService"):SubscribeAsync(topic, fn)
end

Sandbox.DataStoreService = if Sandbox.Active then fakeDS :: any else realDS :: any
Sandbox.MessagingService = if Sandbox.Active then fakeMS :: any else realMS :: any

-- for tests: the local versions, whatever place this is
Sandbox._local = { DataStoreService = fakeDS, MessagingService = fakeMS }

return Sandbox
