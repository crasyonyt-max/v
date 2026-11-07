--!strict
-- Single secure entry point for every client request.
-- Clients call Request:InvokeServer(actionName, ...). Every action:
--   * must be registered here by a server service
--   * is rate limited per player
--   * runs inside pcall (a bad request can never break the server)
--   * validates its own arguments (see the `Check` helpers)
-- The server pushes data to clients with Remotes.Push(player, kind, payload).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Remotes = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local request = Instance.new("RemoteFunction")
request.Name = "Request"
request.Parent = folder

local event = Instance.new("RemoteEvent")
event.Name = "Event"
event.Parent = folder

folder.Parent = ReplicatedStorage

type Handler = {
	fn: (Player, ...any) -> any,
	rate: number, -- max calls per 10 seconds
	needsData: boolean,
}

local handlers: { [string]: Handler } = {}
local buckets: { [Player]: { [string]: { count: number, reset: number } } } = {}

-- Set by Main once DataService exists (avoids a require cycle).
Remotes.IsReady = function(_player: Player): boolean
	return true
end

function Remotes.Handle(name: string, fn: (Player, ...any) -> any, opts: { rate: number?, needsData: boolean? }?)
	assert(handlers[name] == nil, "Duplicate handler " .. name)
	handlers[name] = {
		fn = fn,
		rate = (opts and opts.rate) or 10,
		needsData = if opts and opts.needsData == false then false else true,
	}
end

function Remotes.Ok(data: { [string]: any }?): { [string]: any }
	local out = data or {}
	out.ok = true
	return out
end

function Remotes.Fail(err: string): { [string]: any }
	return { ok = false, err = err }
end

local function allowed(player: Player, name: string, rate: number): boolean
	local now = os.clock()
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local b = perPlayer[name]
	if not b or now >= b.reset then
		b = { count = 0, reset = now + 10 }
		perPlayer[name] = b
	end
	b.count += 1
	return b.count <= rate
end

request.OnServerInvoke = function(player: Player, name: any, ...: any)
	if typeof(name) ~= "string" then
		return Remotes.Fail("bad_request")
	end
	local h = handlers[name]
	if not h then
		return Remotes.Fail("bad_request")
	end
	if not allowed(player, name, h.rate) then
		return Remotes.Fail("too_fast")
	end
	if h.needsData and not Remotes.IsReady(player) then
		return Remotes.Fail("loading")
	end
	local ok, result = pcall(h.fn, player, ...)
	if not ok then
		warn(string.format("[Remotes] %s failed for %s: %s", name, player.Name, tostring(result)))
		return Remotes.Fail("server_error")
	end
	if typeof(result) ~= "table" then
		return Remotes.Ok()
	end
	return result
end

function Remotes.Push(player: Player, kind: string, payload: any?)
	if player.Parent == Players then
		event:FireClient(player, kind, payload)
	end
end

function Remotes.PushAll(kind: string, payload: any?)
	event:FireAllClients(kind, payload)
end

-- Clients only ever send events through Request; ignore anything fired at us.
event.OnServerEvent:Connect(function() end)

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

-- Argument validation helpers ---------------------------------------------
local Check = {}
Remotes.Check = Check

function Check.String(v: any, maxLen: number): string?
	if typeof(v) ~= "string" or #v == 0 or #v > maxLen then
		return nil
	end
	if not utf8.len(v) then
		return nil -- invalid UTF-8
	end
	return v
end

function Check.Int(v: any, min: number, max: number): number?
	if typeof(v) ~= "number" or v ~= v or v % 1 ~= 0 or v < min or v > max then
		return nil
	end
	return v
end

function Check.Number(v: any, min: number, max: number): number?
	if typeof(v) ~= "number" or v ~= v or v < min or v > max then
		return nil
	end
	return v
end

function Check.Bool(v: any): boolean?
	if typeof(v) ~= "boolean" then
		return nil
	end
	return v
end

function Check.OneOf(v: any, options: { string }): string?
	if typeof(v) ~= "string" then
		return nil
	end
	for _, o in options do
		if o == v then
			return v
		end
	end
	return nil
end

return Remotes
