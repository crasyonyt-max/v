--!strict
-- Earthquake easter egg (QuakeService): shakes the camera and shows a warning.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Make = require(script.Parent.Parent.UI.Make)
local Net = require(script.Parent.Parent.Net)

local New, T = Make.New, Make.Theme
local player = Players.LocalPlayer

local gui = New("ScreenGui", {
	Name = "Quake",
	ResetOnSpawn = false,
	DisplayOrder = 60,
	Enabled = false,
	Parent = player:WaitForChild("PlayerGui"),
})
local banner = New("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.fromOffset(560, 84),
	BackgroundColor3 = Color3.fromRGB(170, 20, 20),
	TextColor3 = Color3.new(1, 1, 1),
	Font = T.black,
	TextScaled = true,
	RichText = true,
	Text = "",
	Parent = gui,
}, { Make.Corner(14), Make.Padding(10), Make.Stroke(Color3.fromRGB(255, 220, 0), 3) })

local untilTime = 0
local strength = 0
local duration = 1

RunService:BindToRenderStep("QuakeShake", Enum.RenderPriority.Camera.Value + 1, function()
	local left = untilTime - os.clock()
	if left <= 0 then
		if gui.Enabled then
			gui.Enabled = false
		end
		return
	end
	local fade = math.clamp(left / duration, 0, 1)
	local a = strength * fade
	local t = os.clock() * 30
	local cam = Workspace.CurrentCamera
	cam.CFrame = cam.CFrame
		* CFrame.new(math.noise(t, 0) * a, math.noise(0, t) * a, 0)
		* CFrame.Angles(math.noise(t, 7) * a * 0.05, math.noise(7, t) * a * 0.05, math.noise(t, t) * a * 0.08)
	banner.Rotation = math.noise(t, 3) * 4 * fade
end)

Net.On("Quake", function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	strength = math.clamp(tonumber(payload.strength) or 1, 0.2, 4)
	duration = math.clamp(tonumber(payload.duration) or 5, 1, 15)
	untilTime = os.clock() + duration
	banner.Text = ("⚠️ ERDBEBEN ⚠️\nStärke %s · Ursache: %s"):format(
		tostring(payload.magnitude),
		tostring(payload.who)
	)
	gui.Enabled = true
end)

return {}
