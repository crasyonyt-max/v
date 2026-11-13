--!strict
-- Traffic lights + speed cameras ("Blitzer") from OpenStreetMap (Shared/TrafficData),
-- and Unemployed XP (the "Arbeitslos" job XP): unemployed players earn it for driving
-- through green lights and passing speed cameras within the limit; red lights and
-- speeding cost Unemployed XP (everyone). It can be exchanged for money: drop the last
-- digit = euros.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local TrafficData = require(ReplicatedStorage.Shared.TrafficData)
local TrafficPhase = require(ReplicatedStorage.Shared.TrafficPhase)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local XPService = require(script.Parent.XPService)

local TrafficService = {}

local JUNCTION_R = 32 -- studs (≈ 9 m) from the centre: the crossing area
local CAMERA_R = 22
local TOLERANCE_KMH = 5

TrafficService.XP_GREEN = 5
TrafficService.XP_CAMERA_OK = 5
TrafficService.XP_RED = 25
TrafficService.XP_SPEEDING_MIN = 15

type Junction = { index: number, pos: Vector3, dirA: Vector3, dirB: Vector3 }
type Camera = { index: number, pos: Vector3, limit: number }
local junctions: { Junction } = {}
local cameras: { Camera } = {}

local folder = Instance.new("Folder")
folder.Name = "Traffic"

local function groundY(x: number, z: number): number?
	local city = Workspace:FindFirstChild("City")
	if not city then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local list = {}
	for _, name in { "Roads", "Ground", "Pavements", "Areas" } do
		local f = city:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	params.FilterDescendantsInstances = list
	local hit = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), params)
	return if hit then hit.Position.Y else nil
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local POLE = Color3.fromRGB(70, 72, 76)
local OFF = Color3.fromRGB(30, 30, 30)

-- One signal head facing the traffic that comes from direction `d`.
local function signal(parent: Instance, center: Vector3, d: Vector3, axis: string, index: number)
	local right = Vector3.new(-d.Z, 0, d.X)
	local base = center + d * JUNCTION_R + right * 20
	local face = CFrame.lookAt(base, base + d)
	part(parent, "Pole", Vector3.new(0.5, 11, 0.5), face * CFrame.new(0, 5.5, 0), POLE, Enum.Material.Metal)
	local head =
		part(parent, "SignalHead", Vector3.new(1.4, 3.8, 1), face * CFrame.new(0, 11.6, 0), Color3.fromRGB(25, 25, 27))
	head:SetAttribute("Index", index)
	head:SetAttribute("Axis", axis)
	for i, name in { "Red", "Yellow", "Green" } do
		local lamp = part(
			head,
			name,
			Vector3.new(0.9, 0.9, 0.2),
			face * CFrame.new(0, 11.6 + (2 - i) * 1.15, -0.55),
			OFF,
			Enum.Material.SmoothPlastic
		)
		lamp.Shape = Enum.PartType.Cylinder
		lamp.Size = Vector3.new(0.2, 0.9, 0.9)
		lamp.CFrame = face * CFrame.new(0, 11.6 + (2 - i) * 1.15, -0.55) * CFrame.Angles(0, math.rad(90), 0)
	end
	CollectionService:AddTag(head, "TrafficLight")
end

local function speedCamera(parent: Instance, pos: Vector3, along: Vector3, width: number, limit: number)
	local right = Vector3.new(-along.Z, 0, along.X)
	local base = pos + right * (width / 2 + 3)
	local face = CFrame.lookAt(base, base + along)
	part(
		parent,
		"Pole",
		Vector3.new(0.7, 6, 0.7),
		face * CFrame.new(0, 3, 0),
		Color3.fromRGB(150, 152, 156),
		Enum.Material.Metal
	)
	local box =
		part(parent, "Blitzer", Vector3.new(1.6, 2.4, 1.6), face * CFrame.new(0, 7.2, 0), Color3.fromRGB(235, 235, 235))
	part(
		box,
		"Lens",
		Vector3.new(0.9, 0.9, 0.2),
		face * CFrame.new(0, 7.5, -0.85),
		Color3.fromRGB(20, 20, 22),
		Enum.Material.Glass
	)
	box:SetAttribute("Limit", limit)
	CollectionService:AddTag(box, "SpeedCamera")
	-- speed limit sign a bit before the camera
	local signPos = base - along * 30
	local signCf = CFrame.lookAt(signPos, signPos + along)
	part(parent, "SignPole", Vector3.new(0.3, 6, 0.3), signCf * CFrame.new(0, 3, 0), POLE, Enum.Material.Metal)
	local sign =
		part(parent, "SpeedSign", Vector3.new(2.6, 2.6, 0.15), signCf * CFrame.new(0, 6.6, 0), Color3.new(1, 1, 1))
	sign.Shape = Enum.PartType.Cylinder
	sign.Size = Vector3.new(0.15, 2.6, 2.6)
	sign.CFrame = signCf * CFrame.new(0, 6.6, 0) * CFrame.Angles(0, math.rad(90), 0)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.Parent = sign
	local ring = Instance.new("Frame")
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundColor3 = Color3.fromRGB(200, 20, 20)
	ring.Parent = gui
	Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
	local inner = Instance.new("TextLabel")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(0.78, 0.78)
	inner.BackgroundColor3 = Color3.new(1, 1, 1)
	inner.Text = tostring(limit)
	inner.TextScaled = true
	inner.Font = Enum.Font.GothamBlack
	inner.TextColor3 = Color3.new(0, 0, 0)
	inner.Parent = ring
	Instance.new("UICorner", inner).CornerRadius = UDim.new(1, 0)
end

function TrafficService.Build()
	folder.Parent = Workspace
	for i, l in TrafficData.lights do
		local y = groundY(l[1], l[2])
		if y then
			local a = math.rad(l[3])
			local dirA = Vector3.new(math.cos(a), 0, math.sin(a))
			local dirB = Vector3.new(-dirA.Z, 0, dirA.X)
			local center = Vector3.new(l[1], y, l[2])
			table.insert(junctions, { index = i, pos = center, dirA = dirA, dirB = dirB })
			local model = Instance.new("Model")
			model.Name = "Ampel_" .. i
			for _, spec in { { dirA, "A" }, { -dirA, "A" }, { dirB, "B" }, { -dirB, "B" } } do
				signal(model, center, spec[1], spec[2], i)
			end
			model.Parent = folder
		end
	end
	for i, c in TrafficData.cameras do
		local y = groundY(c[1], c[2])
		if y then
			local a = math.rad(c[3])
			local along = Vector3.new(math.cos(a), 0, math.sin(a))
			local pos = Vector3.new(c[1], y, c[2])
			table.insert(cameras, { index = i, pos = pos, limit = c[4] })
			local model = Instance.new("Model")
			model.Name = "Blitzer_" .. i
			speedCamera(model, pos, along, c[5], c[4])
			model.Parent = folder
		end
	end
end

-- Fahr-XP ------------------------------------------------------------------------------

local function changeXP(player: Player, amount: number, key: string, args: { any })
	local data = DataService.Get(player)
	if not data then
		return
	end
	if amount > 0 then
		-- normal job XP for "Unemployed" (shows the usual +XP message)
		XPService.Add(player, "Unemployed", amount, "Verkehr")
		return
	end
	data.jobXP = data.jobXP or {}
	data.jobXP.Unemployed = math.max(0, (tonumber(data.jobXP.Unemployed) or 0) + amount)
	State.MarkDirty(player)
	Remotes.Push(player, "Notify", { key = key, args = args, error = true })
end

local inside: { [Player]: { [string]: boolean } } = {}
local cooldown: { [Player]: { [string]: number } } = {}

local function check(player: Player, chassis: BasePart)
	local p = chassis.Position
	local v = chassis.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	local speed = v.Magnitude
	local was = inside[player] or {}
	local now: { [string]: boolean } = {}
	local cd = cooldown[player] or {}
	cooldown[player] = cd
	local t = os.clock()
	local unemployed = (DataService.Get(player) or {}).job == "Unemployed"

	for _, j in junctions do
		local key = "j" .. j.index
		local dist = ((p - j.pos) * Vector3.new(1, 0, 1)).Magnitude
		if dist < JUNCTION_R then
			now[key] = true
			if not was[key] and speed > 4 then
				local heading = v.Unit
				local axis = if math.abs(heading:Dot(j.dirA)) >= math.abs(heading:Dot(j.dirB)) then "A" else "B"
				local a, b = TrafficPhase.State(Workspace:GetServerTimeNow(), j.index)
				local light = if axis == "A" then a else b
				if light == "R" then
					changeXP(player, -TrafficService.XP_RED, "red_light", { TrafficService.XP_RED })
				elseif unemployed and (cd[key] or 0) < t then
					cd[key] = t + 30
					changeXP(player, TrafficService.XP_GREEN, "drive_xp_plus", { TrafficService.XP_GREEN })
				end
			end
		end
	end
	for _, c in cameras do
		local key = "c" .. c.index
		local dist = ((p - c.pos) * Vector3.new(1, 0, 1)).Magnitude
		if dist < CAMERA_R then
			now[key] = true
			if not was[key] and speed > 2 then
				local kmh = speed / Config.StudsPerMeter * 3.6
				if kmh > c.limit + TOLERANCE_KMH then
					local loss = math.max(TrafficService.XP_SPEEDING_MIN, math.floor((kmh - c.limit) * 1.5))
					changeXP(player, -loss, "speeding", { math.floor(kmh), c.limit, loss })
					Remotes.Push(player, "Blitz", { kmh = math.floor(kmh), limit = c.limit })
				elseif unemployed and (cd[key] or 0) < t then
					cd[key] = t + 60
					changeXP(player, TrafficService.XP_CAMERA_OK, "drive_xp_plus", { TrafficService.XP_CAMERA_OK })
				end
			end
		end
	end
	inside[player] = now
end

function TrafficService.Start()
	-- Studio / tests without a city: nothing to check
	task.spawn(function()
		while true do
			task.wait(0.2)
			local vehicles = Workspace:FindFirstChild("Vehicles")
			if vehicles and (#junctions > 0 or #cameras > 0) then
				for _, player in Players:GetPlayers() do
					local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					local seat = hum and hum.SeatPart
					local model = seat and seat.Name == "DriveSeat" and seat.Parent
					if model and model:IsA("Model") and model.Parent == vehicles and model.PrimaryPart then
						check(player, model.PrimaryPart)
					else
						inside[player] = nil
					end
				end
			end
		end
	end)

	-- the short-lived separate "Fahr-XP" moves into the Unemployed XP
	DataService.Loaded:Connect(function(player, data)
		local old = math.floor(tonumber(data.driveXP) or 0)
		if old > 0 then
			data.jobXP = data.jobXP or {}
			data.jobXP.Unemployed = (tonumber(data.jobXP.Unemployed) or 0) + old
			State.MarkDirty(player)
		end
		data.driveXP = nil
	end)

	Players.PlayerRemoving:Connect(function(player)
		inside[player] = nil
		cooldown[player] = nil
	end)

	-- 1234 Fahr-XP -> 123 € (the last digit stays as Fahr-XP)
	Remotes.Handle("DriveXP.Exchange", function(player)
		local data = DataService.Get(player) :: { [string]: any }
		data.jobXP = data.jobXP or {}
		local xp = math.floor(tonumber(data.jobXP.Unemployed) or 0)
		local euros = xp // 10
		if euros <= 0 then
			return Remotes.Fail("drive_xp_low")
		end
		data.jobXP.Unemployed = xp - euros * 10
		Economy.Add(player, euros, "XP-Umtausch (Arbeitslos)")
		State.MarkDirty(player)
		return Remotes.Ok({ euros = euros })
	end, { rate = 3 })
end

-- for tests
TrafficService._exchange = function(xp: number): (number, number)
	local euros = xp // 10
	return euros, xp - euros * 10
end

return TrafficService
