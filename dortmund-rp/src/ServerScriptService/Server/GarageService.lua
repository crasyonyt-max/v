--!strict
-- Underground garages ("Tiefgarage") under the Dortmund Tower and the Admin Tower.
-- A drive-in gate on the street takes you (and the vehicle you drive) down; the exit
-- gate brings you back up; a lift goes to the tower lobby. Vehicles spawned while
-- you are down there get a free parking bay. The Admin Tower garage is admins only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Locations = require(ReplicatedStorage.Shared.Locations)
local CityBuilder = require(script.Parent.CityBuilder)
local Interaction = require(script.Parent.InteractionService)
local Remotes = require(script.Parent.Remotes)
local Roles = require(script.Parent.Roles)

local GarageService = {}

local DEPTH = 40 -- the garage floor is this far below the street
local W, D, H = 110, 110, 12

type Garage = {
	name: string,
	adminOnly: boolean,
	floor: CFrame, -- centre of the garage floor (local -Z = towards the street)
	street: CFrame, -- in front of the gate on the street
	gate: Vector3, -- the street gate (drive into it)
	exit: Vector3, -- the exit gate down in the garage
	inside: CFrame, -- just inside, at the bottom of the "ramp"
	lobby: () -> CFrame?, -- where the lift goes
	bays: { CFrame },
}
local garages: { Garage } = {}

local CONCRETE = Color3.fromRGB(120, 120, 124)
local LINE = Color3.fromRGB(235, 235, 235)
local YELLOW = Color3.fromRGB(240, 190, 30)

local function box(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	props: { [string]: any }?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Concrete
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function sign(p: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = bg
	l.TextScaled = true
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = color
	l.Text = text
	l.Parent = gui
end

-- the vehicle the player drives (with everybody in it), or just the player
local function move(player: Player, target: CFrame)
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local model = seat and seat.Parent
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if model and model:IsA("Model") and vehicles and model.Parent == vehicles and seat:IsA("VehicleSeat") then
		local root = model.PrimaryPart :: BasePart
		model:PivotTo(target * CFrame.new(0, 4, 0))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		return
	end
	if c then
		if hum then
			hum.Sit = false
		end
		c:PivotTo(target * CFrame.new(0, 3, 0))
	end
end

local function allowed(player: Player, g: Garage): boolean
	if g.adminOnly and Roles.Rank(player) < Roles.GAME_ADMIN then
		Remotes.Push(player, "Notify", { key = "admin_only", error = true })
		return false
	end
	return true
end

-- builds one garage under a site; `streetSide` is the side of the site the gate is on
local function build(name: string, site: any, adminOnly: boolean, lobby: () -> CFrame?)
	local gy = CityBuilder.GroundY(site.x, site.z)
	local yaw = CFrame.Angles(0, math.rad(site.yaw), 0)
	local floor = CFrame.new(site.x, gy - DEPTH, site.z) * yaw
	local function at(x: number, y: number, z: number): CFrame
		return floor * CFrame.new(x, y, z)
	end
	local m = Instance.new("Model")
	m.Name = "Tiefgarage " .. name

	-- shell
	box(m, "Floor", Vector3.new(W, 1, D), at(0, -0.5, 0), Color3.fromRGB(80, 82, 86), Enum.Material.Concrete)
	box(m, "Ceiling", Vector3.new(W, 1, D), at(0, H + 0.5, 0), CONCRETE)
	for _, s in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		local horizontal = s[1] == 0
		box(
			m,
			"Wall",
			if horizontal then Vector3.new(W, H, 1) else Vector3.new(1, H, D),
			at(s[1] * W / 2, H / 2, s[2] * D / 2),
			CONCRETE
		)
	end
	-- pillars, lights, two rows of bays along the driving lane
	local bays = {}
	for i = 0, 7 do
		local x = -W / 2 + 10 + i * 12.5
		for _, z in { -32, 32 } do
			box(
				m,
				"BayLine",
				Vector3.new(0.4, 0.05, 20),
				at(x - 6.25, 0.03, z),
				LINE,
				Enum.Material.SmoothPlastic,
				{ CanCollide = false }
			)
			table.insert(bays, at(x, 0, z) * CFrame.Angles(0, if z < 0 then 0 else math.pi, 0))
		end
		if i % 2 == 0 then
			box(m, "Pillar", Vector3.new(2, H, 2), at(x - 6.25, H / 2, -20), CONCRETE)
			box(m, "Pillar", Vector3.new(2, H, 2), at(x - 6.25, H / 2, 20), CONCRETE)
		end
		local lampPart = box(
			m,
			"Lamp",
			Vector3.new(6, 0.3, 1),
			at(x, H - 0.3, 0),
			Color3.fromRGB(240, 240, 235),
			Enum.Material.Glass,
			{ CanCollide = false }
		)
		local light = Instance.new("PointLight")
		light.Range = 24
		light.Brightness = 0.8
		light.Color = Color3.fromRGB(235, 240, 255)
		light.Parent = lampPart
	end
	box(
		m,
		"LaneLine",
		Vector3.new(W - 20, 0.05, 0.4),
		at(0, 0.03, 0),
		YELLOW,
		Enum.Material.SmoothPlastic,
		{ CanCollide = false }
	)

	-- exit gate (inside) + lift to the lobby
	local exitGate = box(
		m,
		"ExitGate",
		Vector3.new(14, 8, 1),
		at(-W / 2 + 9, 4, -D / 2 + 1),
		Color3.fromRGB(40, 40, 44),
		Enum.Material.Metal
	)
	sign(exitGate, Enum.NormalId.Back, "⬆ AUSFAHRT", YELLOW, Color3.fromRGB(40, 40, 44))
	local liftPart = box(
		m,
		"Lift",
		Vector3.new(8, 10, 1),
		at(W / 2 - 8, 5, D / 2 - 1),
		Color3.fromRGB(40, 40, 44),
		Enum.Material.Metal
	)
	sign(liftPart, Enum.NormalId.Front, "🛗 LOBBY", YELLOW, Color3.fromRGB(40, 40, 44))

	-- gate on the street: beside the site's front, so it never blocks the entrance
	local front = CFrame.new(site.x, gy, site.z) * yaw * CFrame.new(-site.width / 2 - 8, 0, -site.depth / 2 + 6)
	local gate = box(
		m,
		"Gate",
		Vector3.new(12, 8, 2),
		front * CFrame.new(0, 4, 0),
		Color3.fromRGB(40, 40, 44),
		Enum.Material.Metal
	)
	sign(
		gate,
		Enum.NormalId.Front,
		"🅿 TIEFGARAGE" .. (if adminOnly then " (ADMIN)" else ""),
		YELLOW,
		Color3.fromRGB(40, 40, 44)
	)
	box(
		m,
		"Barrier",
		Vector3.new(10, 0.5, 0.5),
		front * CFrame.new(0, 3, -1.6),
		Color3.fromRGB(220, 30, 30),
		Enum.Material.SmoothPlastic,
		{ CanCollide = false }
	)

	local g: Garage = {
		name = name,
		adminOnly = adminOnly,
		floor = floor,
		street = front * CFrame.new(0, 0, -10) * CFrame.Angles(0, math.pi, 0),
		gate = gate.CFrame.Position,
		exit = exitGate.CFrame.Position,
		inside = at(-W / 2 + 9, 0, -D / 2 + 12),
		lobby = lobby,
		bays = bays,
	}
	table.insert(garages, g)

	local function marker(part: BasePart, kind: string, action: string)
		local p = box(
			m,
			"Marker_" .. kind,
			Vector3.new(2, 2, 2),
			part.CFrame * CFrame.new(0, -1, 0),
			Color3.new(1, 1, 1),
			nil,
			{
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
			}
		)
		Interaction.Mark(p, kind, { ActionText = action, ObjectText = "Tiefgarage " .. name, Garage = #garages })
	end
	marker(gate, "GarageIn", "Reinfahren")
	marker(exitGate, "GarageOut", "Rausfahren")
	marker(liftPart, "GarageLift", "Aufzug → Lobby")
	-- and down again from the lobby
	local lobbySpot = lobby()
	if lobbySpot then
		local down = box(
			m,
			"LobbyLift",
			Vector3.new(4, 7, 0.6),
			lobbySpot * CFrame.new(8, 3.5, 0),
			Color3.fromRGB(40, 40, 44),
			Enum.Material.Metal
		)
		sign(down, Enum.NormalId.Front, "🅿 TIEFGARAGE", YELLOW, Color3.fromRGB(40, 40, 44))
		marker(down, "GarageDown", "Aufzug → Tiefgarage")
	end
	m.Parent = Workspace
end

function GarageService.Build()
	local sites = Locations.Sites :: any
	local TowerBuilder = require(script.Parent.TowerBuilder) :: any
	local AdminTower = require(script.Parent.AdminTowerService) :: any
	if sites.Tower then
		build("Dortmund Tower", sites.Tower, false, function()
			return TowerBuilder.FloorSpots[0]
		end)
	end
	if sites.AdminTower then
		build("Admin Tower", sites.AdminTower, true, function()
			return AdminTower.Spot("Lobby")
		end)
	end
end

-- A free parking bay if the player is in a garage (for spawning vehicles), else nil.
function GarageService.SpawnSpot(player: Player): CFrame?
	local c = player.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	for _, g in garages do
		local lp = g.floor:PointToObjectSpace(root.Position)
		if math.abs(lp.X) < W / 2 and math.abs(lp.Z) < D / 2 and lp.Y > -2 and lp.Y < H + 2 then
			local vehicles = Workspace:FindFirstChild("Vehicles")
			for _, bay in g.bays do
				local taken = false
				for _, v in (if vehicles then vehicles:GetChildren() else {}) do
					local pp = v:IsA("Model") and v.PrimaryPart
					if pp and (pp.CFrame.Position - bay.Position).Magnitude < 7 then
						taken = true
						break
					end
				end
				if not taken then
					return bay
				end
			end
			return nil
		end
	end
	return nil
end

function GarageService.Start()
	local function garageOf(marker: BasePart): Garage?
		return garages[tonumber(marker:GetAttribute("Garage")) or 0]
	end
	Interaction.OnTrigger("GarageIn", function(player, marker)
		local g = garageOf(marker)
		if g and allowed(player, g) then
			move(player, g.inside)
		end
	end)
	Interaction.OnTrigger("GarageOut", function(player, marker)
		local g = garageOf(marker)
		if g then
			move(player, g.street)
		end
	end)
	Interaction.OnTrigger("GarageLift", function(player, marker)
		local g = garageOf(marker)
		local target = g and g.lobby()
		local c = player.Character
		if c and target then
			local hum = c:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Sit = false
			end
			c:PivotTo(target + Vector3.new(0, 3, 0))
		end
	end)
	Interaction.OnTrigger("GarageDown", function(player, marker)
		local g = garageOf(marker)
		if g and allowed(player, g) then
			local c = player.Character
			if c then
				c:PivotTo(g.floor * CFrame.new(W / 2 - 8, 3, D / 2 - 8))
			end
		end
	end)

	-- drivers: prompts are off while driving, so just drive into the gate
	local cooldown: { [Player]: number } = {}
	task.spawn(function()
		while true do
			task.wait(0.3)
			for _, player in Players:GetPlayers() do
				local c = player.Character
				local hum = c and c:FindFirstChildOfClass("Humanoid")
				local seat = hum and hum.SeatPart
				if seat and seat:IsA("VehicleSeat") and (cooldown[player] or 0) < os.clock() then
					local pos = seat.CFrame.Position
					for _, g in garages do
						if (pos - g.gate).Magnitude < 12 then
							if allowed(player, g) then
								cooldown[player] = os.clock() + 4
								move(player, g.inside)
							else
								cooldown[player] = os.clock() + 4
							end
							break
						elseif (pos - g.exit).Magnitude < 10 then
							cooldown[player] = os.clock() + 4
							move(player, g.street)
							break
						end
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		cooldown[player] = nil
	end)
end

return GarageService
