--!strict
-- Admin testing server: a purple banner at the top so nobody mistakes it for the game.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Make = require(script.Parent.Parent.UI.Make)
local Store = require(script.Parent.Parent.Store)

if not Config.Testing then
	return {}
end

local gui = Make.New("ScreenGui", {
	Name = "TestBanner",
	ResetOnSpawn = false,
	DisplayOrder = 40,
	IgnoreGuiInset = false,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})
Make.Label(Store.T("test_banner"), 13, Color3.new(1, 1, 1), Make.Theme.bold, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 4),
	Size = UDim2.fromOffset(340, 24),
	BackgroundTransparency = 0.1,
	BackgroundColor3 = Color3.fromRGB(130, 40, 190),
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = gui,
}, { Make.Corner(8) })

return {}
