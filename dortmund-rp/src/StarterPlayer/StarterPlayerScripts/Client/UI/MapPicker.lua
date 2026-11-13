--!strict
-- Full-screen city map to pick a spot (AA pickups). Tap = choose the spot (and zoom in
-- on the first tap), 🔍 buttons zoom, 📍 uses your own position, ✓ confirms.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local MapImage = require(ReplicatedStorage.Shared.MapImage)
local Make = require(script.Parent.Make)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme
local player = Players.LocalPlayer

local MapPicker = {}

local gui = New("ScreenGui", {
	Name = "MapPicker",
	ResetOnSpawn = false,
	DisplayOrder = 50,
	Enabled = false,
	Parent = player:WaitForChild("PlayerGui"),
})
New("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.35,
	Parent = gui,
})
local frame = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.46),
	Size = UDim2.fromScale(0.8, 0.8),
	BackgroundColor3 = Color3.fromRGB(38, 44, 40),
	ClipsDescendants = true,
	Parent = gui,
}, {
	Make.Corner(12),
	Make.Stroke(Color3.fromRGB(255, 170, 0), 2),
	New("UIAspectRatioConstraint", { AspectRatio = 1 }),
})
local image = New("ImageLabel", {
	BackgroundTransparency = 1,
	Image = MapImage.image,
	Parent = frame,
})
local hint = Make.Label("", 13, T.text, T.bold, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 6),
	Size = UDim2.new(1, -20, 0, 22),
	TextXAlignment = Enum.TextXAlignment.Center,
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.4,
	ZIndex = 5,
	Parent = frame,
})
local bar = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.fromOffset(330, 40),
	BackgroundTransparency = 1,
	Parent = gui,
}, { Make.List(6, true) })
local listLayout = bar:FindFirstChildOfClass("UIListLayout") :: UIListLayout
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

-- view: map centre (0..1) and zoom
local cu, cv, zoom = 0.5, 0.5, 1
local selected: Vector2? = nil -- world X, Z
local markers: { { x: number, z: number, color: Color3, text: string } } = {}
local onPick: ((number, number) -> ())? = nil

local function toUV(x: number, z: number): (number, number)
	return (x - MapImage.minX) / MapImage.span, (z - MapImage.minZ) / MapImage.span
end

local function dot(u: number, v: number, color: Color3, size: number, text: string?)
	local d = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(u, v),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		ZIndex = 3,
		Parent = image,
	}, { Make.Corner(size // 2), Make.Stroke(Color3.new(0, 0, 0), 2) })
	if text then
		Make.Label(text, 11, Color3.new(1, 1, 1), T.bold, {
			Position = UDim2.new(1, 4, 0, -4),
			Size = UDim2.fromOffset(120, 16),
			TextStrokeTransparency = 0.3,
			ZIndex = 3,
			Parent = d,
		})
	end
end

local function redraw()
	zoom = math.clamp(zoom, 1, 12)
	local half = 0.5 / zoom
	cu = math.clamp(cu, half, 1 - half)
	cv = math.clamp(cv, half, 1 - half)
	image.Size = UDim2.fromScale(zoom, zoom)
	image.Position = UDim2.fromScale(0.5 - cu * zoom, 0.5 - cv * zoom)
	for _, c in image:GetChildren() do
		c:Destroy()
	end
	for _, m in markers do
		local u, v = toUV(m.x, m.z)
		dot(u, v, m.color, 12, m.text)
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local u, v = toUV(root.Position.X, root.Position.Z)
		dot(u, v, Color3.fromRGB(60, 150, 255), 12, Store.T("map_you"))
	end
	if selected then
		local u, v = toUV(selected.X, selected.Y)
		dot(u, v, Color3.fromRGB(255, 60, 60), 18, "📦")
		hint.Text = string.format("📦 %d, %d", selected.X, selected.Y)
	else
		hint.Text = Store.T("map_tap")
	end
end

frame.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local rel = (Vector2.new(input.Position.X, input.Position.Y) - frame.AbsolutePosition) / frame.AbsoluteSize
	local u = cu + (rel.X - 0.5) / zoom
	local v = cv + (rel.Y - 0.5) / zoom
	selected = Vector2.new(MapImage.minX + u * MapImage.span, MapImage.minZ + v * MapImage.span)
	if zoom < 4 then
		cu, cv, zoom = u, v, 4 -- first tap: zoom in there, tap again to fine-tune
	end
	redraw()
end)

frame.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		zoom *= if input.Position.Z > 0 then 1.4 else 1 / 1.4
		redraw()
	end
end)

local function close()
	gui.Enabled = false
	onPick = nil
end

local function barButton(text: string, color: Color3, fn: () -> (), width: number?)
	Make.Button(text, color, fn, { Size = UDim2.fromOffset(width or 48, 40), TextSize = 16, Parent = bar })
end
barButton("🔍−", T.card, function()
	zoom /= 2
	redraw()
end)
barButton("🔍+", T.card, function()
	zoom *= 2
	redraw()
end)
barButton("📍", T.card, function()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		selected = Vector2.new(root.Position.X, root.Position.Z)
		cu, cv = toUV(root.Position.X, root.Position.Z)
		zoom = math.max(zoom, 6)
		redraw()
	end
end)
barButton("X", T.bad, close)
barButton("✓ " .. Store.T("map_place"), T.good, function()
	local cb, point = onPick, selected
	if cb and point then
		close()
		cb(point.X, point.Y)
	end
end, 110)

UserInputService.InputBegan:Connect(function(input, processed)
	if gui.Enabled and not processed and input.KeyCode == Enum.KeyCode.Escape then
		close()
	end
end)

-- Opens the map. `existing` are shown as orange dots; `callback(x, z)` gets the chosen spot.
function MapPicker.Pick(existing: { any }, callback: (number, number) -> ())
	markers = {}
	for _, d in existing do
		table.insert(markers, { x = d.x, z = d.z, color = Color3.fromRGB(255, 170, 0), text = tostring(d.name) })
	end
	selected = nil
	cu, cv, zoom = 0.5, 0.5, 1
	onPick = callback
	gui.Enabled = true
	redraw()
end

return MapPicker
