-- Server entry point. Order matters: services connect to DataService.Loaded
-- before DataService starts loading players.

local Players = game:GetService("Players")
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

-- Nobody spawns until the city exists (otherwise they would fall).
Players.CharacterAutoLoads = false
MapBuilder.Build()
require(Server.TrafficService).Build()
require(Server.AdminTowerService).Build()
require(Server.MallBuilder).Build()
require(Server.GarageService).Build()
require(Server.PlateService).Build()
Interaction.Start()
task.spawn(require(Server.StoreBuilder).Build) -- NPCs load from the web; don't block spawning
Players.CharacterAutoLoads = true
for _, player in Players:GetPlayers() do
	if not player.Character then
		task.spawn(player.LoadCharacter, player)
	end
end

local services = {
	require(Server.GameLog),
	require(Server.WorldService),
	require(Server.EconomyService),
	require(Server.JobService),
	require(Server.PhoneService),
	require(Server.ChatService),
	require(Server.EmergencyService),
	require(Server.VehicleService),
	require(Server.BusService),
	require(Server.AdminService),
	require(Server.StoreService),
	require(Server.NewsService),
	require(Server.EventService),
	require(Server.VoteService),
	require(Server.HousingService),
	require(Server.TrafficService),
	require(Server.AdminTowerService),
	require(Server.MallBuilder),
	require(Server.GarageService),
	require(Server.DropEventService),
	require(Server.DropperService),
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
