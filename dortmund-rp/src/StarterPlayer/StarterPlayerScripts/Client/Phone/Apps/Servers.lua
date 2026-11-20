--!strict
-- v0.4 Servers app: this server's code, "My Server" (private servers: buy, name,
-- public on/off, join), "Public Servers" (list) and "Join via Code".

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Make = require(script.Parent.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.Parent.UI.Notify)
local Net = require(script.Parent.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Parent.Store)
local Phone = require(script.Parent.Parent.Phone)

local New, T = Make.New, Make.Theme

local function card(root: Instance, order: number, title: string): Frame
	local c = Make.Card({ LayoutOrder = order, Parent = root })
	Make.Label(title, 14, T.text, T.bold, { Parent = c })
	return c
end

local function join(code: string)
	task.spawn(function()
		Notify.Show(Store.T("server_joining"))
		local r = Net.Request("Servers.Join", code)
		if not r.ok then
			Notify.Error(r.err)
		end
	end)
end

local function thisServer(root: Instance)
	local c = card(root, 1, "🖥 " .. Store.T("server_this"))
	local label = Make.Label("…", 12, T.sub, T.font, { Parent = c })
	-- the code in a text box, so it can be selected and copied
	local codeBox = Make.TextBox("", { Parent = c, TextSize = 22, Font = T.black, ClearTextOnFocus = false })
	codeBox.TextEditable = false
	task.spawn(function()
		local r = Net.Request("Servers.Info")
		if r.ok then
			label.Text = ("%s\n%s · %d/%d"):format(
				tostring(r.name),
				if r.kind == "private"
					then (if r.public then Store.T("server_private_public") else Store.T("server_private"))
					else Store.T("server_normal"),
				r.players or 0,
				r.max or 0
			)
			codeBox.Text = tostring(r.code)
		end
	end)
end

local function myServers(root: Instance)
	local head = card(root, 2, "⭐ " .. Store.T("server_mine"))
	Make.Label(Store.T("server_buy_info"), 11, T.sub, T.font, { Parent = head })
	Make.Button("🛒 " .. Store.T("server_buy"), Color3.fromRGB(0, 170, 90), function()
		local id = Config.PrivateServerProductId
		if id == 0 then
			Notify.Error("pack_not_setup")
			return
		end
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, id)
	end, { Parent = head })
	local list = New("Frame", {
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	}, { Make.List(6) })
	task.spawn(function()
		local r = Net.Request("Servers.Mine")
		if not r.ok then
			Notify.Error(r.err)
			return
		end
		if r.free then
			Make.Button("👑 " .. Store.T("server_create_free"), T.accent, function()
				local rr = Net.Request("Servers.CreateFree")
				if rr.ok then
					Phone.Replace("servers", "mine")
				else
					Notify.Error(rr.err)
				end
			end, { Parent = head })
		end
		if #(r.servers or {}) == 0 then
			Make.Label(Store.T("server_none"), 12, T.sub, T.font, { Parent = list })
		end
		for i, s in r.servers or {} do
			local c = Make.Card({ LayoutOrder = i, Parent = list })
			Make.Label(("%s\nCode: %s"):format(s.name, s.code), 13, T.text, T.bold, { Parent = c })
			local nameBox = Make.TextBox(Store.T("server_name"), { Parent = c })
			nameBox.Text = s.name
			Make.Row({
				Make.Button("✏️ " .. Store.T("server_rename"), T.panel, function()
					local rr = Net.Request("Servers.Rename", s.id, nameBox.Text)
					if rr.ok then
						Notify.Show(Store.T("done"))
						Phone.Replace("servers", "mine")
					else
						Notify.Error(rr.err)
					end
				end, { Size = UDim2.new(0.5, -3, 1, 0) }),
				Make.Button(
					if s.public then "🌍 " .. Store.T("server_public_on") else "🔒 " .. Store.T("server_public_off"),
					if s.public then T.good else T.panel,
					function()
						local rr = Net.Request("Servers.SetPublic", s.id, not s.public)
						if rr.ok then
							Phone.Replace("servers", "mine")
						else
							Notify.Error(rr.err)
						end
					end,
					{ Size = UDim2.new(0.5, -3, 1, 0) }
				),
			}, 34).Parent =
				c
			Make.Button("▶ " .. Store.T("server_open"), T.accent, function()
				task.spawn(function()
					Notify.Show(Store.T("server_joining"))
					local rr = Net.Request("Servers.Open", s.id)
					if not rr.ok then
						Notify.Error(rr.err)
					end
				end)
			end, { Parent = c })
		end
	end)
end

local function publicServers(root: Instance)
	local head = card(root, 2, "🌍 " .. Store.T("server_public_list"))
	Make.Button("🔄", T.panel, function()
		Phone.Replace("servers", "public")
	end, { Parent = head })
	local list = New("Frame", {
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	}, { Make.List(6) })
	task.spawn(function()
		local r = Net.Request("Servers.List")
		if not r.ok then
			Notify.Error(r.err)
			return
		end
		if #(r.servers or {}) == 0 then
			Make.Label(Store.T("server_none_public"), 12, T.sub, T.font, { Parent = list })
		end
		for i, s in r.servers or {} do
			local c = Make.Card({ LayoutOrder = i, Parent = list })
			Make.Label(
				("%s%s\n%d/%d · %s"):format(
					if s.kind == "private" then "⭐ " else "",
					s.name,
					s.players or 0,
					s.max or 0,
					s.code
				),
				13,
				T.text,
				T.bold,
				{ Parent = c }
			)
			if s.here then
				Make.Label(Store.T("server_here"), 12, T.good, T.bold, { Parent = c })
			else
				Make.Button(Store.T("server_join"), T.good, function()
					join(s.code)
				end, { Parent = c })
			end
		end
	end)
end

local function joinCode(root: Instance)
	local c = card(root, 2, "🔑 " .. Store.T("server_join_code"))
	local box = Make.TextBox("ABCD2345", { Parent = c, TextSize = 22, Font = T.black })
	Make.Button(Store.T("server_join"), T.good, function()
		join(box.Text)
	end, { Parent = c })
end

Phone.Register({
	id = "servers",
	icon = "🖥",
	color = Color3.fromRGB(40, 60, 110),
	order = 12,
	visible = function()
		return Config.V04
	end,
	build = function(container, arg)
		local tab = if typeof(arg) == "string" then arg else "mine"
		local bar = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			Parent = container,
		}, { Make.List(4, true) })
		for i, t in { { "mine", "server_mine" }, { "public", "server_public_list" }, { "code", "server_join_code" } } do
			Make.Button(Store.T(t[2]), if t[1] == tab then Color3.fromRGB(57, 160, 20) else T.card, function()
				Phone.Replace("servers", t[1])
			end, { LayoutOrder = i, Size = UDim2.new(1 / 3, -3, 0, 30), TextSize = 11, Parent = bar })
		end
		local root =
			Make.Scroll({ Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), Parent = container })
		thisServer(root)
		if tab == "public" then
			publicServers(root)
		elseif tab == "code" then
			joinCode(root)
		else
			myServers(root)
		end
		return nil
	end,
})

return nil
