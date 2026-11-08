--!strict
-- Einstellungen: language, wallpaper, owned phones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Phones = require(ReplicatedStorage.Shared.Phones)
local Make = require(script.Parent.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.Parent.UI.Notify)
local Net = require(script.Parent.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Parent.Store)
local Phone = require(script.Parent.Parent.Phone)

local New, T = Make.New, Make.Theme

local function req(name: string, ...: any)
	local r = Net.Request(name, ...)
	if not r.ok then
		Notify.Error(r.err)
	end
end

Phone.Register({
	id = "settings",
	icon = "⚙️",
	color = Color3.fromRGB(110, 110, 120),
	order = 20,
	build = function(container)
		local root = Make.Scroll({ Parent = container })
		local function render(state: { [string]: any })
			Make.Clear(root)
			local phone = Phones.ById[state.phone or ""] or Phones.ById[Phones.StarterId]

			local info = Make.Card({ LayoutOrder = 1, Parent = root })
			Make.Label(phone.name, 16, T.text, T.black, { Parent = info })
			Make.Label(
				Store.T("camera_quality", phone.camera) .. "  ·  " .. (state.number or ""),
				12,
				T.sub,
				T.font,
				{ Parent = info }
			)

			local lang = Make.Card({ LayoutOrder = 2, Parent = root })
			Make.Label(Store.T("language"), 14, T.text, T.bold, { Parent = lang })
			Make.Row({
				Make.Button("🇩🇪 Deutsch", if state.language ~= "en" then T.accent else T.panel, function()
					req("Settings.Language", "de")
				end, { Size = UDim2.new(0.5, -3, 1, 0) }),
				Make.Button("🇬🇧 English", if state.language == "en" then T.accent else T.panel, function()
					req("Settings.Language", "en")
				end, { Size = UDim2.new(0.5, -3, 1, 0) }),
			}).Parent =
				lang

			local wp = Make.Card({ LayoutOrder = 3, Parent = root })
			Make.Label(Store.T("wallpaper"), 14, T.text, T.bold, { Parent = wp })
			local grid = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = wp,
			})
			New(
				"UIGridLayout",
				{ CellSize = UDim2.new(0.25, -6, 0, 54), CellPadding = UDim2.fromOffset(6, 6), Parent = grid }
			)
			for i, colors in Phones.Wallpapers do
				local unlocked = i <= phone.wallpapers
				local sw = New("TextButton", {
					Text = if unlocked then (if state.wallpaper == i then "✓" else "") else "🔒",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 18,
					Font = T.bold,
					BackgroundColor3 = Color3.new(1, 1, 1),
					AutoButtonColor = unlocked,
					Parent = grid,
				}, {
					Make.Corner(8),
					New("UIGradient", { Rotation = 90, Color = ColorSequence.new(colors[1], colors[2]) }),
				})
				if unlocked then
					sw.Activated:Connect(function()
						req("Phone.SetWallpaper", i)
					end)
				end
			end

			Make.Label(
				"Karte / Map: © OpenStreetMap-Mitwirkende (ODbL)",
				11,
				T.sub,
				T.font,
				{ LayoutOrder = 9, Parent = root }
			)

			local apt = game:GetService("Players").LocalPlayer:GetAttribute("Apartment")
			if typeof(apt) == "number" then
				local home = Make.Card({ LayoutOrder = 5, Parent = root })
				Make.Label(Store.T("my_apartment", apt), 14, T.text, T.bold, { Parent = home })
				Make.Button(Store.T("move_out"), T.bad, function()
					req("Housing.MoveOut")
				end, { Parent = home })
			end

			local mine = Make.Card({ LayoutOrder = 4, Parent = root })
			Make.Label(Store.T("my_phones"), 14, T.text, T.bold, { Parent = mine })
			for _, id in state.phones or {} do
				local p = Phones.ById[id]
				if p then
					local inUse = state.phone == id
					Make.Button(p.name .. (if inUse then "  ✓" else ""), if inUse then T.good else T.panel, function()
						if not inUse then
							req("Phone.Equip", id)
						end
					end, { Parent = mine })
				end
			end
		end
		render(Store.Get())
		return render
	end,
})

return nil
