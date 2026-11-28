--!strict
-- 🎄 Advent (Config.Advent): while the workspace attribute "AdventSeason" is set, the
-- street lamps near you get Christmas lights: a glowing star on the lamp and a ring of
-- coloured bulbs around the pole. Only near the player (cheap), made on the client.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local ChristmasLights = {}

if not Config.On(Config.Advent) then
	return ChristmasLights
end

local RADIUS = 320
local COLORS = {
	Color3.fromRGB(255, 200, 90),
	Color3.fromRGB(255, 60, 60),
	Color3.fromRGB(80, 200, 90),
	Color3.fromRGB(110, 170, 255),
}

local folder = Instance.new("Folder")
folder.Name = "ChristmasLights"
folder.Parent = Workspace
local made: { [BasePart]: Model } = {}

local function part(m: Model, size: Vector3, cf: CFrame, color: Color3, ball: boolean?): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Size = size
	p.CFrame = cf
	p.Color = color
	if ball then
		p.Shape = Enum.PartType.Ball
	end
	p.Parent = m
	return p
end

local function decorate(lamp: BasePart): Model
	local m = Instance.new("Model")
	m.Name = "Deko"
	local top = lamp.CFrame * CFrame.new(0, lamp.Size.Y / 2 + 1.4, 0)
	-- a star (two crossed squares)
	part(m, Vector3.new(1.8, 1.8, 0.3), top * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(255, 215, 80))
	part(m, Vector3.new(1.8, 1.8, 0.3), top, Color3.fromRGB(255, 215, 80))
	-- a ring of bulbs around the pole, a bit below the lamp
	local ring = CFrame.new(lamp.CFrame.Position) * CFrame.new(0, -3, 0)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		part(
			m,
			Vector3.one * 0.45,
			ring * CFrame.new(math.cos(a) * 0.7, math.sin(a * 2) * 0.25, math.sin(a) * 0.7),
			COLORS[i % #COLORS + 1],
			true
		)
	end
	m.Parent = folder
	return m
end

local function clearAll()
	for lamp, m in made do
		m:Destroy()
		made[lamp] = nil
	end
end

task.spawn(function()
	local blink = 0
	while true do
		task.wait(1.5)
		if Workspace:GetAttribute("AdventSeason") ~= true then
			if next(made) then
				clearAll()
			end
			continue
		end
		local char = Players.LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local cam = Workspace.CurrentCamera
		local center = if root then root.Position elseif cam then cam.CFrame.Position else nil
		if not center then
			continue
		end
		for _, lamp in CollectionService:GetTagged("StreetLamp") do
			if lamp:IsA("BasePart") and lamp.Parent then
				local near = (lamp.CFrame.Position - center).Magnitude < RADIUS
				if near and not made[lamp] then
					made[lamp] = decorate(lamp)
				elseif not near and made[lamp] then
					made[lamp]:Destroy()
					made[lamp] = nil
				end
			end
		end
		for lamp, m in made do
			if not lamp.Parent then
				m:Destroy()
				made[lamp] = nil
			end
		end
		-- the bulbs twinkle: the colours move on
		blink += 1
		for _, m in made do
			local i = blink
			for _, p in m:GetChildren() do
				if p:IsA("Part") and p.Shape == Enum.PartType.Ball then
					i += 1
					p.Color = COLORS[i % #COLORS + 1]
				end
			end
		end
	end
end)

return ChristmasLights
