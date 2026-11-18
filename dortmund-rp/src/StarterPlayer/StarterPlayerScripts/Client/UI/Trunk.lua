--!strict
-- Kofferraum window (📦 on the car dashboard): items in the trunk <-> your bag.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Make = require(script.Parent.Make)
local Net = require(script.Parent.Parent.Net)
local Notify = require(script.Parent.Notify)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme

local TrunkUI = {}

local gui = New("ScreenGui", {
	Name = "Trunk",
	ResetOnSpawn = false,
	DisplayOrder = 30,
	Enabled = false,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})
local panel = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.fromOffset(340, 420),
	BackgroundColor3 = T.bg,
	Parent = gui,
}, { Make.Corner(14), Make.Stroke(Color3.fromRGB(230, 150, 40), 2) })
local title = Make.Label("", 16, T.text, T.black, {
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -60, 0, 24),
	Parent = panel,
})
Make.Button("X", T.card, function()
	gui.Enabled = false
end, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -8, 0, 8),
	Size = UDim2.fromOffset(28, 28),
	TextSize = 14,
	Parent = panel,
})
local list = Make.Scroll({ Position = UDim2.fromOffset(8, 40), Size = UDim2.new(1, -16, 1, -48), Parent = panel })

local render: (any) -> ()

local function request(name: string, itemId: string)
	task.spawn(function()
		local r = Net.Request(name, itemId)
		if r.ok then
			render(r)
		else
			Notify.Error(r.err)
		end
	end)
end

local function counts(ids: { string }): ({ string }, { [string]: number })
	local order, n = {}, {}
	for _, id in ids do
		if not n[id] then
			n[id] = 0
			table.insert(order, id)
		end
		n[id] += 1
	end
	return order, n
end

local function group(order: number, heading: string, ids: { string }, action: string, verb: string)
	local card = Make.Card({ LayoutOrder = order, Parent = list })
	Make.Label(heading, 14, T.text, T.bold, { Parent = card })
	local ids2, n = counts(ids)
	if #ids2 == 0 then
		Make.Label(Store.T("trunk_empty"), 12, T.sub, T.font, { Parent = card })
	end
	for _, id in ids2 do
		local it = Items.ById[id]
		Make.Row({
			Make.Label(("%s  ×%d"):format(if it then it.name else id, n[id]), 13, T.text, T.font, {
				Size = UDim2.new(0.62, 0, 1, 0),
			}),
			Make.Button(verb, T.good, function()
				request(action, id)
			end, { Size = UDim2.new(0.38, -4, 1, 0), TextSize = 12 }),
		}, 30).Parent =
			card
	end
end

render = function(s: any)
	Make.Clear(list)
	title.Text = ("📦 %s · %s"):format(Store.T("trunk"), tostring(s.car or ""))
	group(
		1,
		("🚗 %s  %d / %d"):format(Store.T("trunk"), #s.items, s.limit),
		s.items,
		"Trunk.Take",
		Store.T("trunk_take")
	)
	group(
		2,
		("🎒 %s  %d / %d"):format(Store.T("inventory"), #s.carried, s.maxCarried),
		s.carried,
		"Trunk.Put",
		Store.T("trunk_put")
	)
	Make.Label("🪪 " .. Store.T("trunk_no_id"), 11, T.sub, T.font, { LayoutOrder = 3, Parent = list })
end

function TrunkUI.Open()
	task.spawn(function()
		local r = Net.Request("Trunk.Open")
		if not r.ok then
			Notify.Error(r.err)
			return
		end
		render(r)
		gui.Enabled = true
	end)
end

return TrunkUI
