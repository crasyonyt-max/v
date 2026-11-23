--!strict
-- v0.4 furniture:
--   * Swedea (Locations.Sites.Swedea): the Swedish furniture store with a showroom;
--     buy at the checkout, one SLÄPPA bed is free for everyone
--   * bought furniture goes into your furniture storage (data.furniture)
--   * build mode: owner + co-owners place furniture in the house and garden of the
--     plot; picking it up puts it back into YOUR storage
-- Placed furniture is saved with the house (HouseService record, plot frame).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Furniture = require(ReplicatedStorage.Shared.Furniture)
local Houses = require(ReplicatedStorage.Shared.Houses)
local Locations = require(ReplicatedStorage.Shared.Locations)
local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local GameLog = require(script.Parent.GameLog)
local HouseService = require(script.Parent.HouseService)
local Interaction = require(script.Parent.InteractionService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local ThanksgivingService = require(script.Parent.ThanksgivingService)

local FurnitureService = {}

local SWEDEA_BLUE = Color3.fromRGB(0, 81, 186)
local SWEDEA_YELLOW = Color3.fromRGB(255, 218, 26)
local BUILD_RANGE = 90 -- studs from the plot centre while building

-- Placement rules -----------------------------------------------------------------------

-- the area of a plot where furniture may stand (plot frame, relative)
function FurnitureService.Area(): (Vector3, number)
	-- half extents (x, z) and max height
	return Vector3.new(Houses.PLOT_W / 2 - 1, 0, Houses.PLOT_D / 2 - 1), Houses.FLOOR_H * 3 + 6
end

function FurnitureService.Fits(id: string, x: number, y: number, z: number, r: number): boolean
	local half, maxY = FurnitureService.Area()
	return Furniture.Fits(id, x, y, z, r, half, maxY)
end

-- Rendering -----------------------------------------------------------------------------

local function render(ownerId: number)
	local plot = HouseService.PlotOf(ownerId)
	local record = HouseService.Records[ownerId]
	if not plot or not plot.built or not record then
		return
	end
	local model = plot.built.model
	local folder = model:FindFirstChild("Furniture")
	if folder then
		folder:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "Furniture"
	for i, e in record.furniture do
		local m = Furniture.Build(e.id)
		if m then
			Furniture.Place(m, plot.cf * CFrame.new(e.x, e.y, e.z) * CFrame.Angles(0, math.rad(e.r), 0))
			m:SetAttribute("Index", i)
			if e.id == "oven" then
				ThanksgivingService.EquipOven(m) -- bake Thanksgiving turkeys
			end
			m.Parent = f
		end
	end
	f.Parent = model
end
FurnitureService.Render = render

-- Swedea store ------------------------------------------------------------------------------

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function label(p: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3, ppu: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppu or 20
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = bg
	l.BorderSizePixel = 0
	l.TextScaled = true
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = color
	l.Text = text
	l.Parent = gui
end

function FurnitureService.Build()
	if not Config.V04 then
		return
	end
	local site = (Locations.Sites :: any).Swedea
	if not site then
		return
	end
	local y0 = CityBuilder.GroundY(site.x, site.z) + 0.05
	local origin = CFrame.new(site.x, y0, site.z) * CFrame.Angles(0, math.rad(site.yaw), 0)
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end
	local m = Instance.new("Model")
	m.Name = "Swedea"
	local W, D, H = 150, 110, 30
	local door = 24
	-- big blue box with a yellow band, open entrance in the front
	part(m, "Floor", Vector3.new(W, 1, D), at(0, 0, 0), Color3.fromRGB(205, 200, 190), Enum.Material.Concrete)
	part(m, "Roof", Vector3.new(W + 2, 2, D + 2), at(0, H, 0), Color3.fromRGB(60, 60, 64), Enum.Material.Concrete)
	part(m, "Back", Vector3.new(W, H, 2), at(0, H / 2, D / 2), SWEDEA_BLUE, Enum.Material.Metal)
	for _, sx in { -1, 1 } do
		part(m, "Side", Vector3.new(2, H, D), at(sx * W / 2, H / 2, 0), SWEDEA_BLUE, Enum.Material.Metal)
		local side = (W - door) / 2
		part(
			m,
			"Front",
			Vector3.new(side, H, 2),
			at(sx * (door / 2 + side / 2), H / 2, -D / 2),
			SWEDEA_BLUE,
			Enum.Material.Metal
		)
	end
	part(
		m,
		"FrontTop",
		Vector3.new(door, H - 14, 2),
		at(0, 14 + (H - 14) / 2, -D / 2),
		SWEDEA_BLUE,
		Enum.Material.Metal
	)
	part(m, "Band", Vector3.new(W + 0.4, 3, 2.4), at(0, H - 4, -D / 2), SWEDEA_YELLOW)
	local sign = part(m, "Sign", Vector3.new(60, 14, 1), at(0, H - 12, -D / 2 - 1.6), SWEDEA_YELLOW)
	label(sign, Enum.NormalId.Front, "SWEDEA", SWEDEA_BLUE, SWEDEA_YELLOW, 10)
	-- lights
	for x = -W / 2 + 20, W / 2 - 20, 40 do
		for z = -D / 2 + 20, D / 2 - 20, 35 do
			local lamp = part(
				m,
				"Lamp",
				Vector3.new(6, 0.4, 2),
				at(x, H - 1.5, z),
				Color3.fromRGB(250, 248, 240),
				Enum.Material.Neon
			)
			local l = Instance.new("PointLight")
			l.Range = 40
			l.Brightness = 0.6
			l.Parent = lamp
		end
	end
	-- showroom: every piece on display with its name and price
	local col, row = 0, 0
	for _, it in Furniture.List do
		local x = -W / 2 + 16 + col * 20
		local z = -D / 2 + 26 + row * 18
		local sample = Furniture.Build(it.id)
		if sample then
			Furniture.Place(sample, at(x, 0.5, z))
			sample.Parent = m
		end
		local tag = part(
			m,
			"PriceTag",
			Vector3.new(6, 2, 0.2),
			at(x, 1.5, z - math.max(it.size.Z / 2, 1) - 2),
			Color3.new(1, 1, 1)
		)
		label(
			tag,
			Enum.NormalId.Front,
			("%s\n%s · %d €"):format(it.name, it.kind, it.price),
			Color3.new(0, 0, 0),
			SWEDEA_YELLOW
		)
		col += 1
		if col >= 7 then
			col = 0
			row += 1
		end
	end
	-- checkout
	part(m, "Checkout", Vector3.new(14, 3.4, 3), at(0, 1.7, -D / 2 + 10), Color3.fromRGB(240, 240, 240))
	local marker = part(m, "Marker_Swedea", Vector3.new(3, 3, 3), at(0, 2.5, -D / 2 + 7), Color3.new(1, 1, 1))
	marker.Transparency = 1
	marker.CanCollide = false
	Interaction.Mark(marker, "Shop", { UI = "Swedea", ActionText = "Möbel kaufen", ObjectText = "Swedea" })
	m.Parent = Workspace
end

-- Remotes -------------------------------------------------------------------------------------

local function storage(data: { [string]: any }): { [string]: number }
	data.furniture = data.furniture or {}
	return data.furniture
end

function FurnitureService.Start()
	if not Config.V04 then
		return
	end
	HouseService.OnChanged(render)

	Remotes.Handle("Furniture.Storage", function(player)
		local data = DataService.Get(player)
		if not data then
			return Remotes.Fail("error")
		end
		return Remotes.Ok({ items = table.clone(storage(data)), freeBed = data.freeBed ~= true })
	end, { rate = 10 })

	Remotes.Handle("Swedea.Buy", function(player, id: any, count: any)
		local it = typeof(id) == "string" and Furniture.ById[id] or nil
		local n = Remotes.Check.Int(count or 1, 1, 20)
		local data = DataService.Get(player)
		if not it or not n or not data then
			return Remotes.Fail("bad_item")
		end
		if not Interaction.IsNear(player, "Shop", 30, "UI", "Swedea") then
			return Remotes.Fail("too_far")
		end
		if not Economy.TrySpend(player, it.price * n, "Swedea: " .. it.name) then
			return Remotes.Fail("no_money")
		end
		local s = storage(data)
		s[it.id] = (s[it.id] or 0) + n
		State.MarkDirty(player)
		return Remotes.Ok({ items = table.clone(s) })
	end, { rate = 10 })

	Remotes.Handle("Swedea.FreeBed", function(player)
		local data = DataService.Get(player)
		if not data then
			return Remotes.Fail("error")
		end
		if data.freeBed == true then
			return Remotes.Fail("swedea_free_used")
		end
		data.freeBed = true
		local s = storage(data)
		s[Furniture.FREE_BED] = (s[Furniture.FREE_BED] or 0) + 1
		State.MarkDirty(player)
		GameLog.Add("money", player, "free bed")
		return Remotes.Ok({ items = table.clone(s) })
	end, { rate = 2 })

	-- build mode: which house, its plot frame and what is placed
	Remotes.Handle("Build.Begin", function(player, ownerId: any)
		local oid = Remotes.Check.Int(ownerId, 1, 1e12)
		local plot = oid and HouseService.PlotOf(oid)
		local record = oid and HouseService.Records[oid]
		local data = DataService.Get(player)
		if not plot or not record or not data then
			return Remotes.Fail("house_not_here")
		end
		if not HouseService.CanBuild(record, player.UserId) then
			return Remotes.Fail("no_permission")
		end
		local half, maxY = FurnitureService.Area()
		return Remotes.Ok({
			plot = plot.cf,
			half = half,
			maxY = maxY,
			items = table.clone(storage(data)),
			placed = #record.furniture,
			max = Houses.MAX_FURNITURE,
		})
	end, { rate = 6 })

	local function near(player: Player, ownerId: number): boolean
		local plot = HouseService.PlotOf(ownerId)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		return plot ~= nil and root ~= nil and (root.Position - plot.cf.Position).Magnitude <= BUILD_RANGE
	end

	Remotes.Handle("Build.Place", function(player, ownerId: any, id: any, x: any, y: any, z: any, r: any)
		local oid = Remotes.Check.Int(ownerId, 1, 1e12)
		local record = oid and HouseService.Records[oid]
		local data = DataService.Get(player)
		if not oid or not record or not data or typeof(id) ~= "string" then
			return Remotes.Fail("bad_request")
		end
		if not HouseService.CanBuild(record, player.UserId) then
			return Remotes.Fail("no_permission")
		end
		if not near(player, oid) then
			return Remotes.Fail("too_far")
		end
		local px, py, pz =
			Remotes.Check.Number(x, -200, 200), Remotes.Check.Number(y, -5, 100), Remotes.Check.Number(z, -200, 200)
		local rot = Remotes.Check.Number(r, -360, 720)
		if not px or not py or not pz or not rot or not FurnitureService.Fits(id, px, py, pz, rot) then
			return Remotes.Fail("build_bad_spot")
		end
		local s = storage(data)
		if (s[id] or 0) < 1 then
			return Remotes.Fail("build_none_left")
		end
		if #record.furniture >= Houses.MAX_FURNITURE then
			return Remotes.Fail("build_full")
		end
		s[id] -= 1
		if s[id] <= 0 then
			s[id] = nil
		end
		local saved = HouseService.Edit(oid, function(rec)
			table.insert(rec.furniture, {
				id = id,
				x = math.floor(px * 10 + 0.5) / 10,
				y = math.floor(py * 10 + 0.5) / 10,
				z = math.floor(pz * 10 + 0.5) / 10,
				r = rot % 360,
				by = player.UserId,
			})
		end)
		if not saved then
			s[id] = (s[id] or 0) + 1
			return Remotes.Fail("error")
		end
		State.MarkDirty(player)
		return Remotes.Ok({ items = table.clone(s), placed = #saved.furniture })
	end, { rate = 20 })

	Remotes.Handle("Build.Remove", function(player, ownerId: any, index: any, id: any)
		local oid = Remotes.Check.Int(ownerId, 1, 1e12)
		local i = Remotes.Check.Int(index, 1, 1000)
		local record = oid and HouseService.Records[oid]
		local data = DataService.Get(player)
		if not oid or not i or not record or not data then
			return Remotes.Fail("bad_request")
		end
		if not HouseService.CanBuild(record, player.UserId) then
			return Remotes.Fail("no_permission")
		end
		local removed: string? = nil
		local saved = HouseService.Edit(oid, function(rec)
			local e = rec.furniture[i]
			if e and e.id == id then
				removed = e.id
				table.remove(rec.furniture, i)
			end
		end)
		if not saved or not removed then
			return Remotes.Fail("build_gone")
		end
		local s = storage(data)
		s[removed :: string] = (s[removed :: string] or 0) + 1
		State.MarkDirty(player)
		return Remotes.Ok({ items = table.clone(s), placed = #saved.furniture })
	end, { rate = 20 })
end

return FurnitureService
