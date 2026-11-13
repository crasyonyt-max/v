--!strict
-- World effects of the dropper events (Shared/DropEvents): banner with countdown,
-- colour tint, disco lights around you and the event's emoji raining from the sky.
-- Everything here is local to each player.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DropEvents = require(ReplicatedStorage.Shared.DropEvents)
local Make = require(script.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.UI.Notify)
local Net = require(script.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme
local player = Players.LocalPlayer

local DropEventFX = {}

local gui = New("ScreenGui", {
	Name = "DropEvent",
	ResetOnSpawn = false,
	DisplayOrder = 6,
	Enabled = false,
	Parent = player:WaitForChild("PlayerGui"),
})
local banner = Make.Label("", 15, Color3.new(1, 1, 1), T.black, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 60),
	Size = UDim2.fromOffset(0, 46),
	AutomaticSize = Enum.AutomaticSize.X,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextWrapped = false,
	BackgroundColor3 = Color3.fromRGB(20, 20, 24),
	BackgroundTransparency = 0.15,
	Parent = gui,
})
New("UICorner", { CornerRadius = UDim.new(0, 12), Parent = banner })
New("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = banner })
local stroke = New("UIStroke", { Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = banner })

local current: DropEvents.DropEvent? = nil
local ends = 0
local fx: { Instance } = {}
local rain: { { part: BasePart, speed: number, born: number } } = {}
local disco: { PointLight } = {}
local discoParts: { BasePart } = {}
local tint: ColorCorrectionEffect? = nil

local rainFolder = New("Folder", { Name = "EventRain", Parent = Workspace })

local function clear()
	for _, i in fx do
		i:Destroy()
	end
	fx, disco, discoParts = {}, {}, {}
	for _, r in rain do
		r.part:Destroy()
	end
	rain = {}
	tint = nil
	gui.Enabled = false
end

local function start(e: DropEvents.DropEvent)
	clear()
	tint = New("ColorCorrectionEffect", {
		Name = "DropEventTint",
		TintColor = e.tint,
		Saturation = 0.15,
		Contrast = 0.05,
		Parent = Lighting,
	})
	table.insert(fx, tint :: Instance)
	-- disco lights: little glowing balls that circle around you
	for i = 1, 4 do
		local p = New("Part", {
			Name = "Disco",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.8, 0.8, 0.8),
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Material = Enum.Material.Neon,
			Color = e.colors[(i - 1) % #e.colors + 1],
			Parent = rainFolder,
		})
		local light = New("PointLight", { Range = 20, Brightness = 3, Color = p.Color, Shadows = false, Parent = p })
		table.insert(fx, p)
		table.insert(discoParts, p)
		table.insert(disco, light)
	end
	gui.Enabled = true
end

local function set(payload: any)
	local id = if typeof(payload) == "table" then payload.id else nil
	local e = if typeof(id) == "string" then DropEvents.ById[id] else nil
	if not e then
		current = nil
		clear()
		return
	end
	ends = tonumber(payload.ends) or 0
	if current ~= e then
		current = e
		start(e)
		Notify.Show(Store.T("drop_event_start", e.icon, e.name, tostring(e.mult)), false, 6)
	end
end

local function spawnRain(e: DropEvents.DropEvent, camPos: Vector3)
	if #rain >= 70 then
		return
	end
	local offset = Vector3.new(math.random(-55, 55), math.random(30, 45), math.random(-55, 55))
	local p = New("Part", {
		Name = "Rain",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CFrame = CFrame.new(camPos + offset),
		Parent = rainFolder,
	})
	local board = New("BillboardGui", { Size = UDim2.fromScale(2.2, 2.2), LightInfluence = 0, Parent = p })
	New("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = e.rain,
		TextScaled = true,
		Parent = board,
	})
	table.insert(rain, { part = p, speed = math.random(18, 30), born = os.clock() })
end

local acc = 0
RunService.RenderStepped:Connect(function(dt)
	local e = current
	if not e then
		return
	end
	local left = math.max(0, math.floor(ends - Workspace:GetServerTimeNow()))
	banner.Text = string.format(
		"%s %s  ·  x%s  ·  %s %d:%02d",
		e.icon,
		e.name,
		tostring(e.mult),
		Store.T("drop_event_ends"),
		left // 60,
		left % 60
	)
	local t = os.clock()
	stroke.Color = e.colors[math.floor(t * 3) % #e.colors + 1]
	local cam = Workspace.CurrentCamera
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local center = if root then root.Position else (cam and cam.CFrame.Position or Vector3.zero)
	-- disco: orbit + colour change
	for i, p in discoParts do
		local a = t * 1.6 + i * math.pi / 2
		p.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * 9, 6 + math.sin(t * 2 + i) * 1.5, math.sin(a) * 9))
		local c = e.colors[(math.floor(t * 2) + i) % #e.colors + 1]
		p.Color = c
		disco[i].Color = c
	end
	-- rain
	acc += dt
	while acc > 0.12 do
		acc -= 0.12
		spawnRain(e, if cam then cam.CFrame.Position else center)
	end
	for i = #rain, 1, -1 do
		local r = rain[i]
		r.part.CFrame -= Vector3.new(0, r.speed * dt, 0)
		if t - r.born > 3.2 then
			r.part:Destroy()
			table.remove(rain, i)
		end
	end
end)

Net.On("DropEvent", set)
task.spawn(function()
	local r = Net.Request("DropEvent.Get")
	if r.ok then
		set(r)
	end
end)

return DropEventFX
