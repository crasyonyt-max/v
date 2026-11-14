--!strict
-- Stadtbahn rider HUD: line + destination, next stop / "you can get off now".

local Players = game:GetService("Players")

local Make = require(script.Parent.Parent.UI.Make)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme
local player = Players.LocalPlayer

local gui = New("ScreenGui", {
	Name = "TrainHUD",
	ResetOnSpawn = false,
	DisplayOrder = 9,
	Enabled = false,
	Parent = player:WaitForChild("PlayerGui"),
})
local panel = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.fromOffset(340, 66),
	BackgroundColor3 = Color3.fromRGB(8, 8, 10),
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { Make.Corner(12), Make.Stroke(Color3.fromRGB(0, 133, 199), 2) })
local led = New("TextLabel", {
	Position = UDim2.fromOffset(8, 6),
	Size = UDim2.new(1, -16, 0, 26),
	BackgroundColor3 = Color3.fromRGB(14, 14, 14),
	Font = Enum.Font.Arcade,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 170, 30),
	Text = "",
	Parent = panel,
}, { Make.Corner(6) })
local info = Make.Label("", 13, T.text, T.bold, {
	Position = UDim2.fromOffset(10, 38),
	Size = UDim2.new(1, -20, 0, 22),
	Parent = panel,
})

local car: Model? = nil
local conns: { RBXScriptConnection } = {}

local function refresh()
	local m = car
	if not m then
		return
	end
	led.Text = "U"
		.. tostring(m:GetAttribute("Line") or ""):sub(2)
		.. "  → "
		.. tostring(m:GetAttribute("Dest") or "")
	local station = tostring(m:GetAttribute("Station") or "")
	info.Text = if m:GetAttribute("AtStation") then Store.T("train_at", station) else Store.T("train_next", station)
end

local function leave()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	car = nil
	gui.Enabled = false
end

local function enter(model: Model)
	leave()
	car = model
	gui.Enabled = true
	for _, a in { "Dest", "Station", "AtStation" } do
		table.insert(conns, model:GetAttributeChangedSignal(a):Connect(refresh))
	end
	refresh()
end

local function watch(character: Model)
	leave()
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		local seat = hum.SeatPart
		local model = seat and seat.Parent
		if seat and model and model:IsA("Model") and model:GetAttribute("Train") then
			enter(model)
		elseif car then
			leave()
		end
	end)
end
player.CharacterAdded:Connect(watch)
if player.Character then
	task.spawn(watch, player.Character)
end

return {}
