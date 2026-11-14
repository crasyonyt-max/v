--!strict
-- Navi: route to every store, station and petrol station at its real address.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Jobs = require(ReplicatedStorage.Shared.Jobs)
local Locations = require(ReplicatedStorage.Shared.Locations)
local Make = require(script.Parent.Parent.Parent.UI.Make)
local Waypoint = require(script.Parent.Parent.Parent.UI.Waypoint)
local Store = require(script.Parent.Parent.Parent.Store)
local Phone = require(script.Parent.Parent.Phone)

local T = Make.Theme

local function distanceText(pos: Vector3): string
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return ""
	end
	local d = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude * 0.28
	return if d >= 1000 then string.format("%.1f km", d / 1000) else string.format("%d m", d)
end

Phone.Register({
	id = "navi",
	icon = "🧭",
	color = Color3.fromRGB(30, 140, 110),
	order = 7,
	build = function(container)
		local root = Make.Scroll({ Parent = container })
		local order = 0
		local function header(key: string)
			order += 1
			Make.Label(Store.T(key), 14, T.text, T.bold, { LayoutOrder = order, Parent = root })
		end
		local function entry(title: string, pos: Vector3, color: Color3)
			order += 1
			Make.CardButton({ LayoutOrder = order, Parent = root }, {
				Make.Label(title, 13, T.text, T.bold),
				Make.Label(distanceText(pos), 11, T.sub, T.font),
			}, function()
				Waypoint.Set(pos, title, color)
				Phone.Close()
			end)
		end

		-- nearest first inside each group
		local function sorted(list: { { title: string, pos: Vector3, color: Color3 } })
			local character = Players.LocalPlayer.Character
			local me = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if me then
				table.sort(list, function(a, b)
					return (a.pos - me.Position).Magnitude < (b.pos - me.Position).Magnitude
				end)
			end
			for _, e in list do
				entry(e.title, e.pos, e.color)
			end
		end

		header("navi_shops")
		local shops = {}
		for _, s in Locations.Stores do
			local def = Items.Stores[s.kind]
			local front = CFrame.new(s.x, 0, s.z)
				* CFrame.Angles(0, math.rad(s.yaw), 0)
				* CFrame.new(0, 0, -s.depth / 2 - 4)
			table.insert(shops, { title = s.name, pos = front.Position, color = def and def.color or T.accent })
		end
		for i, f in Locations.Fuel do
			table.insert(
				shops,
				{ title = "⛽ Arol " .. i, pos = Vector3.new(f[1], 0, f[2]), color = Color3.fromRGB(0, 70, 160) }
			)
		end
		local special = Locations.Shops :: any
		table.insert(shops, {
			title = "📱 Handyland",
			pos = Vector3.new(special.Handyland.marker[1], 0, special.Handyland.marker[2]),
			color = Color3.fromRGB(0, 110, 220),
		})
		local siteList = (Locations :: any).Sites or {}
		if siteList.Mall then
			table.insert(shops, {
				title = "🛍️ Dortmund Mall",
				pos = Vector3.new(siteList.Mall.x, 0, siteList.Mall.z),
				color = Color3.fromRGB(255, 190, 60),
			})
		end
		if siteList.ADMC then
			local a = siteList.ADMC
			local spot = CFrame.new(a.x, 0, a.z)
				* CFrame.Angles(0, math.rad(a.yaw), 0)
				* CFrame.new(a.width / 2 + 10, 0, -a.depth / 2 + 8)
			table.insert(shops, {
				title = "🔢 Kennzeichen-Service (ADMC)",
				pos = spot.Position,
				color = Color3.fromRGB(250, 205, 0),
			})
		end
		table.insert(shops, {
			title = "🚗 Autohaus",
			pos = Vector3.new(special.Dealership.marker[1], 0, special.Dealership.marker[2]),
			color = Color3.fromRGB(60, 60, 60),
		})
		sorted(shops)

		header("navi_jobs")
		local stations = {}
		for _, job in Jobs.List do
			local loc = (Locations.Jobs :: any)[job.id]
			if loc then
				table.insert(stations, {
					title = loc.title .. " · " .. Jobs.Name(job.id, Store.Lang()),
					pos = Vector3.new(loc.marker[1], 0, loc.marker[2]),
					color = job.color,
				})
			end
		end
		sorted(stations)

		header("navi_places")
		local sites = (Locations :: any).Sites or {}
		if sites.Tower then
			local t = sites.Tower
			local front = CFrame.new(t.x, 0, t.z) * CFrame.Angles(0, math.rad(t.yaw), 0) * CFrame.new(0, 0, -50)
			local mine = Players.LocalPlayer:GetAttribute("Apartment")
			entry(
				if typeof(mine) == "number" then Store.T("my_apartment", mine) else Store.T("tower"),
				front.Position,
				Color3.fromRGB(57, 160, 20)
			)
		end
		entry("🚉 Dortmund Hbf", Vector3.new(Locations.Spawn[1], 0, Locations.Spawn[2]), Color3.fromRGB(0, 60, 140))
		entry(
			"🏥 " .. special.Hospital.title,
			Vector3.new(special.Hospital.marker[1], 0, special.Hospital.marker[2]),
			Color3.fromRGB(0, 120, 90)
		)
		return nil
	end,
})

return nil
