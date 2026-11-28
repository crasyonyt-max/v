--!strict
-- 🎄 Adventskalender (Config.Advent, testing server first): 24 doors in a shuffled
-- grid like a real calendar. Today's door glows, opened ones show ✓, closed ones 🔒.
-- Below: the way to the Weihnachtsmarkt behind the Parlament.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Advent = require(ReplicatedStorage.Shared.Advent)
local Config = require(ReplicatedStorage.Shared.Config)
local Make = require(script.Parent.Parent.Parent.UI.Make)
local Net = require(script.Parent.Parent.Parent.Net)
local Notify = require(script.Parent.Parent.Parent.UI.Notify)
local Store = require(script.Parent.Parent.Parent.Store)
local Waypoint = require(script.Parent.Parent.Parent.UI.Waypoint)
local Phone = require(script.Parent.Parent.Phone)

local New, T = Make.New, Make.Theme

if not Config.On(Config.Advent) then
	return nil
end

local RED = Color3.fromRGB(170, 30, 40)
local GREEN = Color3.fromRGB(30, 110, 60)
local GOLD = Color3.fromRGB(255, 205, 80)

local function rewardText(r: any): string
	local parts = {}
	if (r.cash or 0) > 0 then
		table.insert(parts, tostring(r.cashText))
	end
	if (r.xp or 0) > 0 then
		table.insert(parts, r.xp .. " XP")
	end
	for _, name in r.items or {} do
		table.insert(parts, name)
	end
	if r.outfit then
		table.insert(parts, "👕 " .. tostring(r.outfit))
	end
	return table.concat(parts, " · ")
end

Phone.Register({
	id = "advent",
	icon = "🎄",
	color = RED,
	order = 11,
	build = function(container)
		local root = Make.Scroll({ Parent = container })
		Make.Label(Store.T("advent_title"), 17, GOLD, T.black, { LayoutOrder = 1, Parent = root })
		Make.Label(Store.T("advent_info"), 12, T.sub, T.font, { LayoutOrder = 2, Parent = root })
		local status = Make.Label("", 12, T.text, T.bold, { LayoutOrder = 3, Parent = root })
		local grid = New("Frame", {
			LayoutOrder = 4,
			BackgroundColor3 = Color3.fromRGB(60, 20, 25),
			Size = UDim2.new(1, 0, 0, 4 * 58 + 12),
			Parent = root,
		}, {
			Make.Corner(12),
			Make.Padding(6),
			New("UIGridLayout", {
				CellSize = UDim2.new(1 / 6, -6, 0, 52),
				CellPadding = UDim2.fromOffset(6, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local market = Make.Card({ LayoutOrder = 5, Parent = root })
		Make.Label(Store.T("advent_market"), 12, T.text, T.font, { Parent = market })
		Make.Button(Store.T("advent_market_go"), GREEN, function()
			local site = Config.ParliamentSite
			Waypoint.Set(Vector3.new(site.x, 0, site.z + 246), "Weihnachtsmarkt", GOLD)
			Phone.Close()
		end, { Size = UDim2.new(1, 0, 0, 36), Parent = market })
		-- the Christmas tree (bought at the market) and the gift cars
		local treeCard = Make.Card({ LayoutOrder = 7, Parent = root })
		-- the Christmas outfit: pieces from the doors, put on / take off
		local outfit = Make.Card({ LayoutOrder = 6, Parent = root })

		local function renderTree(state: any)
			Make.Clear(treeCard)
			Make.Label(Store.T("advent_tree_title"), 13, GOLD, T.bold, { Parent = treeCard })
			Make.Label(
				if state.tree then Store.T("advent_tree_yes") else Store.T("advent_tree_no"),
				12,
				if state.tree then Color3.fromRGB(80, 220, 120) else T.sub,
				T.bold,
				{ Parent = treeCard }
			)
			Make.Label(
				Store.T("advent_tree_info", tostring(state.treePrice or "")),
				12,
				T.text,
				T.font,
				{ Parent = treeCard }
			)
		end

		local function renderOutfit(state: any)
			Make.Clear(outfit)
			Make.Label(Store.T("advent_outfit"), 13, GOLD, T.bold, { Parent = outfit })
			local owned = Advent.OwnedOutfit(state.opened)
			local worn: { [string]: boolean } = {}
			for _, p in state.wearing or {} do
				worn[p] = true
			end
			local pieces = {}
			for id, def in Advent.Outfit do
				table.insert(pieces, { id = id, def = def })
			end
			table.sort(pieces, function(a, b)
				return a.def.order < b.def.order
			end)
			for _, p in pieces do
				local id, def = p.id, p.def
				local label = def.icon .. " " .. def.name
				if not owned[id] then
					Make.Button(label .. "  ·  🔒 " .. Store.T("advent_outfit_door", def.door), T.panel, function()
						Notify.Error("advent_not_owned")
					end, { Size = UDim2.new(1, 0, 0, 34), TextSize = 12, Parent = outfit })
				else
					local on = worn[id] == true
					Make.Button(
						label .. "  ·  " .. Store.T(if on then "advent_take_off" else "advent_put_on"),
						if on then GREEN else RED,
						function()
							task.spawn(function()
								local r = Net.Request("Advent.Wear", id, not on)
								if not r.ok then
									Notify.Error(r.err)
									return
								end
								if not on and Advent.OnHead[id] then
									for h in Advent.OnHead do
										worn[h] = nil
									end
								end
								worn[id] = if on then nil else true
								local list = {}
								for k in worn do
									table.insert(list, k)
								end
								state.wearing = list
								if outfit.Parent then
									renderOutfit(state)
								end
							end)
						end,
						{ Size = UDim2.new(1, 0, 0, 34), TextSize = 12, Parent = outfit }
					)
				end
			end
		end

		local function render(state: any)
			for _, c in grid:GetChildren() do
				if c:IsA("GuiButton") then
					c:Destroy()
				end
			end
			local done: { [number]: boolean } = {}
			for _, n in state.opened do
				done[n] = true
			end
			status.Text = if Config.Testing
				then Store.T("advent_test")
				elseif state.unlocked == 0 then Store.T("advent_before")
				else ""
			for i, door in Advent.Layout do
				local isOpen = done[door] == true
				local can = door <= state.unlocked and not isOpen
				local today = door == state.today
				local b = Make.Button(
					if isOpen then "✓\n" .. door elseif can then tostring(door) else "🔒\n" .. door,
					if isOpen
						then Color3.fromRGB(70, 60, 55)
						elseif today then GOLD
						else (if i % 2 == 0 then RED else GREEN),
					function()
						if not can then
							Notify.Error(if isOpen then "advent_opened" else "advent_locked")
							return
						end
						task.spawn(function()
							local r = Net.Request("Advent.Open", door)
							if r.ok then
								Notify.Show(Store.T("advent_got", door, rewardText(r)), false, 8)
								table.insert(state.opened, door)
								if r.outfit then
									local list = state.wearing or {}
									table.insert(list, Advent.Rewards[door].outfit)
									state.wearing = list
								end
								if grid.Parent then
									render(state)
								end
							else
								Notify.Error(r.err)
							end
						end)
					end,
					{
						LayoutOrder = i,
						TextSize = if door == 24 then 20 else 16,
						TextColor3 = if today and not isOpen then Color3.fromRGB(60, 20, 25) else Color3.new(1, 1, 1),
						Parent = grid,
					}
				)
				if door == 24 or door == 6 then
					Make.Stroke(GOLD, 2).Parent = b
				end
			end
			renderOutfit(state)
			renderTree(state)
		end

		task.spawn(function()
			local r = Net.Request("Advent.Get")
			if r.ok and grid.Parent then
				render(r)
			elseif not r.ok then
				Notify.Error(r.err)
			end
		end)
		return nil
	end,
})

return nil
