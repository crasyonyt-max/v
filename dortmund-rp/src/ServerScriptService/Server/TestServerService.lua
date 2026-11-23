--!strict
-- Admin testing server: one reserved server of this game, the same for every admin
-- (its access code + id are saved in Sandbox.STORE). Game Admins join it from the Admin
-- app ("🧪 Testserver", no menu: one click teleports) and come back with "🏠 Zum Spiel".
-- There everything stays inside the server (Sandbox): bans only kick, events only run
-- there, money / XP / items aren't saved. Only Game Admins and higher may be there.

local DataStoreService = game:GetService("DataStoreService") -- the real one: the saved test server
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local GameLog = require(script.Parent.GameLog)
local Remotes = require(script.Parent.Remotes)
local Roles = require(script.Parent.Roles)
local Sandbox = require(script.Parent.Sandbox)

local TestServerService = {}

function TestServerService.MayJoin(player: Player): boolean
	return Roles.IsGameAdmin(player)
end

local function guard(player: Player)
	if Config.Testing and not TestServerService.MayJoin(player) then
		player:Kick("🧪 Der Testserver ist nur für Admins. / The test server is for admins only.")
	end
end

-- the testing server's access code (made once, then always the same server)
local function accessCode(): string?
	local store = DataStoreService:GetDataStore(Sandbox.STORE)
	local rec = store:GetAsync("server")
	if typeof(rec) == "table" and typeof(rec.code) == "string" then
		return rec.code
	end
	local code, id = TeleportService:ReserveServer(game.PlaceId)
	local final = nil
	store:UpdateAsync("server", function(old: any)
		if typeof(old) == "table" and typeof(old.code) == "string" then
			final = old.code -- another server was quicker: use that one
			return nil
		end
		final = code
		return { code = code, id = id, t = os.time() }
	end)
	return final
end

function TestServerService.Start()
	if Config.Testing then
		Players.PlayerAdded:Connect(guard)
		for _, p in Players:GetPlayers() do
			guard(p)
		end
	end
	Remotes.Handle("TestServer.Join", function(player)
		if not TestServerService.MayJoin(player) then
			return Remotes.Fail("test_only_admins")
		end
		local ok, err = pcall(function()
			if Config.Testing then
				-- back to a normal server of the game
				TeleportService:TeleportAsync(game.PlaceId, { player })
			else
				local code = accessCode()
				assert(code, "no access code")
				local options = Instance.new("TeleportOptions")
				options.ReservedServerAccessCode = code
				TeleportService:TeleportAsync(game.PlaceId, { player }, options)
			end
		end)
		if not ok then
			warn("[TestServer] teleport failed: " .. tostring(err))
			return Remotes.Fail("teleport_failed")
		end
		GameLog.Add("admin", player, if Config.Testing then "left the test server" else "joined the test server")
		return Remotes.Ok()
	end, { rate = 3, needsData = false })
end

return TestServerService
