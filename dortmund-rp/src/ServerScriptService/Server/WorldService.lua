--!strict
-- Day/night cycle and weather. Clients render rain from the workspace "Weather" attribute.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldService = {}

WorldService.WeatherTypes = { "Clear", "Cloudy", "Rain", "Fog" }

local atmosphere: Atmosphere
local clouds: Clouds?
local lockedUntil = 0

local PRESETS = {
	Clear = { density = 0.28, haze = 0.5, cover = 0.35, cloudDensity = 0.4 },
	Cloudy = { density = 0.35, haze = 1.4, cover = 0.75, cloudDensity = 0.7 },
	Rain = { density = 0.45, haze = 2.4, cover = 0.92, cloudDensity = 0.9 },
	Fog = { density = 0.75, haze = 3.5, cover = 0.6, cloudDensity = 0.6 },
}

function WorldService.SetWeather(kind: string, manual: boolean?)
	local preset = PRESETS[kind]
	if not preset then
		return
	end
	if manual then
		lockedUntil = os.clock() + 20 * 60 -- admin choice holds for 20 minutes
	end
	Workspace:SetAttribute("Weather", kind)
	local info = TweenInfo.new(20)
	TweenService:Create(atmosphere, info, { Density = preset.density, Haze = preset.haze }):Play()
	if clouds then
		TweenService:Create(clouds, info, { Cover = preset.cover, Density = preset.cloudDensity }):Play()
	end
end

function WorldService.Start()
	Lighting.ClockTime = 9
	Lighting.GeographicLatitude = 51.5 -- Dortmund
	Lighting.Brightness = 2.5
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)

	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(199, 206, 214)
	atmosphere.Decay = Color3.fromRGB(106, 112, 125)
	atmosphere.Glare = 0.2
	atmosphere.Parent = Lighting
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 124, 132)
	Lighting.Ambient = Color3.fromRGB(40, 42, 46)
	Lighting.ShadowSoftness = 0.25
	Lighting.ExposureCompensation = 0.1
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Contrast = 0.08
	grade.Saturation = -0.08
	grade.TintColor = Color3.fromRGB(255, 250, 244)
	grade.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.35
	bloom.Size = 28
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.04
	rays.Spread = 0.7
	rays.Parent = Lighting
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.Parent = Lighting
	pcall(function()
		local c = Workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
		c.Parent = Workspace.Terrain
		clouds = c
	end)
	WorldService.SetWeather("Clear")

	-- Day/night cycle
	task.spawn(function()
		local hoursPerSecond = 24 / (Config.DayLengthMinutes * 60)
		while true do
			local dt = task.wait(1)
			Lighting.ClockTime = (Lighting.ClockTime + dt * hoursPerSecond) % 24
		end
	end)

	-- Random weather every 10-20 minutes
	task.spawn(function()
		local rng = Random.new()
		while true do
			task.wait(rng:NextInteger(600, 1200))
			if os.clock() >= lockedUntil then
				local roll = rng:NextNumber()
				local kind = if roll < 0.5
					then "Clear"
					elseif roll < 0.8 then "Cloudy"
					elseif roll < 0.95 then "Rain"
					else "Fog"
				WorldService.SetWeather(kind)
			end
		end
	end)
end

return WorldService
