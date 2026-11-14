-- Client entry point.

local Client = script.Parent:WaitForChild("Client")

local Net = require(Client.Net)
local Store = require(Client.Store)
local Notify = require(Client.UI.Notify)
local HUD = require(Client.UI.HUD)
local Phone = require(Client.Phone.Phone)
require(Client.UI.Shops)
require(Client.UI.Inventory)
require(Client.UI.Vote)
require(Client.UI.Countdown)
require(Client.UI.PlatePrompt)

-- Phone apps register themselves.
for _, app in Client.Phone.Apps:GetChildren() do
	if app:IsA("ModuleScript") then
		require(app)
	end
end

require(Client.Controllers.VehicleController)
require(Client.Controllers.WorldController)
require(Client.Controllers.AdminController)
require(Client.Controllers.StuntPoses)
require(Client.Controllers.EventMusic)
require(Client.Controllers.TrafficLights)
require(Client.Controllers.DropEventFX)
require(Client.Controllers.TrainController)

HUD.PhoneButton.Activated:Connect(Phone.Toggle)
Net.On("OpenPC", function(payload)
	Phone.OpenPC(if typeof(payload) == "table" then payload.monitor else nil)
end)

Net.On("Notify", Notify.Key)
Net.On("Events", HUD.SetEvents)
task.spawn(function()
	local r = Net.Request("Events.Get")
	if r.ok then
		HUD.SetEvents(r)
	end
end)
Net.On("XP", function(payload)
	Notify.Show(
		Store.T("xp_gain", payload.amount) .. (if payload.reason then " · " .. tostring(payload.reason) else ""),
		false,
		2.5
	)
end)
Net.On("LevelUp", function(payload)
	Notify.Show("⭐ " .. Store.T("level_up", payload.level), false, 5)
end)
Net.On("Announce", function(payload)
	if typeof(payload) == "table" then
		Notify.Announce(tostring(payload.text), payload.from and tostring(payload.from) or nil)
	end
end)

print("[Dortmund RP] Client ready")
