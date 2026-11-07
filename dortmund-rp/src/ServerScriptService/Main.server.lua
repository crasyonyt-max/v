-- Server entry point. Order matters: services connect to DataService.Loaded
-- before DataService starts loading players.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent:WaitForChild("Server")
local Levels = require(ReplicatedStorage.Shared.Levels)

local Remotes = require(Server.Remotes)
local DataService = require(Server.DataService)
local Interaction = require(Server.InteractionService)
local MapBuilder = require(Server.MapBuilder)
local Roles = require(Server.Roles)
local State = require(Server.State)

Remotes.IsReady = DataService.IsLoaded

MapBuilder.Build()
Interaction.Start()

local services = {
	require(Server.WorldService),
	require(Server.EconomyService),
	require(Server.JobService),
	require(Server.PhoneService),
	require(Server.ChatService),
	require(Server.EmergencyService),
	require(Server.VehicleService),
	require(Server.AdminService),
}
for _, service in services do
	service.Start()
end
State.Start()

DataService.Loaded:Connect(function(player, data)
	Roles.Refresh(player)
	player:SetAttribute("Level", (Levels.FromTotal(data.xp)))
	player:SetAttribute("PhoneNumber", State.PhoneNumber(player.UserId))
	State.SendNow(player)
end)

DataService.Start()

print("[Dortmund RP] Server started")
