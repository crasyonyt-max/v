--!strict
-- V1.0 weapons, checked by the server:
--   * Police on duty: service pistol; civilians: what they bought at the black market
--   * draw / holster (Weapon.Equip), pick (Weapon.Select), shoot / throw (Weapon.Fire),
--     reload (Weapon.Reload), buy (Weapon.Buy, black market, civilians only)
--   * the server traces every shot itself, with fire rate, magazine and range limits
--   * Police only hurt criminals; anyone else who hurts a person commits a crime
--     (wanted again for the full time); a criminal killed by the police goes to prison
-- Config.Guns2 ("test" = testing server only): the weapon is a real model held like a
-- tool (shots leave the muzzle), plus the AK-47 (automatic), the sniper rifle (scope)
-- and grenades (thrown, explode after the fuse; no damage to the map or cars).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local CrimeService = require(script.Parent.CrimeService)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local GameLog = require(script.Parent.GameLog)
local Interaction = require(script.Parent.InteractionService)
local JobService = require(script.Parent.JobService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local WeaponService = {}

type St = { ammo: { [string]: number }, lastShot: number, reloading: boolean }
local states: { [Player]: St } = {}
local lastHitBy: { [Player]: { by: Player, t: number } } = {}

local function newOn(): boolean
	return Config.On(Config.Guns2)
end

local function weaponOf(p: Player): Weapons.Weapon?
	local id = p:GetAttribute("Weapon")
	return if typeof(id) == "string" then Weapons.ById[id] else nil
end
WeaponService.WeaponOf = weaponOf

-- owned weapons in the save: data.weapons = { [id] = true }, data.grenades = count
local function owned(data: { [string]: any }): { [string]: boolean }
	data.weapons = if typeof(data.weapons) == "table" then data.weapons else {}
	if data.weapon == "pistol" then
		data.weapons.pistol = true -- the V1.0 pistol
	end
	return data.weapons
end

-- what a player can carry right now, in a fixed order
function WeaponService.Available(p: Player): { string }
	if JobService.Get(p) == "Police" then
		return { "service_pistol" }
	end
	local data = DataService.Get(p)
	if not data then
		return {}
	end
	local have = owned(data)
	local list = {}
	for _, w in Weapons.List do
		if w.price and Weapons.Enabled(w.id, newOn()) then
			local ok = if w.grenade then (tonumber(data.grenades) or 0) > 0 else have[w.id] == true
			if ok then
				table.insert(list, w.id)
			end
		end
	end
	return list
end

local function setAttrs(p: Player, list: { string }, selected: string?)
	local data = DataService.Get(p)
	p:SetAttribute("Weapons", table.concat(list, ","))
	p:SetAttribute("Grenades", if data then tonumber(data.grenades) or 0 else 0)
	p:SetAttribute("Weapon", selected)
	if not selected then
		p:SetAttribute("WeaponOut", nil)
	end
end

local holster: (Player) -> ()

-- which weapons a player carries right now (job change, purchase, join)
local function refresh(p: Player)
	local list = WeaponService.Available(p)
	local cur = p:GetAttribute("Weapon")
	local selected = if typeof(cur) == "string" and table.find(list, cur) then cur else list[1]
	if selected ~= cur then
		holster(p)
	end
	setAttrs(p, list, selected)
	local s = states[p] or { ammo = {}, lastShot = 0, reloading = false }
	for _, id in list do
		local w = Weapons.ById[id]
		if s.ammo[id] == nil then
			s.ammo[id] = w.mag
		end
	end
	states[p] = s
end
WeaponService.Refresh = refresh

-- Held weapon -------------------------------------------------------------------------

-- old look (Config.Guns2 off): a small block in the right hand
local function showBlock(p: Player, on: boolean)
	local c = p.Character
	local hand = c and (c:FindFirstChild("RightHand") or c:FindFirstChild("Right Arm")) :: BasePart?
	if not c or not hand then
		return
	end
	local old = c:FindFirstChild("HeldGun")
	if old then
		old:Destroy()
	end
	if not on then
		return
	end
	local gun = Instance.new("Part")
	gun.Name = "HeldGun"
	gun.Size = Vector3.new(0.25, 0.5, 1.1)
	gun.Color = Color3.fromRGB(25, 25, 28)
	gun.Material = Enum.Material.Metal
	gun.CanCollide = false
	gun.CanQuery = false
	gun.Massless = true
	gun.CFrame = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, -0.35)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = gun
	weld.Parent = gun
	gun.Parent = c
end

-- Config.Guns2: the weapon model as a Tool in the hand (arm held forward, everyone sees it)
local function makeTool(p: Player, id: string): Tool?
	local model = Weapons.BuildModel(id)
	if not model or not model.PrimaryPart then
		return nil
	end
	local w = Weapons.ById[id]
	local tool = Instance.new("Tool")
	tool.Name = w.name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true
	tool:SetAttribute("WeaponTool", id)
	local handle = model.PrimaryPart :: BasePart
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = part
			part.Parent = tool
		end
	end
	handle.Name = "Handle"
	handle.Parent = tool
	model:Destroy()
	-- put away from the backpack bar (or another tool taken) = holstered
	tool.AncestryChanged:Connect(function(_, parent)
		if parent ~= p.Character and tool.Parent then
			tool:Destroy()
			if p:GetAttribute("WeaponOut") then
				p:SetAttribute("WeaponOut", nil)
			end
		end
	end)
	return tool
end

holster = function(p: Player)
	local c = p.Character
	if c then
		for _, t in c:GetChildren() do
			if t:IsA("Tool") and t:GetAttribute("WeaponTool") then
				t:Destroy()
			end
		end
		local old = c:FindFirstChild("HeldGun")
		if old then
			old:Destroy()
		end
	end
	p:SetAttribute("WeaponOut", nil)
end

local function draw(p: Player, id: string)
	holster(p)
	local c = p.Character
	if not c then
		return
	end
	if newOn() then
		local tool = makeTool(p, id)
		if tool then
			tool.Parent = c -- equips it
		end
	else
		showBlock(p, true)
	end
	p:SetAttribute("WeaponOut", true)
end

-- where the shot starts: the muzzle of the held model (if it is near the head)
local function muzzleOf(p: Player, head: BasePart): Vector3
	local c = p.Character
	for _, t in (if c then c:GetChildren() else {}) do
		if t:IsA("Tool") and t:GetAttribute("WeaponTool") then
			for _, d in t:GetDescendants() do
				if d:IsA("Attachment") and d.Name == "Muzzle" then
					local pos = d.WorldPosition
					if (pos - head.Position).Magnitude < 10 then
						return pos
					end
				end
			end
			local h = t:FindFirstChild("Handle") :: BasePart?
			if h and (h.Position - head.Position).Magnitude < 10 then
				return h.Position
			end
		end
	end
	return head.Position
end

-- Damage ------------------------------------------------------------------------------

-- may `shooter` hurt `victim`?
function WeaponService.MayHurt(shooter: Player, victim: Player): boolean
	if shooter == victim or CrimeService.IsJailed(victim) then
		return false
	end
	if CrimeService.IsPolice(shooter) then
		return CrimeService.IsCriminal(victim) -- the police only shoot suspects
	end
	return true
end

local function hurt(shooter: Player, victim: Player, damage: number)
	local hum = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	lastHitBy[victim] = { by = shooter, t = os.clock() }
	if not CrimeService.IsPolice(shooter) then
		CrimeService.Crime(shooter, "shot " .. victim.Name)
	end
	hum:TakeDamage(damage)
	Remotes.Push(victim, "Hit", { by = shooter.DisplayName, health = hum.Health })
end

-- grenade damage: full in the middle, less towards the edge of the radius
function WeaponService.BlastDamage(w: Weapons.Weapon, distance: number): number
	local r = w.radius or 0
	if distance >= r then
		return 0
	end
	return math.floor(w.damage * (1 - distance / r) ^ 0.6 + 0.5)
end

local function explode(thrower: Player, w: Weapons.Weapon, pos: Vector3)
	local boom = Instance.new("Explosion")
	boom.Position = pos
	boom.BlastRadius = w.radius or 10
	boom.BlastPressure = 0 -- no flinging
	boom.DestroyJointRadiusPercent = 0 -- nothing breaks, the damage is ours
	boom.ExplosionType = Enum.ExplosionType.NoCraters
	boom.Parent = Workspace
	local warned = false
	for _, victim in Players:GetPlayers() do
		local root = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local dmg = WeaponService.BlastDamage(w, (root.Position - pos).Magnitude)
			if dmg > 0 then
				if WeaponService.MayHurt(thrower, victim) then
					hurt(thrower, victim, dmg)
				elseif thrower ~= victim and not warned and CrimeService.IsPolice(thrower) then
					warned = true
					Remotes.Push(thrower, "Notify", { key = "weapon_police_only_suspects" })
				end
			end
		end
	end
end

local function throwGrenade(p: Player, w: Weapons.Weapon, from: Vector3, aim: Vector3)
	local flat = (aim - from) * Vector3.new(1, 0, 1)
	local dist = math.clamp(flat.Magnitude, 8, w.range)
	local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
	-- an arc that lands about where you aimed
	local g = Workspace.Gravity
	local t = math.clamp(dist / 45, 0.5, 2)
	local vy = (aim.Y - from.Y + 0.5 * g * t * t) / t
	local ball = Weapons.BuildModel("grenade")
	if not ball then
		return
	end
	local body = ball.PrimaryPart :: BasePart
	for _, part in ball:GetChildren() do
		if part:IsA("BasePart") and part ~= body then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = part
			weld.Parent = part
		end
	end
	body.Massless = false
	body.CanCollide = true
	ball.Name = "Grenade"
	ball:PivotTo(CFrame.new(from))
	ball.Parent = Workspace
	pcall(function()
		body:SetNetworkOwner(nil)
	end)
	body.AssemblyLinearVelocity = dir * (dist / t) + Vector3.new(0, math.clamp(vy, 5, 80), 0)
	task.delay(w.fuse or 2.5, function()
		local pos = body.Position
		ball:Destroy()
		if p.Parent then
			explode(p, w, pos)
		end
	end)
	Debris:AddItem(ball, (w.fuse or 2.5) + 1)
end

local function onDied(victim: Player)
	local hit = lastHitBy[victim]
	lastHitBy[victim] = nil
	if hit and os.clock() - hit.t < 5 and hit.by.Parent then
		GameLog.Add("crime", hit.by, "killed " .. victim.Name)
		if CrimeService.IsPolice(hit.by) and CrimeService.IsCriminal(victim) then
			CrimeService.Jail(victim, hit.by)
		end
	end
end

local function watch(p: Player)
	p.CharacterAdded:Connect(function(c)
		p:SetAttribute("WeaponOut", nil)
		local hum = c:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum.Died:Connect(function()
				onDied(p)
			end)
		end
	end)
end

-- Black market -------------------------------------------------------------------------

-- may `player` buy weapon `id` now? (nil = yes, else the error key)
function WeaponService.CanBuy(data: { [string]: any }, id: string, newWeapons: boolean): string?
	local w = Weapons.ById[id]
	if not w or not w.price or not Weapons.Enabled(id, newWeapons) then
		return "bad_request"
	end
	if w.grenade then
		if (tonumber(data.grenades) or 0) >= (w.maxCount or 1) then
			return "weapon_grenades_full"
		end
	elseif owned(data)[id] then
		return "already_owned"
	end
	return nil
end

function WeaponService.Start()
	if not Config.V10 then
		return
	end
	DataService.Loaded:Connect(function(p)
		refresh(p)
	end)
	JobService.Changed:Connect(function(p)
		refresh(p)
	end)
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		states[p] = nil
		lastHitBy[p] = nil
	end)

	Remotes.Handle("Weapon.Equip", function(player, on: any)
		local w = weaponOf(player)
		if not w or typeof(on) ~= "boolean" then
			return Remotes.Fail("bad_request")
		end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if on and (not hum or hum.SeatPart or CrimeService.IsJailed(player)) then
			return Remotes.Fail("weapon_not_now")
		end
		if on then
			draw(player, w.id)
		else
			holster(player)
		end
		local s = states[player]
		return Remotes.Ok({ ammo = s and s.ammo[w.id] or 0 })
	end, { rate = 6 })

	-- pick another of your weapons (stays drawn if it was)
	Remotes.Handle("Weapon.Select", function(player, id: any)
		local list = WeaponService.Available(player)
		if typeof(id) ~= "string" or not table.find(list, id) then
			return Remotes.Fail("bad_request")
		end
		local wasOut = player:GetAttribute("WeaponOut") == true
		player:SetAttribute("Weapon", id)
		if wasOut then
			draw(player, id)
		end
		local s = states[player]
		return Remotes.Ok({ ammo = s and s.ammo[id] or 0 })
	end, { rate = 6 })

	Remotes.Handle("Weapon.Reload", function(player)
		local w, s = weaponOf(player), states[player]
		if not w or not s or s.reloading or w.grenade then
			return Remotes.Fail("bad_request")
		end
		s.reloading = true
		task.delay(w.reload, function()
			s.ammo[w.id] = w.mag
			s.reloading = false
			if player.Parent then
				Remotes.Push(player, "Ammo", { ammo = s.ammo[w.id] })
			end
		end)
		return Remotes.Ok({ seconds = w.reload })
	end, { rate = 4 })

	Remotes.Handle("Weapon.Fire", function(player, aim: any)
		local w, s = weaponOf(player), states[player]
		if not w or not s or player:GetAttribute("WeaponOut") ~= true or typeof(aim) ~= "Vector3" then
			return Remotes.Fail("bad_request")
		end
		local c = player.Character
		local head = c and c:FindFirstChild("Head") :: BasePart?
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if not head or not hum or hum.Health <= 0 or hum.SeatPart or CrimeService.IsJailed(player) then
			return Remotes.Fail("weapon_not_now")
		end
		local t = os.clock()
		if s.reloading or t - s.lastShot < w.rate * 0.9 then
			return Remotes.Fail("too_fast")
		end
		local origin = if newOn() then muzzleOf(player, head) else head.Position

		-- grenade: throw one (from your stock)
		if w.grenade then
			local data = DataService.Get(player)
			local left = data and tonumber(data.grenades) or 0
			if not data or left <= 0 then
				return Remotes.Fail("weapon_empty")
			end
			s.lastShot = t
			data.grenades = left - 1
			State.MarkDirty(player)
			throwGrenade(player, w, origin, aim)
			GameLog.Add("crime", player, "threw a grenade")
			if data.grenades <= 0 then
				refresh(player) -- none left: next weapon
			else
				player:SetAttribute("Grenades", data.grenades)
				draw(player, w.id) -- the next one in the hand
			end
			return Remotes.Ok({ ammo = data.grenades })
		end

		if (s.ammo[w.id] or 0) <= 0 then
			return Remotes.Fail("weapon_empty")
		end
		s.lastShot = t
		s.ammo[w.id] -= 1
		local dir = aim - origin
		if dir.Magnitude < 0.1 then
			return Remotes.Fail("bad_request")
		end
		dir = dir.Unit * w.range
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { c :: Instance }
		local result = Workspace:Raycast(origin, dir, params)
		local hitPos = if result then result.Position else origin + dir
		local victim: Player? = nil
		if result then
			local model = result.Instance:FindFirstAncestorOfClass("Model")
			victim = model and Players:GetPlayerFromCharacter(model)
		end
		if victim then
			if WeaponService.MayHurt(player, victim) then
				hurt(player, victim, w.damage)
			else
				Remotes.Push(player, "Notify", { key = "weapon_police_only_suspects" })
			end
		end
		Remotes.PushAll("Shot", { from = origin, to = hitPos, kind = w.id })
		return Remotes.Ok({ ammo = s.ammo[w.id], hit = victim ~= nil })
	end, { rate = 14 })

	-- black market: civilians buy weapons (nil id = the pistol, older clients)
	Remotes.Handle("Weapon.Buy", function(player, id: any)
		local data = DataService.Get(player)
		if not data then
			return Remotes.Fail("error")
		end
		id = if id == nil then "pistol" else id
		if typeof(id) ~= "string" then
			return Remotes.Fail("bad_request")
		end
		if not Interaction.IsNear(player, "Shop", 20, "UI", "Blackmarket") then
			return Remotes.Fail("too_far")
		end
		if not CrimeService.IsCivil(player) then
			return Remotes.Fail("crime_not_civil")
		end
		local err = WeaponService.CanBuy(data, id, newOn())
		if err then
			return Remotes.Fail(err)
		end
		local w = Weapons.ById[id]
		if not Economy.TrySpend(player, w.price :: number, "Schwarzmarkt: " .. w.name) then
			return Remotes.Fail("no_money")
		end
		if w.grenade then
			data.grenades = (tonumber(data.grenades) or 0) + 1
		else
			owned(data)[id] = true
			if id == "pistol" then
				data.weapon = "pistol" -- what older versions read
			end
		end
		State.MarkDirty(player)
		refresh(player)
		GameLog.Add("crime", player, "bought " .. w.name)
		return Remotes.Ok({ grenades = data.grenades })
	end, { rate = 3 })
end

return WeaponService
