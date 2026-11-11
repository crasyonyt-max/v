--!strict
-- Driving (client owns the car's physics while driving) + dashboard UI.
-- Keys: W/S gas/brake, A/D steer, L lights, Q/E indicators, X hazards,
--       B blue lights, N siren, V first-person camera. Mobile: on-screen buttons.
-- Motorbike stunts: hold F = wheelie, 1 = one hand, 2 = no hands (no steering then).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Make = require(script.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.UI.Notify)
local Net = require(script.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme

local player = Players.LocalPlayer
local VehicleController = {}

local WHEEL_DIR = -1 -- forward = negative hinge speed about +X (see VehicleBuilder)
local REVERSE_KMH = 30

-- Dashboard --------------------------------------------------------------------------
local gui = New("ScreenGui", {
	Name = "Dashboard",
	ResetOnSpawn = false,
	DisplayOrder = 8,
	Enabled = false,
	Parent = player:WaitForChild("PlayerGui"),
})

local dash = New("Frame", {
	Name = "Dash",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.fromOffset(340, 118),
	BackgroundColor3 = Color3.fromRGB(8, 8, 10),
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { Make.Corner(16), Make.Stroke(Color3.fromRGB(60, 60, 70), 1) })

local speedLabel = New("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(110, 8),
	Size = UDim2.fromOffset(120, 50),
	Text = "0",
	TextScaled = true,
	Font = T.black,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = dash,
})
Make.Label("km/h", 12, T.sub, T.bold, {
	Position = UDim2.fromOffset(110, 56),
	Size = UDim2.fromOffset(120, 16),
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = dash,
})
local gearLabel = New("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(240, 14),
	Size = UDim2.fromOffset(90, 40),
	RichText = true,
	Text = "P",
	TextScaled = true,
	Font = T.black,
	TextColor3 = T.sub,
	Parent = dash,
})
local function bar(y: number, color: Color3, label: string): Frame
	Make.Label(
		label,
		10,
		T.sub,
		T.bold,
		{ Position = UDim2.fromOffset(12, y - 13), Size = UDim2.fromOffset(90, 12), Parent = dash }
	)
	local back = New(
		"Frame",
		{ Position = UDim2.fromOffset(12, y), Size = UDim2.fromOffset(90, 8), BackgroundColor3 = T.card, Parent = dash },
		{ Make.Corner(4) }
	)
	return New("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = color, Parent = back }, { Make.Corner(4) })
end
local rpmBar = bar(26, Color3.fromRGB(240, 80, 60), "RPM ×1000")
local fuelBar = bar(56, Color3.fromRGB(250, 190, 30), "⛽")
local leftArrow = Make.Label(
	"◀",
	22,
	Color3.fromRGB(60, 60, 60),
	T.black,
	{ Position = UDim2.fromOffset(84, 14), Size = UDim2.fromOffset(24, 30), Parent = dash }
)
local rightArrow = Make.Label(
	"▶",
	22,
	Color3.fromRGB(60, 60, 60),
	T.black,
	{ Position = UDim2.fromOffset(232, 52), Size = UDim2.fromOffset(24, 30), Parent = dash }
)
local lightIcon = Make.Label(
	"💡",
	16,
	T.sub,
	T.font,
	{ Position = UDim2.fromOffset(12, 68), Size = UDim2.fromOffset(30, 20), Parent = dash }
)

local buttons = New("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(8, 86),
	Size = UDim2.new(1, -16, 0, 26),
	Parent = dash,
}, { Make.List(4, true) })

-- State --------------------------------------------------------------------------------
local car: Model? = nil
local seat: VehicleSeat? = nil
local motors: { HingeConstraint } = {}
local steers: { HingeConstraint } = {}
local conn: RBXScriptConnection? = nil
local firstPerson = false
local lastBrake = false
local lastBrakeSent = 0
local warnedFuel = false
local isBike = false
local hands = "" -- "" | "OneHand" | "NoHands" (shown to everyone via the server)
local wheelieAngle = 0 -- degrees, eased
local WHEELIE_MAX = 30

local function control(action: string, value: any?)
	task.spawn(function()
		local r = Net.Request("Vehicle.Control", action, value)
		if not r.ok and r.err ~= "too_fast" then
			Notify.Error(r.err)
		end
	end)
end

local function setCamera(fp: boolean)
	firstPerson = fp
	player.CameraMode = if fp then Enum.CameraMode.LockFirstPerson else Enum.CameraMode.Classic
	if not fp then
		player.CameraMaxZoomDistance = 128
		player.CameraMinZoomDistance = 0.5
	end
end

local function buildButtons()
	Make.Clear(buttons)
	local isEmergency = car ~= nil and car:GetAttribute("Emergency") == true
	local list = {
		{
			"💡",
			function()
				control("Headlights")
			end,
		},
		{
			"◀",
			function()
				control("Indicator", "L")
			end,
		},
		{
			"⚠",
			function()
				control("Indicator", "H")
			end,
		},
		{
			"▶",
			function()
				control("Indicator", "R")
			end,
		},
		{
			"🎥",
			function()
				setCamera(not firstPerson)
			end,
		},
	}
	if isBike then
		table.insert(list, {
			"✋",
			function()
				VehicleController.SetHands(if hands == "OneHand" then "" else "OneHand")
			end,
		})
		table.insert(list, {
			"🙌",
			function()
				VehicleController.SetHands(if hands == "NoHands" then "" else "NoHands")
			end,
		})
	end
	if isEmergency then
		table.insert(list, {
			"🔵",
			function()
				control("Bluelight")
			end,
		})
		table.insert(list, {
			"📢",
			function()
				control("Siren")
			end,
		})
	end
	-- shrink the buttons so they always fit the dashboard (police bike: 9 buttons)
	local width = math.min(40, math.floor((324 - 4 * (#list - 1)) / #list))
	for i, b in list do
		Make.Button(
			b[1],
			T.card,
			b[2],
			{ Size = UDim2.fromOffset(width, 26), TextSize = 14, LayoutOrder = i, Parent = buttons }
		)
	end
end

-- Input ------------------------------------------------------------------------------
-- Touch: transparent pedals + steering buttons. Keyboard: W/S/A/D or arrows.
-- Gamepad: the seat's own values. Steering is smoothed and re-centres by itself.
-- every touchscreen gets the buttons (some tablets also report a keyboard)
local isTouch = UserInputService.TouchEnabled
local touch = { gas = false, brake = false, left = false, right = false, wheelie = false }
-- which finger (InputObject) holds each button, so a lost "release" can never stick
local heldBy: { [string]: InputObject } = {}
local buttons: { [string]: TextButton } = {}

local function release(key: string)
	heldBy[key] = nil
	(touch :: any)[key] = false
	local b = buttons[key]
	if b then
		b.BackgroundTransparency = 0.82
	end
end

UserInputService.InputEnded:Connect(function(input)
	for key, held in heldBy do
		if held == input then
			release(key)
		end
	end
end)
local steerState, throttleState = 0, 0

local touchGui = New("ScreenGui", {
	Name = "DriveButtons",
	ResetOnSpawn = false,
	DisplayOrder = 9,
	Enabled = false,
	Parent = player:WaitForChild("PlayerGui"),
})
local function pedal(name: string, text: string, size: Vector2, position: UDim2, anchor: Vector2, key: string)
	local b = New("TextButton", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.82,
		Text = text,
		TextSize = 30,
		Font = T.black,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 0.25,
		AutoButtonColor = false,
		Parent = touchGui,
	}, { Make.Corner(18), Make.Stroke(Color3.new(1, 1, 1), 2, 0.6) })
	buttons[key] = b
	b.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			heldBy[key] = input;
			(touch :: any)[key] = true
			b.BackgroundTransparency = 0.6
		end
	end)
	b.InputEnded:Connect(function(input)
		if heldBy[key] == input then
			release(key)
		end
	end)
	return b
end
pedal("Left", "◀", Vector2.new(96, 96), UDim2.new(0, 20, 1, -24), Vector2.new(0, 1), "left")
pedal("Right", "▶", Vector2.new(96, 96), UDim2.new(0, 128, 1, -24), Vector2.new(0, 1), "right")
pedal("Gas", "GAS", Vector2.new(92, 150), UDim2.new(1, -20, 1, -24), Vector2.new(1, 1), "gas")
pedal("Brake", "BREMSE", Vector2.new(92, 96), UDim2.new(1, -124, 1, -24), Vector2.new(1, 1), "brake")
local wheelieButton =
	pedal("Wheelie", "WHEELIE", Vector2.new(92, 50), UDim2.new(1, -124, 1, -128), Vector2.new(1, 1), "wheelie")
wheelieButton.TextSize = 16
local exitButton = New("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -20, 0, 70),
	Size = UDim2.fromOffset(120, 40),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.5,
	Text = "🚪 Aussteigen",
	TextSize = 16,
	Font = T.bold,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = touchGui,
}, { Make.Corner(12) })
exitButton.Activated:Connect(function()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Jump = true
	end
end)

local controls: any = nil
local function setDefaultControls(enabled: boolean)
	if not isTouch then
		return
	end
	if not controls then
		local ok, module = pcall(function()
			return require((player:WaitForChild("PlayerScripts") :: any):WaitForChild("PlayerModule")):GetControls()
		end)
		controls = if ok then module else false
	end
	if controls then
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

local function keyDown(...: Enum.KeyCode): boolean
	if UserInputService:GetFocusedTextBox() then
		return false
	end
	for _, k in { ... } do
		if UserInputService:IsKeyDown(k) then
			return true
		end
	end
	return false
end

local function readInput(vseat: VehicleSeat, dt: number, speedRatio: number): (number, number)
	-- safety net: a held button whose finger is gone is released
	for key, input in heldBy do
		if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
			release(key)
		end
	end
	local tT = (if touch.gas then 1 else 0) - (if touch.brake then 1 else 0)
	local tS = (if touch.right then 1 else 0) - (if touch.left then 1 else 0)
	local kT = (if keyDown(Enum.KeyCode.W, Enum.KeyCode.Up) then 1 else 0)
		- (if keyDown(Enum.KeyCode.S, Enum.KeyCode.Down) then 1 else 0)
	local kS = (if keyDown(Enum.KeyCode.D, Enum.KeyCode.Right) then 1 else 0)
		- (if keyDown(Enum.KeyCode.A, Enum.KeyCode.Left) then 1 else 0)
	local rawT = if tT ~= 0 then tT elseif kT ~= 0 then kT else 0
	local rawS = if tS ~= 0 then tS elseif kS ~= 0 then kS else 0
	-- gamepad only: the seat's analogue values (ignored otherwise, they can lag / stick)
	if rawT == 0 and rawS == 0 and UserInputService.GamepadEnabled and not isTouch then
		rawT = vseat.ThrottleFloat
		rawS = if math.abs(vseat.SteerFloat) > 0.15 then vseat.SteerFloat else 0
	end
	-- steering eases in (slower at speed) and springs back to centre
	local inRate = 2.6 - 1.4 * speedRatio
	local outRate = 4.0
	local rate = if rawS == 0 or math.sign(rawS) ~= math.sign(steerState) then outRate else inRate
	steerState += math.clamp(rawS - steerState, -rate * dt, rate * dt)
	throttleState += math.clamp(rawT - throttleState, -4 * dt, 4 * dt)
	if rawT == 0 and math.abs(throttleState) < 0.05 then
		throttleState = 0
	end
	return throttleState, steerState
end

local hiddenPrompts: { ProximityPrompt } = {}

function VehicleController.SetHands(mode: string)
	if not car or not isBike or hands == mode then
		return
	end
	hands = mode
	control("Hands", mode)
	if mode == "NoHands" then
		Notify.Show(Store.T("stunt_no_hands"), false, 2.5)
	end
end

-- Leans the stabiliser's "up" forward so it holds the bike nose-up (wheelie).
local function setPitch(model: Model, degrees: number)
	local chassis = model.PrimaryPart
	local up = chassis and chassis:FindFirstChild("Upright") :: Attachment?
	if up then
		local a = math.rad(degrees)
		up.CFrame = CFrame.fromMatrix(up.Position, Vector3.new(0, math.cos(a), -math.sin(a)), Vector3.xAxis)
	end
end

local function stop()
	for _, pr in hiddenPrompts do
		if pr.Parent then
			pr.Enabled = true
		end
	end
	hiddenPrompts = {}
	if conn then
		conn:Disconnect()
		conn = nil
	end
	for _, m in motors do
		m.AngularVelocity = 0
		m.MotorMaxTorque = (m:GetAttribute("BaseTorque") or 5000) :: number
	end
	for _, s in steers do
		s.TargetAngle = 0
	end
	if firstPerson then
		setCamera(false)
	end
	if car and wheelieAngle ~= 0 then
		setPitch(car, 0)
	end
	wheelieAngle = 0
	hands = ""
	isBike = false
	car, seat = nil, nil
	motors, steers = {}, {}
	gui.Enabled = false
	touchGui.Enabled = false
	player:SetAttribute("DrivingTouch", nil)
	for key in touch do
		release(key)
	end
	setDefaultControls(true)
	steerState, throttleState = 0, 0
end

local function drive(dt: number)
	local model, vseat = car, seat
	if not model or not vseat or not model.PrimaryPart then
		return
	end
	local chassis = model.PrimaryPart :: BasePart
	local top = (model:GetAttribute("TopSpeed") or 100) :: number
	local accel = (model:GetAttribute("Accel") or 1) :: number
	local r = (model:GetAttribute("WheelRadius") or 1.3) :: number
	local fuel = (model:GetAttribute("Fuel") or 100) :: number
	local reverseTop = REVERSE_KMH / 3.6 * Config.StudsPerMeter

	local speedNow = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
	local throttle, steer = readInput(vseat, dt, math.clamp(math.abs(speedNow) / top, 0, 1))
	if fuel <= 0 then
		if throttle ~= 0 and not warnedFuel then
			warnedFuel = true
			Notify.Show(Store.T("out_of_fuel"), true)
		end
		throttle = math.min(throttle, 0)
	else
		warnedFuel = false
	end

	local speed = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector) -- studs/s, + = forward
	local accelRate = 8 + 9 * accel -- studs/s²
	local cmd = 0
	local torqueScale = 1
	local braking = false

	if throttle > 0.05 then
		if speed < -1 then
			cmd, torqueScale, braking = 0, 2.5, true
		else
			cmd = math.min(top, math.max(speed, 0) + accelRate * 0.3 * throttle)
			torqueScale = throttle
		end
	elseif throttle < -0.05 then
		if speed > 1 then
			cmd, torqueScale, braking = 0, 2.5, true
		else
			cmd = math.max(-reverseTop, math.min(speed, 0) - accelRate * 0.25 * -throttle)
			torqueScale = -throttle
		end
	else
		cmd = 0
		torqueScale = if math.abs(speed) < 1.5 then 1.5 else 0.06 -- hold when stopped, roll otherwise
	end

	for _, m in motors do
		local base = (m:GetAttribute("BaseTorque") or 5000) :: number
		m.MotorMaxTorque = base * torqueScale
		m.AngularVelocity = WHEEL_DIR * cmd / r
	end

	local speedRatio = math.clamp(math.abs(speed) / top, 0, 1)
	local maxAngle = 34 - 26 * math.clamp(speedRatio * 1.6, 0, 1)
	if isBike and hands == "NoHands" then
		steer, steerState = 0, 0 -- no hands, no steering
	end
	for _, s in steers do
		s.TargetAngle = -steer * maxAngle
	end

	if isBike then
		-- grip assist: a bike follows its front wheel, it never spins or slides sideways
		local wheelbase = (model:GetAttribute("Wheelbase") or 5.3) :: number
		local wanted = -speed * math.tan(math.rad(steer * maxAngle)) / wheelbase
		local av = chassis.AssemblyAngularVelocity
		local k = math.min(1, dt * 10)
		chassis.AssemblyAngularVelocity = Vector3.new(av.X, av.Y + (wanted - av.Y) * k, av.Z)
		local right = chassis.CFrame.RightVector
		local v = chassis.AssemblyLinearVelocity
		chassis.AssemblyLinearVelocity = v - right * v:Dot(right) * math.min(1, dt * 6)

		-- wheelie: hold F / the button while rolling forward
		local want = (touch.wheelie or keyDown(Enum.KeyCode.F)) and speed > 4
		local target = if want then WHEELIE_MAX else 0
		local step = (if want then 45 else 70) * dt
		local before = wheelieAngle
		wheelieAngle += math.clamp(target - wheelieAngle, -step, step)
		if wheelieAngle ~= before then
			setPitch(model, wheelieAngle)
		end
	end

	-- brake lights (rate limited)
	local now = os.clock()
	if braking ~= lastBrake and now - lastBrakeSent > 0.3 then
		lastBrake = braking
		lastBrakeSent = now
		control("Brake", braking)
	end

	-- dashboard
	local kmh = math.abs(speed) / Config.StudsPerMeter * 3.6
	speedLabel.Text = tostring(math.floor(kmh + 0.5))
	local gear = if math.abs(speed) < 0.5 and throttle == 0
		then "P"
		elseif speed < -0.5 or (throttle < 0 and speed < 1) then "R"
		else "D"
	gearLabel.Text = gear
	gearLabel.TextColor3 = if gear == "D"
		then Color3.fromRGB(120, 230, 140)
		elseif gear == "R" then Color3.fromRGB(250, 120, 120)
		else T.sub
	-- fake 6-speed gearbox for the rev counter
	local gearSpan = 1 / 6
	local inGear = (speedRatio % gearSpan) / gearSpan
	local rpm = if gear == "P" then 0.13 else 0.15 + inGear * 0.7 + math.abs(throttle) * 0.1
	rpmBar.Size = UDim2.fromScale(math.clamp(rpm, 0, 1), 1)
	fuelBar.Size = UDim2.fromScale(math.clamp(fuel / 100, 0, 1), 1)
	fuelBar.BackgroundColor3 = if fuel < 15 then T.bad else Color3.fromRGB(250, 190, 30)
	local ind = model:GetAttribute("Indicator")
	local blink = (os.clock() % 0.8) < 0.4
	leftArrow.TextColor3 = if (ind == "L" or ind == "H") and blink
		then Color3.fromRGB(60, 230, 90)
		else Color3.fromRGB(60, 60, 60)
	rightArrow.TextColor3 = if (ind == "R" or ind == "H") and blink
		then Color3.fromRGB(60, 230, 90)
		else Color3.fromRGB(60, 60, 60)
	lightIcon.TextTransparency = if model:GetAttribute("Headlights") then 0 else 0.7
end

local function start(vseat: VehicleSeat)
	local model = vseat.Parent
	if not model or not model:IsA("Model") then
		return
	end
	car, seat = model, vseat
	isBike = model:GetAttribute("Bike") == true
	hands, wheelieAngle = "", 0
	motors, steers = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("HingeConstraint") then
			if d.Name == "Motor" then
				table.insert(motors, d)
			elseif d.Name == "Steer" then
				table.insert(steers, d)
			end
		end
	end
	-- the car's own "Einsteigen" prompts would sit in your face while you drive
	hiddenPrompts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Enabled then
			d.Enabled = false
			table.insert(hiddenPrompts, d)
		end
	end
	buildButtons()
	gui.Enabled = true
	touchGui.Enabled = isTouch
	wheelieButton.Visible = isBike
	player:SetAttribute("DrivingTouch", isTouch)
	setDefaultControls(false)
	conn = RunService.Heartbeat:Connect(drive)
end

local function onCharacter(character: Model)
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	hum.Seated:Connect(function(active, seatPart)
		if active and seatPart and seatPart:IsA("VehicleSeat") and seatPart.Name == "DriveSeat" then
			start(seatPart)
		else
			stop()
		end
	end)
end

player.CharacterAdded:Connect(function(c)
	stop()
	onCharacter(c)
end)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not car then
		return
	end
	local k = input.KeyCode
	if k == Enum.KeyCode.L then
		control("Headlights")
	elseif k == Enum.KeyCode.Q then
		control("Indicator", "L")
	elseif k == Enum.KeyCode.E then
		control("Indicator", "R")
	elseif k == Enum.KeyCode.X then
		control("Indicator", "H")
	elseif k == Enum.KeyCode.B and car:GetAttribute("Emergency") then
		control("Bluelight")
	elseif k == Enum.KeyCode.N and car:GetAttribute("Emergency") then
		control("Siren")
	elseif k == Enum.KeyCode.V then
		setCamera(not firstPerson)
	elseif k == Enum.KeyCode.One and isBike then
		VehicleController.SetHands(if hands == "OneHand" then "" else "OneHand")
	elseif k == Enum.KeyCode.Two and isBike then
		VehicleController.SetHands(if hands == "NoHands" then "" else "NoHands")
	end
end)

return VehicleController
