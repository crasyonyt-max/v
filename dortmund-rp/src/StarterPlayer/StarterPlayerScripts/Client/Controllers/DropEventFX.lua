--!strict
-- World effects of the dropper events (Shared/DropEvents): banner with countdown,
-- colour tint, disco lights around you and the event's emoji raining from the sky.
-- Everything here is local to each player.
-- Config.FlashyEvents (testing server first): a big start show (flash, giant title,
-- first fireworks), fireworks in the event colours all the time, falling confetti,
-- sweeping searchlights, a glow on the world and a pulsing banner.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
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
local flashy = Config.On(Config.FlashyEvents)
local bannerScale = New("UIScale", { Parent = banner })

-- the start show: white flash + a giant title that zooms in and fades
local showGui = New("ScreenGui", {
	Name = "DropEventShow",
	ResetOnSpawn = false,
	DisplayOrder = 30,
	IgnoreGuiInset = true,
	Parent = player:WaitForChild("PlayerGui"),
})
local flash = New("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 1,
	Parent = showGui,
})
local bigTitle = New("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.4),
	Size = UDim2.fromScale(0.8, 0.22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	TextTransparency = 1,
	Parent = showGui,
})
local bigStroke = New("UIStroke", { Thickness = 5, Transparency = 1, Parent = bigTitle })
local bigScale = New("UIScale", { Scale = 0.3, Parent = bigTitle })

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
	searchlights = {}
	confetti = nil
	bannerScale.Scale = 1
	for _, r in rain do
		r.part:Destroy()
	end
	rain = {}
	tint = nil
	gui.Enabled = false
end

-- one firework: a rocket climbs, then bursts in the event's colours
local function firework(e: DropEvents.DropEvent, center: Vector3)
	local a = math.random() * math.pi * 2
	local d = math.random(40, 110)
	local from = center + Vector3.new(math.cos(a) * d, -2, math.sin(a) * d)
	local top = from + Vector3.new(math.random(-8, 8), math.random(55, 85), math.random(-8, 8))
	local color = e.colors[math.random(1, #e.colors)]
	local rocket = New("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.8, 0.8, 0.8),
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Material = Enum.Material.Neon,
		Color = color,
		CFrame = CFrame.new(from),
		Parent = rainFolder,
	})
	New("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 150)),
		LightEmission = 1,
		Size = NumberSequence.new(0.5, 0),
		Lifetime = NumberRange.new(0.4, 0.7),
		Rate = 60,
		Speed = NumberRange.new(2),
		Parent = rocket,
	})
	local rise = TweenService:Create(
		rocket,
		TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(top) }
	)
	rise:Play()
	rise.Completed:Connect(function()
		rocket.Transparency = 1
		local burst = New("ParticleEmitter", {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(color, e.colors[math.random(1, #e.colors)]),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(1.2, 1.9),
			Speed = NumberRange.new(35, 60),
			Drag = 2.2,
			Acceleration = Vector3.new(0, -12, 0),
			SpreadAngle = Vector2.new(180, 180),
			Rate = 0,
			Parent = rocket,
		}) :: ParticleEmitter
		burst:Emit(140)
		local light = New("PointLight", { Range = 70, Brightness = 7, Color = color, Shadows = false, Parent = rocket })
		TweenService:Create(light, TweenInfo.new(1.4), { Brightness = 0 }):Play()
		task.delay(2.6, function()
			rocket:Destroy()
		end)
	end)
end

local function startShow(e: DropEvents.DropEvent)
	bigTitle.Text = e.icon .. " " .. e.name .. " " .. e.icon
	bigTitle.TextColor3 = e.colors[1]
	bigStroke.Color = Color3.new(0, 0, 0)
	flash.BackgroundTransparency = 0.2
	TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	bigScale.Scale = 0.3
	bigTitle.TextTransparency = 0
	bigStroke.Transparency = 0
	TweenService:Create(bigScale, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	task.delay(3.2, function()
		TweenService:Create(bigTitle, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
		TweenService:Create(bigStroke, TweenInfo.new(0.8), { Transparency = 1 }):Play()
		TweenService:Create(bigScale, TweenInfo.new(0.8), { Scale = 1.4 }):Play()
	end)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		for k = 0, 5 do
			task.delay(k * 0.25, function()
				firework(e, root.Position)
			end)
		end
	end
end

local searchlights: { BasePart } = {}
local confetti: BasePart? = nil

local function start(e: DropEvents.DropEvent)
	clear()
	if flashy then
		-- glow on the world
		table.insert(
			fx,
			New(
				"BloomEffect",
				{ Name = "DropEventBloom", Intensity = 0.9, Size = 36, Threshold = 0.85, Parent = Lighting }
			) :: Instance
		)
		-- confetti above you (follows you)
		local c = New("Part", {
			Name = "Confetti",
			Size = Vector3.new(70, 1, 70),
			Transparency = 1,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Parent = rainFolder,
		})
		local keys = {}
		for i, col in e.colors do
			table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(1, #e.colors - 1), col))
		end
		New("ParticleEmitter", {
			Shape = Enum.ParticleEmitterShape.Box,
			EmissionDirection = Enum.NormalId.Bottom,
			Color = if #keys >= 2 then ColorSequence.new(keys) else ColorSequence.new(e.colors[1]),
			LightEmission = 0.3,
			Size = NumberSequence.new(0.35),
			Lifetime = NumberRange.new(4, 6),
			Rate = 45,
			Speed = NumberRange.new(4, 8),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-180, 180),
			Acceleration = Vector3.new(0, -4, 0),
			SpreadAngle = Vector2.new(30, 30),
			Parent = c,
		})
		confetti = c
		table.insert(fx, c)
		-- searchlights around you, sweeping the sky
		for i = 1, 4 do
			local beam = New("Part", {
				Name = "Searchlight",
				Size = Vector3.new(3, 260, 3),
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Material = Enum.Material.Neon,
				Color = e.colors[(i - 1) % #e.colors + 1],
				Transparency = 0.78,
				Parent = rainFolder,
			})
			table.insert(searchlights, beam)
			table.insert(fx, beam)
		end
	end
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
		Notify.Show(Store.T("drop_event_start", e.icon, e.name, DropEvents.ChanceText(e), tostring(e.mult)), false, 6)
		if flashy then
			startShow(e)
		end
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
local fireTimer = 0
RunService.RenderStepped:Connect(function(dt)
	local e = current
	if not e then
		return
	end
	local left = math.max(0, math.floor(ends - Workspace:GetServerTimeNow()))
	banner.Text = string.format(
		"%s %s  ·  %s%% x%s  ·  %s %d:%02d",
		e.icon,
		e.name,
		DropEvents.ChanceText(e),
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
	-- flashy: pulsing banner, confetti over you, sweeping searchlights, fireworks
	if flashy then
		bannerScale.Scale = 1 + math.sin(t * 4) * 0.04
		if confetti then
			confetti.CFrame = CFrame.new(center + Vector3.new(0, 35, 0))
		end
		for i, beam in searchlights do
			local base = center + Vector3.new(math.cos(i * math.pi / 2) * 90, 0, math.sin(i * math.pi / 2) * 90)
			local tilt = CFrame.Angles(math.sin(t * 0.7 + i) * 0.55, t * 0.3 + i, math.cos(t * 0.5 + i * 2) * 0.35)
			beam.CFrame = CFrame.new(base) * tilt * CFrame.new(0, 130, 0)
			beam.Color = e.colors[(math.floor(t) + i) % #e.colors + 1]
		end
		fireTimer -= dt
		if fireTimer <= 0 then
			fireTimer = 0.9 + math.random() * 1.4
			firework(e, center)
		end
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
