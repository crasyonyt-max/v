--!strict
-- Update 2 (testing server first):
--   👤 Kontakte: saved names for phone numbers. Synced with ChatsApp: the same names
--      show up there, people you chat with can be saved here in one tap, and every
--      contact has 💬 (open the chat) and 📞 (voice call – both need voice chat).
--   📋 Aufgaben: the daily login bonus, the 3 daily tasks and your job rank.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local Make = require(script.Parent.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.Parent.UI.Notify)
local Net = require(script.Parent.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Parent.Store)
local Phone = require(script.Parent.Parent.Phone)

local T = Make.Theme

if not Config.On(Config.Update2) then
	return nil
end

local Update2 = require(script.Parent.Parent.Parent.Controllers.Update2Controller) :: any

local function req(name: string, ...: any): boolean
	local r = Net.Request(name, ...)
	if not r.ok then
		Notify.Error(r.err)
	end
	return r.ok
end

-- phone numbers you chatted with (ChatsApp), newest first
local function chatPeers(state: { [string]: any }): { { peer: string, name: string } }
	local seen, out = {}, {}
	local msgs = state.messages or {}
	for i = #msgs, 1, -1 do
		local m = msgs[i]
		if m.peer and m.peer ~= Config.AdminChatNumber and not seen[m.peer] then
			seen[m.peer] = true
			table.insert(out, { peer = m.peer, name = m.peerName or m.peer })
		end
	end
	return out
end

Phone.Register({
	id = "contacts",
	icon = "👤",
	color = Color3.fromRGB(70, 110, 220),
	order = 2,
	build = function(container)
		local root = Make.Scroll({ Parent = container })
		local function render(state: { [string]: any })
			Make.Clear(root)
			local contacts = state.contacts or {}
			-- new contact
			local nameBox = Make.TextBox(Store.T("contact_name"), { LayoutOrder = 1, Parent = root })
			local numBox = Make.TextBox(Store.T("enter_number"), { LayoutOrder = 2, Parent = root })
			Make.Button("＋ " .. Store.T("contact_add"), Color3.fromRGB(70, 110, 220), function()
				task.spawn(function()
					req("Contacts.Save", numBox.Text, nameBox.Text)
				end)
			end, { LayoutOrder = 3, Parent = root })

			local sorted = {}
			for number, name in contacts do
				table.insert(sorted, { number = number, name = name })
			end
			table.sort(sorted, function(a, b)
				return string.lower(a.name) < string.lower(b.name)
			end)
			if #sorted == 0 then
				Make.Label(Store.T("contacts_none"), 13, T.sub, T.font, { LayoutOrder = 4, Parent = root })
			end
			for i, c in sorted do
				local card = Make.Card({ LayoutOrder = 10 + i, Parent = root })
				Make.Label("👤 " .. c.name, 14, T.text, T.bold, { Parent = card })
				Make.Label(c.number, 12, T.sub, T.font, { Parent = card })
				Make.Row({
					Make.Button("💬", Color3.fromRGB(0, 160, 110), function()
						Phone.OpenApp("chatsapp", c.number)
					end, { Size = UDim2.new(1 / 3, -4, 1, 0) }),
					Make.Button("📞", Color3.fromRGB(0, 140, 70), function()
						Update2.Call({ c.number })
					end, { Size = UDim2.new(1 / 3, -4, 1, 0) }),
					Make.Button("🗑", T.bad, function()
						task.spawn(function()
							req("Contacts.Delete", c.number)
						end)
					end, { Size = UDim2.new(1 / 3, -4, 1, 0) }),
				}, 32).Parent =
					card
			end

			-- from ChatsApp: people you wrote with, not saved yet
			local order = 500
			for _, p in chatPeers(state) do
				if not contacts[p.peer] then
					if order == 500 then
						Make.Label(
							"💬 " .. Store.T("contacts_from_chats"),
							13,
							T.sub,
							T.bold,
							{ LayoutOrder = order, Parent = root }
						)
					end
					order += 1
					local name = p.name
					Make.CardButton({ LayoutOrder = order, Parent = root }, {
						Make.Label(name .. "  ·  " .. p.peer, 13, T.text, T.bold),
						Make.Label("＋ " .. Store.T("contact_add"), 12, T.sub, T.font),
					}, function()
						task.spawn(function()
							req("Contacts.Save", p.peer, name)
						end)
					end)
				end
			end
		end
		render(Store.Get())
		return render
	end,
})

Phone.Register({
	id = "daily",
	icon = "📋",
	color = Color3.fromRGB(230, 150, 30),
	order = 9,
	build = function(container)
		local root = Make.Scroll({ Parent = container })
		local function render(state: { [string]: any })
			task.spawn(function()
				local r = Net.Request("Daily.Get")
				if not root.Parent then
					return
				end
				Make.Clear(root)
				if not r.ok then
					return
				end
				Make.Label(
					Store.T("daily_streak", r.streak or 0),
					16,
					T.text,
					T.black,
					{ LayoutOrder = 1, Parent = root }
				)
				Make.Label(Store.T("daily_streak_info"), 12, T.sub, T.font, { LayoutOrder = 2, Parent = root })
				for i, t in r.tasks or {} do
					local card = Make.Card({ LayoutOrder = 10 + i, Parent = root })
					Make.Label(
						(if t.done then "✅ " else "⬜ ") .. Store.T("task_" .. tostring(t.key), t.n),
						14,
						T.text,
						T.bold,
						{ Parent = card }
					)
					Make.Label(
						("%d / %d  ·  +400 € +100 XP"):format(t.have or 0, t.n or 1),
						12,
						T.sub,
						T.font,
						{ Parent = card }
					)
				end
				-- job rank
				local job = tostring(state.job or "Unemployed")
				if job ~= "Unemployed" then
					local xp = (state.jobXP or {})[job] or 0
					local rank, name = Ranks.For(job, xp)
					local nextXP = Ranks.NextXP(xp)
					local card = Make.Card({ LayoutOrder = 50, Parent = root })
					Make.Label("⭐ " .. name, 15, Color3.fromRGB(255, 210, 90), T.bold, { Parent = card })
					Make.Label(
						Store.T("rank_info", rank, math.floor((rank - 1) * Ranks.BONUS * 100))
							.. (if nextXP then "  ·  " .. Store.T("rank_next", math.floor(nextXP - xp)) else ""),
						12,
						T.sub,
						T.font,
						{ Parent = card }
					)
				end
			end)
		end
		render(Store.Get())
		return nil
	end,
})

Net.On("Daily", function()
	-- (the app reloads itself when opened)
end)

return nil
