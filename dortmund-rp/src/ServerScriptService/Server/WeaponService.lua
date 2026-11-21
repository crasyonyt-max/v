--!strict
-- V1.0 weapons, checked by the server:
--   * Police on duty: service pistol; civilians: the pistol from the black market
--   * draw / holster (Weapon.Equip), shoot (Weapon.Fire), reload (Weapon.Reload)
--   * the server traces every shot itself (from the shooter's head), with fire rate,
--     magazine and range limits
--   * Police only hurt criminals; anyone else who shoots a person commits a crime
--     (wanted again for the full time); a criminal killed by the police goes to prison

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local CrimeService = require(script.Parent.CrimeService)
local DataService = require(script.Parent.DataService)
local GameLog = require(script.Parent.GameLog)
local JobService = require(script.Parent.JobService)
local Remotes = require(script.Parent.Remotes)

local WeaponService = {}

type State = { ammo: number, lastShot: number, reloading: boolean }
local states: { [Player]: State } = {}
local lastHitBy: { [Player]: { by: Player, t: number } } = {}

local function weaponOf(p: Player): Weapons.Weapon?
	local id = p:GetAttribute("Weapon")
	return if typeof(id) == "string" then Weapons.ById[id] else nil
end
WeaponService.WeaponOf = weaponOf

-- which weapon a player carries right now
local function refresh(p: Player)
	local data = DataService.Get(p)
	local id = if JobService.Get(p) == "Police"
		then "service_pistol"
		elseif data and data.weapon == "pistol" then "pistol"
		else nil
	p:SetAttribute("Weapon", id)
	local w = id and Weapons.ById[id]
	states[p] = { ammo = if w then w.mag else 0, lastShot = 0, reloading = false }
	if not id then
		p:SetAttribute("WeaponOut", nil)
	end
end

-- the gun in the right hand (everyone sees it)
local function showGun(p: Player, on: boolean)
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
		if not weaponOf(player) or typeof(on) ~= "boolean" then
			return Remotes.Fail("bad_request")
		end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if on and (not hum or hum.SeatPart or CrimeService.IsJailed(player)) then
			return Remotes.Fail("weapon_not_now")
		end
		player:SetAttribute("WeaponOut", on or nil)
		showGun(player, on)
		local s = states[player]
		return Remotes.Ok({ ammo = s and s.ammo or 0 })
	end, { rate = 6 })

	Remotes.Handle("Weapon.Reload", function(player)
		local w, s = weaponOf(player), states[player]
		if not w or not s or s.reloading then
			return Remotes.Fail("bad_request")
		end
		s.reloading = true
		task.delay(w.reload, function()
			s.ammo = w.mag
			s.reloading = false
			if player.Parent then
				Remotes.Push(player, "Ammo", { ammo = s.ammo })
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
		if s.ammo <= 0 then
			return Remotes.Fail("weapon_empty")
		end
		s.lastShot = t
		s.ammo -= 1
		local origin = head.Position
		local dir = aim - origin
		if dir.Magnitude < 0.1 then
			return Remotes.Fail("bad_request")
		end
		dir = dir.Unit * w.range
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { c }
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
		Remotes.PushAll("Shot", { from = origin, to = hitPos })
		return Remotes.Ok({ ammo = s.ammo, hit = victim ~= nil })
	end, { rate = 12 })
end

return WeaponService
