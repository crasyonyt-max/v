--!strict
-- Votes on this server (started by admins in the Admin app's Server tab).
-- Everyone votes once; all players see the percentages live until time runs out.

local Players = game:GetService("Players")

local Remotes = require(script.Parent.Remotes)

local VoteService = {}

type Vote = {
	id: number,
	question: string,
	options: { string },
	counts: { number },
	ends: number,
	by: string,
	done: boolean,
}

local current: Vote? = nil
local ballots: { [number]: number } = {} -- userId -> option index
local nextId = 1

local function public(v: Vote?): { [string]: any }?
	if not v then
		return nil
	end
	local total = 0
	for _, c in v.counts do
		total += c
	end
	return {
		id = v.id,
		question = v.question,
		options = v.options,
		counts = v.counts,
		total = total,
		ends = v.ends,
		by = v.by,
		done = v.done,
	}
end

local function push()
	local p = public(current)
	for _, player in Players:GetPlayers() do
		local mine = ballots[player.UserId]
		Remotes.Push(player, "Vote", { vote = p, mine = mine })
	end
end

local function finish()
	local v = current
	if not v or v.done then
		return
	end
	v.done = true
	v.ends = os.time()
	push()
	-- the result stays on screen a little, then the vote is gone
	task.delay(20, function()
		if current == v then
			current = nil
			ballots = {}
			push()
		end
	end)
end

-- question / options must already be filtered.
function VoteService.Begin(question: string, options: { string }, minutes: number, by: string)
	if current and not current.done then
		return false
	end
	local counts = {}
	for i = 1, #options do
		counts[i] = 0
	end
	local v: Vote = {
		id = nextId,
		question = question,
		options = options,
		counts = counts,
		ends = os.time() + math.floor(minutes * 60),
		by = by,
		done = false,
	}
	nextId += 1
	current = v
	ballots = {}
	push()
	task.delay(minutes * 60, function()
		if current == v then
			finish()
		end
	end)
	return true
end

function VoteService.End(): boolean
	if not current or current.done then
		return false
	end
	finish()
	return true
end

function VoteService.IsRunning(): boolean
	return current ~= nil and not current.done
end

function VoteService.Start()
	Remotes.Handle("Vote.Get", function(player)
		return Remotes.Ok({ vote = public(current), mine = ballots[player.UserId] })
	end, { rate = 6, needsData = false })

	Remotes.Handle("Vote.Cast", function(player, index: any)
		local v = current
		if not v or v.done then
			return Remotes.Fail("no_vote")
		end
		local i = Remotes.Check.Int(index, 1, #v.options)
		if not i then
			return Remotes.Fail("bad_request")
		end
		if ballots[player.UserId] then
			return Remotes.Fail("already_voted")
		end
		ballots[player.UserId] = i
		v.counts[i] += 1
		push()
		return Remotes.Ok()
	end, { rate = 4, needsData = false })
end

return VoteService
