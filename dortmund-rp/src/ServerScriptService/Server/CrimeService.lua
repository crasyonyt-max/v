--!strict
-- V1.0 crime.
--   * robberies: civilians (not Police / Fire / Rettungsdienst / Notarzt on duty) rob
--     a store till ("Ausrauben"): stay there Config.RobberySeconds, the money goes to
--     the bank as stolen money, the police get an alert
--   * a robbery or shooting someone makes you a criminal ("GESUCHT") for
--     Config.CriminalSeconds; every new crime starts the time again (4:12 -> 5:00)
--   * Police arrest criminals ("Festnehmen") or shoot them: prison for
--     Config.JailSeconds and the stolen money is gone; the officer gets a reward
--   * when the wanted time runs out you are free and keep the money

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local Jobs = require(ReplicatedStorage.Shared.Jobs)
local Locations = require(ReplicatedStorage.Shared.Locations)
local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local GameLog = require(script.Parent.GameLog)
local Interaction = require(script.Parent.InteractionService)
local JobService = require(script.Parent.JobService)
local PrisonService = require(script.Parent.PrisonService)
local Remotes = require(script.Parent.Remotes)
local XPService = require(script.Parent.XPService)

local CrimeService = {}

type Wanted = { untilT: number, stolen: number }
local wanted: { [Player]: Wanted } = {}
local jailed: { [Player]: number } = {} -- release time
local robbing: { [Player]: boolean } = {}
local storeCooldown: { [BasePart]: number } = {}
CrimeService.Wanted = wanted
CrimeService.Jailed = jailed

local function now(): number
	return os.time()
end

-- Rules ---------------------------------------------------------------------------------

function CrimeService.IsPolice(p: Player): boolean
	return JobService.Get(p) == "Police"
end

-- civilians: no emergency job on duty
function CrimeService.IsCivil(p: Player): boolean
	local job = Jobs.ById[JobService.Get(p)]
	return not (job and job.emergency)
end

function CrimeService.IsCriminal(p: Player): boolean
	local w = wanted[p]
	return w ~= nil and w.untilT > now()
end

function CrimeService.IsJailed(p: Player): boolean
	return (jailed[p] or 0) > now()
end

local function setAttrs(p: Player)
	local w = wanted[p]
	p:SetAttribute("CriminalUntil", if w then w.untilT else nil)
	p:SetAttribute("JailedUntil", jailed[p])
end

-- a crime: wanted (again) for the full time
function CrimeService.Crime(p: Player, reason: string)
	if not Config.V10 or CrimeService.IsJailed(p) then
		return
	end
	local w = wanted[p]
	local first = w == nil
	if not w then
		w = { untilT = 0, stolen = 0 }
		wanted[p] = w
	end
	w.untilT = now() + Config.CriminalSeconds
	setAttrs(p)
	GameLog.Add("crime", p, reason)
	Remotes.Push(p, "Notify", { key = if first then "crime_wanted" else "crime_wanted_again", error = true })
end

local function alertPolice(text: string, pos: Vector3?)
	for _, cop in Players:GetPlayers() do
		if CrimeService.IsPolice(cop) then
			Remotes.Push(cop, "CrimeAlert", { text = text, pos = pos })
		end
	end
end

-- Prison --------------------------------------------------------------------------------

local function toCell(p: Player)
	local cells = PrisonService.Cells
	local c = p.Character
	if c and #cells > 0 then
		c:PivotTo(cells[math.random(1, #cells)])
	end
end

-- arrested (or shot by the police): prison, stolen money gone
function CrimeService.Jail(p: Player, officer: Player?)
	local w = wanted[p]
	local stolen = if w then w.stolen else 0
	local lost = 0
	if stolen > 0 then
		lost = math.min(stolen, Economy.Balance(p))
		if lost > 0 then
			Economy.TrySpend(p, lost, "Beute beschlagnahmt")
		end
	end
	wanted[p] = nil
	jailed[p] = now() + Config.JailSeconds
	setAttrs(p)
	toCell(p)
	Remotes.Push(
		p,
		"Notify",
		{ key = "crime_jailed", args = { Config.JailSeconds // 60, math.floor(lost) }, error = true }
	)
	if officer then
		Economy.Earn(officer, Config.ArrestReward, "Festnahme: " .. p.Name)
		pcall(XPService.Earn, officer, "Police", 50, "Festnahme")
		Remotes.Push(officer, "Notify", { key = "crime_arrest_done", args = { p.DisplayName } })
	end
	GameLog.Add("crime", p, ("jailed by %s, %d € stolen money taken"):format(officer and officer.Name or "?", lost))
end

-- Robbery -------------------------------------------------------------------------------

local function storeName(marker: BasePart): string
	return tostring(marker:GetAttribute("ObjectText") or "Laden")
end

function CrimeService.StartRobbery(p: Player, marker: BasePart): (boolean, string?)
	if not Config.V10 then
		return false, "bad_request"
	end
	if not CrimeService.IsCivil(p) then
		return false, "crime_not_civil"
	end
	if robbing[p] or CrimeService.IsJailed(p) then
		return false, "bad_request"
	end
	if (storeCooldown[marker] or 0) > now() then
		return false, "crime_store_empty"
	end
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - marker.Position).Magnitude > 14 then
		return false, "too_far"
	end
	robbing[p] = true
	storeCooldown[marker] = now() + Config.RobberyCooldown
	CrimeService.Crime(p, "robbery " .. storeName(marker))
	alertPolice("🚨 Raubüberfall: " .. storeName(marker), marker.Position)
	Remotes.Push(p, "Robbery", { seconds = Config.RobberySeconds, store = storeName(marker) })
	task.spawn(function()
		local t0 = os.clock()
		local ok = true
		while os.clock() - t0 < Config.RobberySeconds do
			task.wait(0.5)
			local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if not p.Parent or not r or not hum or hum.Health <= 0 or CrimeService.IsJailed(p) then
				ok = false
				break
			end
			if (r.Position - marker.Position).Magnitude > 20 then
				ok = false
				break
			end
		end
		robbing[p] = nil
		if not ok then
			if p.Parent then
				Remotes.Push(p, "Notify", { key = "crime_robbery_failed", error = true })
				Remotes.Push(p, "Robbery", { seconds = 0 })
			end
			return
		end
		local amount = math.random(Config.RobberyMoney[1], Config.RobberyMoney[2])
		Economy.Add(p, amount, "Raub: " .. storeName(marker))
		local w = wanted[p]
		if w then
			w.stolen += amount
		end
		CrimeService.Crime(p, ("robbed %s for %d €"):format(storeName(marker), amount))
		Remotes.Push(p, "Notify", { key = "crime_robbery_done", args = { amount } })
		Remotes.Push(p, "Robbery", { seconds = 0 })
	end)
	return true, nil
end

-- Black market (pistol for civilians) + robbery prompts on every store till -----------

local function robPrompt(marker: BasePart)
	if marker:FindFirstChild("Rob") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Rob"
	prompt.ActionText = "Ausrauben"
	prompt.ObjectText = storeName(marker)
	prompt.HoldDuration = 1.5
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, 80)
	prompt.Parent = marker
	pcall(function()
		prompt.Triggered:Connect(function(p)
			local ok, err = CrimeService.StartRobbery(p, marker)
			if not ok and err then
				Remotes.Push(p, "Notify", { key = err, error = true })
			end
		end)
	end)
end

function CrimeService.Build()
	if not Config.V10 then
		return
	end
	-- every store till (city stores + Mall) can be robbed
	for _, marker in CollectionService:GetTagged("Interaction") do
		if marker:IsA("BasePart") and marker:GetAttribute("Interaction") == "Shop" then
			local ui = marker:GetAttribute("UI")
			if typeof(ui) == "string" and (Items.Stores :: any)[ui] then
				robPrompt(marker)
			end
		end
	end
	-- the black market: a dealer in a dark corner behind the Dortmund Tower
	local site = (Locations.Sites :: any).Tower
	if site then
		local base = CFrame.new(site.x, 0, site.z)
			* CFrame.Angles(0, math.rad(site.yaw), 0)
			* CFrame.new(0, 0, site.depth / 2 + 14)
		local y = CityBuilder.GroundY(base.Position.X, base.Position.Z)
		local m = Instance.new("Model")
		m.Name = "Schwarzmarkt"
		local function part(name: string, size: Vector3, cf: CFrame, color: Color3): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored = true
			p.Size = size
			p.CFrame = cf
			p.Color = color
			p.Material = Enum.Material.Metal
			p.Parent = m
			return p
		end
		local at = CFrame.new(base.Position.X, y, base.Position.Z) * (base - base.Position)
		part("Van", Vector3.new(8, 8, 16), at * CFrame.new(0, 4.3, 0), Color3.fromRGB(30, 30, 34))
		part("Crate", Vector3.new(4, 3, 4), at * CFrame.new(-7, 1.5, -4), Color3.fromRGB(90, 70, 45))
		local marker =
			part("Marker_Blackmarket", Vector3.new(3, 3, 3), at * CFrame.new(-6, 2.5, -8), Color3.new(1, 1, 1))
		marker.Transparency = 1
		marker.CanCollide = false
		Interaction.Mark(marker, "Shop", { UI = "Blackmarket", ActionText = "Ware ansehen", ObjectText = "???" })
		m.Parent = Workspace
	end
end

-- Remotes + loops ----------------------------------------------------------------------------

function CrimeService.Start()
	if not Config.V10 then
		return
	end
	-- wanted time running out, prisoners staying inside
	task.spawn(function()
		while true do
			task.wait(1)
			local t = now()
			for p, w in wanted do
				if w.untilT <= t then
					wanted[p] = nil
					setAttrs(p)
					if p.Parent then
						Remotes.Push(p, "Notify", { key = "crime_free" })
					end
				end
			end
			for p, untilT in jailed do
				if not p.Parent then
					jailed[p] = nil
				elseif untilT <= t then
					jailed[p] = nil
					setAttrs(p)
					local c = p.Character
					if c and PrisonService.Exit then
						c:PivotTo(PrisonService.Exit)
					end
					Remotes.Push(p, "Notify", { key = "crime_released" })
				else
					local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if root and PrisonService.Bounds and not PrisonService.Inside(root.Position) then
						toCell(p)
					end
				end
			end
		end
	end)
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			if CrimeService.IsJailed(p) then
				task.wait(0.5)
				toCell(p)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(p)
		wanted[p] = nil
		jailed[p] = nil
		robbing[p] = nil
	end)

	-- Police: arrest a criminal standing next to you
	Remotes.Handle("Crime.Arrest", function(player, userId: any)
		local target = Players:GetPlayerByUserId(Remotes.Check.Int(userId, 1, 1e12) or 0)
		if not target or not CrimeService.IsPolice(player) then
			return Remotes.Fail("no_permission")
		end
		if not CrimeService.IsCriminal(target) then
			return Remotes.Fail("crime_not_wanted")
		end
		local a = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local b = target.Character and target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not a or not b or (a.Position - b.Position).Magnitude > 12 then
			return Remotes.Fail("too_far")
		end
		CrimeService.Jail(target, player)
		return Remotes.Ok()
	end, { rate = 4 })

	-- black market purchases: WeaponService ("Weapon.Buy")
end

return CrimeService
