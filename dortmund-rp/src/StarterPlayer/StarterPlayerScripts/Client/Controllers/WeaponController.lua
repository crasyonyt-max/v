--!strict
-- V1.0 weapon HUD (police service pistol, black-market weapons):
--   🔫 draw / holster; drawn: aim with the mouse (PC) or the crosshair in the middle
--   (touch), shoot with click / FEUER, reload with R / 🔄. The server checks every shot.
-- Config.Guns2 (testing server first): 🔁 / X switches between your weapons,
-- the AK-47 keeps firing while you hold, the sniper rifle zooms (🔭 / right mouse),
-- a grenade is thrown at the aim point (it explodes after a short fuse).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local guns2 = Config.On(Config.Guns2)

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
local switchButton = Make.Button("🔁", T.panel, function() end, {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -268),
	Size = UDim2.fromOffset(56, 56),
	TextSize = 22,
	Visible = false,
	Parent = gui,
})
local scopeButton = Make.Button("🔭", T.panel, function() end, {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -80, 1, -244),
	Size = UDim2.fromOffset(56, 56),
	TextSize = 22,
	Visible = false,
	Parent = gui,
})
local ammoLabel = Make.Label("", 14, Color3.new(1, 1, 1), T.bold, {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -150, 1, -244),
	Size = UDim2.fromOffset(170, 20),
	TextXAlignment = Enum.TextXAlignment.Right,
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
-- sniper scope: black ring around a round view, fine cross lines
local scope = New("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 0,
	Parent = gui,
})
do
	local ring = New("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.9),
		BackgroundTransparency = 1,
		Parent = scope,
	}, { New("UIAspectRatioConstraint", { AspectRatio = 1 }) })
	New("UIStroke", { Thickness = 2000, Color = Color3.new(0, 0, 0), Parent = ring })
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
	New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Parent = ring,
	})
	New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Parent = ring,
	})
end

local out = false
local ammo = 0
local scoped = false
local holding = false -- fire held (automatic weapons)
local lastFire = 0
local savedFov = 70

local function current(): Weapons.Weapon?
	return Weapons.ById[tostring(me:GetAttribute("Weapon"))]
end

local function myWeapons(): { string }
	local list = {}
	for id in string.gmatch(tostring(me:GetAttribute("Weapons") or ""), "[^,]+") do
		table.insert(list, id)
	end
	local w = current()
	if #list == 0 and w then
		list = { w.id } -- the police pistol
	end
	return list
end

local function setScope(on: boolean)
	local camera = Workspace.CurrentCamera
	if on == scoped then
		return
	end
	scoped = on
	if on then
		savedFov = camera.FieldOfView
		camera.FieldOfView = 14
	else
		camera.FieldOfView = savedFov
	end
	scope.Visible = on
	crosshair.Visible = (on and false) or (out and isTouch)
end

local function updateLabel()
	local w = current()
	if not w then
		ammoLabel.Text = ""
		return
	end
	ammoLabel.Text = if w.grenade
		then ("%s · %d"):format(w.name, tonumber(me:GetAttribute("Grenades")) or 0)
		else ("%s · %d"):format(w.name, ammo)
end

local function applyOut(on: boolean)
	out = on
	local w = current()
	fireButton.Visible = on and isTouch
	reloadButton.Visible = on and not (w and w.grenade)
	ammoLabel.Visible = on
	crosshair.Visible = on and isTouch
	scopeButton.Visible = on and guns2 and w ~= nil and w.scope == true
	switchButton.Visible = guns2 and #myWeapons() > 1
	fireButton.Text = if w and w.grenade then "💣" else Store.T("weapon_fire")
	drawButton.BackgroundColor3 = if on then Color3.fromRGB(200, 30, 30) else Color3.fromRGB(40, 40, 46)
	if not on or not (w and w.scope) then
		setScope(false)
	end
	updateLabel()
end

local function setOut(on: boolean)
	task.spawn(function()
		local r = Net.Request("Weapon.Equip", on)
		if not r.ok then
			Notify.Error(r.err)
			return
		end
		ammo = r.ammo or ammo
		applyOut(on)
	end)
end

local function select(id: string)
	task.spawn(function()
		local r = Net.Request("Weapon.Select", id)
		if r.ok then
			ammo = r.ammo or ammo
			applyOut(out)
		end
	end)
end

local function switchNext()
	local list = myWeapons()
	if #list < 2 then
		return
	end
	local w = current()
	local i = (w and table.find(list, w.id)) or 0
	select(list[i % #list + 1])
end

-- where the shot goes: mouse (PC) or the middle of the screen (touch / scope)
local function aimPoint(): Vector3?
	local camera = Workspace.CurrentCamera
	local pos = if isTouch or scoped then camera.ViewportSize / 2 else UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { me.Character :: any }
	local w = current()
	local reach = if w then math.max(w.range, 400) else 400
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * reach, params)
	return if hit then hit.Position else ray.Origin + ray.Direction * reach
end

local busy = false
local function fire()
	local w = current()
	if not out or busy or not w then
		return
	end
	if os.clock() - lastFire < w.rate then
		return
	end
	local aim = aimPoint()
	if not aim then
		return
	end
	busy = true
	lastFire = os.clock()
	task.spawn(function()
		local r = Net.Request("Weapon.Fire", aim)
		busy = false
		if r.ok then
			ammo = r.ammo or ammo
			updateLabel()
		elseif r.err == "weapon_empty" then
			holding = false
			Notify.Show(Store.T("weapon_empty"), true, 1.5)
		elseif r.err ~= "too_fast" then
			holding = false
			Notify.Error(r.err)
		end
	end)
end

local function reload()
	local w = current()
	if not out or (w and w.grenade) then
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
reloadButton.Activated:Connect(reload)
switchButton.Activated:Connect(switchNext)
scopeButton.Activated:Connect(function()
	setScope(not scoped)
end)
-- the FIRE button: a tap shoots, holding keeps an automatic weapon firing
fireButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = true
		fire()
	end
end)
fireButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = false
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R and out then
		reload()
	elseif input.KeyCode == Enum.KeyCode.X and guns2 then
		switchNext() -- (the number keys belong to the backpack bar)
	end
	if not out then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and not isTouch then
		holding = true
		fire()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		local w = current()
		if w and w.scope then
			setScope(true)
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 and not isTouch then
		setScope(false)
	end
end)

-- automatic fire while held
RunService.Heartbeat:Connect(function()
	local w = current()
	if holding and out and w and w.auto then
		fire()
	end
end)

Net.On("Ammo", function(p)
	if typeof(p) == "table" then
		ammo = p.ammo or ammo
		updateLabel()
	end
end)

-- everyone sees the shots: a short bright tracer from the muzzle
Net.On("Shot", function(p)
	if typeof(p) ~= "table" or typeof(p.from) ~= "Vector3" or typeof(p.to) ~= "Vector3" then
		return
	end
	local len = (p.to - p.from).Magnitude
	local thick = if p.kind == "sniper" then 0.14 else 0.08
	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 220, 120)
	tracer.Size = Vector3.new(thick, thick, len)
	tracer.CFrame = CFrame.lookAt(p.from, p.to) * CFrame.new(0, 0, -len / 2)
	tracer.Parent = Workspace
	-- muzzle flash
	local flash = Instance.new("Part")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 190, 80)
	flash.Size = Vector3.new(0.5, 0.5, 0.5)
	flash.Position = p.from
	flash.Parent = Workspace
	task.delay(0.06, function()
		flash:Destroy()
	end)
	task.delay(0.07, function()
		tracer:Destroy()
	end)
end)

-- show the HUD while you carry a weapon
local function refresh()
	local w = current()
	gui.Enabled = w ~= nil
	if not w and out then
		applyOut(false)
	elseif out then
		applyOut(true)
	else
		switchButton.Visible = guns2 and #myWeapons() > 1
	end
end
me:GetAttributeChangedSignal("Weapon"):Connect(refresh)
me:GetAttributeChangedSignal("Weapons"):Connect(refresh)
me:GetAttributeChangedSignal("Grenades"):Connect(updateLabel)
me:GetAttributeChangedSignal("WeaponOut"):Connect(function()
	if me:GetAttribute("WeaponOut") ~= true and out then
		holding = false
		applyOut(false)
	end
end)
refresh()

return {}
