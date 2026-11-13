--!strict
-- The running dropper event (Shared/DropEvents). Events only start when an AA admin
-- sets one (EventService shares it with every server and calls Set here).
-- While an event runs, every single drop has the event's chance to be multiplied.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropEvents = require(ReplicatedStorage.Shared.DropEvents)
local Remotes = require(script.Parent.Remotes)

local DropEventService = {}

local active: string? = nil
local ends = 0
local rng = Random.new()

local function public(): { [string]: any }
	return { id = DropEventService.Current(), ends = ends }
end

function DropEventService.Current(): string?
	return if active and os.time() < ends then active else nil
end

-- Sets the event (nil = none). Tells the players only when something changed.
function DropEventService.Set(id: string?, endsAt: number?)
	if id and not DropEvents.ById[id] then
		id = nil
	end
	local newEnds = if id then endsAt or 0 else 0
	if id == active and newEnds == ends then
		return
	end
	active, ends = id, newEnds
	Remotes.PushAll("DropEvent", public())
end

-- What one drop is multiplied by: the event's multiplier if this drop "hits"
-- (its chance), otherwise 1. Second result: whether it hit.
function DropEventService.Hit(random: Random?): (number, boolean)
	local id = DropEventService.Current()
	local e = id and DropEvents.ById[id]
	if e and (random or rng):NextNumber() < e.chance then
		return e.mult, true
	end
	return 1, false
end

function DropEventService.Start()
	-- an event that ran out: tell the players
	task.spawn(function()
		while true do
			task.wait(1)
			if active and os.time() >= ends then
				DropEventService.Set(nil)
			end
		end
	end)
	Remotes.Handle("DropEvent.Get", function()
		return Remotes.Ok(public())
	end, { rate = 6, needsData = false })
end

return DropEventService
