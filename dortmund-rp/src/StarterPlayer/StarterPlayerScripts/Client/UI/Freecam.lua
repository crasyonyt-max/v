--!strict
-- V1.0 admin freecam (Admin app → Ich / Me).
--   free:    fly the camera: WASD + Q/E (down/up), Shift = fast, right mouse / drag = look;
--            touch: on-screen arrows, ▲▼ for height, drag on the screen to look
--   orbit:   while spectating a player the camera circles around them: drag = turn,
--            mouse wheel / pinch / + − = closer / further; it follows them
-- Only the camera moves; your character stays where it is.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Make = require(script.Parent.Make)

local New, T = Make.New, Make.Theme
local me = Players.LocalPlayer

local Freecam = {}

local active = false
local orbitTarget: Model? = nil
local pos = Vector3.zero
local yaw, pitch = 0, 0
local distance = 18
local saved: { [string]: any }? = nil
local held: { [string]: boolean } = {}
local dragLast: Vector2? = nil
local conn: RBXScriptConnection? = nil

local gui = New("ScreenGui", {
	Name = "Freecam",
	ResetOnSpawn = false,
	DisplayOrder = 50,
	Enabled = false,
	Parent = me:WaitForChild("PlayerGui"),
})
local title = Make.Label("", 14, Color3.new(1, 1, 1), T.bold, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 60),
	Size = UDim2.fromOffset(360, 26),
	BackgroundTransparency = 0.3,
	BackgroundColor3 = Color3.new(0, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = gui,
}, { Make.Corner(8) })
Make.Button("✕ Freecam", T.bad, function()
	Freecam.Stop()
end, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 60),
	Size = UDim2.fromOffset(120, 36),
	Parent = gui,
})

-- touch / click buttons that are "held" while pressed
local function holdButton(text: string, key: string, pos2: UDim2)
	local b = New("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos2,
		Size = UDim2.fromOffset(60, 60),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.75,
		Text = text,
		TextSize = 24,
		Font = T.black,
		TextColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Parent = gui,
	}, { Make.Corner(14) })
	b.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			held[key] = true
		end
	end)
	b.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			held[key] = false
		end
	end)
end
-- left: move; right: up/down (free) or closer/further (orbit)
holdButton("▲", "fwd", UDim2.new(0, 110, 1, -170))
holdButton("▼", "back", UDim2.new(0, 110, 1, -50))
holdButton("◀", "left", UDim2.new(0, 50, 1, -110))
holdButton("▶", "right", UDim2.new(0, 170, 1, -110))
holdButton("⤒", "up", UDim2.new(1, -60, 1, -170))
holdButton("⤓", "down", UDim2.new(1, -60, 1, -90))

local function keyDown(k: Enum.KeyCode): boolean
	return UserInputService:IsKeyDown(k) and not UserInputService:GetFocusedTextBox()
end

local function rootOf(m: Model?): BasePart?
	return m and (m:FindFirstChild("HumanoidRootPart") :: BasePart?) or nil
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	local fwd = (if held.fwd or keyDown(Enum.KeyCode.W) then 1 else 0)
		- (if held.back or keyDown(Enum.KeyCode.S) then 1 else 0)
	local side = (if held.right or keyDown(Enum.KeyCode.D) then 1 else 0)
		- (if held.left or keyDown(Enum.KeyCode.A) then 1 else 0)
	local vert = (if held.up or keyDown(Enum.KeyCode.E) then 1 else 0)
		- (if held.down or keyDown(Enum.KeyCode.Q) then 1 else 0)
	local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local target = rootOf(orbitTarget)
	if target then
		-- orbit: arrows turn around the player, ⤒⤓ / Q E zoom
		yaw -= side * dt * 1.6
		pitch = math.clamp(pitch - fwd * dt * 1.0, -1.4, 0.6)
		distance = math.clamp(distance - vert * dt * 25, 4, 120)
		rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
		local focus = target.Position + Vector3.new(0, 2, 0)
		camera.CFrame = CFrame.new(focus - rot.LookVector * distance, focus)
		title.Text = "🎥 Freecam · " .. (orbitTarget :: Model).Name
		return
	end
	local speed = if keyDown(Enum.KeyCode.LeftShift) then 360 else 120
	local move = rot.LookVector * fwd + rot.RightVector * side + Vector3.yAxis * vert
	if move.Magnitude > 0 then
		pos += move.Unit * speed * dt
	end
	camera.CFrame = CFrame.new(pos) * rot
	title.Text = "🎥 Freecam"
end

-- look around: right mouse drag (PC) or drag anywhere not on a button (touch)
UserInputService.InputChanged:Connect(function(input, processed)
	if not active then
		return
	end
	if
		input.UserInputType == Enum.UserInputType.MouseMovement
		and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	then
		yaw -= input.Delta.X * 0.005
		pitch = math.clamp(pitch - input.Delta.Y * 0.005, -1.45, 1.45)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and orbitTarget then
		distance = math.clamp(distance - input.Position.Z * 3, 4, 120)
	elseif input.UserInputType == Enum.UserInputType.Touch and not processed then
		local p = Vector2.new(input.Position.X, input.Position.Y)
		if dragLast then
			local d = p - dragLast
			yaw -= d.X * 0.006
			pitch = math.clamp(pitch - d.Y * 0.006, -1.45, 1.45)
		end
		dragLast = p
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		dragLast = nil
	end
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and active then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and active then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end)

-- start; if `target` (a character) is given, orbit around it
function Freecam.Start(target: Model?)
	local camera = Workspace.CurrentCamera
	if not active then
		saved = { type = camera.CameraType, subject = camera.CameraSubject }
	end
	active = true
	orbitTarget = target
	local look = camera.CFrame.LookVector
	pos = camera.CFrame.Position
	yaw = math.atan2(-look.X, -look.Z)
	pitch = math.asin(math.clamp(look.Y, -1, 1))
	distance = if target and rootOf(target)
		then math.clamp(((rootOf(target) :: BasePart).Position - pos).Magnitude, 8, 60)
		else 18
	camera.CameraType = Enum.CameraType.Scriptable
	-- your character doesn't walk off while you steer the camera
	local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
	if hum and saved then
		saved.walk = hum.WalkSpeed
		hum.WalkSpeed = 0
	end
	gui.Enabled = true
	if conn then
		conn:Disconnect()
	end
	conn = RunService.RenderStepped:Connect(step)
end

function Freecam.Stop()
	if not active then
		return
	end
	active = false
	if conn then
		conn:Disconnect()
		conn = nil
	end
	gui.Enabled = false
	table.clear(held)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	local camera = Workspace.CurrentCamera
	local s = saved
	camera.CameraType = if s then s.type else Enum.CameraType.Custom
	if s and s.subject and (s.subject :: Instance).Parent then
		camera.CameraSubject = s.subject
	end
	local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
	if hum and s and s.walk then
		hum.WalkSpeed = s.walk
	end
	saved = nil
end

function Freecam.IsActive(): boolean
	return active
end

return Freecam
