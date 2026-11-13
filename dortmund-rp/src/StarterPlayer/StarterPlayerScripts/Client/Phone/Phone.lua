--!strict
-- The phone: body (styled per model), status bar, home screen, app navigation.
-- Apps live in Phone/Apps and register themselves with Phone.Register.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Phones = require(ReplicatedStorage.Shared.Phones)
local Make = require(script.Parent.Parent.UI.Make)
local Store = require(script.Parent.Parent.Store)
local Boot = require(script.Parent.Boot)

local New, T = Make.New, Make.Theme

local Phone = {}

export type App = {
	id: string,
	icon: string,
	color: Color3,
	order: number,
	visible: ((state: { [string]: any }) -> boolean)?,
	-- builds the app into `container`; may return a function called on every state update
	build: (container: Frame, arg: any) -> ((state: { [string]: any }) -> ())?,
}

local apps: { App } = {}
local appsById: { [string]: App } = {}

local gui = New("ScreenGui", {
	Name = "Phone",
	ResetOnSpawn = false,
	DisplayOrder = 20,
	IgnoreGuiInset = true,
	Enabled = true,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})

local CLOSED = UDim2.new(1, -16, 1, 700)
local OPEN = UDim2.new(1, -16, 1, -16)
-- PC mode (office PCs in the Admin Tower): a wide monitor in the middle of the screen
local PC_OPEN = UDim2.new(0.5, 0, 0.5, 0)
local pcMode = false

local body = New("Frame", {
	Name = "Body",
	AnchorPoint = Vector2.new(1, 1),
	Position = CLOSED,
	Size = UDim2.fromScale(0.36, 0.74),
	SizeConstraint = Enum.SizeConstraint.RelativeYY,
	BackgroundColor3 = Color3.fromRGB(30, 30, 30),
	Visible = false,
	Parent = gui,
}, {
	New("UIAspectRatioConstraint", { Name = "Aspect", AspectRatio = 0.48 }),
	New("UISizeConstraint", { Name = "MaxSize", MaxSize = Vector2.new(360, 750) }),
})

-- PC mode: the phone's screen is shown ON the office monitor (a SurfaceGui on it),
-- the camera looks at the monitor and you tap the apps there.
local pcSurface: SurfaceGui? = nil
local pcExit: ScreenGui? = nil
local pcMonitor: BasePart? = nil
local savedCamera: { [string]: any }? = nil
local savedWalk: { [string]: number }? = nil

local function setPcMode(on: boolean, monitor: BasePart?)
	pcMode = on
	local aspect = body:FindFirstChild("Aspect") :: UIAspectRatioConstraint
	local max = body:FindFirstChild("MaxSize") :: UISizeConstraint
	local camera = workspace.CurrentCamera
	local hum = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if on and monitor then
		pcMonitor = monitor
		-- hide the monitor's own "NVDR OS" picture while the phone is on it
		for _, g in monitor:GetChildren() do
			if g:IsA("SurfaceGui") then
				g.Enabled = false
			end
		end
		local face = Enum.NormalId[(monitor:GetAttribute("ScreenFace") or "Front") :: string]
		local surface = New("SurfaceGui", {
			Name = "PCScreen",
			Adornee = monitor,
			Face = face,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 120,
			LightInfluence = 0,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		})
		pcSurface = surface
		body.Parent = surface
		body.AnchorPoint = Vector2.new(0.5, 0.5)
		body.SizeConstraint = Enum.SizeConstraint.RelativeXY
		body.Size = UDim2.fromScale(1, 1)
		aspect.AspectRatio = monitor.Size.X / monitor.Size.Y
		max.MaxSize = Vector2.new(math.huge, math.huge)
		-- camera in front of the screen, filling the view
		local normal = monitor.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face))
		local center = monitor.Position + normal * (monitor.Size.Z / 2)
		savedCamera = { type = camera.CameraType, fov = camera.FieldOfView, cf = camera.CFrame }
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 40
		local distance = (monitor.Size.Y / 2) / math.tan(math.rad(20)) * 1.12
		camera.CFrame = CFrame.lookAt(center + normal * distance, center)
		if hum then
			savedWalk = { walk = hum.WalkSpeed, jump = hum.JumpPower }
			hum.WalkSpeed = 0
			hum.JumpPower = 0
		end
		-- a way out (also the phone's own home bar / close)
		local exitGui = New("ScreenGui", {
			Name = "PCExit",
			ResetOnSpawn = false,
			DisplayOrder = 30,
			Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		})
		pcExit = exitGui
		Make.Button("✕ PC verlassen", T.bad, function()
			Phone.Close()
		end, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.fromOffset(170, 40),
			TextSize = 16,
			Parent = exitGui,
		})
		return
	end
	-- back to the normal phone
	if pcSurface then
		body.Parent = gui
		pcSurface:Destroy()
		pcSurface = nil
	end
	if pcExit then
		pcExit:Destroy()
		pcExit = nil
	end
	if pcMonitor then
		for _, g in pcMonitor:GetChildren() do
			if g:IsA("SurfaceGui") then
				g.Enabled = true
			end
		end
		pcMonitor = nil
	end
	if savedCamera then
		camera.CameraType = savedCamera.type
		camera.FieldOfView = savedCamera.fov
		savedCamera = nil
	end
	if savedWalk and hum then
		hum.WalkSpeed = savedWalk.walk
		hum.JumpPower = savedWalk.jump
	end
	savedWalk = nil
	body.AnchorPoint = Vector2.new(1, 1)
	body.SizeConstraint = Enum.SizeConstraint.RelativeYY
	body.Size = UDim2.fromScale(0.36, 0.74)
	aspect.AspectRatio = 0.48
	max.MaxSize = Vector2.new(360, 750)
end
local bodyCorner = Make.Corner(34)
bodyCorner.Parent = body
local bodyStroke = Make.Stroke(Color3.fromRGB(60, 60, 60), 2)
bodyStroke.Parent = body
local glowStroke: UIStroke? = nil

local screen = New("Frame", {
	Name = "Screen",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -14, 1, -14),
	BackgroundColor3 = Color3.new(0, 0, 0),
	ClipsDescendants = true,
	Parent = body,
})
local screenCorner = Make.Corner(28)
screenCorner.Parent = screen
local wallpaper = New("UIGradient", { Rotation = 90, Parent = screen })

-- Status bar
local status = New("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 26),
	ZIndex = 10,
	Parent = screen,
}, { Make.Padding(6) })
local clock = Make.Label(
	"12:00",
	13,
	Color3.new(1, 1, 1),
	T.bold,
	{ Size = UDim2.fromScale(0.5, 1), Parent = status, ZIndex = 10 }
)
local brandLabel = Make.Label("", 12, Color3.new(1, 1, 1), T.bold, {
	Size = UDim2.fromScale(0.5, 1),
	Position = UDim2.fromScale(0.5, 0),
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = status,
	ZIndex = 10,
})
local _ = clock

-- Home screen
local home = New("Frame", {
	Name = "Home",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 0, 0, 30),
	Size = UDim2.new(1, 0, 1, -60),
	Parent = screen,
}, { Make.Padding(10) })
local grid = New("UIGridLayout", {
	CellSize = UDim2.new(0.25, -8, 0, 78),
	CellPadding = UDim2.fromOffset(8, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = home,
})
local _ = grid

-- App view
local appView = New("Frame", {
	Name = "AppView",
	BackgroundColor3 = T.bg,
	Position = UDim2.new(0, 0, 0, 26),
	Size = UDim2.new(1, 0, 1, -50),
	Visible = false,
	Parent = screen,
})
local appBar = New("Frame", { BackgroundColor3 = T.panel, Size = UDim2.new(1, 0, 0, 36), Parent = appView })
local appTitle = Make.Label("", 15, T.text, T.bold, {
	Position = UDim2.new(0, 44, 0, 0),
	Size = UDim2.new(1, -50, 1, 0),
	Parent = appBar,
})
local appContent = New("Frame", {
	Name = "Content",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 0, 0, 36),
	Size = UDim2.new(1, 0, 1, -36),
	ClipsDescendants = true,
	Parent = appView,
}, { Make.Padding(8) })

-- Home indicator (tap = home)
local homeBar = New("TextButton", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -6),
	Size = UDim2.new(0.38, 0, 0, 16),
	BackgroundTransparency = 1,
	Text = "",
	ZIndex = 20,
	Parent = screen,
})
New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, 0, 0, 5),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.2,
	ZIndex = 20,
	Parent = homeBar,
}, { Make.Corner(3) })

local isOpen = false
local currentApp: App? = nil
local onState: ((state: { [string]: any }) -> ())? = nil
local bootedPhone: string? = nil
local booting = false
local stack: { { id: string, arg: any } } = {}

local backButton = Make.Button("‹", T.card, function()
	Phone.Back()
end, { Size = UDim2.fromOffset(32, 28), Position = UDim2.fromOffset(6, 4), TextSize = 22, Parent = appBar })
local _ = backButton

function Phone.Register(app: App)
	table.insert(apps, app)
	appsById[app.id] = app
end

local function currentPhone()
	return Phones.ById[Store.Get().phone or Phones.StarterId] or Phones.ById[Phones.StarterId]
end

local function styleBody()
	local p = currentPhone()
	body.BackgroundColor3 = p.frame
	bodyCorner.CornerRadius = UDim.new(0, p.corner + 7)
	screenCorner.CornerRadius = UDim.new(0, p.corner)
	-- small (phone) screens get a near full-height phone so apps stay usable
	local camera = workspace.CurrentCamera
	local small = camera ~= nil and camera.ViewportSize.Y < 520
	local height = if small then 0.94 else math.min(0.9, 0.74 * p.screen)
	body.Size = UDim2.fromScale(height * 0.48, height)
	brandLabel.Text = p.brand
	if p.id == "nvdr_p1" then
		-- black glass body with the neon green edge from the product shot
		bodyStroke.Color = Color3.fromRGB(57, 255, 20)
		bodyStroke.Thickness = 2.5
		if not glowStroke then
			local glowFrame = New("Frame", {
				Name = "Glow",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, 6, 1, 6),
				ZIndex = 0,
				Parent = body,
			}, { New("UICorner", { CornerRadius = UDim.new(0, p.corner + 10) }) })
			glowStroke = New(
				"UIStroke",
				{ Color = Color3.fromRGB(57, 255, 20), Thickness = 5, Transparency = 0.7, Parent = glowFrame }
			)
		end
	else
		bodyStroke.Color = p.frame:Lerp(Color3.new(1, 1, 1), 0.25)
		bodyStroke.Thickness = 2
		if glowStroke then
			(glowStroke.Parent :: Instance):Destroy()
			glowStroke = nil
		end
	end
	local wp = Phones.Wallpapers[Store.Get().wallpaper or 1] or Phones.Wallpapers[1]
	wallpaper.Color = ColorSequence.new(wp[1], wp[2])
end

local function renderHome()
	Make.Clear(home)
	local s = Store.Get()
	table.sort(apps, function(a, b)
		return a.order < b.order
	end)
	for _, app in apps do
		if not app.visible or app.visible(s) then
			local tile = New("TextButton", {
				BackgroundTransparency = 1,
				Text = "",
				LayoutOrder = app.order,
				Parent = home,
			})
			New("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromOffset(52, 52),
				BackgroundColor3 = app.color,
				Text = app.icon,
				TextSize = 26,
				Font = T.bold,
				TextColor3 = Color3.new(1, 1, 1),
				Parent = tile,
			}, { Make.Corner(14) })
			Make.Label(Store.T("app_" .. app.id), 11, Color3.new(1, 1, 1), T.bold, {
				Position = UDim2.fromOffset(0, 56),
				Size = UDim2.new(1, 0, 0, 16),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Parent = tile,
			})
			tile.Activated:Connect(function()
				Phone.OpenApp(app.id)
			end)
		end
	end
end

local function showApp(id: string, arg: any)
	local app = appsById[id]
	if not app then
		return
	end
	Make.Clear(appContent)
	currentApp = app
	appTitle.Text = Store.T("app_" .. id)
	home.Visible = false
	appView.Visible = true
	onState = app.build(appContent, arg)
end

function Phone.OpenApp(id: string, arg: any)
	if not isOpen then
		Phone.Open()
	end
	table.insert(stack, { id = id, arg = arg })
	showApp(id, arg)
end

-- Replace the current app view without growing the back stack.
function Phone.Replace(id: string, arg: any)
	if #stack > 0 then
		stack[#stack] = { id = id, arg = arg }
	else
		table.insert(stack, { id = id, arg = arg })
	end
	showApp(id, arg)
end

function Phone.Home()
	stack = {}
	currentApp = nil
	onState = nil
	Make.Clear(appContent)
	appView.Visible = false
	home.Visible = true
	renderHome()
end

function Phone.Back()
	table.remove(stack)
	local top = stack[#stack]
	if top then
		showApp(top.id, top.arg)
	else
		Phone.Home()
	end
end

function Phone.IsOpen(): boolean
	return isOpen
end

function Phone.Open()
	if isOpen then
		return
	end
	isOpen = true
	styleBody()
	body.Visible = true
	if pcMode then
		body.Position = PC_OPEN -- on the monitor: just there
	else
		body.Position = CLOSED
		TweenService:Create(body, TweenInfo.new(0.35, Enum.EasingStyle.Quint), { Position = OPEN }):Play()
	end
	local p = currentPhone()
	if bootedPhone ~= p.id and not booting then
		booting = true
		bootedPhone = p.id
		if not currentApp then
			Phone.Home()
		end
		task.spawn(function()
			if p.boot == "NVDR" then
				Boot.NVDR(screen)
			else
				Boot.Simple(screen, p.name, p.accent)
			end
			booting = false
		end)
	elseif not currentApp then
		Phone.Home()
	end
end

function Phone.Close()
	if not isOpen then
		return
	end
	isOpen = false
	if pcMode then
		body.Visible = false
		setPcMode(false) -- next time it's the phone again
		return
	end
	local tw = TweenService:Create(body, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Position = CLOSED })
	tw:Play()
	tw.Completed:Once(function()
		if not isOpen then
			body.Visible = false
		end
	end)
end

-- Opens the phone's apps on a PC monitor (Admin Tower offices).
function Phone.OpenPC(monitor: BasePart?)
	if not monitor or not monitor:IsDescendantOf(workspace) then
		return
	end
	if isOpen then
		Phone.Close()
		task.wait(0.35)
	end
	setPcMode(true, monitor)
	Phone.Open()
end

function Phone.Toggle()
	if isOpen then
		Phone.Close()
	else
		Phone.Open()
	end
end

-- Changing phones re-runs the boot animation the next time it opens.
local lastPhoneId: string? = nil
Store.Changed:Connect(function(s)
	if s.phone ~= lastPhoneId then
		if lastPhoneId ~= nil then
			bootedPhone = nil
		end
		lastPhoneId = s.phone
	end
	if isOpen then
		styleBody()
		if currentApp and onState then
			onState(s)
		elseif not currentApp then
			renderHome()
		end
	end
end)

homeBar.Activated:Connect(Phone.Home)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.P then
		Phone.Toggle()
	end
end)

-- Live in-game clock in the status bar.
task.spawn(function()
	while true do
		local h = Lighting.ClockTime
		clock.Text = string.format("%02d:%02d", math.floor(h), math.floor((h % 1) * 60))
		task.wait(1)
	end
end)

return Phone
