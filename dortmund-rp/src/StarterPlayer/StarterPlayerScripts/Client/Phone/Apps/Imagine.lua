--!strict
-- v0.4 "imagine" online shop app: search, categories, order (standard / express),
-- "Meine Bestellungen" with the time until delivery.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Imagine = require(ReplicatedStorage.Shared.Imagine)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Make = require(script.Parent.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.Parent.UI.Notify)
local Net = require(script.Parent.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Parent.Store)
local Phone = require(script.Parent.Parent.Phone)

local New, T = Make.New, Make.Theme

local ORANGE = Color3.fromRGB(255, 153, 0)
local NAVY = Color3.fromRGB(19, 25, 33)

local query = ""
local category: string? = nil

local function mmss(s: number): string
	return ("%d:%02d"):format(s // 60, s % 60)
end

local function order(key: string, express: boolean)
	task.spawn(function()
		local r = Net.Request("Imagine.Order", key, express)
		if r.ok then
			Notify.Show(Store.T(if express then "imagine_ordered_express" else "imagine_ordered"))
		else
			Notify.Error(r.err)
		end
	end)
end

local function shop(root: Instance)
	local search = Make.TextBox("🔍 " .. Store.T("imagine_search"), { LayoutOrder = 1, Parent = root })
	search.Text = query
	search.FocusLost:Connect(function()
		query = search.Text
		Phone.Replace("imagine", "shop")
	end)
	local cats = New(
		"Frame",
		{ LayoutOrder = 2, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Parent = root },
		{
			Make.List(4, true),
		}
	)
	local all = { "" }
	for _, c in Imagine.Categories do
		table.insert(all, c)
	end
	for i, c in all do
		local active = (category or "") == c
		Make.Button(if c == "" then Store.T("swedea_all") else c, if active then ORANGE else T.card, function()
			category = if c == "" then nil else c
			Phone.Replace("imagine", "shop")
		end, { LayoutOrder = i, Size = UDim2.new(0.25, -3, 1, 0), TextSize = 10, Parent = cats })
	end
	local q = string.lower(query)
	local n = 0
	for _, p in Imagine.List do
		if (not category or p.category == category) and (q == "" or string.find(string.lower(p.name), q, 1, true)) then
			n += 1
			if n > 60 then
				break
			end
			local card = Make.Card({ LayoutOrder = 10 + n, Parent = root })
			New(
				"Frame",
				{ Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = p.color, Parent = card },
				{ Make.Corner(2) }
			)
			Make.Label(p.name, 13, T.text, T.bold, { Parent = card })
			Make.Label(("%s · %s"):format(Locale.Euro(p.price), p.info), 11, T.sub, T.font, { Parent = card })
			Make.Row({
				Make.Button(Store.T("imagine_buy"), ORANGE, function()
					order(p.key, false)
				end, { Size = UDim2.new(0.5, -3, 1, 0), TextSize = 12 }),
				Make.Button(
					"⚡ " .. Store.T("imagine_express", Locale.Euro(Imagine.EXPRESS_FEE)),
					T.accent,
					function()
						order(p.key, true)
					end,
					{ Size = UDim2.new(0.5, -3, 1, 0), TextSize = 11 }
				),
			}, 32).Parent =
				card
		end
	end
	if n == 0 then
		Make.Label(Store.T("imagine_nothing"), 12, T.sub, T.font, { LayoutOrder = 11, Parent = root })
	end
end

local function orders(root: Instance)
	local r = Net.Request("Imagine.Orders")
	if not r.ok then
		Notify.Error(r.err)
		return
	end
	if #(r.orders or {}) == 0 then
		Make.Label(Store.T("imagine_no_orders"), 12, T.sub, T.font, { LayoutOrder = 1, Parent = root })
		return
	end
	local labels = {}
	for i, o in r.orders do
		local card = Make.Card({ LayoutOrder = i, Parent = root })
		Make.Label(("📦 #%d %s"):format(o.n, o.name), 13, T.text, T.bold, { Parent = card })
		local l = Make.Label("", 12, if o.express then ORANGE else T.sub, T.bold, { Parent = card })
		table.insert(labels, { label = l, left = o.left, waiting = o.waiting, express = o.express })
	end
	-- count down while the app is open; when one is due, reload the list a moment
	-- later (the server delivers within a few seconds), so delivered ones disappear
	task.spawn(function()
		local started = os.clock()
		local reloadAt: number? = nil
		while #labels > 0 and labels[1].label.Parent do
			local passed = math.floor(os.clock() - started)
			if reloadAt and os.clock() >= reloadAt then
				Phone.Replace("imagine", "orders")
				return
			end
			for _, e in labels do
				local left = math.max(0, e.left - passed)
				if left == 0 and not e.waiting and not reloadAt then
					reloadAt = os.clock() + 7
				end
				e.label.Text = if e.waiting
					then Store.T("imagine_waiting")
					elseif left > 0 then (if e.express then "⚡ " else "🚚 ") .. Store.T(
						"imagine_eta",
						mmss(left)
					)
					else Store.T("imagine_soon")
			end
			task.wait(1)
		end
	end)
end

Phone.Register({
	id = "imagine",
	icon = "📦",
	color = NAVY,
	order = 11,
	visible = function()
		return Config.V04
	end,
	build = function(container, arg)
		local tab = if arg == "orders" then "orders" else "shop"
		local head = New(
			"Frame",
			{ Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = NAVY, Parent = container },
			{ Make.Corner(8) }
		)
		Make.Label(
			"imagine",
			22,
			Color3.new(1, 1, 1),
			T.black,
			{ Position = UDim2.fromOffset(10, 4), Size = UDim2.new(0.5, 0, 1, -8), Parent = head }
		)
		New("Frame", {
			Position = UDim2.new(0, 12, 1, -9),
			Size = UDim2.fromOffset(70, 3),
			BackgroundColor3 = ORANGE,
			Parent = head,
		}, { Make.Corner(2) })
		local tabs = New("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.new(0.5, 0, 0, 28),
			BackgroundTransparency = 1,
			Parent = head,
		}, { Make.List(4, true) })
		for i, t in { { "shop", "imagine_shop" }, { "orders", "imagine_orders" } } do
			Make.Button(Store.T(t[2]), if t[1] == tab then ORANGE else T.card, function()
				Phone.Replace("imagine", t[1])
			end, { LayoutOrder = i, Size = UDim2.new(0.5, -2, 1, 0), TextSize = 11, Parent = tabs })
		end
		local root =
			Make.Scroll({ Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46), Parent = container })
		if tab == "orders" then
			task.spawn(orders, root)
		else
			shop(root)
		end
		return nil
	end,
})

return nil
