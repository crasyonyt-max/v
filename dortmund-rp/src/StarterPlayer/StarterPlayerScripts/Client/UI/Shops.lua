--!strict
-- Shop windows opened by the server when a player uses a ProximityPrompt:
-- Handyland, Autohaus (dealer + gamepass packs + sell), job vehicle garages.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Furniture = require(ReplicatedStorage.Shared.Furniture)
local Houses = require(ReplicatedStorage.Shared.Houses)
local Laptops = require(ReplicatedStorage.Shared.Laptops)
local Items = require(ReplicatedStorage.Shared.Items)
local Jobs = require(ReplicatedStorage.Shared.Jobs)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Phones = require(ReplicatedStorage.Shared.Phones)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local BuildMode = require(script.Parent.BuildMode)
local Make = require(script.Parent.Make)
local Notify = require(script.Parent.Notify)
local Net = require(script.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme

local Shops = {}

local gui = New("ScreenGui", {
	Name = "Shops",
	ResetOnSpawn = false,
	DisplayOrder = 30,
	Enabled = false,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})

local window = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.94, 0.9),
	BackgroundColor3 = T.bg,
	Parent = gui,
}, { Make.Corner(16), New("UISizeConstraint", { MaxSize = Vector2.new(720, 640) }), Make.Stroke(T.card, 2) })

local title = Make.Label(
	"",
	20,
	T.text,
	T.black,
	{ Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -80, 0, 30), Parent = window }
)
Make.Button("X", T.card, function()
	Shops.Close()
end, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(36, 36),
	TextSize = 18,
	Parent = window,
})

local tabBar = New("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 50),
	Size = UDim2.new(1, -24, 0, 34),
	Parent = window,
}, { Make.List(6, true) })
local body = Make.Scroll({ Position = UDim2.fromOffset(12, 90), Size = UDim2.new(1, -24, 1, -100), Parent = window })

local currentUI: string? = nil
local currentArg: any = nil
local currentTab = 1
local renderers: { [string]: (any) -> () } = {}

local function result(r: { [string]: any })
	if r.ok then
		Notify.Show(Store.T("done"))
	else
		Notify.Error(r.err)
	end
end

local function tabs(names: { string })
	Make.Clear(tabBar)
	for i, key in names do
		Make.Button(Store.T(key), if i == currentTab then T.accent else T.card, function()
			currentTab = i
			Shops.Refresh()
		end, { Size = UDim2.fromOffset(120, 32), LayoutOrder = i, Parent = tabBar })
	end
end

-- Two-column grid inside the scroll body
local function grid(): Frame
	local g = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = body,
	})
	New("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, 150),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = g,
	})
	return g
end

local function itemCard(
	parent: Instance,
	order: number,
	color: Color3,
	name: string,
	line: string,
	buttonText: string,
	buttonColor: Color3,
	onClick: (() -> ())?
)
	local card = New(
		"Frame",
		{ BackgroundColor3 = T.card, LayoutOrder = order, Parent = parent },
		{ Make.Corner(12), Make.Padding(10), Make.List(4) }
	)
	New("Frame", { Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = color, Parent = card }, { Make.Corner(4) })
	Make.Label(name, 14, T.text, T.bold, { Size = UDim2.new(1, 0, 0, 36), Parent = card })
	Make.Label(line, 12, T.sub, T.font, { Size = UDim2.new(1, 0, 0, 34), Parent = card })
	local b = Make.Button(
		buttonText,
		buttonColor,
		onClick or function() end,
		{ Size = UDim2.new(1, 0, 0, 34), Parent = card }
	)
	b.AutoButtonColor = onClick ~= nil
end

-- Handyland --------------------------------------------------------------------
renderers.Handyland = function()
	title.Text = "📱 " .. Store.T("handyland")
	local s = Store.Get()
	-- v0.4: second tab with laptops
	if Config.V04 then
		tabs({ "handyland_phones", "handyland_laptops" })
	else
		Make.Clear(tabBar)
	end
	if Config.V04 and currentTab == 2 then
		local lg = grid()
		for i, l in Laptops.List do
			local owned = table.find(s.laptops or {}, l.id) ~= nil
			local line = Locale.Euro(l.price) .. "\n" .. l.info
			if s.laptop == l.id then
				itemCard(lg, i, l.body, l.name, line, Store.T("equipped"), T.panel, nil)
			elseif owned then
				itemCard(lg, i, l.body, l.name, line, Store.T("equip"), T.accent, function()
					result(Net.Request("Laptop.Equip", l.id))
				end)
			else
				itemCard(lg, i, l.body, l.name, line, Store.T("buy"), T.good, function()
					result(Net.Request("Laptop.Buy", l.id))
				end)
			end
		end
		return
	end
	local g = grid()
	for i, phone in Phones.List do
		if phone.shop then
			local owned = table.find(s.phones or {}, phone.id) ~= nil
			local inUse = s.phone == phone.id
			local line = (if phone.price == 0 then Store.T("free") else Locale.Euro(phone.price))
				.. "\n"
				.. Store.T("camera_quality", phone.camera)
			if inUse then
				itemCard(g, i, phone.accent, phone.name, line, Store.T("equipped"), T.panel, nil)
			elseif owned then
				itemCard(g, i, phone.accent, phone.name, line, Store.T("equip"), T.accent, function()
					result(Net.Request("Phone.Equip", phone.id))
				end)
			else
				itemCard(g, i, phone.accent, phone.name, line, Store.T("buy"), T.good, function()
					result(Net.Request("Phone.Buy", phone.id))
				end)
			end
		end
	end
end

-- Autohaus -----------------------------------------------------------------------
local function ownsAny(state: { [string]: any }, vehicleId: string): boolean
	for _, entry in state.vehicles or {} do
		if entry.id == vehicleId then
			return true
		end
	end
	return false
end

renderers.Dealership = function()
	title.Text = "🚗 " .. Store.T("dealership")
	tabs({ "dealer_tab", "packs_tab", "sell_tab" })
	local s = Store.Get()
	if not s.carStarterChosen then
		Make.Label(Store.T("starter_needed"), 13, T.warn, T.bold, { Parent = body })
	end
	if currentTab == 1 then
		local g = grid()
		for i, v in Vehicles.ByCategory("Dealer") do
			local line = Locale.Euro(v.price)
				.. "\n"
				.. Vehicles.Stats(v)
				.. (if ownsAny(s, v.id) then "\n" .. Store.T("owned") else "")
			itemCard(g, i, v.color, v.name, line, Store.T("buy"), T.good, function()
				result(Net.Request("Vehicle.Buy", v.id))
			end)
		end
	elseif currentTab == 2 then
		for p, packId in Vehicles.PackOrder do
			local unlocked = (s.packs or {})[packId] == true
			local header = Make.Card({ LayoutOrder = p * 2, Parent = body })
			Make.Label(
				packId .. "  ·  " .. (Config.GamepassRobux :: any)[packId] .. " R$",
				16,
				T.text,
				T.black,
				{ Parent = header }
			)
			if not unlocked then
				local passId = (Config.Gamepasses :: any)[packId]
				Make.Button(
					Store.T("unlock_pack", (Config.GamepassRobux :: any)[packId]),
					Color3.fromRGB(0, 170, 90),
					function()
						if passId and passId ~= 0 then
							MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, passId)
						else
							Notify.Error("pack_not_setup")
						end
					end,
					{ Parent = header }
				)
			end
			local g = grid()
			g.LayoutOrder = p * 2 + 1
			for i, v in Vehicles.ByCategory("Pack", packId) do
				local line = Locale.Euro(v.price) .. "\n" .. Vehicles.Stats(v)
				if unlocked then
					itemCard(g, i, v.color, v.name, line, Store.T("buy"), T.good, function()
						result(Net.Request("Vehicle.Buy", v.id))
					end)
				else
					itemCard(g, i, v.color, v.name, line, "🔒", T.panel, nil)
				end
			end
		end
	else
		local g = grid()
		local i = 0
		for uid, entry in s.vehicles or {} do
			local v = Vehicles.ById[entry.id]
			if v and v.category ~= "Starter" and v.category ~= "CarStarter" then
				i += 1
				itemCard(
					g,
					i,
					v.color,
					v.name,
					entry.plate .. "\n" .. Locale.Euro(math.floor(v.price * 0.5)),
					Store.T("sell"),
					T.bad,
					function()
						result(Net.Request("Vehicle.Sell", uid))
					end
				)
			end
		end
	end
end

-- Job garage ---------------------------------------------------------------------
renderers.JobGarage = function(jobId: any)
	local job = Jobs.ById[jobId] or Jobs.ById.Police
	title.Text = "🚨 " .. Store.T("job_garage") .. " – " .. Jobs.Name(job.id, Store.Lang())
	Make.Clear(tabBar)
	local s = Store.Get()
	if s.job ~= job.id then
		Make.Label(Store.T("wrong_job") .. " " .. Store.T("start_at_station"), 13, T.warn, T.bold, { Parent = body })
	end
	local xp = (s.jobXP or {})[job.id] or 0
	local g = grid()
	for i, v in Vehicles.ForJob(job.id) do
		local need = v.xp or 0
		if xp >= need or Store.Rank() >= 3 then
			itemCard(
				g,
				i,
				v.color,
				v.name,
				if need == 0 then "🏍️" else Store.T("requires_xp", need),
				Store.T("spawn"),
				T.good,
				function()
					local r = Net.Request("Vehicle.SpawnJob", v.id)
					if r.ok or r.err == "plate_required" then -- (plate pop-up is open)
						Shops.Close()
					else
						Notify.Error(r.err)
					end
				end
			)
		else
			itemCard(
				g,
				i,
				v.color,
				v.name,
				Store.T("requires_xp", need) .. "\n" .. Store.T("job_xp", xp),
				"🔒",
				T.panel,
				nil
			)
		end
	end
end

-- ADMC Kennzeichen-Service: change the plate of any of your vehicles (city DO) ------
local function plateEditor(parent: Instance, order: number, label: string, current: string?, apply: (string) -> ())
	local card = Make.Card({ LayoutOrder = order, Parent = parent })
	Make.Label(label, 14, T.text, T.bold, { Parent = card })
	Make.Label(current or "–", 12, T.sub, T.font, { Parent = card })
	local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = card })
	Make.Label("DO-", 18, T.text, T.black, { Size = UDim2.fromOffset(44, 36), Parent = row })
	local input = Make.TextBox("AB 123", {
		Text = string.match(current or "", "^DO%-(.+)$") or "",
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.new(1, -46, 1, 0),
		Parent = row,
	})
	Make.Button(Store.T("change_plate"), T.accent, function()
		apply("DO-" .. input.Text)
	end, { Parent = card })
end

renderers.Plates = function()
	title.Text = "🔢 " .. Store.T("plate_service")
	Make.Clear(tabBar)
	local s = Store.Get()
	plateEditor(body, 1, "👤 " .. Store.T("plate_personal_title"), s.personalPlate, function(text)
		result(Net.Request("Vehicle.SetPersonalPlate", text))
	end)
	local uids = {}
	for uid in s.vehicles or {} do
		table.insert(uids, uid)
	end
	table.sort(uids)
	for i, uid in uids do
		local entry = s.vehicles[uid]
		local v = Vehicles.ById[entry.id]
		plateEditor(
			body,
			1 + i,
			(if v and v.car then "🚗 " else "🏍️ ") .. (if v then v.name else entry.id),
			entry.plate,
			function(text)
				result(Net.Request("Vehicle.SetPlate", uid, text))
			end
		)
	end
end

renderers.Store = function(kind: any)
	local store = Items.Stores[kind]
	if not store then
		return
	end
	title.Text = "🛒 " .. store.title
	Make.Clear(tabBar)
	Make.Label(Store.T("store_hint"), 12, T.sub, T.font, { Parent = body })
	local g = grid()
	for i, id in store.items do
		local it = Items.ById[id]
		local price = Items.Price(kind, id) or it.price
		local line = Locale.Euro(price)
			.. "\n"
			.. (if it.hunger > 0 then "🍔 +" .. it.hunger .. "  " else "")
			.. (if it.thirst > 0 then "💧 +" .. it.thirst else "")
		itemCard(g, i, it.color, it.name, line, Store.T("buy"), T.good, function()
			local r = Net.Request("Store.Buy", kind, id)
			if r.ok then
				Notify.Show("🛍️ " .. it.name, false, 2)
			else
				Notify.Error(r.err)
			end
		end)
	end
end

renderers.Elevator = function(current: any)
	title.Text = "🛗 " .. Store.T("elevator")
	Make.Clear(tabBar)
	local g = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = body,
	})
	New("UIGridLayout", {
		CellSize = UDim2.new(0.25, -6, 0, 54),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = g,
	})
	local mine = Players.LocalPlayer:GetAttribute("Apartment")
	local myFloor = if typeof(mine) == "number" then math.ceil(mine / 2) else nil
	for f = 16, 0, -1 do
		local label = if f == 0 then Store.T("lobby") else Store.T("floor", f)
		if f == myFloor then
			label ..= " 🏠"
		end
		Make.Button(label, if f == current then T.panel else (if f == myFloor then T.good else T.accent), function()
			if f == current then
				return
			end
			local r = Net.Request("Tower.Go", f)
			if r.ok then
				Shops.Close()
			else
				Notify.Error(r.err)
			end
		end, { LayoutOrder = 16 - f, Parent = g })
	end
end

renderers.Housing = function()
	title.Text = "🏠 Ferdinandstraße 24"
	Make.Clear(tabBar)
	Make.Label(Store.T("housing_soon"), 15, T.text, T.bold, { Parent = body })
end

-- v0.4 Immobilienmakler: buy a house (one per player) ----------------------------
renderers.Makler = function()
	title.Text = "🏡 Immobilienmakler"
	Make.Clear(tabBar)
	Make.Label(Store.T("house_makler_info"), 12, T.sub, T.font, { Parent = body })
	local g = grid()
	for i, h in Houses.List do
		itemCard(g, i, h.wall, h.name, Locale.Euro(h.price) .. "\n" .. h.info, Store.T("buy"), T.good, function()
			result(Net.Request("House.Buy", h.id))
		end)
	end
end

-- v0.4 "Haus verwalten" (mailbox of the house): furnish, people, sell ---------------
local function roleName(role: any): string
	return Store.T("house_role_name_" .. tostring(role))
end

renderers.HouseManage = function(ownerId: any)
	Make.Clear(tabBar)
	title.Text = "🏡 " .. Store.T("house_manage")
	task.spawn(function()
		local r = Net.Request("House.Mine")
		if not r.ok then
			Notify.Error(r.err)
			return
		end
		local h = nil
		if r.own and r.own.owner == ownerId then
			h = r.own
		end
		for _, o in r.others or {} do
			if o.owner == ownerId then
				h = o
			end
		end
		if not h then
			Notify.Error("no_permission")
			return
		end
		title.Text = ("🏡 %s · %s"):format(h.name, h.ownerName)
		local head = Make.Card({ LayoutOrder = 1, Parent = body })
		Make.Label(
			("%s · %s"):format(roleName(h.role), Store.T("house_plot", h.plot or "?", h.furniture or 0)),
			13,
			T.text,
			T.bold,
			{
				Parent = head,
			}
		)
		Make.Button("🛠 " .. Store.T("house_furnish"), T.good, function()
			Shops.Close()
			BuildMode.Start(h.owner)
		end, { Parent = head })

		-- people: the owner sets co-owners + guests, co-owners set guests
		local people = Make.Card({ LayoutOrder = 2, Parent = body })
		Make.Label("👥 " .. Store.T("house_people"), 14, T.text, T.bold, { Parent = people })
		for _, m in h.members or {} do
			local canRemove = h.role == "owner" or (h.role == "coowner" and m.role == "guest")
			Make.Row({
				Make.Label(
					("%s · %s"):format(m.name, roleName(m.role)),
					12,
					T.text,
					T.font,
					{ Size = UDim2.new(0.62, 0, 1, 0) }
				),
				Make.Button(Store.T("house_remove"), if canRemove then T.bad else T.panel, function()
					if canRemove then
						result(Net.Request("House.SetRole", h.owner, m.userId, nil))
						Shops.Refresh()
					end
				end, { Size = UDim2.new(0.38, -4, 1, 0), TextSize = 11 }),
			}, 30).Parent =
				people
		end
		local selected: Player? = nil
		local pick: TextButton
		pick = Make.Button("👤 " .. Store.T("recipient"), T.panel, function()
			local list = {}
			for _, p in Players:GetPlayers() do
				if p ~= Players.LocalPlayer and p.UserId ~= h.owner then
					table.insert(list, p)
				end
			end
			if #list == 0 then
				Notify.Error("target_offline")
				return
			end
			local i = if selected then (table.find(list, selected) or 0) else 0
			selected = list[i % #list + 1]
			pick.Text = "👤 " .. (selected :: Player).DisplayName
		end, { Parent = people })
		local function give(role: string)
			if not selected then
				Notify.Error("bad_target")
				return
			end
			result(Net.Request("House.SetRole", h.owner, (selected :: Player).UserId, role))
			Shops.Refresh()
		end
		local row = {}
		if h.role == "owner" then
			table.insert(
				row,
				Make.Button("⭐ " .. roleName("coowner"), T.good, function()
					give("coowner")
				end, { Size = UDim2.new(0.5, -3, 1, 0), TextSize = 12 })
			)
		end
		table.insert(
			row,
			Make.Button("🚪 " .. roleName("guest"), T.accent, function()
				give("guest")
			end, { Size = UDim2.new(if h.role == "owner" then 0.5 else 1, -3, 1, 0), TextSize = 12 })
		)
		Make.Row(row, 34).Parent = people

		if h.role == "owner" then
			local sell = Make.Card({ LayoutOrder = 3, Parent = body })
			Make.Label(
				Store.T("house_sell_info", Locale.Euro(math.floor((h.price or 0) * Houses.SELL_BACK))),
				12,
				T.sub,
				T.font,
				{
					Parent = sell,
				}
			)
			local armed = false
			local b: TextButton
			b = Make.Button("💰 " .. Store.T("house_sell"), T.bad, function()
				if not armed then
					armed = true
					b.Text = "⚠️ " .. Store.T("house_sell_confirm")
					return
				end
				local rr = Net.Request("House.Sell")
				if rr.ok then
					Notify.Show(Store.T("house_sold", Locale.Euro(rr.refund or 0)))
					Shops.Close()
				else
					Notify.Error(rr.err)
				end
			end, { Parent = sell })
		end
	end)
end

-- v0.4 Swedea: furniture (into your storage) + the free bed ----------------------
renderers.Swedea = function()
	title.Text = "🛋 SWEDEA"
	local cats = { "swedea_all" }
	for _, c in Furniture.Categories do
		table.insert(cats, c)
	end
	Make.Clear(tabBar)
	for i, key in cats do
		Make.Button(if i == 1 then Store.T(key) else key, if i == currentTab then T.accent else T.card, function()
			currentTab = i
			Shops.Refresh()
		end, { Size = UDim2.fromOffset(96, 32), LayoutOrder = i, TextSize = 11, Parent = tabBar })
	end
	local cat = if currentTab > 1 then cats[currentTab] else nil
	task.spawn(function()
		local r = Net.Request("Furniture.Storage")
		local owned = if r.ok then r.items or {} else {}
		if r.ok and r.freeBed then
			local free = Make.Card({ LayoutOrder = 0, Parent = body })
			Make.Label("🎁 " .. Store.T("swedea_free_bed"), 14, T.text, T.bold, { Parent = free })
			Make.Button(Store.T("swedea_take"), T.good, function()
				result(Net.Request("Swedea.FreeBed"))
				Shops.Refresh()
			end, { Parent = free })
		end
		Make.Label(Store.T("swedea_info"), 12, T.sub, T.font, { LayoutOrder = 1, Parent = body })
		local g = grid()
		g.LayoutOrder = 2
		local n = 0
		for _, it in Furniture.List do
			if not cat or it.category == cat then
				n += 1
				itemCard(
					g,
					n,
					it.color,
					it.name .. " · " .. it.kind,
					Locale.Euro(it.price)
						.. (if (owned[it.id] or 0) > 0 then "\n" .. Store.T("swedea_have", owned[it.id]) else ""),
					Store.T("buy"),
					T.good,
					function()
						result(Net.Request("Swedea.Buy", it.id, 1))
						Shops.Refresh()
					end
				)
			end
		end
	end)
end

-- V1.0 black market: a pistol for civilians -------------------------------------------
renderers.Blackmarket = function()
	title.Text = "🕶 ???"
	Make.Clear(tabBar)
	Make.Label(Store.T("blackmarket_info"), 12, T.sub, T.font, { Parent = body })
	local g = grid()
	local owned = Store.Get().weapon == "pistol" or Players.LocalPlayer:GetAttribute("Weapon") == "pistol"
	itemCard(
		g,
		1,
		Color3.fromRGB(30, 30, 34),
		Store.T("blackmarket_pistol"),
		Locale.Euro(Config.BlackMarketPistol),
		if owned then Store.T("owned") else Store.T("buy"),
		if owned then T.panel else T.bad,
		if owned
			then nil
			else function()
				result(Net.Request("Weapon.Buy"))
			end
	)
end

function Shops.Refresh()
	if not currentUI then
		return
	end
	Make.Clear(body)
	local fn = renderers[currentUI]
	if fn then
		fn(currentArg)
	end
end

function Shops.Open(ui: string, arg: any)
	if not renderers[ui] then
		return
	end
	if currentUI ~= ui then
		currentTab = 1
	end
	currentUI = ui
	currentArg = arg
	gui.Enabled = true
	Shops.Refresh()
end

function Shops.Close()
	currentUI = nil
	gui.Enabled = false
end

Net.On("OpenUI", function(payload)
	if typeof(payload) == "table" and typeof(payload.ui) == "string" then
		Shops.Open(payload.ui, payload.arg)
	end
end)

Store.Changed:Connect(function()
	if gui.Enabled then
		Shops.Refresh()
	end
end)

-- Close when walking away.
task.spawn(function()
	local openedAt: Vector3? = nil
	while true do
		task.wait(0.5)
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if gui.Enabled and root then
			openedAt = openedAt or root.Position
			if (root.Position - (openedAt :: Vector3)).Magnitude > 30 then
				Shops.Close()
			end
		else
			openedAt = nil
		end
	end
end)

return Shops
