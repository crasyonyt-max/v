--!strict
-- Runs the dropper events (Shared/DropEvents) on this server: rolls every few minutes,
-- tells all players (world effects), and gives the multiplier to DropperService.
-- The AA tab can also start one by hand.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropEvents = require(ReplicatedStorage.Shared.DropEvents)
local Remotes = require(script.Parent.Remotes)

local DropEventService = {}

local active: string? = nil
local ends = 0
local rng = Random.new()

local function public(): { [string]: any }
	return { id = if active and os.time() < ends then active else nil, ends = ends }
end

function DropEventService.Mult(): number
	local e = active and os.time() < ends and DropEvents.ById[active]
	return if e then e.mult else 1
end

function DropEventService.Current(): string?
	return if active and os.time() < ends then active else nil
end

function DropEventService.Begin(id: string, seconds: number?): boolean
	if not DropEvents.ById[id] then
		return false
	end
	active = id
	ends = os.time() + (seconds or DropEvents.LENGTH)
	Remotes.PushAll("DropEvent", public())
	return true
end

function DropEventService.Stop()
	active = nil
	ends = 0
	Remotes.PushAll("DropEvent", public())
end

-- One roll: the events in random order, the first whose chance hits starts.
function DropEventService.Roll(random: Random?): string?
	local r = random or rng
	local order = table.clone(DropEvents.List)
	for i = #order, 2, -1 do
		local j = r:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for _, e in order do
		if r:NextNumber() < e.chance then
			return e.id
		end
	end
	return nil
end

function DropEventService.Start()
	task.spawn(function()
		local nextRoll = os.time() + DropEvents.ROLL_EVERY
		while true do
			task.wait(1)
			if active and os.time() >= ends then
				DropEventService.Stop()
				nextRoll = os.time() + DropEvents.ROLL_EVERY
			end
			if not active and os.time() >= nextRoll then
				nextRoll = os.time() + DropEvents.ROLL_EVERY
				local id = DropEventService.Roll()
				if id then
					DropEventService.Begin(id)
				end
			end
		end
	end)
	Remotes.Handle("DropEvent.Get", function()
		return Remotes.Ok(public())
	end, { rate = 6, needsData = false })
end

return DropEventService
