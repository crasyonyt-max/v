--!strict
-- Thanksgiving event (Shared/Thanksgiving): every 2 minutes 1–10 turkeys on the server,
-- on random streets and in parks, while the AA dropper event "thanksgiving" runs; collect them (carried item,
-- fits in the trunk) and bake them in an oven (Swedea furniture) for a roast and a
-- random bonus: an item, XP or cash.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Items = require(ReplicatedStorage.Shared.Items)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Locations = require(ReplicatedStorage.Shared.Locations)
local TG = require(ReplicatedStorage.Shared.Thanksgiving)
local DropEventService = require(script.Parent.DropEventService)
local Economy = require(script.Parent.EconomyService)
local GameLog = require(script.Parent.GameLog)
local Remotes = require(script.Parent.Remotes)
local StoreService = require(script.Parent.StoreService)
local XPService = require(script.Parent.XPService)

local ThanksgivingService = {}

local rng = Random.new()
local folder: Folder? = nil
local alive: { [Model]: number } = {} -- turkey -> despawn time

local function notify(player: Player, key: string, args: { any }?)
	Remotes.Push(player, "Notify", { key = key, args = args })
end

local function turkeyFolder(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "Turkeys"
		f.Parent = Workspace
		folder = f
	end
	return folder :: Folder
end

function ThanksgivingService.Active(): boolean
	return DropEventService.Current() == TG.EVENT
end

-- ground below a point (ignores characters and the turkeys)
local function ground(x: number, z: number, fromY: number): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { turkeyFolder() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then
		table.insert(ignore, vehicles)
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(Vector3.new(x, fromY + 60, z), Vector3.new(0, -160, 0), params)
	if not hit or hit.Material == Enum.Material.Water or hit.Normal.Y < 0.7 then
		return nil
	end
	return hit.Position
end

local function remove(t: Model)
	alive[t] = nil
	if t.Parent then
		t:Destroy()
	end
end

local function collect(player: Player, t: Model)
	if alive[t] == nil or t:GetAttribute("Taken") then
		return
	end
	t:SetAttribute("Taken", true)
	if not StoreService.Give(player, TG.ALIVE) then
		t:SetAttribute("Taken", nil)
		notify(player, "turkey_bag_full")
		return
	end
	remove(t)
	notify(player, "turkey_collected")
end

local function spawnTurkey(pos: Vector3)
	local t = TG.BuildTurkey(false)
	local body = t.PrimaryPart :: BasePart
	-- everything follows the body (anchored), so moving the body moves the turkey
	for _, p in t:GetDescendants() do
		if p:IsA("BasePart") and p ~= body then
			p.Anchored = false
			p.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = body
			w.Part1 = p
			w.Parent = p
		end
	end
	t:PivotTo(CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Collect"
	prompt.ActionText = "Einsammeln"
	prompt.ObjectText = "🦃 Truthahn"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	pcall(function()
		prompt.Triggered:Connect(function(player)
			collect(player, t)
		end)
	end)
	t.Parent = turkeyFolder()
	alive[t] = os.time() + TG.LIFETIME
end

-- a random spot on a street (road / pavement) or in a park (grass area) of the city
local function cityFolders(): (Instance?, Instance?, Instance?)
	local city = Workspace:FindFirstChild("City")
	if not city then
		return nil, nil, nil
	end
	return city:FindFirstChild("Roads"), city:FindFirstChild("Pavements"), city:FindFirstChild("Areas")
end

function ThanksgivingService.RandomSpot(): Vector3?
	local roads, walks, areas = cityFolders()
	if not roads and not areas then
		return nil
	end
	local b = Locations.Bounds
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { turkeyFolder() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then
		table.insert(ignore, vehicles)
	end
	params.FilterDescendantsInstances = ignore
	for _ = 1, 80 do
		local x, z = rng:NextNumber(b[1], b[3]), rng:NextNumber(b[2], b[4])
		local hit = Workspace:Raycast(Vector3.new(x, 1500, z), Vector3.new(0, -3000, 0), params)
		local inst = hit and hit.Instance
		if inst and hit.Normal.Y > 0.8 then
			local street = (roads and inst:IsDescendantOf(roads)) or (walks and inst:IsDescendantOf(walks))
			local park = areas and inst:IsDescendantOf(areas) and inst.Material == Enum.Material.Grass
			if street or park then
				return hit.Position
			end
		end
	end
	return nil
end

-- one wave: the old turkeys walk off, 1–10 new ones appear somewhere in the city
-- (on a street or in a park) – that's for the whole server
function ThanksgivingService.SpawnWave(): number
	for t in alive do
		remove(t)
	end
	local want = rng:NextInteger(TG.SPAWN_MIN, TG.SPAWN_MAX)
	local made = 0
	for _ = 1, want * 2 do
		if made >= want then
			break
		end
		local pos = ThanksgivingService.RandomSpot()
		if pos then
			spawnTurkey(pos)
			made += 1
		end
	end
	return made
end

-- turkeys strut around a little
local function wander()
	for t in alive do
		local body = t.PrimaryPart
		if body and not t:GetAttribute("Taken") and rng:NextNumber() < 0.6 then
			local from = t:GetPivot()
			local a = rng:NextNumber(0, math.pi * 2)
			local step = rng:NextNumber(1.5, 4)
			local to = from.Position + Vector3.new(math.cos(a) * step, 0, math.sin(a) * step)
			local g = ground(to.X, to.Z, from.Position.Y)
			if g and math.abs(g.Y - from.Position.Y) < 3 then
				local target = CFrame.lookAt(g, g + (g - from.Position) * Vector3.new(1, 0, 1))
				local offset = from:ToObjectSpace(body.CFrame)
				TweenService:Create(body, TweenInfo.new(1.2, Enum.EasingStyle.Sine), { CFrame = target * offset })
					:Play()
			end
		end
	end
end

-- Oven -----------------------------------------------------------------------------------

local function bonus(player: Player): string
	local pick = rng:NextInteger(1, 3)
	if pick == 1 then
		local pool = {}
		for _, it in Items.List do
			if not it.event then
				table.insert(pool, it)
			end
		end
		local it = pool[rng:NextInteger(1, #pool)]
		if it and StoreService.Give(player, it.id) then
			return it.name
		end
		pick = 3 -- bag full: cash instead
	end
	if pick == 2 then
		local xp = rng:NextInteger(TG.XP[1], TG.XP[2])
		XPService.Add(player, nil, xp, "Thanksgiving: Truthahn gebacken")
		return xp .. " XP"
	end
	local cash = rng:NextInteger(TG.CASH[1], TG.CASH[2])
	Economy.Add(player, cash, "Thanksgiving: Truthahn gebacken")
	return Locale.Euro(cash)
end

local function bake(player: Player, oven: Model)
	if oven:GetAttribute("Baking") then
		notify(player, "oven_busy")
		return
	end
	if not StoreService.Take(player, TG.ALIVE) then
		notify(player, "turkey_need")
		return
	end
	oven:SetAttribute("Baking", true)
	local glow = oven:FindFirstChild("Glow", true) :: BasePart?
	local light = glow and glow:FindFirstChild("BakeLight") :: PointLight?
	local function setGlow(on: boolean)
		if glow then
			glow.Transparency = if on then 0.3 else 1
		end
		if light then
			light.Enabled = on
		end
	end
	-- the turkey sits in the oven (seen through the window) and turns into a roast
	local spot = if glow then glow.CFrame * CFrame.new(0, 0.05, 0) else oven:GetPivot() + Vector3.new(0, 1.5, 0)
	local inside = TG.BuildTurkey(false, 0.42)
	inside:PivotTo(spot)
	inside.Parent = oven
	setGlow(true)
	notify(player, "turkey_baking", { TG.BAKE_SECONDS })
	task.delay(TG.BAKE_SECONDS, function()
		inside:Destroy()
		local roast = TG.BuildTurkey(true, 0.42)
		roast:PivotTo(spot)
		roast.Parent = oven
		setGlow(false)
		local extra = "?"
		if player.Parent then
			StoreService.Give(player, TG.BAKED)
			extra = bonus(player)
			notify(player, "turkey_baked", { extra })
		end
		GameLog.Add("event", player, "Truthahn gebacken: " .. extra)
		task.delay(4, function()
			roast:Destroy()
			oven:SetAttribute("Baking", nil)
		end)
	end)
end

-- called by FurnitureService for every placed oven
function ThanksgivingService.EquipOven(oven: Model)
	local hit = oven:FindFirstChild("Hitbox") :: BasePart? or oven.PrimaryPart
	if not hit then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Bake"
	prompt.ActionText = "Truthahn backen"
	prompt.ObjectText = "🦃 Backofen"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = hit
	pcall(function()
		prompt.Triggered:Connect(function(player)
			bake(player, oven)
		end)
	end)
end

function ThanksgivingService.Start()
	task.spawn(function()
		local nextWave = os.time() + 5
		while true do
			task.wait(3)
			local now = os.time()
			if ThanksgivingService.Active() then
				if now >= nextWave then
					nextWave = now + TG.SPAWN_EVERY
					ThanksgivingService.SpawnWave()
				end
				wander()
			else
				nextWave = now + 5 -- first wave right after the event starts
			end
			-- event over or walked off: gone
			for t, ends in alive do
				if now >= ends or not ThanksgivingService.Active() then
					remove(t)
				end
			end
		end
	end)
end

return ThanksgivingService
