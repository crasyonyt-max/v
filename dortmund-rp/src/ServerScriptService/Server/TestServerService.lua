--!strict
-- Admin testing server: a second place of the experience (Config.TestPlaceId) that
-- gets new updates first. Game Admins join it from the Admin app ("🧪 Testserver",
-- no menu: one click teleports) and come back with "🏠 Zum Spiel". On that place
-- everything stays inside the server (Sandbox): bans only kick, events only run
-- there, money / XP / items aren't saved. Only Game Admins and higher may be there.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local GameLog = require(script.Parent.GameLog)
local Remotes = require(script.Parent.Remotes)
local Roles = require(script.Parent.Roles)

local TestServerService = {}

function TestServerService.MayJoin(player: Player): boolean
	return Roles.IsGameAdmin(player)
end

local function guard(player: Player)
	if Config.Testing and not TestServerService.MayJoin(player) then
		player:Kick("🧪 Der Testserver ist nur für Admins. / The test server is for admins only.")
	end
end

function TestServerService.Start()
	if Config.Testing then
		Players.PlayerAdded:Connect(guard)
		for _, p in Players:GetPlayers() do
			guard(p)
		end
	end
	Remotes.Handle("TestServer.Join", function(player)
		if Config.TestPlaceId == 0 then
			return Remotes.Fail("test_not_set")
		end
		if not TestServerService.MayJoin(player) then
			return Remotes.Fail("test_only_admins")
		end
		local target = if Config.Testing then Config.MainPlaceId else Config.TestPlaceId
		GameLog.Add("admin", player, if Config.Testing then "left the test server" else "joined the test server")
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(target, { player })
		end)
		if not ok then
			warn("[TestServer] teleport failed: " .. tostring(err))
			return Remotes.Fail("teleport_failed")
		end
		return Remotes.Ok()
	end, { rate = 3, needsData = false })
end

return TestServerService
