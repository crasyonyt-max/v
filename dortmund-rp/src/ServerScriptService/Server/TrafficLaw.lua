--!strict
-- Update 2 (Config.Update2, testing server first):
--   🚓 Police traffic stops: officers on duty pull a car over ("Anhalten": a big
--      STOP POLIZEI sign for the driver; driving off = wanted), check the person
--      ("Kontrolle": name, job, wanted) and give fines (30 / 80 / 150 / 300 €, the
--      officer gets 20 %).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CareerService = require(script.Parent.CareerService)
local CrimeService = require(script.Parent.CrimeService)
local Economy = require(script.Parent.EconomyService)
local GameLog = require(script.Parent.GameLog)
local JobService = require(script.Parent.JobService)
local Remotes = require(script.Parent.Remotes)

local TrafficLaw = {}

TrafficLaw.FINES = { 30, 80, 150, 300 }
TrafficLaw.OFFICER_SHARE = 0.2

local stops: { [Player]: { by: Player, pos: Vector3, t: number } } = {}

local function on(): boolean
	return Config.On(Config.Update2)
end

local function rootPos(p: Player): Vector3?
	local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return r and r.Position
end

local function distance(a: Player, b: Player): number
	local pa, pb = rootPos(a), rootPos(b)
	return if pa and pb then (pa - pb).Magnitude else math.huge
end

local function isPolice(p: Player): boolean
	return JobService.Get(p) == "Police"
end

local function driving(p: Player): boolean
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	return seat ~= nil and seat:IsA("VehicleSeat")
end

local function target(player: Player, userId: any, maxDist: number): Player?
	local t = typeof(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
	if not t or t == player or distance(player, t) > maxDist then
		return nil
	end
	return t
end

function TrafficLaw.Start()
	if not on() then
		return
	end
	-- police: pull over / check / fine
	Remotes.Handle("Police.Stop", function(player, userId: any)
		if not isPolice(player) then
			return Remotes.Fail("wrong_job")
		end
		local t = target(player, userId, 80)
		if not t then
			return Remotes.Fail("too_far")
		end
		if not driving(t) then
			return Remotes.Fail("police_not_driving")
		end
		local pos = rootPos(t)
		stops[t] = { by = player, pos = pos or Vector3.zero, t = os.clock() }
		Remotes.Push(t, "PoliceStop", { by = player.DisplayName, seconds = 20 })
		GameLog.Add("admin", player, "traffic stop " .. t.Name)
		return Remotes.Ok()
	end, { rate = 4 })

	Remotes.Handle("Police.Check", function(player, userId: any)
		if not isPolice(player) then
			return Remotes.Fail("wrong_job")
		end
		local t = target(player, userId, 25)
		if not t then
			return Remotes.Fail("too_far")
		end
		stops[t] = nil -- stopped properly
		Remotes.Push(t, "Notify", { key = "police_checked_you", args = { player.DisplayName } })
		return Remotes.Ok({
			name = t.DisplayName,
			wanted = CrimeService.IsCriminal(t),
			job = JobService.Get(t),
		})
	end, { rate = 6 })

	Remotes.Handle("Police.Fine", function(player, userId: any, amount: any)
		if not isPolice(player) then
			return Remotes.Fail("wrong_job")
		end
		local t = target(player, userId, 25)
		local a = tonumber(amount)
		if not t or not a or not table.find(TrafficLaw.FINES, a) then
			return Remotes.Fail("bad_request")
		end
		local pay = math.min(a, Economy.Balance(t))
		if pay > 0 then
			Economy.TrySpend(t, pay, "Bußgeld")
			Economy.Add(player, math.floor(pay * TrafficLaw.OFFICER_SHARE * 100) / 100, "Bußgeld kassiert")
		end
		CareerService.Progress(player, "fine")
		Remotes.Push(t, "Notify", { key = "police_fined_you", args = { pay } })
		GameLog.Add("money", t, ("fine %d € by %s"):format(pay, player.Name))
		return Remotes.Ok({ paid = pay })
	end, { rate = 4 })

	-- a stopped driver who drives off (more than 150 studs) is wanted
	task.spawn(function()
		while true do
			task.wait(2)
			for t, s in stops do
				local pos = rootPos(t)
				if not t.Parent or not pos or os.clock() - s.t > 60 then
					stops[t] = nil
				elseif os.clock() - s.t > 8 and (pos - s.pos).Magnitude > 150 then
					stops[t] = nil
					CrimeService.Crime(t, "Flucht vor der Polizei")
					if s.by.Parent then
						Remotes.Push(s.by, "Notify", { key = "police_fled", args = { t.DisplayName } })
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		stops[p] = nil
	end)
end

return TrafficLaw
