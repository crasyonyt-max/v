--!strict
-- XP: one global total (player level) + one total per job (unlocks job vehicles).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Jobs = require(ReplicatedStorage.Shared.Jobs)
local Levels = require(ReplicatedStorage.Shared.Levels)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local XPService = {}

function XPService.Add(player: Player, jobId: string?, amount: number, reason: string?)
	local data = DataService.Get(player)
	if not data or amount ~= amount or amount <= 0 or amount > 1e7 then
		return
	end
	amount = math.floor(amount)
	local before = Levels.FromTotal(data.xp)
	data.xp += amount
	if jobId and Jobs.ById[jobId] then
		data.jobXP[jobId] = (data.jobXP[jobId] or 0) + amount
	end
	local after = Levels.FromTotal(data.xp)
	player:SetAttribute("Level", after)
	Remotes.Push(player, "XP", { amount = amount, reason = reason })
	if after > before then
		Remotes.Push(player, "LevelUp", { level = after })
	end
	State.MarkDirty(player)
end

function XPService.JobXP(player: Player, jobId: string): number
	local data = DataService.Get(player)
	return if data then data.jobXP[jobId] or 0 else 0
end

return XPService
