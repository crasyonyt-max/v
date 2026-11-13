--!strict
-- Dropper "tycoon" in every player's apartment: up to 10 droppers over a conveyor
-- belt that drop cash into a collector. The first dropper is free, the next one can be
-- bought on the green pad. Money waits in the collector until the owner collects it.
-- Dropper events (DropEventService) multiply what the droppers make.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DropEvents = require(ReplicatedStorage.Shared.DropEvents)
local Locale = require(ReplicatedStorage.Shared.Locale)
local DataService = require(script.Parent.DataService)
local DropEventService = require(script.Parent.DropEventService)
local Economy = require(script.Parent.EconomyService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local TowerBuilder = require(script.Parent.TowerBuilder)

local DropperService = {}

local MAX = #Config.DropperCosts

local folder = Instance.new("Folder")
folder.Name = "Droppers"
folder.Parent = Workspace

type Tycoon = {
	model: Model,
	frame: CFrame,
	unit: number,
	label: TextLabel,
	info: TextLabel,
	belt: BasePart,
	last: { number },
	built: number,
}
local tycoons: { [Player]: Tycoon } = {}

-- dropper i sits at x = slotX(i) along the flat (local frame of the apartment)
local function slotX(i: number): number
	return 13 - (i - 1) * 4.4
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function count(data: { [string]: any }): number
	return math.clamp(math.floor(tonumber(data.droppers) or 0), 0, MAX)
end

function DropperService.Cost(i: number): number?
	return Config.DropperCosts[i]
end

function DropperService.Drop(i: number): number?
	return Config.DropperDrops[i]
end

local refresh: (Player) -> ()

-- prompt.Triggered:Connect, but quiet where prompts have no events (the Lune tests)
local function onTriggered(prompt: ProximityPrompt, fn: (Player) -> ())
	local ok, signal = pcall(function()
		return prompt.Triggered
	end)
	if ok and signal then
		signal:Connect(fn)
	end
end

local function dropperColor(i: number): Color3
	return Color3.fromHSV(((i - 1) / MAX) * 0.8, 0.7, 0.95)
end

local function buildDropper(t: Tycoon, i: number)
	local at = function(x: number, y: number, z: number): CFrame
		return t.frame * CFrame.new(x, y, z)
	end
	local x = slotX(i)
	local m = Instance.new("Model")
	m.Name = "Dropper" .. i
	part(m, "Leg", Vector3.new(0.8, 7.5, 0.8), at(x, 3.75, 3.4), Color3.fromRGB(60, 62, 66), Enum.Material.Metal)
	part(m, "Arm", Vector3.new(3, 1.8, 4), at(x, 8, 1.6), Color3.fromRGB(30, 30, 32), Enum.Material.Metal)
	local band = part(m, "Band", Vector3.new(3.1, 0.6, 4.1), at(x, 7.3, 1.6), dropperColor(i), Enum.Material.Neon)
	band.CanCollide = false
	part(m, "Nozzle", Vector3.new(1.4, 1, 1.4), at(x, 6.6, 0), Color3.fromRGB(45, 45, 48), Enum.Material.Metal)
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromOffset(110, 26)
	board.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	board.MaxDistance = 60
	board.Parent = band
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(120, 255, 120)
	l.TextStrokeTransparency = 0.3
	l.Text = Locale.Euro(Config.DropperDrops[i])
	l.Parent = board
	m.Parent = t.model
end

local function buildPad(t: Tycoon, player: Player, i: number)
	local old = t.model:FindFirstChild("BuyPad")
	if old then
		old:Destroy()
	end
	if i > MAX then
		return
	end
	local cost = Config.DropperCosts[i]
	local pad = part(
		t.model,
		"BuyPad",
		Vector3.new(3.4, 0.4, 3.4),
		t.frame * CFrame.new(slotX(i), 0.3, -4.2),
		Color3.fromRGB(40, 220, 80),
		Enum.Material.Neon
	)
	pad.CanCollide = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Dropper " .. i .. " kaufen"
	prompt.ObjectText = if cost == 0 then "Gratis" else Locale.Euro(cost)
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad
	onTriggered(prompt, function(who)
		if who ~= player then
			Remotes.Push(who, "Notify", { key = "dropper_not_yours", error = true })
			return
		end
		local ok, err = DropperService.Buy(player)
		if not ok and err then
			Remotes.Push(player, "Notify", { key = err, error = true })
		end
	end)
end

-- Buys the next dropper (the one on the pad).
function DropperService.Buy(player: Player): (boolean, string?)
	local data = DataService.Get(player)
	if not data then
		return false, nil
	end
	local i = count(data) + 1
	if i > MAX then
		return false, "dropper_max"
	end
	local cost = Config.DropperCosts[i]
	if cost > 0 and not Economy.TrySpend(player, cost, "Dropper " .. i) then
		return false, "no_money"
	end
	data.droppers = i
	State.MarkDirty(player)
	Remotes.Push(player, "Notify", { key = "dropper_bought", args = { i, Locale.Euro(Config.DropperDrops[i]) } })
	refresh(player)
	return true, nil
end

local function updateLabel(t: Tycoon, data: { [string]: any })
	t.label.Text = "💶 " .. Locale.Euro(tonumber(data.dropCash) or 0)
	local id = DropEventService.Current()
	local e = id and DropEvents.ById[id]
	t.info.Text = string.format("Dropper %d/%d", count(data), MAX)
		.. (if e then string.format("  ·  %s %d%% x%g", e.icon, math.floor(e.chance * 100 + 0.5), e.mult) else "")
end

local function destroy(player: Player)
	local t = tycoons[player]
	if t then
		t.model:Destroy()
		tycoons[player] = nil
	end
end

local enabled = true -- AA can switch the tycoons off for everyone (EventService)

local function build(player: Player)
	destroy(player)
	local data = DataService.Get(player)
	local n = player:GetAttribute("Apartment")
	if not enabled or not data or typeof(n) ~= "number" then
		return
	end
	local unit = nil
	for _, u in TowerBuilder.Units do
		if u.number == n then
			unit = u
		end
	end
	if not unit or not unit.frame then
		return
	end
	if count(data) == 0 then
		data.droppers = 1 -- the first one is free
		State.MarkDirty(player)
	end
	local frame = unit.frame :: CFrame
	local model = Instance.new("Model")
	model.Name = "Tycoon_" .. player.UserId
	local at = function(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	-- conveyor: moves the dropped cash towards the collector (local -X)
	local belt = part(
		model,
		"Belt",
		Vector3.new(44, 1, 3),
		at(-6.5, 0.6, 0),
		Color3.fromRGB(35, 35, 38),
		Enum.Material.DiamondPlate
	)
	belt.AssemblyLinearVelocity = frame:VectorToWorldSpace(Vector3.new(-12, 0, 0))
	for _, z in { -1.7, 1.7 } do
		part(
			model,
			"Rail",
			Vector3.new(44, 1.2, 0.4),
			at(-6.5, 1.2, z),
			Color3.fromRGB(200, 200, 205),
			Enum.Material.Metal
		)
	end
	local collector = part(model, "Collector", Vector3.new(4, 3, 4.6), at(-31, 1.5, 0), Color3.fromRGB(240, 240, 240))
	part(
		model,
		"CollectorTop",
		Vector3.new(4.2, 0.4, 4.8),
		at(-31, 3.1, 0),
		Color3.fromRGB(40, 220, 80),
		Enum.Material.Neon
	).CanCollide =
		false
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromOffset(200, 64)
	board.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	board.MaxDistance = 80
	board.Parent = collector
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.62)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(120, 255, 120)
	label.TextStrokeTransparency = 0.2
	label.Parent = board
	local info = Instance.new("TextLabel")
	info.Position = UDim2.fromScale(0, 0.62)
	info.Size = UDim2.fromScale(1, 0.38)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.GothamBold
	info.TextScaled = true
	info.TextColor3 = Color3.new(1, 1, 1)
	info.TextStrokeTransparency = 0.3
	info.Parent = board
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Einsammeln"
	prompt.ObjectText = "Dropper-Kasse"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = collector
	onTriggered(prompt, function(who)
		if who ~= player then
			Remotes.Push(who, "Notify", { key = "dropper_not_yours", error = true })
			return
		end
		DropperService.Collect(player)
	end)

	local t: Tycoon = {
		model = model,
		frame = frame,
		unit = n,
		label = label,
		info = info,
		belt = belt,
		last = {},
		built = 0,
	}
	tycoons[player] = t
	model.Parent = folder
	refresh(player)
end

refresh = function(player: Player)
	local t = tycoons[player]
	local data = DataService.Get(player)
	if not t or not data then
		return
	end
	for i = t.built + 1, count(data) do
		buildDropper(t, i)
		t.last[i] = os.clock() + i * 2 - DropperService.INTERVAL -- first drops come quickly, staggered
	end
	t.built = count(data)
	buildPad(t, player, count(data) + 1)
	updateLabel(t, data)
end

DropperService.INTERVAL = Config.DropInterval

function DropperService.Collect(player: Player): number
	local data = DataService.Get(player)
	local amount = data and math.floor((tonumber(data.dropCash) or 0) * 100) / 100 or 0
	if not data or amount <= 0 then
		return 0
	end
	data.dropCash = 0
	Economy.Add(player, amount, "Dropper")
	Remotes.Push(player, "Notify", { key = "dropper_collected", args = { Locale.Euro(amount) } })
	local t = tycoons[player]
	if t then
		updateLabel(t, data)
	end
	return amount
end

-- One drop of dropper i: its value, and whether the running event hit it.
function DropperService.Value(i: number, random: Random?): (number, boolean)
	local mult, hit = DropEventService.Hit(random)
	return (Config.DropperDrops[i] or 0) * mult, hit
end

-- Turns the tycoons on / off for everyone (money waiting in collectors is kept).
function DropperService.SetEnabled(on: boolean)
	if on == enabled then
		return
	end
	enabled = on
	for _, player in Players:GetPlayers() do
		if on then
			task.spawn(build, player)
		else
			destroy(player)
		end
	end
end

function DropperService.Enabled(): boolean
	return enabled
end

-- The cash you see falling onto the belt (the money itself is booked right away).
-- Capped per apartment: droppers drop every second.
local MAX_VISIBLE = 24
local function dropCash(t: Tycoon, i: number, value: number, hit: boolean)
	local alive = 0
	for _, c in t.model:GetChildren() do
		if c.Name == "Cash" then
			alive += 1
		end
	end
	if alive >= MAX_VISIBLE and not hit then
		return
	end
	local cash = Instance.new("Part")
	cash.Name = "Cash"
	cash.Size = if hit then Vector3.new(1.5, 0.5, 0.9) else Vector3.new(1.2, 0.35, 0.7)
	cash.CFrame = t.frame * CFrame.new(slotX(i), 5.6, 0)
	cash.Color = if hit then Color3.fromRGB(255, 205, 40) else Color3.fromRGB(70, 200, 90)
	cash.Material = if hit then Enum.Material.Neon else Enum.Material.SmoothPlastic
	cash.CanTouch = false
	cash.CanQuery = false
	cash.Parent = t.model
	if hit then
		local board = Instance.new("BillboardGui")
		board.Size = UDim2.fromOffset(90, 26)
		board.StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0)
		board.MaxDistance = 60
		board.Parent = cash
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBlack
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(255, 220, 60)
		l.TextStrokeTransparency = 0.2
		l.Text = "+" .. Locale.Euro(value)
		l.Parent = board
	end
	pcall(function()
		cash:SetNetworkOwner(nil)
	end)
	task.delay(5, function()
		if cash.Parent then
			cash:Destroy()
		end
	end)
end

DropperService._build = function(player: Player)
	build(player)
end
DropperService._tycoon = function(player: Player)
	return tycoons[player]
end

function DropperService.Start()
	local function watch(player: Player)
		player:GetAttributeChangedSignal("Apartment"):Connect(function()
			task.defer(build, player)
		end)
		if player:GetAttribute("Apartment") then
			task.defer(build, player)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerRemoving:Connect(destroy)

	-- drops
	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = os.clock()
			for player, t in tycoons do
				local data = DataService.Get(player)
				if data and t.model.Parent then
					local changed = false
					for i = 1, count(data) do
						if now - (t.last[i] or 0) >= DropperService.INTERVAL then
							-- keep an exact pace (every INTERVAL), but never catch up a long gap
							local last = (t.last[i] or now) + DropperService.INTERVAL
							t.last[i] = if now - last > DropperService.INTERVAL * 3 then now else last
							local value, hit = DropperService.Value(i)
							data.dropCash = (tonumber(data.dropCash) or 0) + value
							dropCash(t, i, value, hit)
							changed = true
						end
					end
					if changed then
						updateLabel(t, data)
					end
				end
			end
		end
	end)
	-- the event shown on the collectors
	task.spawn(function()
		local shown: string? = nil
		while true do
			task.wait(2)
			local now = DropEventService.Current()
			if now ~= shown then
				shown = now
				for player, t in tycoons do
					local data = DataService.Get(player)
					if data then
						updateLabel(t, data)
					end
				end
			end
		end
	end)
end

return DropperService
