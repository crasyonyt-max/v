--!strict
-- Jobs: start a job at its station, quit anywhere via the phone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Jobs = require(ReplicatedStorage.Shared.Jobs)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Interaction = require(script.Parent.InteractionService)

local JobService = {}

local changedEvent = Instance.new("BindableEvent")
JobService.Changed = changedEvent.Event -- (player, oldJob, newJob)

local lastChange: { [Player]: number } = {}
-- Every team needs its own BrickColor (Roblox links Player.Team and TeamColor).
local TEAM_COLORS = {
	Unemployed = "Medium stone grey",
	Police = "Bright blue",
	Fire = "Bright red",
	Rettungsdienst = "Neon orange",
	Notarzt = "Bright yellow",
	ADMC = "New Yeller",
	DXL = "Daisy orange",
	LKW = "Sea green",
}
local teams: { [string]: Team } = {}

local function setupTeams()
	for _, job in Jobs.List do
		local team = Instance.new("Team")
		team.Name = job.de
		team.TeamColor = BrickColor.new(TEAM_COLORS[job.id] or "White")
		team.AutoAssignable = false
		team:SetAttribute("JobId", job.id)
		team.Parent = Teams
		teams[job.id] = team
	end
end

function JobService.Get(player: Player): string
	local data = DataService.Get(player)
	return if data then data.job else "Unemployed"
end

function JobService.Apply(player: Player)
	local job = JobService.Get(player)
	player:SetAttribute("Job", job)
	player.Team = teams[job]
end

function JobService.Set(player: Player, jobId: string): (boolean, string?)
	local data = DataService.Get(player)
	if not data or not Jobs.ById[jobId] then
		return false, "bad_job"
	end
	if data.job == jobId then
		return false, "same_job"
	end
	local now = os.clock()
	if lastChange[player] and now - lastChange[player] < 20 then
		return false, "too_fast"
	end
	lastChange[player] = now
	local old = data.job
	data.job = jobId
	JobService.Apply(player)
	State.MarkDirty(player)
	changedEvent:Fire(player, old, jobId)
	Remotes.Push(player, "Notify", { key = "job_changed", args = { jobId } })
	return true, nil
end

function JobService.Start()
	setupTeams()

	DataService.Loaded:Connect(function(player)
		JobService.Apply(player)
	end)

	-- Station prompts: "Dienst antreten" at each job station.
	Interaction.OnTrigger("JobStart", function(player, marker)
		local jobId = marker:GetAttribute("JobId")
		if typeof(jobId) ~= "string" then
			return
		end
		local ok, err = JobService.Set(player, jobId)
		if not ok and err then
			Remotes.Push(player, "Notify", { key = err, error = true })
		end
	end)

	Remotes.Handle("Job.Quit", function(player)
		local ok, err = JobService.Set(player, "Unemployed")
		return if ok then Remotes.Ok() else Remotes.Fail(err or "error")
	end, { rate = 3 })

	Players.PlayerRemoving:Connect(function(player)
		lastChange[player] = nil
	end)
end

return JobService
