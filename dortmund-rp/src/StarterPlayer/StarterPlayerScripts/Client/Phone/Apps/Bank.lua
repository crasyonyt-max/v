--!strict
-- Bank: balance, transfers to players on this server, transaction history.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Make = require(script.Parent.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.Parent.UI.Notify)
local Net = require(script.Parent.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Parent.Store)
local Phone = require(script.Parent.Parent.Phone)

local T = Make.Theme

Phone.Register({
	id = "bank",
	icon = "🏦",
	color = Color3.fromRGB(20, 90, 180),
	order = 3,
	build = function(container)
		local root = Make.Scroll({ Parent = container })

		local balanceCard =
			Make.Card({ LayoutOrder = 1, Parent = root, BackgroundColor3 = Color3.fromRGB(20, 60, 130) })
		Make.Label(Store.T("balance"), 12, T.sub, T.bold, { Parent = balanceCard })
		local balance = Make.Label("", 26, T.text, T.black, { Parent = balanceCard })

		-- transfer
		local transferCard = Make.Card({ LayoutOrder = 2, Parent = root })
		Make.Label(Store.T("transfer"), 14, T.text, T.bold, { Parent = transferCard })
		local selected: Player? = nil
		local recipient = Make.Button(
			"👤 " .. Store.T("recipient"),
			T.panel,
			function() end,
			{ Parent = transferCard }
		)
		local function others(): { Player }
			local list = {}
			for _, p in Players:GetPlayers() do
				if p ~= Players.LocalPlayer then
					table.insert(list, p)
				end
			end
			return list
		end
		recipient.Activated:Connect(function()
			local list = others()
			if #list == 0 then
				Notify.Error("target_offline")
				return
			end
			local index = if selected then (table.find(list, selected) or 0) else 0
			selected = list[index % #list + 1]
			recipient.Text = "👤 " .. (selected :: Player).DisplayName .. " (@" .. (selected :: Player).Name .. ")"
		end)
		local amount = Make.TextBox(Store.T("amount") .. " (€)", { Parent = transferCard })
		Make.Button(Store.T("transfer"), T.good, function()
			local value = tonumber(amount.Text)
			if not selected or not value then
				Notify.Error(if not selected then "bad_target" else "bad_amount")
				return
			end
			local r = Net.Request("Bank.Transfer", selected.UserId, math.floor(value))
			if r.ok then
				amount.Text = ""
				Notify.Show(Store.T("transfer_done"))
			else
				Notify.Error(r.err)
			end
		end, { Parent = transferCard })

		-- history
		Make.Label(Store.T("transactions"), 14, T.text, T.bold, { LayoutOrder = 3, Parent = root })
		local history = Make.Card({ LayoutOrder = 4, Parent = root })

		local function render(state: { [string]: any })
			balance.Text = Locale.Euro(state.bank or 0)
			Make.Clear(history)
			local tx = state.tx or {}
			for i = #tx, 1, -1 do
				local e = tx[i]
				Make.Label(
					string.format(
						"%s  %s\n%s",
						if e.amount >= 0 then "＋" else "－",
						Locale.Euro(math.abs(e.amount)),
						tostring(e.reason)
					),
					12,
					if e.amount >= 0 then Color3.fromRGB(120, 230, 140) else Color3.fromRGB(240, 130, 130),
					T.font,
					{ Size = UDim2.new(1, 0, 0, 32), Parent = history }
				)
			end
		end
		render(Store.Get())
		return render
	end,
})

return nil
