--!strict
-- Garage: spawn / park your motorbike, plate, paint colour.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local Make = require(script.Parent.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.Parent.UI.Notify)
local Net = require(script.Parent.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Parent.Store)
local Phone = require(script.Parent.Parent.Phone)

local New, T = Make.New, Make.Theme

local function req(name: string, ...: any): boolean
	local r = Net.Request(name, ...)
	if not r.ok then
		Notify.Error(r.err)
	end
	return r.ok == true
end

Phone.Register({
	id = "garage",
	icon = "🏍️",
	color = Color3.fromRGB(80, 85, 95),
	order = 5,
	build = function(container)
		local root = Make.Scroll({ Parent = container })
		local expanded: string? = nil

		local function render(state: { [string]: any })
			Make.Clear(root)
			Make.Button("🅿️ " .. Store.T("despawn"), T.panel, function()
				req("Vehicle.Despawn")
			end, { LayoutOrder = 1, Parent = root })

			local uids = {}
			for uid in state.vehicles or {} do
				table.insert(uids, uid)
			end
			table.sort(uids, function(a, b)
				return (tonumber(string.sub(a, 2)) or 0) < (tonumber(string.sub(b, 2)) or 0)
			end)
			if #uids == 0 then
				Make.Label(Store.T("no_cars"), 13, T.sub, T.font, { LayoutOrder = 2, Parent = root })
			end
			for i, uid in uids do
				local entry = state.vehicles[uid]
				local def = Vehicles.ById[entry.id]
				local card = Make.Card({ LayoutOrder = 10 + i, Parent = root })
				local c = entry.color or { 200, 200, 200 }
				New(
					"Frame",
					{ Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = Color3.fromRGB(c[1], c[2], c[3]), Parent = card },
					{ Make.Corner(3) }
				)
				Make.Label(if def then def.name else entry.id, 14, T.text, T.bold, { Parent = card })
				Make.Label(
					string.format("%s  ·  %s %d%%", entry.plate or "", Store.T("fuel"), math.floor(entry.fuel or 100)),
					12,
					T.sub,
					T.font,
					{ Parent = card }
				)
				Make.Row({
					Make.Button(Store.T("spawn"), T.good, function()
						if req("Vehicle.Spawn", uid) then
							Phone.Close()
						end
					end, { Size = UDim2.new(0.5, -3, 1, 0) }),
					Make.Button("⚙️", T.panel, function()
						expanded = if expanded == uid then nil else uid
						render(Store.Get())
					end, { Size = UDim2.new(0.5, -3, 1, 0) }),
				}, 34).Parent =
					card

				if expanded == uid then
					local plateBox = Make.TextBox("DO-AB 1234", { Text = entry.plate or "", Parent = card })
					Make.Button(Store.T("change_plate"), T.accent, function()
						req("Vehicle.SetPlate", uid, plateBox.Text)
					end, { Parent = card })
					Make.Label(Store.T("color"), 12, T.sub, T.bold, { Parent = card })
					local swatches =
						New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64), Parent = card })
					New("UIGridLayout", {
						CellSize = UDim2.new(1 / 6, -4, 0, 28),
						CellPadding = UDim2.fromOffset(4, 4),
						Parent = swatches,
					})
					for index, rgb in Vehicles.Palette do
						local sw = New("TextButton", {
							Text = "",
							BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
							Parent = swatches,
						}, { Make.Corner(6), Make.Stroke(Color3.new(1, 1, 1), 1, 0.6) })
						sw.Activated:Connect(function()
							req("Vehicle.SetColor", uid, index)
						end)
					end
				end
			end
		end
		render(Store.Get())
		return render
	end,
})

return nil
