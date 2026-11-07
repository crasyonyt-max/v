--!strict
-- Telefon: keypad, 110 / 112 emergency calls, 23646 admin hotline.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Make = require(script.Parent.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.Parent.UI.Notify)
local Net = require(script.Parent.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Parent.Store)
local Phone = require(script.Parent.Parent.Phone)

local New, T = Make.New, Make.Theme

Phone.Register({
	id = "phone",
	icon = "📞",
	color = Color3.fromRGB(40, 170, 80),
	order = 1,
	build = function(container, arg)
		local number = if typeof(arg) == "string" then arg else ""
		local root = Make.Scroll({ Parent = container })

		Make.Label(
			Store.T("your_number", Store.Get().number or "?"),
			12,
			T.sub,
			T.font,
			{ LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Center, Parent = root }
		)
		local display = Make.Label(number, 28, T.text, T.bold, {
			LayoutOrder = 2,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 40),
			Parent = root,
		})

		local emergency = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Visible = false,
			LayoutOrder = 3,
			Parent = root,
		}, { Make.List(6) })
		local reason = Make.TextBox(
			Store.T("emergency_what"),
			{ Size = UDim2.new(1, 0, 0, 60), TextWrapped = true, MultiLine = true, Parent = emergency }
		)
		local emergencyBtn: TextButton

		local pad =
			New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 220), LayoutOrder = 4, Parent = root })
		New("UIGridLayout", {
			CellSize = UDim2.new(1 / 3, -6, 0, 48),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = pad,
		})

		local function refresh()
			display.Text = number
			emergency.Visible = Config.EmergencyNumbers[number] ~= nil
		end

		for i, key in { "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "⌫" } do
			Make.Button(key, T.card, function()
				if key == "⌫" then
					number = string.sub(number, 1, -2)
				elseif #number < 16 then
					number ..= key
				end
				refresh()
			end, { LayoutOrder = i, TextSize = 20, Parent = pad })
		end

		emergencyBtn = Make.Button("🚨 " .. Store.T("send"), T.bad, function()
			local r = Net.Request("Call.Make", number, reason.Text)
			if r.ok then
				Notify.Show(Store.T("call_sent"))
				number = ""
				reason.Text = ""
				refresh()
			else
				Notify.Error(r.err)
			end
		end, { Parent = emergency })
		local _ = emergencyBtn

		Make.Button("📞", T.good, function()
			if number == "" then
				return
			end
			if Config.EmergencyNumbers[number] then
				reason:CaptureFocus()
				return
			end
			if number == Config.AdminChatNumber then
				Phone.Replace("chatsapp", number)
				return
			end
			Notify.Show(Store.T("calls_soon"))
			Phone.Replace("chatsapp", number)
		end, { LayoutOrder = 5, TextSize = 22, Size = UDim2.new(0.5, 0, 0, 44), Parent = root })

		refresh()
		return nil
	end,
})

return nil
