--!strict
-- Client-side visuals for everyone's vehicles (lights, indicators, blue lights),
-- street lights at night and rain. Server only sets attributes; animation is local.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldController = {}

local HEAD_ON = Color3.fromRGB(255, 250, 230)
local HEAD_OFF = Color3.fromRGB(200, 200, 190)
local TAIL_ON = Color3.fromRGB(255, 20, 20)
local TAIL_DIM = Color3.fromRGB(170, 10, 10)
local TAIL_OFF = Color3.fromRGB(110, 0, 0)
local IND_ON = Color3.fromRGB(255, 150, 0)
local IND_OFF = Color3.fromRGB(120, 70, 0)
local BLUE_ON = Color3.fromRGB(40, 110, 255)
local BLUE_OFF = Color3.fromRGB(20, 40, 120)

type Parts = { head: { BasePart }, tail: { BasePart }, indL: { BasePart }, indR: { BasePart }, blue: { BasePart } }
local cache: { [Model]: Parts } = {}

local function scan(model: Model): Parts
	local p: Parts = { head = {}, tail = {}, indL = {}, indR = {}, blue = {} }
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			if d.Name == "Headlight" then
				table.insert(p.head, d)
			elseif d.Name == "Taillight" then
				table.insert(p.tail, d)
			elseif d.Name == "IndicatorL" then
				table.insert(p.indL, d)
			elseif d.Name == "IndicatorR" then
				table.insert(p.indR, d)
			elseif d.Name == "Bluelight" then
				table.insert(p.blue, d)
			end
		end
	end
	return p
end

local function setLit(part: BasePart, on: boolean, onColor: Color3, offColor: Color3)
	part.Color = if on then onColor else offColor
	part.Material = if on then Enum.Material.Neon else Enum.Material.Glass
	local light = part:FindFirstChildWhichIsA("Light")
	if light then
		light.Enabled = on
	end
end

local function updateVehicles()
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then
		return
	end
	local t = os.clock()
	local blinkOn = (t % 0.8) < 0.4
	-- German pattern: quick double flash alternating left/right
	local phase = t % 0.5
	local blueSide = if phase < 0.25 then -1 else 1
	local flash = (phase % 0.25) < 0.07 or ((phase % 0.25) > 0.11 and (phase % 0.25) < 0.18)

	for _, model in folder:GetChildren() do
		if model:IsA("Model") then
			local parts = cache[model]
			if not parts then
				parts = scan(model)
				cache[model] = parts
				model.Destroying:Connect(function()
					cache[model] = nil
				end)
			end
			local head = model:GetAttribute("Headlights") == true
			local brake = model:GetAttribute("Brake") == true
			local ind = model:GetAttribute("Indicator")
			local blue = model:GetAttribute("Bluelight") == true
			for _, p in parts.head do
				setLit(p, head, HEAD_ON, HEAD_OFF)
			end
			for _, p in parts.tail do
				if brake then
					setLit(p, true, TAIL_ON, TAIL_OFF)
				else
					setLit(p, head, TAIL_DIM, TAIL_OFF)
				end
			end
			for _, p in parts.indL do
				setLit(p, (ind == "L" or ind == "H") and blinkOn, IND_ON, IND_OFF)
			end
			for _, p in parts.indR do
				setLit(p, (ind == "R" or ind == "H") and blinkOn, IND_ON, IND_OFF)
			end
			for _, p in parts.blue do
				local side = p:GetAttribute("Side")
				setLit(p, blue and flash and side == blueSide, BLUE_ON, BLUE_OFF)
			end
		end
	end
end

local streetOn: boolean? = nil
local function updateStreetLights()
	local h = Lighting.ClockTime
	local night = h < 6.8 or h > 18.6
	if night == streetOn then
		return
	end
	streetOn = night
	local map = Workspace:FindFirstChild("Map")
	local lights = map and map:FindFirstChild("StreetLights")
	if not lights then
		streetOn = nil
		return
	end
	for _, d in lights:GetDescendants() do
		if d:IsA("SpotLight") then
			d.Enabled = night
		elseif d:IsA("BasePart") and d.Name == "Lamp" then
			d.Material = if night then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

-- Rain: a particle box that follows the camera.
local rainPart = Instance.new("Part")
rainPart.Name = "Rain"
rainPart.Anchored = true
rainPart.CanCollide = false
rainPart.CanQuery = false
rainPart.CanTouch = false
rainPart.Transparency = 1
rainPart.Size = Vector3.new(120, 1, 120)
local rain = Instance.new("ParticleEmitter")
rain.Texture = "rbxasset://textures/particles/sparkles_main.dds"
rain.Color = ColorSequence.new(Color3.fromRGB(180, 200, 230))
rain.LightEmission = 0.2
rain.Transparency = NumberSequence.new(0.4)
rain.Size = NumberSequence.new(0.12)
rain.Lifetime = NumberRange.new(0.8)
rain.Speed = NumberRange.new(90)
rain.EmissionDirection = Enum.NormalId.Bottom
rain.Rate = 0
rain.Shape = Enum.ParticleEmitterShape.Box
rain.Parent = rainPart

RunService.Heartbeat:Connect(function()
	local camera = Workspace.CurrentCamera
	if camera then
		rainPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 40, 0))
	end
end)

task.spawn(function()
	rainPart.Parent = Workspace
	local tick = 0
	while true do
		task.wait(0.05)
		updateVehicles()
		tick += 1
		if tick % 20 == 0 then
			updateStreetLights()
			rain.Rate = if Workspace:GetAttribute("Weather") == "Rain" then 1500 else 0
		end
	end
end)

return WorldController
