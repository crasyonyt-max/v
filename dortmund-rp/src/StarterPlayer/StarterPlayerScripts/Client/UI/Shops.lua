--!strict
-- Shop windows opened by the server when a player uses a ProximityPrompt:
-- Handyland, Autohaus (dealer + gamepass packs + sell), job vehicle garages.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local Jobs = require(ReplicatedStorage.Shared.Jobs)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Phones = require(ReplicatedStorage.Shared.Phones)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
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
	Make.Clear(tabBar)
	local s = Store.Get()
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
			local line = Locale.Euro(v.price) .. (if ownsAny(s, v.id) then "\n" .. Store.T("owned") else "")
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
				local line = Locale.Euro(v.price)
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
