--!strict
-- Admin app (Server Admins + Game Admins). The server checks every action again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Items = require(ReplicatedStorage.Shared.Items)
local Jobs = require(ReplicatedStorage.Shared.Jobs)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Phones = require(ReplicatedStorage.Shared.Phones)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local Make = require(script.Parent.Parent.Parent.UI.Make)
local MapPicker = require(script.Parent.Parent.Parent.UI.MapPicker)
local Notify = require(script.Parent.Parent.Parent.UI.Notify)
local Net = require(script.Parent.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Parent.Store)
local Phone = require(script.Parent.Parent.Phone)
local News = require(script.Parent.News) :: any

local New, T = Make.New, Make.Theme

local CO_OWNER = 4
local GAME_ADMIN = 3
local SERVER_OWNER = 2

local Admin = {}

local function act(action: string, args: { [string]: any }?): { [string]: any }
	local r = Net.Request("Admin.Do", action, args or {})
	if r.ok then
		Notify.Show(Store.T("done"))
	else
		Notify.Error(r.err)
	end
	return r
end

-- Spectate support (camera only, client side)
local spectating = false
function Admin.Spectate(userId: number?)
	local camera = Workspace.CurrentCamera
	local target = userId and Players:GetPlayerByUserId(userId)
	local hum = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		camera.CameraSubject = hum
		spectating = true
	else
		local mine = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if mine then
			camera.CameraSubject = mine
		end
		spectating = false
	end
end

local function section(root: Instance, order: number, title: string): Frame
	local card = Make.Card({ LayoutOrder = order, Parent = root })
	Make.Label(title, 14, T.text, T.bold, { Parent = card })
	return card
end

local function half(text: string, color: Color3, fn: () -> ()): TextButton
	return Make.Button(text, color, fn, { Size = UDim2.new(0.5, -3, 1, 0) })
end

-- Tabs -------------------------------------------------------------------------
local function playerDetail(root: ScrollingFrame, info: { [string]: any }, back: () -> ())
	Make.Clear(root)
	local isGA = Store.Rank() >= GAME_ADMIN
	Make.Button("‹ " .. Store.T("admin_players"), T.panel, back, { LayoutOrder = 0, Parent = root })
	local head = section(root, 1, string.format("%s (@%s)", info.display, info.name))
	Make.Label(
		string.format(
			"ID %d · %s%s",
			info.userId,
			Jobs.Name(info.job, Store.Lang()),
			if info.bank then " · " .. Locale.Euro(info.bank) else ""
		),
		12,
		T.sub,
		T.font,
		{ Parent = head }
	)

	local id = info.userId
	local moves = section(root, 2, "🧭")
	Make.Row({
		half("TP →", T.accent, function()
			act("tp_to", { userId = id })
		end),
		half("← Bring", T.accent, function()
			act("bring", { userId = id })
		end),
	}).Parent =
		moves
	Make.Row({
		half("👁 Spectate", T.panel, function()
			local r = act("spectate", { userId = id })
			if r.ok then
				Admin.Spectate(id)
			end
		end),
		half("👁 Stop", T.panel, function()
			Admin.Spectate(nil)
		end),
	}).Parent =
		moves
	Make.Row({
		half("🧊 Freeze", T.panel, function()
			act("freeze", { userId = id })
		end),
		half("🛡 God", T.panel, function()
			act("god", { userId = id })
		end),
	}).Parent =
		moves
	if Store.Rank() >= SERVER_OWNER then
		Make.Button(if info.appointed then "Server-Admin entfernen" else "Zum Server-Admin machen", T.panel, function()
			act("appoint", { userId = id })
		end, { Parent = moves })
	end

	local mod = section(root, 3, "⚖️")
	local reason = Make.TextBox(Store.T("reason"), { Parent = mod })
	local minutes = Make.TextBox(Store.T("minutes"), { Parent = mod })
	Make.Row({
		half("Kick", T.warn, function()
			act("kick", { userId = id, reason = reason.Text })
		end),
		half(if isGA then "Ban (global)" else "Ban (Server)", T.bad, function()
			act("ban", { userId = id, reason = reason.Text, minutes = math.floor(tonumber(minutes.Text) or 0) })
		end),
	}).Parent =
		mod

	if isGA then
		local give = section(root, 4, "🎁 Game Admin")
		local amount = Make.TextBox(Store.T("amount"), { Parent = give })
		local jobIndex = 1
		local jobBtn: TextButton
		jobBtn = Make.Button("XP: " .. Jobs.List[1].id, T.panel, function()
			jobIndex = jobIndex % #Jobs.List + 1
			jobBtn.Text = "XP: " .. Jobs.List[jobIndex].id
		end, { Parent = give })
		Make.Row({
			half("€ geben", T.good, function()
				act("give_money", { userId = id, amount = math.floor(tonumber(amount.Text) or 0) })
			end),
			half("XP geben", T.good, function()
				local job = Jobs.List[jobIndex].id
				act("give_xp", {
					userId = id,
					amount = math.floor(tonumber(amount.Text) or 0),
					job = if job == "Unemployed" then nil else job,
				})
			end),
		}).Parent =
			give
	end
end

local function playersTab(root: ScrollingFrame)
	local function list()
		Make.Clear(root)
		local r = Net.Request("Admin.Players")
		if not r.ok then
			Notify.Error(r.err)
			return
		end
		for i, info in r.players do
			local badge = if info.rank >= 5
				then " 👑"
				elseif info.rank >= 4 then " 💠"
				elseif info.rank >= GAME_ADMIN then " 🛡️"
				elseif info.rank >= 1 then " ⭐"
				else ""
			Make.CardButton({ LayoutOrder = i, Parent = root }, {
				Make.Label(info.display .. badge, 14, T.text, T.bold),
				Make.Label("@" .. info.name .. " · " .. Jobs.Name(info.job, Store.Lang()), 12, T.sub, T.font),
			}, function()
				playerDetail(root, info, list)
			end)
		end
	end
	list()
end

local function selfTab(root: ScrollingFrame)
	local card = section(root, 1, Store.T("admin_self"))
	Make.Row({
		half("🕊 Fly (F)", T.accent, function()
			act("fly")
		end),
		half("👻 Noclip", T.accent, function()
			act("noclip")
		end),
	}).Parent =
		card
	Make.Button("🛡 God", T.panel, function()
		act("god", { userId = Players.LocalPlayer.UserId })
	end, { Parent = card })
	if spectating then
		Make.Button("👁 Stop spectating", T.panel, function()
			Admin.Spectate(nil)
		end, { Parent = card })
	end
end

local function number(text: string): number?
	return tonumber((string.gsub(text, ",", ".")))
end

-- Votes on this server: question, 2-4 answers, time limit
local function voteSection(root: ScrollingFrame, order: number)
	local card = section(root, order, "🗳️ " .. Store.T("vote"))
	local question = Make.TextBox(Store.T("vote_question"), { Parent = card })
	local answers = {}
	for i = 1, 4 do
		answers[i] = Make.TextBox(Store.T("vote_answer", i), { Parent = card })
	end
	local minutes = Make.TextBox(Store.T("duration_min") .. " (5)", { Parent = card })
	Make.Row({
		half(Store.T("vote_start"), T.good, function()
			local options = {}
			for i = 1, 4 do
				table.insert(options, answers[i].Text)
			end
			act("vote_start", {
				question = question.Text,
				options = options,
				minutes = math.floor(number(minutes.Text) or 5),
			})
		end),
		half(Store.T("vote_end"), T.bad, function()
			act("vote_end")
		end),
	}).Parent =
		card
end

local function serverTab(root: ScrollingFrame)
	voteSection(root, 20)
	local isGA = Store.Rank() >= GAME_ADMIN
	local ann = section(root, 1, "📢")
	local text = Make.TextBox(Store.T("announce_text"), { Parent = ann })
	if isGA then
		Make.Row({
			half(Store.T("this_server"), T.accent, function()
				act("announce", { text = text.Text })
			end),
			half(Store.T("global"), T.warn, function()
				act("announce", { text = text.Text, global = true })
			end),
		}).Parent =
			ann
	else
		Make.Button(Store.T("send"), T.accent, function()
			act("announce", { text = text.Text })
		end, { Parent = ann })
	end

	local world = section(root, 2, "🌦")
	Make.Row({
		Make.Button("06:00", T.panel, function()
			act("time", { hour = 6 })
		end, { Size = UDim2.new(0.25, -5, 1, 0) }),
		Make.Button("12:00", T.panel, function()
			act("time", { hour = 12 })
		end, { Size = UDim2.new(0.25, -5, 1, 0) }),
		Make.Button("18:00", T.panel, function()
			act("time", { hour = 18 })
		end, { Size = UDim2.new(0.25, -5, 1, 0) }),
		Make.Button("00:00", T.panel, function()
			act("time", { hour = 0 })
		end, { Size = UDim2.new(0.25, -5, 1, 0) }),
	}).Parent =
		world
	Make.Row({
		Make.Button("☀️", T.panel, function()
			act("weather", { kind = "Clear" })
		end, { Size = UDim2.new(0.25, -5, 1, 0) }),
		Make.Button("☁️", T.panel, function()
			act("weather", { kind = "Cloudy" })
		end, { Size = UDim2.new(0.25, -5, 1, 0) }),
		Make.Button("🌧", T.panel, function()
			act("weather", { kind = "Rain" })
		end, { Size = UDim2.new(0.25, -5, 1, 0) }),
		Make.Button("🌫", T.panel, function()
			act("weather", { kind = "Fog" })
		end, { Size = UDim2.new(0.25, -5, 1, 0) }),
	}).Parent =
		world

	local bans = section(root, 3, "⛔ Ban / Unban")
	local name = Make.TextBox(Store.T("username"), { Parent = bans })
	local reason = Make.TextBox(Store.T("reason"), { Parent = bans })
	local minutes = Make.TextBox(Store.T("minutes"), { Parent = bans })
	Make.Row({
		half("Ban", T.bad, function()
			act("ban", { name = name.Text, reason = reason.Text, minutes = math.floor(tonumber(minutes.Text) or 0) })
		end),
		half("Unban", T.good, function()
			act("unban", { name = name.Text })
		end),
	}).Parent =
		bans

	local power = section(root, 4, "⏻ " .. Store.T("shutdown"))
	Make.Button(Store.T("this_server"), T.bad, function()
		act("shutdown")
	end, { Parent = power })
	if isGA then
		Make.Button(Store.T("global"), T.bad, function()
			act("shutdown", { global = true })
		end, { Parent = power })
	end
end

local function vehiclesTab(root: ScrollingFrame)
	local isGA = Store.Rank() >= GAME_ADMIN
	local order = 0
	for _, category in { "Admin", "Starter", "Job" } do
		order += 1
		local card = section(root, order, category)
		for _, v in Vehicles.ByCategory(category) do
			if not (v.adminLevel == "Game" and not isGA) then
				Make.Button(v.name, if v.category == "Admin" then T.accent else T.panel, function()
					local r = act("spawn_vehicle", { vehicleId = v.id })
					if r.ok then
						Phone.Close()
					end
				end, { Size = UDim2.new(1, 0, 0, 30), TextSize = 12, Parent = card })
			end
		end
	end
end

-- News app posts (Game Admins): write a new one, delete old ones
local function newsTab(root: ScrollingFrame)
	local form = section(root, 1, "📰 " .. Store.T("news_new"))
	local title = Make.TextBox(Store.T("news_title"), { Parent = form })
	local text = Make.TextBox(Store.T("news_text"), {
		Size = UDim2.new(1, 0, 0, 96),
		MultiLine = true,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = form,
	})
	Make.Button(Store.T("news_post"), T.good, function()
		local r = act("news_post", { title = title.Text, text = text.Text })
		if r.ok then
			Phone.Replace("admin", "admin_news")
		end
	end, { Parent = form })
	local list = Make.Card({ LayoutOrder = 2, BackgroundTransparency = 1, Parent = root })
	local function show()
		Make.Clear(list)
		News.RenderPosts(list, function(id: string)
			local r = act("news_delete", { id = id })
			if r.ok then
				Phone.Replace("admin", "admin_news")
			end
		end, 0)
	end
	task.spawn(function()
		News.Load()
		if list.Parent then
			show()
		end
	end)
end

-- AA (Owner + Co-Owners): boosts, gifts and pickups on every server ----------------------
local REWARD_KINDS = { "cash", "xp", "item", "phone" }
local REWARD_ICON = { cash = "💶", xp = "⭐", item = "🍕", phone = "📱" }
local itemChoices = {}
for _, it in Items.List do
	table.insert(itemChoices, { id = it.id, name = it.name })
end
local phoneChoices = {}
for _, ph in Phones.List do
	if ph.shop and not ph.adminOnly then
		table.insert(phoneChoices, { id = ph.id, name = ph.name })
	end
end

-- A reward chooser (kind + amount / item / phone). Returns a getter.
local function rewardPicker(parent: Instance): () -> (string, any)
	local kindIndex, itemIndex, phoneIndex = 1, 1, 1
	local holder = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, { Make.List(6) })
	local amount = Make.TextBox(Store.T("amount"), { LayoutOrder = 2, Parent = holder })
	local choice: TextButton
	local kindButton: TextButton
	local function show()
		local kind = REWARD_KINDS[kindIndex]
		kindButton.Text = REWARD_ICON[kind] .. " " .. Store.T("reward_" .. kind) .. "  ⟳"
		amount.Visible = kind == "cash" or kind == "xp"
		choice.Visible = kind == "item" or kind == "phone"
		if kind == "item" then
			choice.Text = itemChoices[itemIndex].name .. "  ⟳"
		elseif kind == "phone" then
			choice.Text = phoneChoices[phoneIndex].name .. "  ⟳"
		end
	end
	kindButton = Make.Button("", T.panel, function()
		kindIndex = kindIndex % #REWARD_KINDS + 1
		show()
	end, { LayoutOrder = 1, Parent = holder })
	choice = Make.Button("", T.card, function()
		if REWARD_KINDS[kindIndex] == "item" then
			itemIndex = itemIndex % #itemChoices + 1
		else
			phoneIndex = phoneIndex % #phoneChoices + 1
		end
		show()
	end, { LayoutOrder = 3, Parent = holder })
	show()
	return function()
		local kind = REWARD_KINDS[kindIndex]
		if kind == "item" then
			return kind, itemChoices[itemIndex].id
		elseif kind == "phone" then
			return kind, phoneChoices[phoneIndex].id
		end
		return kind, math.floor(number(amount.Text) or 0)
	end
end

local function aaTab(root: ScrollingFrame)
	local snap: { [string]: any } = { drops = {} }

	-- what is running right now
	local status = section(root, 1, "📊 " .. Store.T("aa_running"))
	local statusList = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = status,
	}, { Make.List(6) })
	local function showStatus()
		Make.Clear(statusList)
		local now = workspace:GetServerTimeNow()
		local any = false
		for _, info in { { "cash", "💸 Cash" }, { "xp", "⭐ XP" } } do
			local b = snap[info[1]]
			if typeof(b) == "table" and (b.m or 1) > 1 and (b.ends or 0) > now then
				any = true
				local mins = math.ceil((b.ends - now) / 60)
				Make.Row({
					Make.Label(
						string.format("%s %gx · %d min", info[2], b.m, mins),
						13,
						T.text,
						T.bold,
						{ Size = UDim2.new(0.6, 0, 1, 0) }
					),
					Make.Button("⏹ " .. Store.T("stop"), T.bad, function()
						act("aa_boost_stop", { kind = info[1] })
					end, { Size = UDim2.new(0.4, -6, 1, 0) }),
				}, 30).Parent =
					statusList
			end
		end
		if snap.weekly then
			any = true
			Make.Label("🗓️ " .. Store.T("aa_weekly_now"), 12, T.warn, T.bold, { Parent = statusList })
		end
		for _, d in snap.drops or {} do
			any = true
			local mins = math.ceil((d.ends - now) / 60)
			Make.Row({
				Make.Label(
					string.format("📦 %s · %d min", tostring(d.name), mins),
					13,
					T.text,
					T.bold,
					{ Size = UDim2.new(0.6, 0, 1, 0) }
				),
				Make.Button("🗑", T.bad, function()
					act("aa_drop_remove", { id = d.id })
				end, { Size = UDim2.new(0.4, -6, 1, 0) }),
			}, 30).Parent =
				statusList
		end
		if not any then
			Make.Label(Store.T("aa_nothing"), 12, T.sub, T.font, { Parent = statusList })
		end
	end
	local function refresh()
		local r = Net.Request("Events.Get")
		if r.ok and statusList.Parent then
			snap = r
			showStatus()
		end
	end
	local stopListening = Net.On("Events", function(e)
		if typeof(e) == "table" and statusList.Parent then
			snap = e
			showStatus()
		end
	end)
	root.Destroying:Connect(stopListening)
	task.spawn(refresh)

	-- ?x Cash / ?x XP with a time limit
	for i, info in { { "cash", "💸 ?x Cash" }, { "xp", "⭐ ?x XP" } } do
		local card = section(root, 1 + i, info[2])
		local mult = Make.TextBox(Store.T("aa_multiplier"), { Parent = card })
		local minutes = Make.TextBox(Store.T("duration_min") .. " (30)", { Parent = card })
		Make.Button("▶ " .. Store.T("aa_start"), T.good, function()
			act("aa_boost", {
				kind = info[1],
				mult = number(mult.Text) or 2,
				minutes = math.floor(number(minutes.Text) or 30),
			})
		end, { Parent = card })
	end

	-- free cash / XP / items / phones for everyone online (all servers)
	local gift = section(root, 4, "🎁 " .. Store.T("aa_gift"))
	local getGift = rewardPicker(gift)
	Make.Button(Store.T("aa_gift_all"), T.good, function()
		local kind, value = getGift()
		act("aa_gift", { kind = kind, value = value })
	end, { Parent = gift })

	-- a pickup at a spot on the map, with a time limit
	local drop = section(root, 5, "📦 " .. Store.T("aa_drop"))
	local getDrop = rewardPicker(drop)
	local dropMinutes = Make.TextBox(Store.T("duration_min") .. " (15)", { Parent = drop })
	Make.Button("🗺️ " .. Store.T("aa_pick_spot"), T.accent, function()
		MapPicker.Pick(snap.drops or {}, function(x, z)
			local kind, value = getDrop()
			act("aa_drop", {
				x = x,
				z = z,
				kind = kind,
				value = value,
				minutes = math.floor(number(dropMinutes.Text) or 15),
			})
		end)
	end, { Parent = drop })

	Make.Label("🗓️ " .. Store.T("aa_weekly_info"), 12, T.sub, T.font, { LayoutOrder = 6, Parent = root })
end

local function inboxTab(root: ScrollingFrame)
	local r = Net.Request("Admin.Inbox")
	if not r.ok then
		Notify.Error(r.err)
		return
	end
	local inbox = r.inbox or {}
	if #inbox == 0 then
		Make.Label(Store.T("no_chats"), 13, T.sub, T.font, { Parent = root })
	end
	for i = #inbox, math.max(1, #inbox - 50), -1 do
		local e = inbox[i]
		local card = Make.Card({ LayoutOrder = #inbox - i, Parent = root })
		Make.Label(
			string.format("%s · %s · %s", e.fromName, e.number, os.date("%d.%m. %H:%M", e.t)),
			12,
			T.sub,
			T.bold,
			{ Parent = card }
		)
		Make.Label(e.text, 14, T.text, T.font, { Parent = card })
		local reply = Make.TextBox(Store.T("reply") .. " …", { Parent = card })
		Make.Button(Store.T("reply"), T.good, function()
			local res = act("reply", { userId = e.fromUserId, text = reply.Text })
			if res.ok then
				reply.Text = ""
			end
		end, { Parent = card })
	end
end

local function logsTab(root: ScrollingFrame)
	local r = Net.Request("Admin.Logs")
	if not r.ok then
		Notify.Error(r.err)
		return
	end
	for i, e in r.logs or {} do
		Make.Label(
			string.format("%s  %s: %s %s", os.date("%H:%M", e.t), e.actor, e.action, e.detail or ""),
			11,
			T.sub,
			T.font,
			{
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 30),
				Parent = root,
			}
		)
	end
end

Phone.Register({
	id = "admin",
	icon = "🛡️",
	color = Color3.fromRGB(20, 20, 20),
	order = 30,
	visible = function(state)
		return (state.rank or 0) >= 1
	end,
	build = function(container, arg)
		local isGA = Store.Rank() >= GAME_ADMIN
		local tabs = { "admin_players", "admin_self", "admin_server", "admin_vehicles", "admin_logs" }
		if isGA then
			table.insert(tabs, 5, "admin_inbox")
			table.insert(tabs, 5, "admin_news")
		end
		if Store.Rank() >= CO_OWNER then
			table.insert(tabs, 1, "admin_aa")
		end
		local current = if typeof(arg) == "string" then arg else "admin_players"

		local bar = New("ScrollingFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 0,
			Parent = container,
		}, { Make.List(4, true) })
		local root =
			Make.Scroll({ Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), Parent = container })

		for i, key in tabs do
			Make.Button(Store.T(key), if key == current then Color3.fromRGB(57, 160, 20) else T.card, function()
				Phone.Replace("admin", key)
			end, { LayoutOrder = i, Size = UDim2.fromOffset(78, 30), TextSize = 12, Parent = bar })
		end

		if current == "admin_players" then
			playersTab(root)
		elseif current == "admin_self" then
			selfTab(root)
		elseif current == "admin_server" then
			serverTab(root)
		elseif current == "admin_vehicles" then
			vehiclesTab(root)
		elseif current == "admin_inbox" then
			inboxTab(root)
		elseif current == "admin_news" then
			newsTab(root)
		elseif current == "admin_aa" then
			aaTab(root)
		elseif current == "admin_logs" then
			logsTab(root)
		end
		return nil
	end,
})

-- 23646 messages arriving live for Game Admins.
Net.On("AdminChat", function(entry)
	if typeof(entry) == "table" and Store.Rank() >= GAME_ADMIN then
		Notify.Show(Store.T("admin_chat_new", tostring(entry.fromName)) .. "\n" .. tostring(entry.text), false, 7)
	end
end)

return Admin
