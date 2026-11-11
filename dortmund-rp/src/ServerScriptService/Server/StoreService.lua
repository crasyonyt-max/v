--!strict
-- Buying food & drinks from NPC cashiers, carried items (saved), eating/drinking,
-- and hunger + thirst. Everything is decided on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local Interaction = require(script.Parent.InteractionService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local StoreService = {}

local HUNGER_MINUTES = 60 -- full -> empty
local THIRST_MINUTES = 40
local TICK = 6

local function clamp(v: number): number
	return math.clamp(v, 0, 100)
end

local function setAttrs(player: Player, data: { [string]: any })
	player:SetAttribute("Hunger", math.floor(data.hunger + 0.5))
	player:SetAttribute("Thirst", math.floor(data.thirst + 0.5))
end

local consume: (Player, Tool, string) -> ()

local function makeTool(player: Player, itemId: string): Tool?
	local it = Items.ById[itemId]
	if not it then
		return nil
	end
	local tool = Instance.new("Tool")
	tool.Name = it.name
	tool.ToolTip = it.name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ItemId", itemId)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = it.size
	handle.Color = it.color
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true
	if it.shape == "Cylinder" then
		-- cylinder axis is X; stand it upright in the hand
		handle.Shape = Enum.PartType.Cylinder
		handle.Size = Vector3.new(it.size.Y, it.size.X, it.size.Z)
		tool.Grip = CFrame.Angles(0, 0, math.pi / 2)
	elseif it.shape == "Ball" then
		handle.Shape = Enum.PartType.Ball
	end
	handle.Parent = tool
	tool.Activated:Connect(function()
		consume(player, tool, itemId)
	end)
	return tool
end

local function giveTools(player: Player)
	local data = DataService.Get(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not data or not backpack then
		return
	end
	for _, t in backpack:GetChildren() do
		if t:IsA("Tool") and t:GetAttribute("ItemId") then
			t:Destroy()
		end
	end
	for _, id in data.inventory do
		local tool = makeTool(player, id)
		if tool then
			tool.Parent = backpack
		end
	end
end

local eating: { [Player]: number } = {}

consume = function(player: Player, tool: Tool, itemId: string)
	local data = DataService.Get(player)
	local it = Items.ById[itemId]
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not data or not it or (tool.Parent ~= player.Character and tool.Parent ~= backpack) then
		return
	end
	local now = os.clock()
	if eating[player] and now - eating[player] < 1.5 then
		return
	end
	local index = table.find(data.inventory, itemId)
	if not index then
		tool:Destroy()
		return
	end
	eating[player] = now
	table.remove(data.inventory, index)
	data.hunger = clamp(data.hunger + it.hunger)
	data.thirst = clamp(data.thirst + it.thirst)
	setAttrs(player, data)
	tool:Destroy()
	Remotes.Push(player, "Notify", { key = if it.thirst > it.hunger then "drank" else "ate", args = { it.name } })
	State.MarkDirty(player)
end

-- Gives a carried item for free (events / pickups). False if unknown or the bag is full.
function StoreService.Give(player: Player, itemId: string): boolean
	local data = DataService.Get(player)
	if not data or not Items.ById[itemId] or #data.inventory >= Items.MaxCarried then
		return false
	end
	table.insert(data.inventory, itemId)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = makeTool(player, itemId)
	if tool and backpack then
		tool.Parent = backpack
	end
	State.MarkDirty(player)
	return true
end

function StoreService.Start()
	DataService.Loaded:Connect(function(player, data)
		data.hunger = clamp(tonumber(data.hunger) or 100)
		data.thirst = clamp(tonumber(data.thirst) or 100)
		setAttrs(player, data)
		player.CharacterAdded:Connect(function(character)
			-- after dying from hunger/thirst you come back with a little left
			data.hunger = math.max(data.hunger, 30)
			data.thirst = math.max(data.thirst, 30)
			setAttrs(player, data)
			task.wait()
			giveTools(player)
			local _ = character
		end)
		if player.Character then
			giveTools(player)
		end
	end)

	-- eat / drink straight from the item panel
	Remotes.Handle("Item.Use", function(player, itemId: any)
		if typeof(itemId) ~= "string" or not Items.ById[itemId] then
			return Remotes.Fail("bad_item")
		end
		local backpack = player:FindFirstChildOfClass("Backpack")
		for _, container in { player.Character, backpack } do
			if container then
				for _, t in container:GetChildren() do
					if t:IsA("Tool") and t:GetAttribute("ItemId") == itemId then
						consume(player, t, itemId)
						return Remotes.Ok()
					end
				end
			end
		end
		return Remotes.Fail("not_owned")
	end, { rate = 6 })

	Remotes.Handle("Store.Buy", function(player, kind: any, itemId: any)
		local data = DataService.Get(player) :: { [string]: any }
		local price = typeof(kind) == "string" and typeof(itemId) == "string" and Items.Price(kind, itemId) or nil
		if not price then
			return Remotes.Fail("bad_item")
		end
		if not Interaction.IsNear(player, "Store", 16, "Store", kind) then
			return Remotes.Fail("not_near")
		end
		if #data.inventory >= Items.MaxCarried then
			return Remotes.Fail("inventory_full")
		end
		if
			not Economy.TrySpend(player, price, (Items.Stores[kind] :: any).title .. ": " .. Items.ById[itemId].name)
		then
			return Remotes.Fail("no_money")
		end
		table.insert(data.inventory, itemId)
		local backpack = player:FindFirstChildOfClass("Backpack")
		local tool = makeTool(player, itemId)
		if tool and backpack then
			tool.Parent = backpack
		end
		State.MarkDirty(player)
		return Remotes.Ok()
	end, { rate = 12 })

	-- hunger / thirst
	task.spawn(function()
		local hungerStep = 100 / (HUNGER_MINUTES * 60 / TICK)
		local thirstStep = 100 / (THIRST_MINUTES * 60 / TICK)
		while true do
			task.wait(TICK)
			for _, player in Players:GetPlayers() do
				local data = DataService.Get(player)
				local character = player.Character
				local hum = character and character:FindFirstChildOfClass("Humanoid")
				if data and hum and hum.Health > 0 and not player:GetAttribute("God") then
					data.hunger = clamp(data.hunger - hungerStep)
					data.thirst = clamp(data.thirst - thirstStep)
					setAttrs(player, data)
					if data.hunger <= 0 or data.thirst <= 0 then
						hum:TakeDamage(3)
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		eating[player] = nil
	end)
end

return StoreService
