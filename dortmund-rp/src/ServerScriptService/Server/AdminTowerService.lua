--!strict
-- Admin Tower (on Locations.Sites.AdminTower):
--   Lobby       - the entrance only lets admins in (Game Admin and up). Whoever is
--                 inside may stay, whatever their rank (e.g. a player an admin brought in).
--   Floor 1     - an office per admin (name on the door) with a PC = the phone apps
--   Floor 2     - meeting room
--   Floor 3     - "Sonderraum": a closed room admins can put players in (e.g. cheaters).
--                 They stay there (also after respawning / rejoining) until released.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Locations = require(ReplicatedStorage.Shared.Locations)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local Roles = require(script.Parent.Roles)

local AdminTowerService = {}

local W, D = 104, 104
local FH = 14
local FLOORS = 4 -- lobby, offices, meeting, holding room

local CONCRETE = Color3.fromRGB(60, 62, 68)
local GLASS = Color3.fromRGB(40, 60, 80)
local WALL = Color3.fromRGB(232, 230, 225)
local CARPET = Color3.fromRGB(70, 76, 92)
local WOOD = Color3.fromRGB(150, 110, 75)
local DARK = Color3.fromRGB(30, 30, 34)
local ORANGE = Color3.fromRGB(255, 115, 0)

local origin: CFrame? = nil
local spots: { [string]: CFrame } = {} -- where people are put: Outside, Lobby, Offices, Meeting, Holding, HoldingHall

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
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function sign(p: BasePart, face: Enum.NormalId, text: string, color: Color3?, bg: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = if bg then 0 else 1
	l.BackgroundColor3 = bg or Color3.new()
	l.TextScaled = true
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Text = text
	l.Parent = gui
	return l
end

local function prompt(parent: BasePart, action: string, object: string, fn: (Player) -> ())
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = action
	pr.ObjectText = object
	pr.HoldDuration = 0
	pr.MaxActivationDistance = 10
	pr.RequiresLineOfSight = false
	pr.Parent = parent
	local ok, signal = pcall(function()
		return pr.Triggered
	end)
	if ok and signal then
		signal:Connect(fn)
	end
	return pr
end

local function isAdmin(player: Player): boolean
	return Roles.Rank(player) >= Roles.GAME_ADMIN
end

local function moveTo(player: Player, cf: CFrame?)
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not c or not cf then
		return
	end
	if hum then
		hum.Sit = false
	end
	c:PivotTo(cf + Vector3.new(0, 3, 0))
end

-- the admins, in rank order (each gets an office)
function AdminTowerService.AdminIds(): { number }
	local out, seen = {}, {}
	local function add(id: number)
		if not seen[id] then
			seen[id] = true
			table.insert(out, id)
		end
	end
	add(Config.OwnerId)
	for _, id in Config.CoOwners do
		add(id)
	end
	for _, id in Config.SecondCoOwners do
		add(id)
	end
	for _, id in Config.GameAdmins do
		add(id)
	end
	return out
end

local function groundY(x: number, z: number): number
	local ok, y = pcall(function()
		local city = Workspace:FindFirstChild("City")
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		local list = {}
		if city then
			for _, name in { "Ground", "Areas", "Pavements", "Roads" } do
				local f = city:FindFirstChild(name)
				if f then
					table.insert(list, f)
				end
			end
		end
		params.FilterDescendantsInstances = list
		local hit = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), params)
		return if hit then hit.Position.Y else 0
	end)
	return if ok then y else 0
end

-- Floors ------------------------------------------------------------------------------

local function elevator(m: Instance, at: (number, number, number) -> CFrame, floor: number, y: number)
	-- a panel of buttons at the back wall; the Sonderraum button only works for admins
	local face = CFrame.Angles(0, math.rad(90), 0) -- front (-Z) turned to -X
	local panel = box(m, "LiftPanel", Vector3.new(10, 6, 0.6), at(W / 2 - 1.6, y + 6, 0) * face, DARK)
	sign(panel, Enum.NormalId.Front, "🛗 AUFZUG", Color3.fromRGB(255, 200, 80))
	local buttons = {
		{ "Lobby", "Lobby", false },
		{ "Büros", "Offices", false },
		{ "Besprechung", "Meeting", false },
		{ "Sonderraum", "HoldingHall", true },
	}
	for i, b in buttons do
		if i - 1 ~= floor then
			local btn = box(
				m,
				"LiftButton",
				Vector3.new(1.6, 1.6, 0.4),
				at(W / 2 - 2.2, y + 3.4, -6 + i * 2.4) * face,
				if b[3] then ORANGE else Color3.fromRGB(220, 220, 225),
				Enum.Material.Neon
			)
			prompt(btn, "→ " .. b[1], "Aufzug", function(player)
				if b[3] and not isAdmin(player) then
					Remotes.Push(player, "Notify", { key = "admin_only", error = true })
					return
				end
				moveTo(player, spots[b[2]])
			end)
		end
	end
end

local function buildLobby(m: Instance, at: (number, number, number) -> CFrame, y: number)
	box(m, "Reception", Vector3.new(16, 3.6, 4), at(0, y + 1.8, -10), WOOD, Enum.Material.Wood)
	local logo = box(m, "Logo", Vector3.new(24, 6, 0.4), at(0, y + 8, D / 2 - 1), DARK)
	sign(logo, Enum.NormalId.Front, "🛡️ ADMIN TOWER", ORANGE)
	for _, sx in { -1, 1 } do
		box(m, "Sofa", Vector3.new(12, 2, 4), at(sx * 32, y + 1, 0), Color3.fromRGB(50, 52, 60), Enum.Material.Fabric)
		box(m, "Plant", Vector3.new(3, 6, 3), at(sx * 44, y + 3, -40), Color3.fromRGB(60, 140, 70), Enum.Material.Grass)
	end
	-- leave: anyone inside may leave
	local exitPad = box(
		m,
		"ExitDoor",
		Vector3.new(8, 10, 0.6),
		at(0, y + 5, -D / 2 + 1.4),
		Color3.fromRGB(80, 60, 45),
		Enum.Material.Wood
	)
	prompt(exitPad, "Verlassen", "Admin Tower", function(player)
		if player:GetAttribute("Detained") then
			return
		end
		moveTo(player, spots.Outside)
	end)
	spots.Lobby = at(0, y + 0.5, -30)
end

local function buildOffices(m: Instance, at: (number, number, number) -> CFrame, y: number)
	local ids = AdminTowerService.AdminIds()
	local hall = 10 -- corridor z from -hall/2 to hall/2
	local perSide = 3
	local ow = W / perSide
	for side = -1, 1, 2 do
		local wallZ = side * hall / 2
		for i = 1, perSide do
			local cx = -W / 2 + (i - 0.5) * ow
			local n = (if side < 0 then 0 else perSide) + i
			local userId = ids[n]
			-- corridor wall with a door gap
			local gap = 6
			local seg = (ow - gap) / 2
			for _, s in { -1, 1 } do
				box(
					m,
					"OfficeWall",
					Vector3.new(seg, FH - 1, 0.6),
					at(cx + s * (gap / 2 + seg / 2), y + (FH - 1) / 2, wallZ),
					WALL
				)
			end
			box(m, "DoorTop", Vector3.new(gap, 3, 0.6), at(cx, y + FH - 2.5, wallZ), WALL)
			-- side wall between offices
			if i < perSide then
				box(
					m,
					"OfficeWall",
					Vector3.new(0.6, FH - 1, D / 2 - hall / 2),
					at(cx + ow / 2, y + (FH - 1) / 2, side * (hall / 2 + (D / 2 - hall / 2) / 2)),
					WALL
				)
			end
			-- name plate (filled in below)
			local plate = box(m, "NamePlate", Vector3.new(7, 1.4, 0.2), at(cx, y + 9.5, wallZ - side * 0.45), DARK)
			local face = if side < 0 then Enum.NormalId.Back else Enum.NormalId.Front
			local label = sign(plate, face, if userId then "…" else "Frei", ORANGE)
			if userId then
				task.spawn(function()
					local ok, name = pcall(function()
						return Players:GetNameFromUserIdAsync(userId)
					end)
					label.Text = if ok then name else tostring(userId)
				end)
			end
			-- desk + chair + PC
			local dz = side * (hall / 2 + 16)
			box(m, "Desk", Vector3.new(10, 0.5, 4), at(cx, y + 3, dz), WOOD, Enum.Material.Wood)
			box(m, "DeskLeg", Vector3.new(9.4, 2.8, 3.4), at(cx, y + 1.4, dz), DARK)
			local monitor = box(
				m,
				"PC",
				Vector3.new(4, 2.6, 0.3),
				at(cx, y + 4.6, dz + side * 1.2) * CFrame.Angles(0, if side < 0 then math.pi else 0, 0),
				DARK,
				Enum.Material.Glass
			)
			sign(monitor, Enum.NormalId.Front, "NVDR OS", Color3.fromRGB(57, 255, 20), Color3.fromRGB(10, 14, 20))
			prompt(monitor, "PC benutzen", "Büro", function(player)
				Remotes.Push(player, "OpenPC", {})
			end)
			local chair = Instance.new("Seat")
			chair.Name = "Chair"
			chair.Anchored = true
			chair.Size = Vector3.new(2.6, 0.6, 2.6)
			chair.CFrame = at(cx, y + 1.6, dz - side * 3.4) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0)
			chair.Color = Color3.fromRGB(40, 40, 44)
			chair.Parent = m
		end
	end
	spots.Offices = at(W / 2 - 8, y + 0.5, 0)
end

local function buildMeeting(m: Instance, at: (number, number, number) -> CFrame, y: number)
	box(m, "Table", Vector3.new(44, 0.6, 12), at(0, y + 3, -6), WOOD, Enum.Material.Wood)
	box(m, "TableBase", Vector3.new(40, 2.6, 6), at(0, y + 1.4, -6), DARK)
	for i = 0, 5 do
		for _, sz in { -1, 1 } do
			local chair = Instance.new("Seat")
			chair.Name = "Chair"
			chair.Anchored = true
			chair.Size = Vector3.new(2.6, 0.6, 2.6)
			chair.CFrame = at(-17.5 + i * 7, y + 1.6, -6 + sz * 8.5)
				* CFrame.Angles(0, if sz < 0 then math.pi else 0, 0)
			chair.Color = Color3.fromRGB(40, 40, 44)
			chair.Parent = m
		end
	end
	local screen = box(m, "Screen", Vector3.new(30, 12, 0.4), at(0, y + 7.5, -D / 2 + 1.2), DARK, Enum.Material.Glass)
	sign(screen, Enum.NormalId.Back, "🛡️ Admin-Meeting", ORANGE, Color3.fromRGB(10, 14, 20))
	local pc = box(
		m,
		"PC",
		Vector3.new(4, 2.6, 0.3),
		at(-24, y + 4.6, -6) * CFrame.Angles(0, math.rad(90), 0),
		DARK,
		Enum.Material.Glass
	)
	sign(pc, Enum.NormalId.Front, "NVDR OS", Color3.fromRGB(57, 255, 20), Color3.fromRGB(10, 14, 20))
	prompt(pc, "PC benutzen", "Besprechung", function(player)
		Remotes.Push(player, "OpenPC", {})
	end)
	spots.Meeting = at(W / 2 - 8, y + 0.5, 0)
end

local function buildHolding(m: Instance, at: (number, number, number) -> CFrame, y: number)
	-- the cell: front part of the floor, closed on all sides (window to the hallway)
	local cellD = 46
	local wallZ = -D / 2 + cellD
	box(m, "CellWall", Vector3.new(W, FH - 1, 0.8), at(0, y + 3.5, wallZ), WALL) -- lower part
	box(
		m,
		"CellWindow",
		Vector3.new(W, 5, 0.4),
		at(0, y + 9.5, wallZ),
		GLASS,
		Enum.Material.Glass,
		{ Transparency = 0.5 }
	)
	box(m, "CellWallTop", Vector3.new(W, 1.5, 0.8), at(0, y + FH - 1.75, wallZ), WALL)
	box(
		m,
		"Bench",
		Vector3.new(14, 1.4, 3),
		at(-30, y + 0.7, -D / 2 + 4),
		Color3.fromRGB(120, 120, 125),
		Enum.Material.Concrete
	)
	box(m, "Toilet", Vector3.new(2.4, 2.4, 2.8), at(40, y + 1.2, -D / 2 + 4), Color3.fromRGB(240, 240, 240))
	local cellSign = box(m, "CellSign", Vector3.new(20, 3, 0.2), at(0, y + 6, wallZ - 0.5), DARK)
	sign(cellSign, Enum.NormalId.Front, "SONDERRAUM", Color3.fromRGB(255, 70, 60))
	local outSign = box(m, "CellSignOut", Vector3.new(20, 3, 0.2), at(0, y + 6, wallZ + 0.5), DARK)
	sign(outSign, Enum.NormalId.Back, "🚔 SONDERRAUM", Color3.fromRGB(255, 70, 60))
	-- admin door (both sides)
	local doorOut = box(m, "CellDoor", Vector3.new(6, 9, 0.5), at(30, y + 4.5, wallZ + 0.7), ORANGE)
	prompt(doorOut, "Sonderraum betreten", "Nur Admins", function(player)
		if not isAdmin(player) then
			Remotes.Push(player, "Notify", { key = "admin_only", error = true })
			return
		end
		moveTo(player, spots.Holding)
	end)
	local doorIn = box(m, "CellDoorInside", Vector3.new(6, 9, 0.5), at(30, y + 4.5, wallZ - 0.7), ORANGE)
	prompt(doorIn, "Sonderraum verlassen", "Nur Admins", function(player)
		if not isAdmin(player) then
			return -- the people put in here can't open it
		end
		moveTo(player, spots.HoldingHall)
	end)
	spots.Holding = at(0, y + 0.5, -D / 2 + 20)
	spots.HoldingHall = at(W / 2 - 8, y + 0.5, wallZ + 12)
end

function AdminTowerService.Build()
	local site = (Locations.Sites :: any).AdminTower
	if not site then
		warn("[AdminTower] no site")
		return
	end
	local y0 = groundY(site.x, site.z) + 0.05
	origin = CFrame.new(site.x, y0, site.z) * CFrame.Angles(0, math.rad(site.yaw), 0)
	local o = origin :: CFrame
	local function at(x: number, y: number, z: number): CFrame
		return o * CFrame.new(x, y, z)
	end
	local root = Instance.new("Model")
	root.Name = "Admin Tower"

	local H = FLOORS * FH
	-- outer shell: concrete corners, dark glass between, orange band on top
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(
				root,
				"Corner",
				Vector3.new(4, H + 2, 4),
				at(sx * (W / 2 - 2), H / 2 + 1, sz * (D / 2 - 2)),
				CONCRETE,
				Enum.Material.Concrete
			)
		end
	end
	for f = 0, FLOORS - 1 do
		local y = f * FH
		box(
			root,
			"Floor",
			Vector3.new(W, 1, D),
			at(0, y - 0.5, 0),
			if f == 0 then Color3.fromRGB(200, 200, 205) else CARPET,
			if f == 0 then Enum.Material.Marble else Enum.Material.Fabric
		)
		for _, side in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
			local horizontal = side[1] == 0
			local size = if horizontal then Vector3.new(W - 8, FH, 1) else Vector3.new(1, FH, D - 8)
			local cf = at(side[1] * (W / 2 - 0.5), y + FH / 2, side[2] * (D / 2 - 0.5))
			box(root, "Facade", size, cf, GLASS, Enum.Material.Glass, { Transparency = 0.25, Reflectance = 0.15 })
			box(
				root,
				"Band",
				if horizontal then Vector3.new(W, 1.2, 1.4) else Vector3.new(1.4, 1.2, D),
				at(side[1] * (W / 2 - 0.5), y + FH - 0.6, side[2] * (D / 2 - 0.5)),
				CONCRETE,
				Enum.Material.Concrete
			)
		end
		-- ceiling lights
		for _, lx in { -25, 25 } do
			for _, lz in { -25, 25 } do
				local lamp = box(
					root,
					"Lamp",
					Vector3.new(6, 0.3, 6),
					at(lx, y + FH - 1.4, lz),
					Color3.fromRGB(255, 250, 235),
					Enum.Material.Neon,
					{ CanCollide = false }
				)
				local light = Instance.new("PointLight")
				light.Range = 30
				light.Brightness = 1.4
				light.Parent = lamp
			end
		end
	end
	box(root, "Roof", Vector3.new(W, 1.5, D), at(0, H + 0.25, 0), CONCRETE, Enum.Material.Concrete)
	local roofSign = box(root, "RoofSign", Vector3.new(60, 10, 1), at(0, H + 6, -D / 2 + 2), DARK)
	sign(roofSign, Enum.NormalId.Front, "ADMIN TOWER", ORANGE)

	-- entrance (outside): only admins get in
	local door = box(
		root,
		"EntranceDoor",
		Vector3.new(10, 11, 1.2),
		at(0, 5.5, -D / 2 - 0.2),
		Color3.fromRGB(25, 25, 28),
		Enum.Material.Metal
	)
	sign(door, Enum.NormalId.Front, "🛡️ NUR ADMINS", ORANGE, Color3.fromRGB(25, 25, 28))
	prompt(door, "Betreten", "Admin Tower", function(player)
		if not isAdmin(player) then
			Remotes.Push(player, "Notify", { key = "admin_only", error = true })
			return
		end
		moveTo(player, spots.Lobby)
	end)
	spots.Outside = at(0, 0.5, -D / 2 - 10) * CFrame.Angles(0, math.pi, 0)

	buildLobby(root, at, 0)
	buildOffices(root, at, FH)
	buildMeeting(root, at, FH * 2)
	buildHolding(root, at, FH * 3)
	for f = 0, FLOORS - 1 do
		elevator(root, at, f, f * FH)
	end
	root.Parent = Workspace
end

-- Sonderraum ----------------------------------------------------------------------------

local function sendBack(player: Player)
	if player:GetAttribute("Detained") then
		task.wait(0.3)
		moveTo(player, spots.Holding)
	end
end

function AdminTowerService.Detain(player: Player)
	local data = DataService.Get(player)
	if data then
		data.detained = true
	end
	player:SetAttribute("Detained", true)
	moveTo(player, spots.Holding)
	Remotes.Push(player, "Notify", { key = "detained", error = true })
end

function AdminTowerService.Release(player: Player)
	local data = DataService.Get(player)
	if data then
		data.detained = nil
	end
	player:SetAttribute("Detained", nil)
	moveTo(player, spots.Outside)
	Remotes.Push(player, "Notify", { key = "released" })
end

function AdminTowerService.Spot(name: string): CFrame?
	return spots[name]
end

function AdminTowerService.Start()
	DataService.Loaded:Connect(function(player, data)
		if data.detained then
			player:SetAttribute("Detained", true)
			if player.Character then
				task.spawn(sendBack, player)
			end
		end
	end)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			task.spawn(sendBack, player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
end

return AdminTowerService
