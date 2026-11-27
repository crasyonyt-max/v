--!strict
-- Update 2 (Config.Update2, testing server first):
--   * daily login reward: 250 € × days in a row (up to 7), and 3 daily tasks
--     (e.g. "serve 10 bus stops", "make 2 arrests") worth 400 € + 100 XP each
--   * job ranks (Shared/Ranks): shown on the HUD, +5 % paycheck per rank
--   * night bonus: +25 % paycheck between 22:00 and 6:00 game time

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local XPService = require(script.Parent.XPService)

local CareerService = {}

CareerService.DAILY_BASE = 250
CareerService.TASK_CASH = 400
CareerService.TASK_XP = 100
CareerService.NIGHT_BONUS = 0.25

-- the task pool: key (what counts), how many, the text key; `job` = only offered then
CareerService.Tasks = {
	{ key = "bus_stop", n = 10, job = "Bus" },
	{ key = "arrest", n = 2, job = "Police" },
	{ key = "fine", n = 3, job = "Police" },
	{ key = "fire", n = 1, job = "Fire" },
	{ key = "patient", n = 1, job = "Rettungsdienst" },
	{ key = "patient", n = 1, job = "Notarzt" },
	{ key = "repair", n = 2, job = "ADMC" },
	{ key = "taxi", n = 3, job = "Taxi" },
	{ key = "paycheck", n = 3 },
	{ key = "food", n = 2 },
	{ key = "call", n = 1 },
	{ key = "drive", n = 3 }, -- km
}

local function on(): boolean
	return Config.On(Config.Update2)
end

local function today(): number
	return os.time() // 86400
end

-- Daily --------------------------------------------------------------------------------

local function pickTasks(job: string, rng: Random): { { [string]: any } }
	local pool = {}
	for _, t in CareerService.Tasks do
		if not t.job or t.job == job then
			table.insert(pool, t)
		end
	end
	local out = {}
	-- one task for the current job first (if there is one), then random ones
	for _, t in pool do
		if t.job == job then
			table.insert(out, { key = t.key, n = t.n, have = 0 })
			break
		end
	end
	while #out < 3 and #pool > 0 do
		local t = table.remove(pool, rng:NextInteger(1, #pool))
		local dup = false
		for _, o in out do
			dup = dup or o.key == t.key
		end
		if not dup then
			table.insert(out, { key = t.key, n = t.n, have = 0 })
		end
	end
	return out
end

local function publish(player: Player)
	local data = DataService.Get(player)
	local d = data and data.daily
	if d then
		Remotes.Push(player, "Daily", { streak = d.streak, tasks = d.tasks, day = d.day })
	end
end

-- once a day on joining: the reward and new tasks
function CareerService.CheckDaily(player: Player, data: { [string]: any }, day: number?)
	local now = day or today()
	local d = data.daily
	if typeof(d) == "table" and d.day == now then
		return
	end
	local streak = if typeof(d) == "table" and d.day == now - 1 then math.min((d.streak or 0) + 1, 99) else 1
	data.daily = {
		day = now,
		streak = streak,
		tasks = pickTasks(tostring(data.job or "Unemployed"), Random.new(player.UserId + now)),
	}
	local reward = CareerService.DAILY_BASE * math.min(streak, 7)
	local paid = Economy.Earn(player, reward, "Täglicher Bonus (Tag " .. streak .. ")")
	State.MarkDirty(player)
	task.delay(4, function()
		if player.Parent then
			Remotes.Push(player, "Notify", { key = "daily_reward", args = { streak, paid } })
			publish(player)
		end
	end)
end

-- something counted for the daily tasks (called by the job services)
function CareerService.Progress(player: Player, key: string, n: number?)
	if not on() then
		return
	end
	local data = DataService.Get(player)
	local d = data and data.daily
	if not d or d.day ~= today() then
		return
	end
	for _, t in d.tasks do
		if t.key == key and not t.done then
			t.have = math.min(t.n, t.have + (n or 1))
			if t.have >= t.n then
				t.done = true
				Economy.Earn(player, CareerService.TASK_CASH, "Tagesaufgabe")
				XPService.Earn(player, nil, CareerService.TASK_XP, "Tagesaufgabe")
				Remotes.Push(player, "Notify", { key = "daily_task_done", args = { CareerService.TASK_CASH } })
			end
			State.MarkDirty(player)
			publish(player)
		end
	end
end

-- Ranks + paycheck -------------------------------------------------------------------------

function CareerService.Rank(player: Player): (number, string)
	local data = DataService.Get(player)
	local job = data and tostring(data.job) or "Unemployed"
	local xp = data and data.jobXP and data.jobXP[job] or 0
	return Ranks.For(job, xp)
end

local function setRank(player: Player)
	local data = DataService.Get(player)
	if not data or not on() then
		return
	end
	local job = tostring(data.job)
	if job == "Unemployed" then
		player:SetAttribute("JobRank", nil)
		return
	end
	local _, name = CareerService.Rank(player)
	player:SetAttribute("JobRank", name)
end

function CareerService.IsNight(clock: number?): boolean
	local t = clock or Lighting.ClockTime
	return t >= 22 or t < 6
end

-- the paycheck multiplier for this player now (rank + night)
function CareerService.PayFactor(player: Player): number
	if not on() then
		return 1
	end
	local data = DataService.Get(player)
	if not data or data.job == "Unemployed" then
		return 1
	end
	local r = CareerService.Rank(player)
	local f = 1 + (r - 1) * Ranks.BONUS
	if CareerService.IsNight() then
		f += CareerService.NIGHT_BONUS
	end
	return f
end

-- after a paycheck: the daily task and the rank on the HUD
function CareerService.AfterPaycheck(player: Player, _paid: number)
	if not on() then
		return
	end
	CareerService.Progress(player, "paycheck")
	setRank(player)
end

function CareerService.Start()
	if not on() then
		return
	end
	DataService.Loaded:Connect(function(player, data)
		CareerService.CheckDaily(player, data)
		setRank(player)
	end)
	-- the day changes while playing: next check on the next paycheck tick
	task.spawn(function()
		while true do
			task.wait(60)
			for _, p in Players:GetPlayers() do
				local data = DataService.Get(p)
				if data then
					CareerService.CheckDaily(p, data)
					setRank(p)
				end
			end
		end
	end)

	Remotes.Handle("Daily.Get", function(player)
		local data = DataService.Get(player)
		local d = data and data.daily
		return Remotes.Ok({ streak = d and d.streak or 0, tasks = d and d.tasks or {} })
	end, { rate = 6 })
end

return CareerService
