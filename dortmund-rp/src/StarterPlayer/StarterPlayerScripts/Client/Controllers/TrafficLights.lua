--!strict
-- Colours the traffic lights near the camera (timing from Shared/TrafficPhase, the
-- same the server checks red lights with) and flashes the screen at a speed camera.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TrafficPhase = require(ReplicatedStorage.Shared.TrafficPhase)
local Make = require(script.Parent.Parent.UI.Make)
local Net = require(script.Parent.Parent.Net)

local TrafficLights = {}

local OFF = Color3.fromRGB(30, 30, 30)
local ON = {
	Red = Color3.fromRGB(255, 40, 30),
	Yellow = Color3.fromRGB(255, 190, 0),
	Green = Color3.fromRGB(40, 230, 70),
}
local LIT = { G = { Green = true }, Y = { Yellow = true }, R = { Red = true } }

local function paint(head: Instance, state: string)
	for name, color in ON do
		local lamp = head:FindFirstChild(name) :: BasePart?
		if lamp then
			local on = LIT[state][name] == true
			lamp.Color = if on then color else OFF
			lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

task.spawn(function()
	while true do
		task.wait(0.25)
		local cam = Workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		local t = Workspace:GetServerTimeNow()
		for _, head in CollectionService:GetTagged("TrafficLight") do
			if head:IsA("BasePart") and (head.Position - camPos).Magnitude < 600 then
				local a, b = TrafficPhase.State(t, (head:GetAttribute("Index") or 0) :: number)
				paint(head, if head:GetAttribute("Axis") == "A" then a else b)
			end
		end
	end
end)

-- Blitzer flash
local flashGui = Make.New("ScreenGui", {
	Name = "Blitz",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 60,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})
local flash = Make.New("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 1,
	Parent = flashGui,
})
Net.On("Blitz", function()
	for _, tr in { 0, 0.4, 0.1, 0.7, 1 } do
		flash.BackgroundTransparency = tr
		task.wait(0.06)
	end
end)

return TrafficLights
