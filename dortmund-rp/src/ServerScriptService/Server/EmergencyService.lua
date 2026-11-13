--!strict
-- Emergency calls (110 / 112). Callers create a call at their position,
-- matching on-duty players accept and drive there; arriving completes the call.
-- Anti-farming: caller cooldown, responder must travel, cannot respond to own call.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ChatService = require(script.Parent.ChatService)
local Economy = require(script.Parent.EconomyService)
local JobService = require(script.Parent.JobService)
local GameLog = require(script.Parent.GameLog)
local Remotes = require(script.Parent.Remotes)
local XPService = require(script.Parent.XPService)

local Emergency = {}

type Call = {
	id: string,
	number: string,
	jobs: { string },
	callerId: number,
	callerName: string,
	text: string,
	position: Vector3,
	created: number,
	responders: { [number]: { job: string, accepted: number, startDistance: number } },
}

local calls: { [string]: Call } = {}
local lastCall: { [number]: number } = {}
local EXPIRE = 15 * 60

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function public(call: Call): { [string]: any }
	local count = 0
	for _ in call.responders do
		count += 1
	end
	return {
		id = call.id,
		number = call.number,
		callerName = call.callerName,
		text = call.text,
		position = call.position,
		created = call.created,
		responders = count,
	}
end

local function servesCall(player: Player, call: Call): boolean
	return table.find(call.jobs, JobService.Get(player)) ~= nil
end

local function broadcast(call: Call, kind: string)
	for _, player in Players:GetPlayers() do
		if servesCall(player, call) then
			Remotes.Push(player, kind, public(call))
		end
	end
end

function Emergency.Start()
	Remotes.Handle("Call.Make", function(player, number: any, text: any)
		local num = Remotes.Check.String(number, 5)
		local jobs = num and Config.EmergencyNumbers[num]
		if not num or not jobs then
			return Remotes.Fail("bad_number")
		end
		local body = Remotes.Check.String(text, 200) or "Notruf"
		local now = os.time()
		if lastCall[player.UserId] and now - lastCall[player.UserId] < Config.CallCooldown then
			return Remotes.Fail("call_cooldown")
		end
		local root = rootOf(player)
		if not root then
			return Remotes.Fail("no_character")
		end
		local filtered = ChatService.Filter(body, player.UserId)
		if not filtered then
			return Remotes.Fail("filter_failed")
		end
		lastCall[player.UserId] = now
		GameLog.Add("call", player, num .. ": " .. filtered)
		local call: Call = {
			id = HttpService:GenerateGUID(false),
			number = num,
			jobs = jobs,
			callerId = player.UserId,
			callerName = player.DisplayName,
			text = filtered,
			position = root.Position,
			created = now,
			responders = {},
		}
		calls[call.id] = call
		broadcast(call, "CallNew")
		return Remotes.Ok({ id = call.id })
	end, { rate = 3 })

	Remotes.Handle("Call.List", function(player)
		local out = {}
		for _, call in calls do
			if servesCall(player, call) then
				local p = public(call)
				p.mine = call.responders[player.UserId] ~= nil
				table.insert(out, p)
			end
		end
		table.sort(out, function(a, b)
			return a.created > b.created
		end)
		return Remotes.Ok({ calls = out })
	end, { rate = 10 })

	Remotes.Handle("Call.Accept", function(player, id: any)
		local call = typeof(id) == "string" and calls[id] or nil
		if not call then
			return Remotes.Fail("call_gone")
		end
		if not servesCall(player, call) then
			return Remotes.Fail("wrong_job")
		end
		if call.callerId == player.UserId then
			return Remotes.Fail("own_call")
		end
		local root = rootOf(player)
		if not root then
			return Remotes.Fail("no_character")
		end
		call.responders[player.UserId] = {
			job = JobService.Get(player),
			accepted = os.clock(),
			startDistance = (root.Position - call.position).Magnitude,
		}
		local caller = Players:GetPlayerByUserId(call.callerId)
		if caller then
			Remotes.Push(caller, "Notify", { key = "call_accepted" })
		end
		broadcast(call, "CallUpdate")
		return Remotes.Ok({ position = call.position })
	end, { rate = 5 })

	Remotes.Handle("Call.Complete", function(player, id: any)
		local call = typeof(id) == "string" and calls[id] or nil
		if not call then
			return Remotes.Fail("call_gone")
		end
		local r = call.responders[player.UserId]
		if not r then
			return Remotes.Fail("not_accepted")
		end
		local root = rootOf(player)
		if not root or (root.Position - call.position).Magnitude > Config.CallArriveDistance then
			return Remotes.Fail("not_arrived")
		end
		if os.clock() - r.accepted < 10 then
			return Remotes.Fail("too_fast")
		end
		call.responders[player.UserId] = nil
		-- Reward only real responses (travelled there, still in the job).
		if r.startDistance >= Config.CallMinTravel and JobService.Get(player) == r.job then
			XPService.Earn(player, r.job, Config.CallXP, "Einsatz")
			Economy.Earn(player, Config.CallBonus, "Einsatzprämie")
		else
			Remotes.Push(player, "Notify", { key = "call_no_reward" })
		end
		if next(call.responders) == nil then
			calls[call.id] = nil
			broadcast(call, "CallClosed")
		end
		return Remotes.Ok()
	end, { rate = 5 })

	-- Expire old calls.
	task.spawn(function()
		while true do
			task.wait(30)
			local now = os.time()
			for id, call in calls do
				if now - call.created > EXPIRE then
					calls[id] = nil
					broadcast(call, "CallClosed")
				end
			end
		end
	end)
end

return Emergency
