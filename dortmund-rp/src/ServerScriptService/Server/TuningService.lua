--!strict
-- Update 2 (Config.Update2, testing server first): tuning shop at the Autohaus for your
-- own cars (saved on the car, applied every time it is spawned):
--   engine stage 1 / 2 (+15 % / +30 % power), tinted windows, rim colour, underglow

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Locations = require(ReplicatedStorage.Shared.Locations)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local Interaction = require(script.Parent.InteractionService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local TuningService = {}

TuningService.Prices = { engine1 = 8000, engine2 = 20000, tint = 2500, rims = 1500, neon = 3000 }
TuningService.Power = { [0] = 1, [1] = 1.15, [2] = 1.3 }

local function palette(i: any): Color3?
	local rgb = Vehicles.Palette[tonumber(i) or 0]
	return rgb and Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- puts a car's tuning on its model (also when it is spawned)
function TuningService.Apply(model: Model, tune: { [string]: any }?)
	if not tune then
		return
	end
	local stage = tonumber(tune.engine) or 0
	if stage > 0 then
		local base = tonumber(model:GetAttribute("BasePower")) or tonumber(model:GetAttribute("Power"))
		if base then
			model:SetAttribute("BasePower", base)
			model:SetAttribute("Power", base * (TuningService.Power[stage] or 1))
		end
	end
	local rims = palette(tune.rims)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if tune.tint and d.Material == Enum.Material.Glass then
				d.Color = Color3.fromRGB(18, 18, 22)
				d.Transparency = math.min(d.Transparency, 0.15)
			end
			if rims and (d.Name == "Rim" or d.Name == "Spoke") then
				d.Color = rims
			end
		end
	end
	local neon = palette(tune.neon)
	local chassis = model:FindFirstChild("Chassis") :: BasePart?
	local old = model:FindFirstChild("Underglow")
	if old then
		old:Destroy()
	end
	if neon and chassis then
		local cf, size = model:GetBoundingBox()
		local glow = Instance.new("Part")
		glow.Name = "Underglow"
		glow.Size = Vector3.new(size.X * 0.7, 0.1, size.Z * 0.75)
		glow.CFrame = cf * CFrame.new(0, -size.Y / 2 + 0.35, 0)
		glow.Color = neon
		glow.Material = Enum.Material.Neon
		glow.Transparency = 0.25
		glow.CanCollide = false
		glow.CanQuery = false
		glow.CanTouch = false
		glow.Massless = true
		glow.Anchored = false
		local light = Instance.new("PointLight")
		light.Color = neon
		light.Range = 12
		light.Brightness = 2
		light.Parent = glow
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = chassis
		weld.Part1 = glow
		weld.Parent = glow
		glow.Parent = model
	end
end

local function spawnedOf(player: Player, uid: string): Model?
	local folder = Workspace:FindFirstChild("Vehicles")
	for _, m in (if folder then folder:GetChildren() else {}) do
		if m:IsA("Model") and m:GetAttribute("OwnerId") == player.UserId and m:GetAttribute("Uid") == uid then
			return m
		end
	end
	return nil
end

function TuningService.Start()
	if not Config.On(Config.Update2) then
		return
	end
	-- the tuning garage next to the Autohaus
	local dealer = (Locations.Shops :: any).Dealership
	if dealer then
		local a = math.rad(dealer.angle or 0)
		local x, z =
			dealer.marker[1] - math.cos(a + math.pi / 2) * 24, dealer.marker[2] - math.sin(a + math.pi / 2) * 24
		local y = CityBuilder.GroundY(x, z)
		local marker = Instance.new("Part")
		marker.Name = "Marker_Tuning"
		marker.Anchored = true
		marker.CanCollide = false
		marker.Shape = Enum.PartType.Cylinder
		marker.Size = Vector3.new(0.15, 9, 9)
		marker.CFrame = CFrame.new(x, y + 0.1, z) * CFrame.Angles(0, 0, math.pi / 2)
		marker.Color = Color3.fromRGB(200, 40, 200)
		marker.Material = Enum.Material.Neon
		marker.Transparency = 0.45
		marker.Parent = Workspace
		Interaction.Mark(marker, "Shop", { UI = "Tuning", ActionText = "Auto tunen", ObjectText = "Tuning" })
	end

	-- spawned cars get their tuning
	local function watch(folder: Instance)
		folder.ChildAdded:Connect(function(m)
			task.defer(function()
				if not m:IsA("Model") then
					return
				end
				local owner = Players:GetPlayerByUserId(tonumber(m:GetAttribute("OwnerId")) or 0)
				local data = owner and DataService.Get(owner)
				local entry = data and data.vehicles[tostring(m:GetAttribute("Uid"))]
				if entry and entry.tune then
					TuningService.Apply(m, entry.tune)
				end
			end)
		end)
	end
	local folder = Workspace:FindFirstChild("Vehicles")
	if folder then
		watch(folder)
	else
		Workspace.ChildAdded:Connect(function(c)
			if c.Name == "Vehicles" then
				watch(c)
			end
		end)
	end

	-- kind: "engine1" | "engine2" | "tint" | "rims" | "neon"; value = palette index
	Remotes.Handle("Tuning.Buy", function(player, uid: any, kind: any, value: any)
		local data = DataService.Get(player)
		local entry = data and typeof(uid) == "string" and data.vehicles[uid] or nil
		local price = typeof(kind) == "string" and TuningService.Prices[kind] or nil
		if not entry or not price then
			return Remotes.Fail("bad_request")
		end
		local def = Vehicles.ById[entry.id]
		if not def or not def.car then
			return Remotes.Fail("tuning_cars_only")
		end
		if not Interaction.IsNear(player, "Shop", 25, "UI", "Tuning") then
			return Remotes.Fail("too_far")
		end
		local tune = entry.tune or {}
		if kind == "engine1" and (tune.engine or 0) >= 1 or kind == "engine2" and (tune.engine or 0) >= 2 then
			return Remotes.Fail("already_owned")
		end
		if kind == "engine2" and (tune.engine or 0) < 1 then
			return Remotes.Fail("tuning_stage1_first")
		end
		if kind == "tint" and tune.tint then
			return Remotes.Fail("already_owned")
		end
		if (kind == "rims" or kind == "neon") and not palette(value) then
			return Remotes.Fail("bad_request")
		end
		if not Economy.TrySpend(player, price, "Tuning") then
			return Remotes.Fail("no_money")
		end
		if kind == "engine1" then
			tune.engine = 1
		elseif kind == "engine2" then
			tune.engine = 2
		elseif kind == "tint" then
			tune.tint = true
		else
			tune[kind] = tonumber(value)
		end
		entry.tune = tune
		State.MarkDirty(player)
		local m = spawnedOf(player, uid)
		if m then
			TuningService.Apply(m, tune)
		end
		return Remotes.Ok()
	end, { rate = 5 })
end

return TuningService
