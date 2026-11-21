--!strict
-- V1.0 weapon HUD (police service pistol, black-market pistol):
--   🔫 draw / holster; drawn: aim with the mouse (PC) or the crosshair in the middle
--   (touch), shoot with click / FEUER, reload with R / 🔄. The server checks every shot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Make = require(script.Parent.Parent.UI.Make)
local Net = require(script.Parent.Parent.Net)
local Notify = require(script.Parent.Parent.UI.Notify)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme
local me = Players.LocalPlayer

if not Config.V10 then
	return {}
end

local isTouch = UserInputService.TouchEnabled

local gui = New("ScreenGui", {
	Name = "WeaponHUD",
	ResetOnSpawn = false,
	DisplayOrder = 7,
	Enabled = false,
	Parent = me:WaitForChild("PlayerGui"),
})
local drawButton = Make.Button("🔫", Color3.fromRGB(40, 40, 46), function() end, {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -140),
	Size = UDim2.fromOffset(56, 56),
	TextSize = 26,
	Parent = gui,
})
local fireButton = Make.Button(Store.T("weapon_fire"), Color3.fromRGB(200, 30, 30), function() end, {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -80, 1, -140),
	Size = UDim2.fromOffset(96, 96),
	TextSize = 18,
	Visible = false,
	Parent = gui,
})
local reloadButton = Make.Button("🔄", T.panel, function() end, {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -204),
	Size = UDim2.fromOffset(56, 56),
	TextSize = 22,
	Visible = false,
	Parent = gui,
})
local ammoLabel = Make.Label("", 14, Color3.new(1, 1, 1), T.bold, {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -80, 1, -240),
	Size = UDim2.fromOffset(96, 20),
	TextXAlignment = Enum.TextXAlignment.Center,
	Visible = false,
	Parent = gui,
})
local crosshair = Make.Label("+", 30, Color3.new(1, 1, 1), T.black, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(30, 30),
	TextXAlignment = Enum.TextXAlignment.Center,
	Visible = false,
	Parent = gui,
})

local out = false
local ammo = 0

local function setOut(on: boolean)
	task.spawn(function()
		local r = Net.Request("Weapon.Equip", on)
		if not r.ok then
			Notify.Error(r.err)
			return
		end
		out = on
		ammo = r.ammo or ammo
		fireButton.Visible = on and isTouch
		reloadButton.Visible = on
		ammoLabel.Visible = on
		crosshair.Visible = on and isTouch
		drawButton.BackgroundColor3 = if on then Color3.fromRGB(200, 30, 30) else Color3.fromRGB(40, 40, 46)
		ammoLabel.Text = ("%d"):format(ammo)
	end)
end

-- where the shot goes: mouse (PC) or the middle of the screen (touch)
local function aimPoint(): Vector3?
	local camera = Workspace.CurrentCamera
	local pos = if isTouch then camera.ViewportSize / 2 else UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { me.Character :: any }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 400, params)
	return if hit then hit.Position else ray.Origin + ray.Direction * 400
end

local busy = false
local function fire()
	if not out or busy then
		return
	end
	local aim = aimPoint()
	if not aim then
		return
	end
	busy = true
	task.spawn(function()
		local r = Net.Request("Weapon.Fire", aim)
		busy = false
		if r.ok then
			ammo = r.ammo or ammo
			ammoLabel.Text = ("%d"):format(ammo)
		elseif r.err == "weapon_empty" then
			Notify.Show(Store.T("weapon_empty"), true, 1.5)
		elseif r.err ~= "too_fast" then
			Notify.Error(r.err)
		end
	end)
end

local function reload()
	if not out then
		return
	end
	task.spawn(function()
		local r = Net.Request("Weapon.Reload")
		if r.ok then
			ammoLabel.Text = "…"
		end
	end)
end

drawButton.Activated:Connect(function()
	setOut(not out)
end)
fireButton.Activated:Connect(fire)
reloadButton.Activated:Connect(reload)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not out then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		fire()
	elseif input.KeyCode == Enum.KeyCode.R then
		reload()
	end
end)

Net.On("Ammo", function(p)
	if typeof(p) == "table" then
		ammo = p.ammo or ammo
		ammoLabel.Text = ("%d"):format(ammo)
	end
end)

-- everyone sees the shots: a short bright tracer
Net.On("Shot", function(p)
	if typeof(p) ~= "table" or typeof(p.from) ~= "Vector3" or typeof(p.to) ~= "Vector3" then
		return
	end
	local len = (p.to - p.from).Magnitude
	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 220, 120)
	tracer.Size = Vector3.new(0.08, 0.08, len)
	tracer.CFrame = CFrame.lookAt(p.from, p.to) * CFrame.new(0, 0, -len / 2)
	tracer.Parent = Workspace
	task.delay(0.07, function()
		tracer:Destroy()
	end)
end)

-- show the HUD while you carry a weapon (and are not in a vehicle)
local function refresh()
	local w = Weapons.ById[tostring(me:GetAttribute("Weapon"))]
	gui.Enabled = w ~= nil
	if not w and out then
		out = false
	end
end
me:GetAttributeChangedSignal("Weapon"):Connect(refresh)
me:GetAttributeChangedSignal("WeaponOut"):Connect(function()
	if me:GetAttribute("WeaponOut") ~= true and out then
		out = false
		fireButton.Visible, reloadButton.Visible, ammoLabel.Visible, crosshair.Visible = false, false, false, false
		drawButton.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
	end
end)
refresh()

return {}
