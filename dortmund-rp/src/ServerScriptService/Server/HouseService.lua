--!strict
-- v0.4 houses in the Wohngebiet (Locations.Sites.Estate).
--   * buy a house type at the Immobilienmakler (200.000 € – 5.000.000 €), one per player
--   * on every server your house is built on a free plot while you (or a co-owner)
--     are there; furniture and roles are saved in the "_Houses" DataStore, so
--     co-owners can furnish it even when the owner is offline
--   * roles: owner, co-owner (enter + furnish + invite guests), guest (enter)
--   * the front door only lets the allowed players through (opened on their own
--     screen, closed for everybody else); others can ring the bell

local DataStoreService = require(script.Parent.Sandbox).DataStoreService -- local only on the testing server
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Houses = require(ReplicatedStorage.Shared.Houses)
local Locations = require(ReplicatedStorage.Shared.Locations)
local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local GameLog = require(script.Parent.GameLog)
local HouseBuilder = require(script.Parent.HouseBuilder)
local Interaction = require(script.Parent.InteractionService)
local Remotes = require(script.Parent.Remotes)

local HouseService = {}

export type Record = {
	owner: number,
	ownerName: string,
	type: string,
	plot: number?,
	members: { [string]: { role: string, name: string } }, -- [userId] = role
	furniture: { { id: string, x: number, y: number, z: number, r: number, by: number? } },
	bought: number,
}

type Plot = {
	index: number,
	cf: CFrame,
	owner: number?, -- whose house stands here
	built: HouseBuilder.Built?,
	sign: Model?,
}

local store: DataStore? = nil
local links: DataStore? = nil -- [userId] = { ownerIds they are co-owner / guest of }
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName .. "_Houses")
	links = DataStoreService:GetDataStore(Config.DataStoreName .. "_HouseLinks")
end)

local plots: { Plot } = {}
local records: { [number]: Record } = {} -- owner -> record (houses on this server)
local memory: { [string]: any } = {} -- Studio / tests without DataStores
HouseService.Plots = plots
HouseService.Records = records
local listeners: { (number) -> () } = {}
-- fn(ownerId) runs whenever a house on this server changed (furniture, roles)
function HouseService.OnChanged(fn: (number) -> ())
	table.insert(listeners, fn)
end
local function changed(ownerId: number)
	for _, fn in listeners do
		task.spawn(fn, ownerId)
	end
end

local folder = Instance.new("Folder")
folder.Name = "Wohngebiet"

-- DataStore helpers ------------------------------------------------------------------

local function dsGet(ds: DataStore?, key: string): any
	if not ds then
		return memory[key]
	end
	local ok, v = pcall(function()
		return (ds :: DataStore):GetAsync(key)
	end)
	return if ok then v else nil
end

local function dsUpdate(ds: DataStore?, key: string, fn: (any) -> any): (boolean, any)
	if not ds then
		local v = fn(memory[key])
		memory[key] = v
		return true, v
	end
	local result = nil
	local ok, err = pcall(function()
		(ds :: DataStore):UpdateAsync(key, function(old)
			result = fn(old)
			return result
		end)
	end)
	if not ok then
		warn("[Houses] save failed (" .. key .. "): " .. tostring(err))
	end
	return ok, result
end

local function dsRemove(ds: DataStore?, key: string)
	if not ds then
		memory[key] = nil
		return
	end
	pcall(function()
		(ds :: DataStore):RemoveAsync(key)
	end)
end

function HouseService.Load(ownerId: number): Record?
	local r = dsGet(store, "h_" .. ownerId)
	return if typeof(r) == "table" then r :: any else nil
end

-- change a house record safely (also from another server at the same time)
function HouseService.Edit(ownerId: number, fn: (Record) -> ()): Record?
	local ok, r = dsUpdate(store, "h_" .. ownerId, function(old: any)
		if typeof(old) ~= "table" then
			return nil
		end
		old.members = old.members or {}
		old.furniture = old.furniture or {}
		fn(old)
		return old
	end)
	if not ok or typeof(r) ~= "table" then
		return nil
	end
	if records[ownerId] then
		records[ownerId] = r
		changed(ownerId)
	end
	return r
end

-- creates a house record if the player has none yet (false: has one / save failed)
function HouseService.Create(record: Record): boolean
	local created = false
	local ok = dsUpdate(store, "h_" .. record.owner, function(old: any)
		if typeof(old) == "table" then
			return old -- already has one (maybe from another server): keep it
		end
		created = true
		return record
	end)
	return ok and created
end

local function setLink(userId: number, ownerId: number, on: boolean)
	dsUpdate(links, "l_" .. userId, function(old: any)
		local list = if typeof(old) == "table" then old else {}
		local i = table.find(list, ownerId)
		if on and not i then
			table.insert(list, ownerId)
		elseif not on and i then
			table.remove(list, i)
		end
		return list
	end)
end

-- Roles ------------------------------------------------------------------------------

function HouseService.RoleOf(record: Record, userId: number): string?
	if record.owner == userId then
		return "owner"
	end
	local m = record.members[tostring(userId)]
	return m and m.role or nil
end

function HouseService.CanEnter(record: Record, userId: number): boolean
	return HouseService.RoleOf(record, userId) ~= nil
end

function HouseService.CanBuild(record: Record, userId: number): boolean
	local role = HouseService.RoleOf(record, userId)
	return role == "owner" or role == "coowner"
end

-- Estate + plots -------------------------------------------------------------------------

local ROAD = Color3.fromRGB(58, 58, 62)

local function box(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

local function label(p: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = bg
	l.BorderSizePixel = 0
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color
	l.Text = text
	l.Parent = gui
end

-- "Zu verkaufen" sign on a free plot
local function forSale(plot: Plot)
	local m = Instance.new("Model")
	m.Name = "ZuVerkaufen"
	local post = Instance.new("Part")
	post.Anchored = true
	post.Size = Vector3.new(0.4, 6, 0.4)
	post.CFrame = plot.cf * CFrame.new(0, 3, -Houses.PLOT_D / 2 + 4)
	post.Color = Color3.fromRGB(240, 240, 240)
	post.Parent = m
	local board = Instance.new("Part")
	board.Anchored = true
	board.Size = Vector3.new(6, 3, 0.3)
	board.CFrame = plot.cf * CFrame.new(0, 6.5, -Houses.PLOT_D / 2 + 4)
	board.Color = Color3.fromRGB(200, 30, 30)
	board.Parent = m
	label(
		board,
		Enum.NormalId.Front,
		("ZU VERKAUFEN\nGrundstück %d · Immobilienmakler"):format(plot.index),
		Color3.new(1, 1, 1),
		Color3.fromRGB(200, 30, 30)
	)
	local lawn = Instance.new("Part")
	lawn.Anchored = true
	lawn.Size = Vector3.new(Houses.PLOT_W, 0.2, Houses.PLOT_D)
	lawn.CFrame = plot.cf * CFrame.new(0, 0.1, 0)
	lawn.Color = Color3.fromRGB(110, 160, 80)
	lawn.Material = Enum.Material.Grass
	lawn.Parent = m
	m.Parent = folder
	plot.sign = m
end

-- Builds the estate (roads, plots, Makler office). Plot layout in the site frame:
-- two streets along X at z = ±100, a main street along Z (x = 0) to the city road,
-- 4 plots on each side of each street = 16 plots.
function HouseService.Build()
	if not Config.V04 then
		return
	end
	local site = (Locations.Sites :: any).Estate
	if not site then
		return
	end
	local y0 = CityBuilder.GroundY(site.x, site.z) + 0.05
	local origin = CFrame.new(site.x, y0, site.z) * CFrame.Angles(0, math.rad(site.yaw), 0)
	local W = site.width
	-- clear trees / lamps of the city inside the estate
	pcall(function()
		local city = Workspace:FindFirstChild("City")
		if city then
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			local list = {}
			for _, n in { "Trees", "StreetLights" } do
				local f = city:FindFirstChild(n, true)
				if f then
					table.insert(list, f)
				end
			end
			params.FilterDescendantsInstances = list
			for _, hit in Workspace:GetPartBoundsInBox(origin * CFrame.new(0, 10, 0), Vector3.new(W, 40, W), params) do
				hit:Destroy()
			end
		end
	end)
	box(
		"EstateGround",
		Vector3.new(W, 0.2, W),
		origin * CFrame.new(0, 0, 0),
		Color3.fromRGB(100, 150, 75),
		Enum.Material.Grass
	)
	for _, z in { -100, 100 } do
		box("Street", Vector3.new(W, 0.3, 24), origin * CFrame.new(0, 0.1, z), ROAD, Enum.Material.Asphalt)
		box(
			"Sidewalk",
			Vector3.new(W, 0.4, 3),
			origin * CFrame.new(0, 0.15, z - 13.5),
			Color3.fromRGB(170, 168, 160),
			Enum.Material.Concrete
		)
		box(
			"Sidewalk",
			Vector3.new(W, 0.4, 3),
			origin * CFrame.new(0, 0.15, z + 13.5),
			Color3.fromRGB(170, 168, 160),
			Enum.Material.Concrete
		)
	end
	box("MainStreet", Vector3.new(24, 0.3, W), origin * CFrame.new(0, 0.12, 0), ROAD, Enum.Material.Asphalt)
	-- entrance arch over the main street
	local entrance =
		box("EstateSign", Vector3.new(30, 5, 1), origin * CFrame.new(0, 17, -W / 2 + 3), Color3.fromRGB(30, 90, 60))
	label(entrance, Enum.NormalId.Front, "🏡 WOHNGEBIET AM PARK", Color3.new(1, 1, 1), Color3.fromRGB(30, 90, 60))
	for _, sx in { -1, 1 } do
		box(
			"ArchPost",
			Vector3.new(1.2, 19, 1.2),
			origin * CFrame.new(sx * 15, 9.5, -W / 2 + 3),
			Color3.fromRGB(60, 60, 64),
			Enum.Material.Metal
		)
	end

	-- Immobilienmakler office in the green strip between the two rows
	box(
		"MaklerOffice",
		Vector3.new(26, 12, 16),
		origin * CFrame.new(-60, 6, 0),
		Color3.fromRGB(245, 245, 240),
		Enum.Material.Plaster
	)
	local officeSign =
		box("MaklerSign", Vector3.new(22, 3, 0.4), origin * CFrame.new(-60, 10, -8.3), Color3.fromRGB(20, 60, 120))
	label(officeSign, Enum.NormalId.Front, "IMMOBILIENMAKLER", Color3.new(1, 1, 1), Color3.fromRGB(20, 60, 120))
	local marker = box("Marker_Makler", Vector3.new(3, 3, 3), origin * CFrame.new(-60, 2.5, -10.5), Color3.new(1, 1, 1))
	marker.Transparency = 1
	marker.CanCollide = false
	Interaction.Mark(marker, "Shop", { UI = "Makler", ActionText = "Häuser ansehen", ObjectText = "Immobilienmakler" })

	-- 16 plots: -Z of each plot frame faces its street
	local n = 0
	for _, row in { { z = -150 }, { z = -50 }, { z = 50 }, { z = 150 } } do
		for _, x in { -150, -65, 65, 150 } do
			n += 1
			-- street of rows at ±150 / ±50 is at ±100: rows at -150 and +50 look towards +Z
			local turn = if row.z == -150 or row.z == 50 then math.pi else 0
			local cf = origin * CFrame.new(x, 0.15, row.z) * CFrame.Angles(0, turn, 0)
			local plot: Plot = { index = n, cf = cf, owner = nil, built = nil, sign = nil }
			table.insert(plots, plot)
			forSale(plot)
		end
	end
	folder.Parent = Workspace
end

-- Houses on this server --------------------------------------------------------------

local function plotOf(ownerId: number): Plot?
	for _, p in plots do
		if p.owner == ownerId then
			return p
		end
	end
	return nil
end
HouseService.PlotOf = plotOf

local function allowedText(record: Record): string
	local ids = { tostring(record.owner) }
	for id in record.members do
		table.insert(ids, id)
	end
	return "," .. table.concat(ids, ",") .. ","
end

local function buildersText(record: Record): string
	local ids = { tostring(record.owner) }
	for id, m in record.members do
		if m.role == "coowner" then
			table.insert(ids, id)
		end
	end
	return "," .. table.concat(ids, ",") .. ","
end

local function refreshDoor(plot: Plot, record: Record)
	local built = plot.built
	if not built then
		return
	end
	built.door:SetAttribute("Allowed", allowedText(record))
	-- the mailbox "Haus verwalten" prompt shows only for these (HouseDoors, client)
	built.mailbox:SetAttribute("Builders", buildersText(record))
	built.mailbox:SetAttribute("HouseOwner", record.owner)
	built.door:SetAttribute("HouseOwner", record.owner)
	built.nameLabel.Text = record.ownerName
end

-- prompts on a new house (guarded: the offline tests can't connect events)
local function onTriggered(prompt: ProximityPrompt, fn: (Player) -> ())
	pcall(function()
		prompt.Triggered:Connect(fn)
	end)
end

local function spawnHouse(record: Record): Plot?
	local existing = plotOf(record.owner)
	if existing then
		return existing
	end
	local def = Houses.ById[record.type]
	if not def then
		return nil
	end
	-- the plot from last time if free, otherwise the first free one
	local plot: Plot? = nil
	local wanted = record.plot and plots[record.plot]
	if wanted and not wanted.owner then
		plot = wanted
	else
		for _, p in plots do
			if not p.owner then
				plot = p
				break
			end
		end
	end
	if not plot then
		return nil
	end
	if plot.sign then
		plot.sign:Destroy()
		plot.sign = nil
	end
	local built = HouseBuilder.Build(def, plot.cf, record.ownerName)
	built.model.Name = "Haus_" .. record.owner
	built.model:SetAttribute("HouseOwner", record.owner)
	built.model:SetAttribute("Plot", plot.index)
	built.model.Parent = folder
	plot.owner = record.owner
	plot.built = built
	records[record.owner] = record
	local ownerPlayer = Players:GetPlayerByUserId(record.owner)
	if ownerPlayer then
		ownerPlayer:SetAttribute("MyHouse", built.outside.Position) -- Navi "Mein Haus"
	end
	refreshDoor(plot, record)
	-- door: allowed players open it on their own screen (client); others can ring
	local bell = Instance.new("ProximityPrompt")
	bell.Name = "Bell"
	bell.ActionText = "Klingeln"
	bell.ObjectText = record.ownerName
	bell.HoldDuration = 0
	bell.MaxActivationDistance = 8
	bell.RequiresLineOfSight = false
	bell.Parent = built.door
	onTriggered(bell, function(visitor)
		local r = records[record.owner]
		if not r then
			return
		end
		for _, p in Players:GetPlayers() do
			local role = HouseService.RoleOf(r, p.UserId)
			if (role == "owner" or role == "coowner") and p ~= visitor then
				Remotes.Push(p, "Notify", { key = "house_bell", args = { visitor.DisplayName } })
			end
		end
	end)
	-- mailbox: manage the house (people, furnish, sell) – owner + co-owners
	local manage = Instance.new("ProximityPrompt")
	manage.Name = "Manage"
	manage.ActionText = "Haus verwalten"
	manage.ObjectText = def.name
	manage.HoldDuration = 0
	manage.MaxActivationDistance = 10
	manage.RequiresLineOfSight = false
	manage.Enabled = false -- switched on per player by the client (HouseDoors)
	manage.Parent = built.mailbox
	onTriggered(manage, function(p)
		local r = records[record.owner]
		if r and HouseService.CanBuild(r, p.UserId) then
			Remotes.Push(p, "OpenUI", { ui = "HouseManage", arg = record.owner })
		end
	end)
	changed(record.owner)
	return plot
end
HouseService.Spawn = spawnHouse

local function despawn(ownerId: number)
	local plot = plotOf(ownerId)
	if not plot then
		return
	end
	-- anyone inside goes out to the street
	local built = plot.built
	if built then
		for _, p in Players:GetPlayers() do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local rel = built.bounds.cf:PointToObjectSpace(root.Position)
				local half = built.bounds.size / 2 + Vector3.new(2, 4, 2)
				if math.abs(rel.X) < half.X and math.abs(rel.Y) < half.Y and math.abs(rel.Z) < half.Z then
					(p.Character :: Model):PivotTo(built.outside)
				end
			end
		end
		built.model:Destroy()
	end
	plot.owner = nil
	plot.built = nil
	records[ownerId] = nil
	local ownerPlayer = Players:GetPlayerByUserId(ownerId)
	if ownerPlayer then
		ownerPlayer:SetAttribute("MyHouse", nil)
	end
	forSale(plot)
end

-- is anyone who keeps this house here (owner or co-owner) still on the server?
local function keepsHouse(record: Record, leaving: Player?): boolean
	for _, p in Players:GetPlayers() do
		if p ~= leaving then
			local role = HouseService.RoleOf(record, p.UserId)
			if role == "owner" or role == "coowner" then
				return true
			end
		end
	end
	return false
end

local function onJoin(player: Player)
	-- own house
	local own = HouseService.Load(player.UserId)
	if own then
		own.ownerName = player.Name
		local plot = spawnHouse(own)
		if not plot then
			Remotes.Push(player, "Notify", { key = "house_no_plot", error = true })
		elseif own.plot ~= plot.index then
			HouseService.Edit(player.UserId, function(r)
				r.plot = plot.index
				r.ownerName = player.Name
			end)
		end
	end
	-- houses you co-own: built when their owner isn't here (one extra house at most)
	local mine = dsGet(links, "l_" .. player.UserId)
	if typeof(mine) == "table" then
		for _, ownerId in mine do
			local r = HouseService.Load(ownerId)
			if r and HouseService.RoleOf(r, player.UserId) == "coowner" and not plotOf(ownerId) then
				spawnHouse(r)
				break
			elseif r and plotOf(ownerId) then
				refreshDoor(plotOf(ownerId) :: Plot, r)
			end
		end
	end
end

local function onLeave(player: Player)
	for ownerId, record in records do
		if not keepsHouse(record, player) then
			despawn(ownerId)
		end
	end
end

-- what the Home app shows
local function view(record: Record, viewer: number): { [string]: any }
	local def = Houses.ById[record.type]
	local members = {}
	for id, m in record.members do
		table.insert(members, { userId = tonumber(id), name = m.name, role = m.role })
	end
	table.sort(members, function(a, b)
		return a.name < b.name
	end)
	local plot = plotOf(record.owner)
	return {
		owner = record.owner,
		ownerName = record.ownerName,
		type = record.type,
		name = def and def.name or record.type,
		price = def and def.price or 0,
		role = HouseService.RoleOf(record, viewer),
		members = members,
		furniture = #record.furniture,
		plot = plot and plot.index,
		position = plot and plot.built and plot.built.outside.Position,
	}
end

function HouseService.Start()
	if not Config.V04 then
		return
	end
	Players.PlayerAdded:Connect(function(p)
		task.spawn(onJoin, p)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(onJoin, p)
	end
	Players.PlayerRemoving:Connect(onLeave)

	Remotes.Handle("House.Mine", function(player)
		local out = { own = nil, others = {} }
		local own = records[player.UserId] or HouseService.Load(player.UserId)
		if own then
			out.own = view(own, player.UserId)
		end
		for ownerId, r in records do
			if ownerId ~= player.UserId and HouseService.RoleOf(r, player.UserId) then
				table.insert(out.others, view(r, player.UserId))
			end
		end
		return Remotes.Ok(out)
	end, { rate = 10 })

	Remotes.Handle("House.Buy", function(player, typeId: any)
		local def = typeof(typeId) == "string" and Houses.ById[typeId] or nil
		if not def then
			return Remotes.Fail("bad_item")
		end
		if not Interaction.IsNear(player, "Shop", 25, "UI", "Makler") then
			return Remotes.Fail("too_far")
		end
		if HouseService.Load(player.UserId) then
			return Remotes.Fail("house_have_one")
		end
		if not Economy.TrySpend(player, def.price, "Haus: " .. def.name) then
			return Remotes.Fail("no_money")
		end
		local record: Record = {
			owner = player.UserId,
			ownerName = player.Name,
			type = def.id,
			plot = nil,
			members = {},
			furniture = {},
			bought = os.time(),
		}
		if not HouseService.Create(record) then
			Economy.Add(player, def.price, "Rückerstattung Haus")
			return Remotes.Fail("house_have_one")
		end
		local plot = spawnHouse(record)
		if plot then
			HouseService.Edit(player.UserId, function(r)
				r.plot = plot.index
			end)
		end
		GameLog.Add("money", player, ("bought house %s for %d €"):format(def.id, def.price))
		return Remotes.Ok({ plot = plot and plot.index })
	end, { rate = 2 })

	Remotes.Handle("House.Sell", function(player)
		local record = HouseService.Load(player.UserId)
		local data = DataService.Get(player)
		if not record or not data then
			return Remotes.Fail("house_none")
		end
		local def = Houses.ById[record.type]
		local refund = math.floor((def and def.price or 0) * Houses.SELL_BACK)
		-- placed furniture goes back into the owner's furniture storage
		data.furniture = data.furniture or {}
		for _, f in record.furniture do
			data.furniture[f.id] = (data.furniture[f.id] or 0) + 1
		end
		for id in record.members do
			task.spawn(setLink, tonumber(id) :: number, player.UserId, false)
		end
		dsRemove(store, "h_" .. player.UserId)
		despawn(player.UserId)
		if refund > 0 then
			Economy.Add(player, refund, "Hausverkauf: " .. (def and def.name or ""))
		end
		GameLog.Add("money", player, ("sold house %s for %d €"):format(record.type, refund))
		return Remotes.Ok({ refund = refund })
	end, { rate = 2 })

	-- owner: co-owner / guest / nobody; co-owners: guests only
	Remotes.Handle("House.SetRole", function(player, ownerId: any, who: any, role: any)
		local oid = Remotes.Check.Int(ownerId, 1, 1e12)
		if not oid or (role ~= nil and role ~= "coowner" and role ~= "guest") then
			return Remotes.Fail("bad_request")
		end
		local target: Player? = nil
		if typeof(who) == "number" then
			target = Players:GetPlayerByUserId(who)
		elseif typeof(who) == "string" then
			local found = Players:FindFirstChild(who)
			target = if found and found:IsA("Player") then found else nil
		end
		local targetId = if target then target.UserId elseif typeof(who) == "number" then who else nil
		if not targetId or targetId == oid then
			return Remotes.Fail("bad_target")
		end
		local current = records[oid] or HouseService.Load(oid)
		if not current then
			return Remotes.Fail("house_none")
		end
		local myRole = HouseService.RoleOf(current, player.UserId)
		local theirRole = HouseService.RoleOf(current, targetId)
		local allowed = myRole == "owner"
			or (myRole == "coowner" and (role == "guest" or role == nil) and theirRole ~= "coowner")
		if not allowed then
			return Remotes.Fail("no_permission")
		end
		local record = HouseService.Edit(oid, function(r)
			if role then
				r.members[tostring(targetId)] = { role = role, name = if target then target.Name else "?" }
			else
				r.members[tostring(targetId)] = nil
			end
		end)
		if not record then
			return Remotes.Fail("error")
		end
		task.spawn(setLink, targetId, oid, role ~= nil)
		local plot = plotOf(oid)
		if plot then
			refreshDoor(plot, record)
		end
		if target then
			Remotes.Push(
				target,
				"Notify",
				{ key = if role then "house_role_" .. role else "house_role_removed", args = { current.ownerName } }
			)
		end
		return Remotes.Ok({ house = view(record, player.UserId) })
	end, { rate = 6 })
end

return HouseService
