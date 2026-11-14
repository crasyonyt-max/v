--!strict
-- Robux -> money (Developer Products, Config.MoneyProducts): can be bought any
-- number of times. Roblox calls ProcessReceipt until we answer PurchaseGranted, maybe
-- more than once and on another server, so every PurchaseId is paid out only once:
-- it is stored with the player's data and the data is saved BEFORE we say "granted".

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local GameLog = require(script.Parent.GameLog)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Remotes = require(script.Parent.Remotes)

local PurchaseService = {}

local KEEP = 100 -- remembered receipts per player

local function productFor(id: number): { [string]: any }?
	for _, p in Config.MoneyProducts do
		if p.id ~= 0 and p.id == id then
			return p
		end
	end
	return nil
end

local function alreadyPaid(data: { [string]: any }, purchaseId: string): boolean
	for _, r in data.receipts do
		if r == purchaseId then
			return true
		end
	end
	return false
end

-- returns the Enum.ProductPurchaseDecision name (also used by the tests)
function PurchaseService.Process(receipt: { [string]: any }): string
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = productFor(receipt.ProductId)
	if not player or not product then
		return "NotProcessedYet" -- player left / unknown product: Roblox asks again later
	end
	local data = DataService.Get(player)
	if not data then
		return "NotProcessedYet"
	end
	data.receipts = data.receipts or {}
	local purchaseId = tostring(receipt.PurchaseId)
	if not alreadyPaid(data, purchaseId) then
		if not Economy.Add(player, product.cash, "Robux-Kauf: " .. Locale.Euro(product.cash)) then
			return "NotProcessedYet"
		end
		table.insert(data.receipts, purchaseId)
		while #data.receipts > KEEP do
			table.remove(data.receipts, 1)
		end
		GameLog.Add("money", player, ("bought %d € for Robux (product %d)"):format(product.cash, product.id))
		Remotes.Push(player, "Notify", { key = "money_bought", args = { Locale.Euro(product.cash) } })
	end
	-- only "granted" once it is saved; otherwise Roblox retries and the receipt id
	-- above makes sure the money is not paid twice
	if DataService.Save(player, false) then
		return "PurchaseGranted"
	end
	return "NotProcessedYet"
end

function PurchaseService.Start()
	MarketplaceService.ProcessReceipt = function(receipt)
		local ok, decision = pcall(PurchaseService.Process, receipt)
		if ok and decision == "PurchaseGranted" then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if not ok then
			warn("[Purchase] " .. tostring(decision))
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

return PurchaseService
