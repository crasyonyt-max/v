--!strict
-- ChatsApp: conversations by phone number. 23646 = Admin-Team (pinned).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Make = require(script.Parent.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.Parent.UI.Notify)
local Net = require(script.Parent.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Parent.Store)
local Phone = require(script.Parent.Parent.Phone)

local New, T = Make.New, Make.Theme

local CHAT_GREEN = Color3.fromRGB(0, 160, 110)

local function conversations(state: { [string]: any })
	local byPeer: { [string]: { peer: string, name: string, last: any } } = {}
	for _, m in state.messages or {} do
		local c = byPeer[m.peer]
		if not c then
			c = { peer = m.peer, name = m.peerName or m.peer, last = m }
			byPeer[m.peer] = c
		end
		c.last = m
		if not m.out and m.peerName then
			c.name = m.peerName
		end
	end
	local list = {}
	for _, c in byPeer do
		if c.peer ~= Config.AdminChatNumber then
			table.insert(list, c)
		end
	end
	table.sort(list, function(a, b)
		return (a.last.t or 0) > (b.last.t or 0)
	end)
	return list, byPeer[Config.AdminChatNumber]
end

local function timeText(t: number?): string
	if not t then
		return ""
	end
	return os.date("%H:%M", t) :: string
end

local function listView(container: Frame)
	local root = Make.Scroll({ Parent = container })
	local function render(state: { [string]: any })
		Make.Clear(root)
		local newBox = Make.TextBox(Store.T("enter_number"), { LayoutOrder = 1, Parent = root })
		Make.Button("＋ " .. Store.T("new_chat"), CHAT_GREEN, function()
			local n = string.gsub(newBox.Text, "[%s%-/]", "")
			if n ~= "" then
				Phone.OpenApp("chatsapp", n)
			end
		end, { LayoutOrder = 2, Parent = root })

		local list, admin = conversations(state)
		local function row(order: number, title: string, preview: string, peer: string, highlight: boolean)
			Make.CardButton({
				LayoutOrder = order,
				Parent = root,
				BackgroundColor3 = if highlight then Color3.fromRGB(20, 60, 45) else T.card,
			}, {
				Make.Label(title, 14, T.text, T.bold),
				Make.Label(preview, 12, T.sub, T.font, { TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false }),
			}, function()
				Phone.OpenApp("chatsapp", peer)
			end)
		end
		row(3, "🛡️ " .. Store.T("admin_team"), if admin then admin.last.text else "", Config.AdminChatNumber, true)
		if #list == 0 then
			Make.Label(
				Store.T("no_chats"),
				13,
				T.sub,
				T.font,
				{ LayoutOrder = 4, Parent = root, TextXAlignment = Enum.TextXAlignment.Center }
			)
		end
		for i, c in list do
			row(10 + i, c.name .. "  ·  " .. c.peer, (if c.last.out then "✓ " else "") .. c.last.text, c.peer, false)
		end
	end
	render(Store.Get())
	return render
end

local function chatView(container: Frame, peer: string)
	local isAdmin = peer == Config.AdminChatNumber
	local header = Make.Label(if isAdmin then "🛡️ " .. Store.T("admin_team") else peer, 13, T.sub, T.bold, {
		Size = UDim2.new(1, 0, 0, 18),
		Parent = container,
	})
	local _ = header
	local log = Make.Scroll({ Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 1, -66), Parent = container })
	local input = Make.TextBox(Store.T("type_message"), {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, -54, 0, 40),
		Parent = container,
	})
	local function send()
		local text = input.Text
		if text == "" then
			return
		end
		input.Text = ""
		local r = Net.Request("Chat.Send", peer, text)
		if not r.ok then
			input.Text = text
			Notify.Error(r.err)
		end
	end
	Make.Button("➤", CHAT_GREEN, send, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.fromOffset(48, 40),
		TextSize = 20,
		Parent = container,
	})
	input.FocusLost:Connect(function(enter)
		if enter then
			send()
		end
	end)

	local count = -1
	local function render(state: { [string]: any })
		local msgs = {}
		for _, m in state.messages or {} do
			if m.peer == peer then
				table.insert(msgs, m)
			end
		end
		if #msgs == count then
			return
		end
		count = #msgs
		Make.Clear(log)
		for i, m in msgs do
			local bubble = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = i,
				Parent = log,
			})
			local inner = New("TextLabel", {
				AnchorPoint = Vector2.new(if m.out then 1 else 0, 0),
				Position = UDim2.fromScale(if m.out then 1 else 0, 0),
				Size = UDim2.new(0.8, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = if m.out then Color3.fromRGB(0, 110, 80) else T.card,
				Text = m.text .. "   " .. timeText(m.t),
				TextWrapped = true,
				TextSize = 13,
				Font = T.font,
				TextColor3 = T.text,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = bubble,
			}, { Make.Corner(10), Make.Padding(8) })
			local _ = inner
		end
		task.defer(function()
			log.CanvasPosition = Vector2.new(0, math.max(0, log.AbsoluteCanvasSize.Y - log.AbsoluteWindowSize.Y))
		end)
	end
	render(Store.Get())
	return render
end

Phone.Register({
	id = "chatsapp",
	icon = "💬",
	color = CHAT_GREEN,
	order = 2,
	build = function(container, arg)
		if typeof(arg) == "string" and arg ~= "" then
			return chatView(container, arg)
		end
		return listView(container)
	end,
})

-- Incoming messages while the phone is closed.
Net.On("Message", function(msg)
	if typeof(msg) == "table" and not msg.out then
		Notify.Show(Store.T("message_from", tostring(msg.peerName or msg.peer), tostring(msg.text)))
	end
end)

return nil
