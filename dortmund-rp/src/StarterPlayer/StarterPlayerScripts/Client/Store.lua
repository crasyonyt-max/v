--!strict
-- Latest copy of this player's private state, as sent by the server.
-- Display only: the server re-checks everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Net = require(script.Parent.Net)

local Store = {}

Store.state = nil :: { [string]: any }?
local changed = Instance.new("BindableEvent")
Store.Changed = changed.Event

function Store.Get(): { [string]: any }
	return Store.state or {}
end

function Store.Lang(): string
	local s = Store.state
	return if s and s.language == "en" then "en" else "de"
end

function Store.T(key: string, ...: any): string
	return Locale.T(Store.Lang(), key, ...)
end

function Store.Rank(): number
	local s = Store.state
	return if s then s.rank or 0 else 0
end

Net.On("State", function(snapshot)
	Store.state = snapshot
	changed:Fire(snapshot)
end)

task.spawn(function()
	-- In case the first push arrived before we listened.
	for _ = 1, 20 do
		if Store.state then
			return
		end
		local result = Net.Request("State.Get")
		if result.ok and result.state then
			Store.state = result.state
			changed:Fire(result.state)
			return
		end
		task.wait(1)
	end
end)

return Store
