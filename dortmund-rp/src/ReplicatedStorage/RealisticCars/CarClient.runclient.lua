--[[
	Realistic Cars - client

	* While you drive: reads keyboard / gamepad / touch, runs the physics for
	  your car, shows the dashboard HUD.
	* For every car: animates wheels (suspension, steering, spin) and engine sound.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local root = script.Parent
local Configs = require(root.Configs)
local CarTuning = require(script.Parent.CarTuning)
local Sim = require(root.Sim)
-- Dortmund RP: the game's own dashboard + touch pedals drive cars (see CarInput)
local CarInput = require(root.CarInput)
local stateRemote = root:WaitForChild("CarState")
local commandRemote = root:WaitForChild("CarCommand")

local MPS = Configs.METERS_PER_STUD
local TAU = math.pi * 2
local VISUAL_RANGE = 450 -- studs

local player = Players.LocalPlayer
local driving = nil
local handbrakeHeld = false
local useMph = false
local lastReset = 0

-------------------------------------------------------------------------------
-- HUD
-------------------------------------------------------------------------------

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, val in pairs(props) do
		inst[k] = val
	end
	inst.Parent = parent
	return inst
end

local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local gui = make("ScreenGui", { Name = "CarHUD", ResetOnSpawn = false, Enabled = false, IgnoreGuiInset = false }, player:WaitForChild("PlayerGui"))
local panel = make("Frame", {
	AnchorPoint = touchOnly and Vector2.new(0.5, 0) or Vector2.new(1, 1),
	Position = touchOnly and UDim2.new(0.5, 0, 0, 8) or UDim2.new(1, -20, 1, -20),
	Size = UDim2.fromOffset(300, 132),
	BackgroundColor3 = Color3.fromRGB(12, 13, 16),
	BackgroundTransparency = 0.3,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)

local function label(props)
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or Color3.fromRGB(240, 240, 240)
	props.Font = props.Font or Enum.Font.GothamBold
	return make("TextLabel", props, panel)
end
local speedLabel = label({ Position = UDim2.fromOffset(16, 6), Size = UDim2.fromOffset(170, 62), Text = "0", TextSize = 58, TextXAlignment = Enum.TextXAlignment.Left })
local unitLabel = label({ Position = UDim2.fromOffset(18, 66), Size = UDim2.fromOffset(100, 18), Text = "km/h", TextSize = 15, Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(170, 170, 175), TextXAlignment = Enum.TextXAlignment.Left })
local gearLabel = label({ Position = UDim2.new(1, -96, 0, 6), Size = UDim2.fromOffset(80, 62), Text = "N", TextSize = 58, TextXAlignment = Enum.TextXAlignment.Right })
local modeLabel = label({ Position = UDim2.new(1, -136, 0, 66), Size = UDim2.fromOffset(120, 18), Text = "AUTO", TextSize = 14, Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(170, 170, 175), TextXAlignment = Enum.TextXAlignment.Right })
local rpmBack = make("Frame", { Position = UDim2.new(0, 16, 1, -38), Size = UDim2.new(1, -32, 0, 10), BackgroundColor3 = Color3.fromRGB(45, 46, 52), BorderSizePixel = 0 }, panel)
make("UICorner", { CornerRadius = UDim.new(0, 4) }, rpmBack)
local redZone = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.1, 1), BackgroundColor3 = Color3.fromRGB(120, 20, 24), BorderSizePixel = 0 }, rpmBack)
make("UICorner", { CornerRadius = UDim.new(0, 4) }, redZone)
local rpmFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(235, 235, 235), BorderSizePixel = 0, ZIndex = 2 }, rpmBack)
make("UICorner", { CornerRadius = UDim.new(0, 4) }, rpmFill)
local rpmLabel = label({ Position = UDim2.new(0, 16, 1, -24), Size = UDim2.fromOffset(110, 18), Text = "0 rpm", TextSize = 13, Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(170, 170, 175), TextXAlignment = Enum.TextXAlignment.Left })
local assistLabel = label({ Position = UDim2.new(1, -196, 1, -24), Size = UDim2.fromOffset(180, 18), Text = "", TextSize = 13, RichText = true, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Right })

local helpText = table.concat({
	"<b>W/S</b> throttle / brake (hold S to reverse)",
	"<b>A/D</b> steer    <b>Space</b> handbrake",
	"<b>E/Q</b> shift up / down (switches to manual)",
	"<b>M</b> auto / manual   <b>T</b> traction control   <b>B</b> ABS",
	"<b>L</b> headlights   <b>G</b> siren   <b>R</b> flip car",
	"<b>U</b> km/h / mph   <b>F</b> get out   <b>H</b> hide help",
	"Gamepad: RT/LT pedals, stick steer, X handbrake, RB/LB shift",
}, "\n")
local help = make("TextLabel", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 20, 1, -20),
	Size = UDim2.fromOffset(360, 132),
	BackgroundColor3 = Color3.fromRGB(12, 13, 16),
	BackgroundTransparency = 0.35,
	Text = helpText,
	RichText = true,
	TextSize = 13,
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(225, 225, 228),
	TextXAlignment = Enum.TextXAlignment.Left,
	Visible = not touchOnly,
}, gui)
make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingTop = UDim.new(0, 8) }, help)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, help)

local function assistText(name, on, active)
	if not on then
		return string.format('<font color="#6a6a70">%s OFF</font>', name)
	end
	return string.format('<font color="%s">%s</font>', active and "#ffb020" or "#9a9aa0", name)
end

local function updateHud(sim, tel)
	local cfg = sim.cfg
	local speed = math.abs(tel.forward or tel.speed)
	CarInput.telemetry = {
		kmh = speed * 3.6,
		forward = (tel.forward or tel.speed) * 3.6,
		gear = tel.gear,
		rpm = tel.rpm,
		maxRPM = cfg.engine.maxRPM,
		redline = cfg.engine.redline,
	}
	speedLabel.Text = tostring(math.floor(speed * (useMph and 2.23694 or 3.6) + 0.5))
	unitLabel.Text = useMph and "mph" or "km/h"
	gearLabel.Text = tel.gear == -1 and "R" or tel.gear == 0 and "N" or tostring(tel.gear)
	modeLabel.Text = sim.auto and "AUTO" or "MANUAL"
	local e = cfg.engine
	rpmFill.Size = UDim2.fromScale(math.clamp(tel.rpm / e.maxRPM, 0, 1), 1)
	rpmFill.BackgroundColor3 = tel.rpm > e.redline - 300 and Color3.fromRGB(255, 70, 60) or Color3.fromRGB(235, 235, 235)
	redZone.Size = UDim2.fromScale(1 - e.redline / e.maxRPM + 0.02, 1)
	rpmLabel.Text = string.format("%d rpm", math.floor(tel.rpm / 50 + 0.5) * 50)
	assistLabel.Text = assistText("ABS", sim.absOn, tel.absActive) .. "   " .. assistText("TCS", sim.tcsOn, tel.tcsActive)
end

-------------------------------------------------------------------------------
-- Input
-------------------------------------------------------------------------------

local function keyDown(...)
	for _, k in ipairs({ ... }) do
		if UserInputService:IsKeyDown(k) then
			return true
		end
	end
	return false
end

local function readInput(seat)
	local K = Enum.KeyCode
	local throttle, brake, steer, analog = 0, 0, 0, false
	if not UserInputService:GetFocusedTextBox() then
		throttle = keyDown(K.W, K.Up) and 1 or 0
		brake = keyDown(K.S, K.Down) and 1 or 0
		steer = (keyDown(K.D, K.Right) and 1 or 0) - (keyDown(K.A, K.Left) and 1 or 0)
	end
	if UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		for _, st in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
			if st.KeyCode == K.ButtonR2 and st.Position.Z > 0.05 then
				throttle = math.max(throttle, st.Position.Z)
			elseif st.KeyCode == K.ButtonL2 and st.Position.Z > 0.05 then
				brake = math.max(brake, st.Position.Z)
			elseif st.KeyCode == K.Thumbstick1 and math.abs(st.Position.X) > 0.12 then
				local x = (math.abs(st.Position.X) - 0.12) / 0.88
				steer = math.sign(st.Position.X) * x ^ 1.4
				analog = true
			end
		end
	end
	-- Touch thumbstick (and anything else that drives the VehicleSeat).
	if throttle == 0 and brake == 0 then
		local tf = seat.ThrottleFloat
		throttle, brake = math.max(tf, 0), math.max(-tf, 0)
	end
	if steer == 0 then
		steer = seat.SteerFloat
	end
	if CarInput.external then
		throttle = math.max(throttle, CarInput.throttle)
		brake = math.max(brake, CarInput.brake)
		if steer == 0 then
			steer = CarInput.steer
		end
	end
	return throttle, brake, steer, analog
end

local function flipCar()
	if not driving or os.clock() - lastReset < 2 then
		return
	end
	lastReset = os.clock()
	local chassis = driving.model:FindFirstChild("Chassis")
	local cf = chassis.CFrame
	local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	end
	local pos = cf.Position + Vector3.new(0, 6, 0)
	driving.model:PivotTo(CFrame.lookAt(pos, pos + flat.Unit))
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	for _, w in ipairs(driving.sim.wheels) do
		w.omega = 0
	end
end

CarInput.flip = function()
	flipCar()
end

local function getOut()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Sit = false
		hum.Jump = true
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not driving then
		return
	end
	local K = Enum.KeyCode
	local key = input.KeyCode
	local sim = driving.sim
	if key == K.E or key == K.ButtonR1 then
		sim.auto = false
		sim:shiftUp()
	elseif key == K.Q or key == K.ButtonL1 then
		sim.auto = false
		sim:shiftDown()
	elseif key == K.M then
		sim.auto = not sim.auto
		if sim.auto and sim.gear == 0 then
			sim:shift(1)
		end
	elseif key == K.T then
		sim.tcsOn = not sim.tcsOn
	elseif key == K.B then
		sim.absOn = not sim.absOn
	elseif key == K.L or key == K.DPadUp then
		commandRemote:FireServer(driving.model, "Headlights")
	elseif key == K.G or key == K.DPadDown then
		commandRemote:FireServer(driving.model, "Siren")
	elseif key == K.R or key == K.ButtonY then
		flipCar()
	elseif key == K.U then
		useMph = not useMph
	elseif key == K.H then
		help.Visible = not help.Visible
	elseif key == K.F then
		getOut()
	end
end)

local function handbrakeAction(_, state)
	handbrakeHeld = state == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink
end

-------------------------------------------------------------------------------
-- Driving
-------------------------------------------------------------------------------

local function stopDriving()
	if not driving then
		return
	end
	driving = nil
	handbrakeHeld = false
	gui.Enabled = false
	ContextActionService:UnbindAction("CarHandbrake")
	ContextActionService:UnbindAction("CarFlip")
	pcall(function()
		ProximityPromptService.Enabled = true
	end)
end

local function startDriving(seat)
	local model = seat.Parent
	local cfg = CarTuning.For(model) -- Dortmund RP: per-car power + top speed
	if not cfg then
		return
	end
	stopDriving()
	local sim = Sim.fromModel(model, cfg)
	-- Moving car: start the wheels rolling so they do not lock up.
	local chassis = model:FindFirstChild("Chassis")
	local vF = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector) * MPS
	for _, w in ipairs(sim.wheels) do
		w.omega = vF / w.radius
	end
	driving = { model = model, seat = seat, sim = sim, cfg = cfg, lastSend = 0, sent = {} }
	gui.Enabled = false -- Dortmund RP: the game's own dashboard is shown instead
	ContextActionService:BindActionAtPriority("CarHandbrake", handbrakeAction, false, Enum.ContextActionPriority.High.Value + 50, Enum.KeyCode.Space, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("CarHandbrake", "Brake")
	if false then -- Dortmund RP: the flip button is on the game's dashboard (CarInput.flip)
		ContextActionService:BindAction("CarFlip", function(_, state)
			if state == Enum.UserInputState.Begin then
				flipCar()
			end
			return Enum.ContextActionResult.Sink
		end, true)
		ContextActionService:SetTitle("CarFlip", "Flip")
	end
	pcall(function()
		ProximityPromptService.Enabled = false
	end)
end

local function hookCharacter(char)
	local hum = char:WaitForChild("Humanoid")
	hum.Seated:Connect(function(active, seatPart)
		if active and seatPart and seatPart:IsA("VehicleSeat") and seatPart.Parent and seatPart.Parent:GetAttribute("CarType") then
			startDriving(seatPart)
		else
			stopDriving()
		end
	end)
	hum.Died:Connect(stopDriving)
end
if player.Character then
	task.spawn(hookCharacter, player.Character)
end
player.CharacterAdded:Connect(hookCharacter)

-------------------------------------------------------------------------------
-- Visuals for every car
-------------------------------------------------------------------------------

local visual = {} -- [model] = cache

local function getCache(model)
	local cache = visual[model]
	if cache then
		return cache
	end
	local cfg = CarTuning.For(model) -- Dortmund RP: per-car power + top speed
	local chassis = model:FindFirstChild("Chassis")
	if not cfg or not chassis then
		return nil
	end
	cache = {
		cfg = cfg,
		chassis = chassis,
		motors = Sim.getMotors(model),
		mounts = Sim.getMounts(model),
		params = Sim.makeRaycastParams(model),
		paramsAge = os.clock(),
		len = {},
		spin = {},
		sound = chassis:FindFirstChild("Engine"),
	}
	for _, name in ipairs({ "FL", "FR", "RL", "RR" }) do
		cache.len[name] = cfg.suspension.restLength
		cache.spin[name] = 0
	end
	visual[model] = cache
	return cache
end
CollectionService:GetInstanceRemovedSignal("RealisticCar"):Connect(function(model)
	visual[model] = nil
end)

local function setEngineSound(cache, rpm, throttle)
	local sound = cache.sound
	if sound then
		local e = cache.cfg.engine
		sound.PlaybackSpeed = 0.55 + (rpm / e.redline) * 1.25
		sound.Volume = 0.25 + 0.35 * throttle
	end
end

local function animateOtherCar(model, cache, dt)
	local cfg, chassis = cache.cfg, cache.chassis
	local cf = chassis.CFrame
	local up = cf.UpVector
	local vF = chassis.AssemblyLinearVelocity:Dot(cf.LookVector) * MPS
	local steerAngle = model:GetAttribute("Steer") or 0
	local s = cfg.suspension
	if os.clock() - cache.paramsAge > 3 then
		cache.params = Sim.makeRaycastParams(model)
		cache.paramsAge = os.clock()
	end
	for name, motor in pairs(cache.motors) do
		local origin = cf:PointToWorldSpace(cache.mounts[name])
		local hit = workspace:Raycast(origin, -up * ((s.restLength + cfg.wheelRadius) / MPS), cache.params)
		local target = s.restLength
		if hit then
			target = math.max((hit.Position - origin).Magnitude * MPS - cfg.wheelRadius, s.restLength - s.travel)
		end
		cache.len[name] += (target - cache.len[name]) * math.min(1, dt * 25)
		cache.spin[name] = (cache.spin[name] + vF / cfg.wheelRadius * dt) % TAU
		local steer = name:sub(1, 1) == "F" and steerAngle or 0
		motor.Transform = CFrame.new(0, -cache.len[name] / MPS, 0) * CFrame.Angles(0, steer, 0) * CFrame.Angles(-cache.spin[name], 0, 0)
	end
	setEngineSound(cache, model:GetAttribute("RPM") or cfg.engine.idleRPM, model:GetAttribute("Throttle") or 0)
end

RunService.Heartbeat:Connect(function(dt)
	local d = driving
	if d then
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not d.model.Parent or not hum or hum.SeatPart ~= d.seat then
			stopDriving()
		else
			local sim = d.sim
			local throttle, brake, steer, analog = readInput(d.seat)
			local inp = sim.input
			inp.throttle, inp.brake, inp.steer, inp.analog = throttle, brake, steer, analog
			inp.handbrake = handbrakeHeld and 1 or 0
			local tel = sim:step(dt)
			sim:updateVisuals(sim.motors)
			updateHud(sim, tel)
			local cache = getCache(d.model)
			if cache then
				setEngineSound(cache, tel.rpm, tel.throttle)
			end

			d.lastSend += dt
			if d.lastSend >= 0.08 then
				d.lastSend = 0
				local wheelSteer = (sim.wheels.FL.steer + sim.wheels.FR.steer) / 2
				local brakeOn = tel.brake > 0.05
				local s = d.sent
				if math.abs((s.steer or 99) - wheelSteer) > 0.01 or math.abs((s.rpm or -1e9) - tel.rpm) > 40
					or s.gear ~= tel.gear or s.brake ~= brakeOn or math.abs((s.throttle or -1) - tel.throttle) > 0.08 then
					s.steer, s.rpm, s.gear, s.brake, s.throttle = wheelSteer, tel.rpm, tel.gear, brakeOn, tel.throttle
					stateRemote:FireServer(d.model, wheelSteer, tel.rpm, tel.gear, brakeOn, tel.throttle)
				end
			end
		end
	end

	local camPos = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or Vector3.zero
	for _, model in ipairs(CollectionService:GetTagged("RealisticCar")) do
		if not (driving and driving.model == model) and model.Parent then
			local cache = getCache(model)
			if cache and (cache.chassis.Position - camPos).Magnitude < VISUAL_RANGE then
				animateOtherCar(model, cache, dt)
			end
		end
	end
end)
