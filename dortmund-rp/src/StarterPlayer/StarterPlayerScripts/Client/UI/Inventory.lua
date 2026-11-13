--!strict
-- Custom item panel (replaces Roblox's item bar, which covered the dashboard).
-- 🎒 button above the phone button; lists carried food & drinks with use / hold.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Items = require(ReplicatedStorage.Shared.Items)
local Make = require(script.Parent.Make)
local Notify = require(script.Parent.Notify)
local Net = require(script.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme
local player = Players.LocalPlayer

local Inventory = {}

-- turn off the default item bar (retry: StarterGui may not be ready yet)
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end)

local gui = New("ScreenGui", {
	Name = "Inventory",
	ResetOnSpawn = false,
	DisplayOrder = 6,
	Parent = player:WaitForChild("PlayerGui"),
})

local button = New("TextButton", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -76), -- directly above the 📱 button
	Size = UDim2.fromOffset(56, 56),
	BackgroundColor3 = T.bg,
	BackgroundTransparency = 0.15,
	Text = "🎒",
	TextSize = 26,
	Parent = gui,
}, { Make.Corner(28), Make.Stroke(Color3.fromRGB(230, 150, 40), 2) })
local badge = New("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 2, 0, -2),
	Size = UDim2.fromOffset(22, 22),
	BackgroundColor3 = Color3.fromRGB(230, 60, 60),
	Text = "0",
	TextSize = 12,
	Font = T.bold,
	TextColor3 = Color3.new(1, 1, 1),
	Visible = false,
	Parent = button,
}, { Make.Corner(11) })

local panel = New("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -80, 1, -12),
	Size = UDim2.fromOffset(300, 360),
	BackgroundColor3 = T.bg,
	BackgroundTransparency = 0.05,
	Visible = false,
	Parent = gui,
}, { Make.Corner(14), Make.Stroke(T.card, 2), New("UISizeConstraint", { MaxSize = Vector2.new(320, 420) }) })
Make.Label(
	"🎒 " .. Store.T("inventory"),
	16,
	T.text,
	T.black,
	{ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -60, 0, 24), Parent = panel }
)
Make.Button("X", T.card, function()
	panel.Visible = false
end, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -8, 0, 8),
	Size = UDim2.fromOffset(28, 28),
	TextSize = 14,
	Parent = panel,
})
local list = Make.Scroll({ Position = UDim2.fromOffset(8, 40), Size = UDim2.new(1, -16, 1, -48), Parent = panel })

local function placeButton()
	local up = player:GetAttribute("DrivingTouch") == true
	button.Position = if up then UDim2.new(1, -12, 1, -254) else UDim2.new(1, -12, 1, -76)
	panel.Position = if up then UDim2.new(1, -80, 1, -190) else UDim2.new(1, -80, 1, -12)
end
player:GetAttributeChangedSignal("DrivingTouch"):Connect(placeButton)

local function tools(): { Tool }
	local out = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, t in container:GetChildren() do
				if t:IsA("Tool") and t:GetAttribute("ItemId") then
					table.insert(out, t)
				end
			end
		end
	end
	return out
end

local function render()
	local all = tools()
	badge.Text = tostring(#all)
	badge.Visible = #all > 0
	if not panel.Visible then
		return
	end
	Make.Clear(list)
	-- group by item
	local groups: { [string]: { Tool } } = {}
	local order: { string } = {}
	for _, t in all do
		local id = t:GetAttribute("ItemId") :: string
		if not groups[id] then
			groups[id] = {}
			table.insert(order, id)
		end
		table.insert(groups[id], t)
	end
	if #order == 0 then
		Make.Label(
			Store.T("empty_inventory"),
			13,
			T.sub,
			T.font,
			{ Parent = list, TextXAlignment = Enum.TextXAlignment.Center }
		)
		return
	end
	for i, id in order do
		local it = Items.ById[id]
		if it then
			local held = false
			for _, t in groups[id] do
				if t.Parent == player.Character then
					held = true
				end
			end
			local card = Make.Card({ LayoutOrder = i, Parent = list })
			Make.Label(string.format("%s  ×%d", it.name, #groups[id]), 14, T.text, T.bold, { Parent = card })
			Make.Label(
				(if it.hunger > 0 then "🍔 +" .. it.hunger .. "   " else "")
					.. (if it.thirst > 0 then "💧 +" .. it.thirst else ""),
				12,
				T.sub,
				T.font,
				{ Parent = card }
			)
			local isDrink = it.thirst > it.hunger
			Make.Row({
				Make.Button(Store.T(if isDrink then "drink" else "eat"), T.good, function()
					local r = Net.Request("Item.Use", id)
					if not r.ok then
						Notify.Error(r.err)
					end
				end, { Size = UDim2.new(0.5, -3, 1, 0) }),
				Make.Button(Store.T(if held then "put_away" else "hold"), T.panel, function()
					local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if not hum then
						return
					end
					if held then
						hum:UnequipTools()
					else
						hum:EquipTool(groups[id][1])
					end
				end, { Size = UDim2.new(0.5, -3, 1, 0) }),
			}, 32).Parent =
				card
		end
	end
end

button.Activated:Connect(function()
	panel.Visible = not panel.Visible
	render()
end)

local function watch(container: Instance?)
	if container then
		container.ChildAdded:Connect(render)
		container.ChildRemoved:Connect(render)
	end
end
player.ChildAdded:Connect(function(c)
	if c:IsA("Backpack") then
		watch(c)
		render()
	end
end)
watch(player:FindFirstChildOfClass("Backpack"))
player.CharacterAdded:Connect(function(c)
	watch(c)
	render()
end)
watch(player.Character)
render()

return Inventory
