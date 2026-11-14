--[[
	VehicleAccess (server only)

	All rules for who may buy, claim, spawn and repaint what. Every function
	returns (ok: boolean, reason: string).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerData = require(script.Parent.PlayerDataAdapter)
local AdminConfig = require(script.Parent.AdminConfig)
local ServerAdmins = require(script.Parent.ServerAdmins)

local Access = {}

-------------------------------------------------------------------------------
-- Admins and gamepasses
-------------------------------------------------------------------------------

function Access.IsGameAdmin(player)
	return AdminConfig.IsGameAdmin(player.UserId)
end

function Access.IsServerAdmin(player)
	return ServerAdmins.IsServerAdmin(player)
end

local passCache = {} -- [player] = { [gamepassId] = true/false }

function Access.OwnsGamepass(player, gamepass)
	if not gamepass then
		return true
	end
	if gamepass.Id == 0 then
		-- Placeholder ID: usable in Studio for testing, locked in live games.
		if RunService:IsStudio() then
			return true
		end
		warn(("[VehicleAccess] Gamepass pack %s still has placeholder ID 0"):format(gamepass.Pack))
		return false
	end
	local cache = passCache[player]
	if not cache then
		cache = {}
		passCache[player] = cache
	end
	if cache[gamepass.Id] == nil then
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, gamepass.Id)
		if not ok then
			warn("[VehicleAccess] Gamepass check failed: " .. tostring(owns))
			return false -- don't cache failures
		end
		cache[gamepass.Id] = owns
	end
	return cache[gamepass.Id]
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, purchased)
	if purchased then
		passCache[player] = passCache[player] or {}
		passCache[player][gamepassId] = true
	end
end)
Players.PlayerRemoving:Connect(function(player)
	passCache[player] = nil
end)

-------------------------------------------------------------------------------
-- Rules
-------------------------------------------------------------------------------

local BUYABLE = { Dealership = true, Gamepass = true }
local OWNABLE = { Dealership = true, Gamepass = true, Starter = true }

function Access.CanBuy(player, vehicle)
	if not PlayerData.IsLoaded(player) then
		return false, "Your data is still loading."
	end
	if not BUYABLE[vehicle.Category] then
		return false, "This vehicle can't be bought."
	end
	if PlayerData.OwnsVehicle(player, vehicle.Id) then
		return false, "You already own this vehicle."
	end
	if vehicle.Gamepass and not Access.OwnsGamepass(player, vehicle.Gamepass) then
		return false, ("Requires the %s gamepass (%d R$)."):format(vehicle.Gamepass.Pack, vehicle.Gamepass.Robux)
	end
	if PlayerData.GetMoney(player) < vehicle.Price then
		return false, "Not enough money."
	end
	return true, "OK"
end

function Access.CanClaimStarter(player, vehicle)
	if not PlayerData.IsLoaded(player) then
		return false, "Your data is still loading."
	end
	if vehicle.Category ~= "Starter" then
		return false, "That is not a starter car."
	end
	if PlayerData.HasClaimedStarter(player) then
		return false, "You already picked your starter car."
	end
	return true, "OK"
end

function Access.CanSpawn(player, vehicle)
	if not PlayerData.IsLoaded(player) then
		return false, "Your data is still loading."
	end
	local category = vehicle.Category

	if OWNABLE[category] then
		if not PlayerData.OwnsVehicle(player, vehicle.Id) then
			return false, "You don't own this vehicle."
		end
		return true, "OK"
	end

	if vehicle.Job then
		local current = PlayerData.GetCurrentJob(player)
		if current ~= vehicle.Job then
			return false, ("You must be on duty as %s to use this vehicle."):format(vehicle.Job)
		end
		local xp = PlayerData.GetJobXP(player, vehicle.Job)
		if xp < vehicle.XPRequired then
			return false, ("Requires %d %s XP (you have %d)."):format(vehicle.XPRequired, vehicle.Job, xp)
		end
		return true, "OK"
	end

	if category == "ServerAdmin" then
		if not Access.IsServerAdmin(player) then
			return false, "Only Server Admins of this private server can use this vehicle."
		end
		return true, "OK"
	end

	if category == "GameAdmin" then
		if not Access.IsGameAdmin(player) then
			return false, "Only Game Admins can use this vehicle."
		end
		return true, "OK"
	end

	return false, "This vehicle is not available."
end

function Access.CanRepaint(player, vehicle)
	if not vehicle.Repaintable then
		return false, "This vehicle's livery is locked."
	end
	if not PlayerData.OwnsVehicle(player, vehicle.Id) then
		return false, "You don't own this vehicle."
	end
	return true, "OK"
end

return Access
