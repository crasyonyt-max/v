--!strict
-- Money. The ONLY place that changes a player's balance.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Jobs = require(ReplicatedStorage.Shared.Jobs)
local Boosts = require(script.Parent.Boosts)
local GameLog = require(script.Parent.GameLog)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local Economy = {}

local function logTx(data: { [string]: any }, amount: number, reason: string)
	table.insert(data.tx, { amount = amount, reason = reason, t = os.time() })
	while #data.tx > 30 do
		table.remove(data.tx, 1)
	end
end

function Economy.Balance(player: Player): number
	local data = DataService.Get(player)
	return if data then data.bank else 0
end

function Economy.Add(player: Player, amount: number, reason: string): boolean
	local data = DataService.Get(player)
	if not data or amount ~= amount or amount <= 0 or amount > 1e10 then
		return false
	end
	amount = math.floor(amount * 100 + 0.5) / 100 -- cents
	data.bank = math.floor((data.bank + amount) * 100 + 0.5) / 100
	logTx(data, amount, reason)
	GameLog.Add("money", player, string.format("+%.2f € %s (bank %.2f €)", amount, reason, data.bank))
	State.MarkDirty(player)
	return true
end

-- Money a player earns (pay, rewards): multiplied while a cash event runs.
function Economy.Earn(player: Player, amount: number, reason: string): number
	local mult = Boosts.Cash()
	local total = amount * mult
	if Economy.Add(player, total, if mult > 1 then string.format("%s (%gx)", reason, mult) else reason) then
		return total
	end
	return 0
end

function Economy.TrySpend(player: Player, amount: number, reason: string): boolean
	local data = DataService.Get(player)
	if not data or amount ~= amount or amount < 0 then
		return false
	end
	amount = math.floor(amount * 100 + 0.5) / 100 -- cents
	if data.bank < amount then
		return false
	end
	data.bank = math.floor((data.bank - amount) * 100 + 0.5) / 100
	if amount > 0 then
		logTx(data, -amount, reason)
		GameLog.Add("money", player, string.format("-%.2f € %s (bank %.2f €)", amount, reason, data.bank))
	end
	State.MarkDirty(player)
	return true
end

local function paychecks()
	while true do
		task.wait(Config.PaycheckInterval)
		for _, player in Players:GetPlayers() do
			local data = DataService.Get(player)
			if data then
				local job = Jobs.ById[data.job] or Jobs.ById.Unemployed
				local paid = Economy.Earn(
					player,
					job.paycheck,
					if job.id == "Unemployed" then "Bürgergeld" else "Gehalt " .. job.de
				)
				Remotes.Push(player, "Notify", { key = "paycheck", args = { paid } })
			end
		end
	end
end

function Economy.Start()
	task.spawn(paychecks)

	Remotes.Handle("Bank.Transfer", function(player, targetUserId: any, amount: any)
		local Check = Remotes.Check
		local target = Check.Int(targetUserId, 1, 1e12)
		local value = Check.Int(amount, 1, Config.MaxTransfer)
		if not target or not value then
			return Remotes.Fail("bad_amount")
		end
		if target == player.UserId then
			return Remotes.Fail("bad_target")
		end
		local targetPlayer = Players:GetPlayerByUserId(target)
		if not targetPlayer or not DataService.IsLoaded(targetPlayer) then
			return Remotes.Fail("target_offline")
		end
		if not Economy.TrySpend(player, value, "Überweisung an " .. targetPlayer.Name) then
			return Remotes.Fail("no_money")
		end
		Economy.Add(targetPlayer, value, "Überweisung von " .. player.Name)
		Remotes.Push(targetPlayer, "Notify", { key = "transfer_in", args = { value, player.DisplayName } })
		return Remotes.Ok()
	end, { rate = 5 })
end

return Economy
