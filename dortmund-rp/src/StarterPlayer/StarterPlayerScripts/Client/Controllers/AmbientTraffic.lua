--!strict
-- Update 2 (Config.Update2, testing server first): NPC cars and pedestrians around you,
-- so the city feels alive. They only exist on your own device (no server cost, other
-- players see their own ones): cars drive on the right along the real streets and stop
-- for people and cars in front of them, pedestrians walk on the pavements.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Parent.Net)

local me = Players.LocalPlayer

if not Config.On(Config.Update2) then
	return {}
end

local MAX_CARS, MAX_PEOPLE = 10, 12
local NEAR, FAR = 320, 460
local rng = Random.new()

type Line = { number } -- width, x1, z1, x2, z2, ...
local lines: { Line } = {}
local loadedAt: Vector3? = nil

local folder = Instance.new("Folder")
folder.Name = "AmbientTraffic"
folder.Parent = Workspace

type Agent = {
	model: Model,
	line: Line,
	seg: number, -- segment index (1 = first two points)
	dir: number, -- +1 forwards, -1 backwards along the line
	t: number, -- 0..1 along the segment
	speed: number,
	side: number, -- studs right of the centre line
	car: boolean,
	phase: number,
	legs: { BasePart }?,
}
local agents: { Agent } = {}

local COLORS = {
	Color3.fromRGB(230, 230, 230),
	Color3.fromRGB(30, 30, 34),
	Color3.fromRGB(150, 155, 160),
	Color3.fromRGB(170, 30, 30),
	Color3.fromRGB(30, 70, 150),
	Color3.fromRGB(60, 110, 70),
	Color3.fromRGB(200, 170, 60),
}

local function part(m: Model, name: string, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = m
	return p
end

-- models are built at the origin; offsets are kept in attributes for posing
local function carModel(): Model
	local m = Instance.new("Model")
	m.Name = "NPCCar"
	local body =
		part(m, "Body", Vector3.new(6.4, 2.2, 14), COLORS[rng:NextInteger(1, #COLORS)], Enum.Material.SmoothPlastic)
	body.CanCollide = true
	m.PrimaryPart = body
	local cabin = part(m, "Cabin", Vector3.new(5.8, 2, 7), Color3.fromRGB(60, 80, 95), Enum.Material.Glass)
	cabin:SetAttribute("Off", Vector3.new(0, 2.1, 0.8))
	for _, x in { -2.6, 2.6 } do
		local hl = part(m, "Headlight", Vector3.new(1.2, 0.6, 0.2), Color3.fromRGB(255, 250, 220), Enum.Material.Neon)
		hl:SetAttribute("Off", Vector3.new(x, 0.3, -7.05))
		local tl = part(m, "Taillight", Vector3.new(1.2, 0.5, 0.2), Color3.fromRGB(160, 10, 10), Enum.Material.Neon)
		tl:SetAttribute("Off", Vector3.new(x, 0.3, 7.05))
		for _, z in { -4.4, 4.4 } do
			local w = part(m, "Wheel", Vector3.new(1, 2.6, 2.6), Color3.fromRGB(25, 25, 25));
			(w :: Part).Shape = Enum.PartType.Cylinder
			w:SetAttribute("Off", Vector3.new(x * 1.18, -0.8, z))
		end
	end
	m.Parent = folder
	return m
end

local function personModel(): (Model, { BasePart })
	local m = Instance.new("Model")
	m.Name = "NPCPerson"
	local shirt = COLORS[rng:NextInteger(1, #COLORS)]
	local torso = part(m, "Torso", Vector3.new(2, 2, 1), shirt)
	torso.CanCollide = false
	m.PrimaryPart = torso
	local head = part(m, "Head", Vector3.new(1.2, 1.2, 1.2), Color3.fromRGB(225, 185, 150))
	head:SetAttribute("Off", Vector3.new(0, 1.6, 0))
	local legs = {}
	for _, s in { -1, 1 } do
		local leg = part(m, "Leg", Vector3.new(0.9, 2, 0.9), Color3.fromRGB(40, 50, 80))
		leg:SetAttribute("Off", Vector3.new(s * 0.5, -2, 0))
		leg:SetAttribute("Side", s)
		table.insert(legs, leg)
		local arm = part(m, "Arm", Vector3.new(0.8, 1.9, 0.8), shirt)
		arm:SetAttribute("Off", Vector3.new(s * 1.4, 0, 0))
	end
	for _, p in m:GetChildren() do
		(p :: BasePart).CanCollide = false
	end
	m.Parent = folder
	return m, legs
end

local function point(line: Line, i: number): Vector3
	return Vector3.new(line[2 * i], 0, line[2 * i + 1])
end

local function pointCount(line: Line): number
	return (#line - 1) // 2
end

-- where an agent is and which way it looks
local function placeOf(a: Agent): (Vector3, Vector3)
	local n = pointCount(a.line)
	local i0 = math.clamp(a.seg, 1, n - 1)
	local p0, p1 = point(a.line, i0), point(a.line, i0 + 1)
	if a.dir < 0 then
		p0, p1 = p1, p0
	end
	local dir = (p1 - p0)
	local unit = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-unit.Z, 0, unit.X)
	return p0:Lerp(p1, a.t) + right * a.side, unit
end

local function pose(a: Agent)
	local pos, look = placeOf(a)
	local y = if a.car then 1.6 else 3.2
	local base = CFrame.lookAt(pos + Vector3.new(0, y, 0), pos + Vector3.new(0, y, 0) + look)
	for _, p in a.model:GetChildren() do
		if p:IsA("BasePart") then
			local off = (p:GetAttribute("Off") :: Vector3?) or Vector3.zero
			local cf = base * CFrame.new(off)
			if p.Name == "Wheel" then
				cf *= CFrame.Angles(0, math.pi / 2, 0)
			elseif p.Name == "Leg" then
				local swing = math.sin(a.phase) * 0.5 * ((p:GetAttribute("Side") :: number?) or 1)
				cf = base * CFrame.new(off + Vector3.new(0, 1, 0)) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -1, 0)
			end
			p.CFrame = cf
		end
	end
end

local function myPos(): Vector3?
	local r = me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return r and r.Position
end

-- a line with a point near `pos` (within `radius`), and that point's index
local function lineNear(pos: Vector3, radius: number): (Line?, number)
	for _ = 1, 40 do
		local line = lines[rng:NextInteger(1, #lines)]
		local n = pointCount(line)
		local i = rng:NextInteger(1, math.max(1, n - 1))
		if (point(line, i) - pos * Vector3.new(1, 0, 1)).Magnitude < radius then
			return line, i
		end
	end
	return nil, 1
end

local function spawnAgent(car: boolean)
	local pos = myPos()
	if not pos or #lines == 0 then
		return
	end
	local line, i = lineNear(pos, NEAR)
	if not line or pointCount(line) < 2 then
		return
	end
	local w = line[1]
	local a: Agent = {
		model = Instance.new("Model"),
		line = line,
		seg = math.min(i, pointCount(line) - 1),
		dir = if rng:NextNumber() < 0.5 then 1 else -1,
		t = rng:NextNumber(),
		speed = if car then rng:NextNumber(22, 34) else rng:NextNumber(4, 6),
		side = if car then math.max(3, w * 0.25) else w / 2 + 3.5,
		car = car,
		phase = rng:NextNumber(0, 6),
	}
	a.model:Destroy()
	if car then
		a.model = carModel()
	else
		local m, legs = personModel()
		a.model, a.legs = m, legs
	end
	if (placeOf(a) - pos * Vector3.new(1, 0, 1)).Magnitude < 60 then
		a.model:Destroy() -- not right next to you (no popping in)
		return
	end
	pose(a)
	table.insert(agents, a)
end

-- the next line at the end of this one (connected point within 10 studs), else turn
local function continueFrom(a: Agent)
	local n = pointCount(a.line)
	local endPt = if a.dir > 0 then point(a.line, n) else point(a.line, 1)
	for _ = 1, 30 do
		local other = lines[rng:NextInteger(1, #lines)]
		if other ~= a.line and pointCount(other) >= 2 then
			local m = pointCount(other)
			if (point(other, 1) - endPt).Magnitude < 10 then
				a.line, a.seg, a.dir, a.t = other, 1, 1, 0
				return
			elseif (point(other, m) - endPt).Magnitude < 10 then
				a.line, a.seg, a.dir, a.t = other, m - 1, -1, 0
				return
			end
		end
	end
	a.dir = -a.dir -- dead end: turn around
	a.t = 0
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function blocked(a: Agent): boolean
	if not a.car then
		return false
	end
	local pos, look = placeOf(a)
	params.FilterDescendantsInstances = { folder }
	local hit = Workspace:Raycast(pos + Vector3.new(0, 2, 0) + look * 7, look * 14, params)
	if not hit then
		return false
	end
	local m = hit.Instance:FindFirstAncestorOfClass("Model")
	return m ~= nil and (m:FindFirstChildOfClass("Humanoid") ~= nil or m.Parent == Workspace:FindFirstChild("Vehicles"))
end

local function step(dt: number)
	local pos = myPos()
	for k = #agents, 1, -1 do
		local a = agents[k]
		local here = placeOf(a)
		if not pos or (here - pos * Vector3.new(1, 0, 1)).Magnitude > FAR then
			a.model:Destroy()
			table.remove(agents, k)
			continue
		end
		if not blocked(a) then
			local n = pointCount(a.line)
			local i0 = math.clamp(a.seg, 1, n - 1)
			local len = (point(a.line, i0 + 1) - point(a.line, i0)).Magnitude
			a.t += a.speed * dt / math.max(len, 0.5)
			a.phase += dt * a.speed * 1.4
			while a.t >= 1 do
				a.t -= 1
				a.seg += a.dir
				if a.seg < 1 or a.seg > n - 1 then
					a.seg = math.clamp(a.seg, 1, n - 1)
					continueFrom(a)
					break
				end
			end
		end
		pose(a)
	end
end

task.spawn(function()
	while true do
		task.wait(1)
		local pos = myPos()
		if pos and (not loadedAt or (pos - loadedAt).Magnitude > 500) then
			local r = Net.Request("Traffic.Roads")
			if r.ok and typeof(r.lines) == "table" then
				lines = r.lines
				loadedAt = pos
			end
		end
		local cars, people = 0, 0
		for _, a in agents do
			if a.car then
				cars += 1
			else
				people += 1
			end
		end
		if cars < MAX_CARS then
			spawnAgent(true)
		end
		if people < MAX_PEOPLE then
			spawnAgent(false)
		end
	end
end)

RunService.Heartbeat:Connect(step)

return {}
