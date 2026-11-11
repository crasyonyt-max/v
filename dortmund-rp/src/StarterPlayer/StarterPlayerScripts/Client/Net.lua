--!strict
-- Thin client wrapper around the server's Request / Event remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local request = remotes:WaitForChild("Request") :: RemoteFunction
local event = remotes:WaitForChild("Event") :: RemoteEvent

local Net = {}

local listeners: { [string]: { (any) -> () } } = {}

function Net.Request(name: string, ...: any): { [string]: any }
	local ok, result = pcall(request.InvokeServer, request, name, ...)
	if not ok or typeof(result) ~= "table" then
		return { ok = false, err = "server_error" }
	end
	return result
end

-- Returns a function that removes the listener again.
function Net.On(kind: string, fn: (any) -> ()): () -> ()
	listeners[kind] = listeners[kind] or {}
	table.insert(listeners[kind], fn)
	return function()
		local list = listeners[kind]
		local i = list and table.find(list, fn)
		if i then
			table.remove(list, i)
		end
	end
end

event.OnClientEvent:Connect(function(kind: string, payload: any)
	local list = listeners[kind]
	if list then
		for _, fn in list do
			task.spawn(fn, payload)
		end
	end
end)

return Net
