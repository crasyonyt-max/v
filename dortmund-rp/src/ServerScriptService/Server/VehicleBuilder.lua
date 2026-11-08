--!strict
-- Builds the motorbike from parts, in the civilian paint colour or a job livery.
-- Model space: forward = -Z, right = +X, ground = y 0.
--
-- Physics layout (a two-wheeler that can't fall over)
--   Chassis (invisible, PrimaryPart) <- everything decorative is welded to it (Massless)
--   four hidden physics wheels in two narrow pairs (front pair steered, see AddPhysics)
--   plus the Stabilizer that keeps it upright. The visible front wheel, fork and
--   handlebar are welded to the left front wheel / knuckle, so they spin and steer.
-- The driver's client sets motor speed + steering angle (it owns the physics);
-- see StarterPlayerScripts/Client/Controllers/VehicleController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local VehicleBuilder = {}

local GLASS = Color3.fromRGB(25, 35, 45)
local TRIM = Color3.fromRGB(20, 20, 22)
local METAL = Color3.fromRGB(150, 152, 158)
local CHROME = Color3.fromRGB(205, 208, 214)

local SILVER = Color3.fromRGB(222, 224, 228)
local POL_BLUE = Color3.fromRGB(0, 58, 150)
local NEON_YELLOW = Color3.fromRGB(205, 230, 0)
local SIGNAL_RED = Color3.fromRGB(200, 20, 20)
local SNOW = Color3.fromRGB(242, 242, 242)
local ORANGE = Color3.fromRGB(255, 115, 0)

-- body: tank, tail, fenders · fairing: front cowl · panel: side panels + top case
-- stripe: reflective band · text: written on the top case
type Scheme = {
	body: Color3,
	fairing: Color3,
	panel: Color3,
	stripe: Color3?,
	stripe2: Color3?,
	reflective: boolean?,
	text: string?,
	textColor: Color3?,
}
local SCHEMES: { [string]: Scheme } = {
	Police = {
		body = SILVER,
		fairing = POL_BLUE,
		panel = SILVER,
		stripe = NEON_YELLOW,
		stripe2 = POL_BLUE,
		reflective = true,
		text = "POLIZEI",
		textColor = POL_BLUE,
	},
	Fire = {
		body = SIGNAL_RED,
		fairing = SIGNAL_RED,
		panel = SIGNAL_RED,
		stripe = SNOW,
		reflective = true,
		text = "FEUERWEHR",
		textColor = SNOW,
	},
	Rescue = {
		body = SNOW,
		fairing = SNOW,
		panel = SNOW,
		stripe = NEON_YELLOW,
		stripe2 = Color3.fromRGB(235, 40, 30),
		reflective = true,
		text = "RETTUNGSDIENST",
		textColor = Color3.fromRGB(200, 20, 20),
	},
	ADMC = {
		body = Color3.fromRGB(250, 205, 0),
		fairing = Color3.fromRGB(250, 205, 0),
		panel = Color3.fromRGB(250, 205, 0),
		stripe = TRIM,
		text = "ADMC",
		textColor = TRIM,
	},
	DXL = {
		body = Color3.fromRGB(255, 204, 0),
		fairing = Color3.fromRGB(255, 204, 0),
		panel = Color3.fromRGB(255, 204, 0),
		stripe = Color3.fromRGB(210, 20, 30),
		text = "DXL",
		textColor = Color3.fromRGB(210, 20, 30),
	},
	LKW = {
		body = Color3.fromRGB(40, 90, 60),
		fairing = Color3.fromRGB(40, 90, 60),
		panel = SNOW,
		stripe = Color3.fromRGB(240, 170, 30),
		text = "SPEDITION",
		textColor = Color3.fromRGB(40, 90, 60),
	},
	Admin = {
		body = ORANGE,
		fairing = TRIM,
		panel = ORANGE,
		stripe = TRIM,
		stripe2 = Color3.fromRGB(255, 160, 40),
		reflective = true,
		text = "ADMIN",
		textColor = TRIM,
	},
}
VehicleBuilder.Schemes = SCHEMES

-- extra text per job (both rescue jobs share one livery)
local TEXT_BY_JOB: { [string]: string } = { Notarzt = "NOTARZT" }

local function part(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	props: { [string]: any }?
): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.Massless = true
	p.Anchored = false
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

local function wedge(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	props: { [string]: any }?
): BasePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanTouch = false
	p.Massless = true
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

local function weld(a: BasePart, c: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = c
	w.Parent = c
end

local function textPanel(p: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if bg then 0 else 1
	label.BackgroundColor3 = bg or Color3.new(1, 1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.Parent = gui
	return label
end

-- Builds the plate parts and returns them; text is set by VehicleBuilder.SetPlate.
local function plate(model: Model, name: string, cf: CFrame, face: Enum.NormalId)
	local p = part(model, name, Vector3.new(2.4, 0.55, 0.08), cf, Color3.new(1, 1, 1))
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlateGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.Parent = p
	local eu = Instance.new("Frame")
	eu.Size = UDim2.fromScale(0.12, 1)
	eu.BackgroundColor3 = Color3.fromRGB(0, 50, 153)
	eu.BorderSizePixel = 0
	eu.Parent = gui
	local d = Instance.new("TextLabel")
	d.Size = UDim2.fromScale(1, 0.4)
	d.Position = UDim2.fromScale(0, 0.55)
	d.BackgroundTransparency = 1
	d.Text = "D"
	d.TextScaled = true
	d.Font = Enum.Font.GothamBold
	d.TextColor3 = Color3.new(1, 1, 1)
	d.Parent = eu
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(0.86, 0.9)
	label.Position = UDim2.fromScale(0.13, 0.05)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.Arcade -- closest built-in to the German FE-Schrift look
	label.TextColor3 = Color3.new(0, 0, 0)
	label.Text = ""
	label.Parent = gui
	return p
end

VehicleBuilder.MakePlate = plate
VehicleBuilder.TextPanel = textPanel

function VehicleBuilder.SetPlate(model: Model, text: string)
	model:SetAttribute("Plate", text)
	for _, name in { "PlateFront", "PlateRear" } do
		local p = model:FindFirstChild(name)
		local gui = p and p:FindFirstChild("PlateGui")
		local label = gui and gui:FindFirstChild("Text") :: TextLabel?
		if label then
			label.Text = text
		end
	end
end

function VehicleBuilder.SetColor(model: Model, color: Color3)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Paint") then
			d.Color = color
		end
	end
end

-- Wheels (front steered), motors, stabiliser and the attributes the client drives with.
-- wheelSpecs: { name, x, y, z (model space centre), r (radius), w (width), front }
function VehicleBuilder.AddPhysics(
	model: Model,
	chassis: BasePart,
	def: any,
	wheelSpecs: { any },
	mass: number,
	generatedWheels: boolean
)
	local wheelPhys = PhysicalProperties.new(1.2, 2, 0, 100, 1)

	local motors: { HingeConstraint } = {}
	local steering: { HingeConstraint } = {}

	local function makeWheel(spec: any)
		local name, x, y, z, front, r, wheelW = spec.name, spec.x, spec.y, spec.z, spec.front, spec.r, spec.w
		local wheel = Instance.new("Part")
		wheel.Name = name
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(wheelW, r * 2, r * 2)
		wheel.CFrame = CFrame.new(x, y, z)
		wheel.Color = TRIM
		wheel.Material = Enum.Material.SmoothPlastic
		wheel.CustomPhysicalProperties = wheelPhys
		wheel.CanCollide = true
		wheel.Parent = model
		if not generatedWheels then
			wheel.Transparency = 1 -- the body brings its own (visual) wheels
		end

		local noCol = Instance.new("NoCollisionConstraint")
		noCol.Part0 = chassis
		noCol.Part1 = wheel
		noCol.Parent = wheel

		local wheelAtt = Instance.new("Attachment")
		wheelAtt.Name = "Axle"
		wheelAtt.Parent = wheel

		local hub: BasePart = chassis
		if front then
			local knuckle = Instance.new("Part")
			knuckle.Name = "Knuckle"
			knuckle.Size = Vector3.new(1, 1, 1)
			knuckle.CFrame = CFrame.new(x, y, z)
			knuckle.Transparency = 1
			knuckle.CanCollide = false
			knuckle.CanQuery = false
			knuckle.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0)
			knuckle.Parent = model
			local nc2 = Instance.new("NoCollisionConstraint")
			nc2.Part0 = knuckle
			nc2.Part1 = wheel
			nc2.Parent = wheel

			local a0 = Instance.new("Attachment")
			a0.Name = "SteerBase"
			a0.Position = chassis.CFrame:PointToObjectSpace(Vector3.new(x, y, z))
			a0.Axis = Vector3.new(0, 1, 0)
			a0.SecondaryAxis = Vector3.new(1, 0, 0)
			a0.Parent = chassis
			local a1 = Instance.new("Attachment")
			a1.Name = "SteerKnuckle"
			a1.Axis = Vector3.new(0, 1, 0)
			a1.SecondaryAxis = Vector3.new(1, 0, 0)
			a1.Parent = knuckle
			local servo = Instance.new("HingeConstraint")
			servo.Name = "Steer"
			servo.ActuatorType = Enum.ActuatorType.Servo
			servo.Attachment0 = a0
			servo.Attachment1 = a1
			servo.ServoMaxTorque = 1e7
			servo.AngularSpeed = 5
			servo.TargetAngle = 0
			servo.LimitsEnabled = true
			servo.LowerAngle = -40
			servo.UpperAngle = 40
			servo.Parent = knuckle
			table.insert(steering, servo)
			hub = knuckle
		end

		local hubAtt = Instance.new("Attachment")
		hubAtt.Name = "AxleBase_" .. name
		hubAtt.Position = hub.CFrame:PointToObjectSpace(Vector3.new(x, y, z))
		hubAtt.Parent = hub

		local motor = Instance.new("HingeConstraint")
		motor.Name = "Motor"
		motor.ActuatorType = Enum.ActuatorType.Motor
		motor.Attachment0 = hubAtt
		motor.Attachment1 = wheelAtt
		motor.AngularVelocity = 0
		motor.MotorMaxTorque = 0 -- set below once total mass is known
		motor.MotorMaxAcceleration = math.huge
		motor.Parent = wheel
		table.insert(motors, motor)
	end

	for _, spec in wheelSpecs do
		makeWheel(spec)
	end

	-- Driving parameters for the client controller -----------------------------
	local topSpeed = def.speed / 3.6 * Config.StudsPerMeter -- studs/s
	local r = wheelSpecs[1].r
	model:SetAttribute("WheelRadius", r)
	model:SetAttribute("TopSpeed", topSpeed)
	model:SetAttribute("Accel", def.accel or 1)
	model:SetAttribute("Wheelbase", math.abs(wheelSpecs[3].z - wheelSpecs[1].z))
	model:SetAttribute("Emergency", def.emergency == true)
	model:SetAttribute("Headlights", false)
	model:SetAttribute("Indicator", "")
	model:SetAttribute("Bluelight", false)
	model:SetAttribute("Siren", false)
	model:SetAttribute("Brake", false)
	model:SetAttribute("Fuel", 100)

	-- Torque scales with mass so heavy trucks still move.
	local torquePerWheel = mass * 60 * r * math.max(0.6, def.accel or 1) / 4
	-- anti-roll stabiliser: keeps the car upright (does not affect steering / yaw)
	local upAtt = Instance.new("Attachment")
	upAtt.Name = "Upright"
	upAtt.Axis = Vector3.new(0, 1, 0)
	upAtt.SecondaryAxis = Vector3.new(1, 0, 0)
	upAtt.Parent = chassis
	local upright = Instance.new("AlignOrientation")
	upright.Name = "Stabilizer"
	upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
	upright.AlignType = Enum.AlignType.PrimaryAxisParallel
	upright.PrimaryAxis = Vector3.new(0, 1, 0)
	upright.Attachment0 = upAtt
	upright.MaxTorque = mass * 400
	upright.Responsiveness = 10
	upright.Parent = chassis

	for _, m in motors do
		m.MotorMaxTorque = torquePerWheel
		m:SetAttribute("BaseTorque", torquePerWheel)
	end
end

-- A cylinder part from a to b (its axis is X).
local function tube(
	model: Model,
	name: string,
	a: Vector3,
	b: Vector3,
	d: number,
	color: Color3,
	props: { [string]: any }?
)
	local dir = b - a
	local up = if math.abs(dir.Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	local cf = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0)
	local p = part(model, name, Vector3.new(dir.Magnitude, d, d), cf, color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A wheel (tyre, rim, hub, brake disc) centred on x = 0, welded to `to` so it spins with it.
local function visualWheel(model: Model, to: BasePart, y: number, z: number, r: number, front: boolean)
	local axle = CFrame.new(0, y, z)
	local function disc(name: string, w: number, d: number, x: number, color: Color3, material: Enum.Material)
		local p = part(model, name, Vector3.new(w, d, d), axle * CFrame.new(x, 0, 0), color, {
			Shape = Enum.PartType.Cylinder,
			Material = material,
		})
		weld(to, p)
		return p
	end
	disc("Tyre", 0.55, r * 2, 0, Color3.fromRGB(22, 22, 24), Enum.Material.Rubber)
	disc("Rim", 0.6, r * 1.45, 0, Color3.fromRGB(40, 42, 46), Enum.Material.Metal)
	disc("Hub", 0.66, r * 0.4, 0, CHROME, Enum.Material.Metal)
	-- spokes so you can see the wheel turn
	for i = 0, 2 do
		local spoke = part(
			model,
			"Spoke",
			Vector3.new(0.12, r * 1.4, 0.16),
			axle * CFrame.Angles(i * math.pi / 3, 0, 0),
			CHROME,
			{ Material = Enum.Material.Metal }
		)
		weld(to, spoke)
	end
	if front then
		disc("BrakeDisc", 0.06, r * 1.15, -0.34, METAL, Enum.Material.Metal)
		disc("BrakeDisc", 0.06, r * 1.15, 0.34, METAL, Enum.Material.Metal)
	else
		disc("Sprocket", 0.06, r * 0.9, -0.34, TRIM, Enum.Material.Metal)
	end
end

-- Returns the model (unparented). `def` is a Vehicles catalog entry.
function VehicleBuilder.Build(def: any, color: Color3?): Model
	local scheme: Scheme? = if def.livery then SCHEMES[def.livery] else nil
	local paint = color or def.color
	local model = Instance.new("Model")
	model.Name = def.name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local R = 1.15 -- wheel radius (≈ 0.32 m)
	local zF, zR = -2.65, 2.65 -- axles (wheelbase ≈ 1.5 m)

	-- Chassis (invisible, collides, carries the mass)
	local chassis = part(model, "Chassis", Vector3.new(1.4, 0.8, 5), CFrame.new(0, 1.7, 0), TRIM, {
		CanCollide = true,
		Massless = false,
		Transparency = 1,
		CustomPhysicalProperties = PhysicalProperties.new(3, 0.3, 0.1),
	})
	model.PrimaryPart = chassis

	local function attach(p: BasePart): BasePart
		weld(chassis, p)
		return p
	end
	-- civilian: one paint colour (repaintable) · on duty: the job livery
	local function painted(p: BasePart, which: string): BasePart
		if scheme then
			p.Color = (scheme :: any)[which]
		else
			p.Color = paint
			p:SetAttribute("Paint", true)
		end
		p.Reflectance = 0.05
		return p
	end
	local function stripe(name: string, size: Vector3, cf: CFrame, c: Color3)
		local reflective = scheme ~= nil and scheme.reflective == true
		attach(part(model, name, size, cf, if reflective then c:Lerp(Color3.new(0, 0, 0), 0.25) else c, {
			Material = if reflective then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		}))
	end

	-- Engine + frame -------------------------------------------------------------------
	local ENGINE = Color3.fromRGB(58, 60, 64)
	attach(part(model, "Engine", Vector3.new(1.1, 1.1, 1.4), CFrame.new(0, 1.75, -0.35), ENGINE, {
		Material = Enum.Material.Metal,
	}))
	attach(
		part(
			model,
			"Cylinders",
			Vector3.new(1.5, 0.55, 0.7),
			CFrame.new(0, 2.3, -0.85) * CFrame.Angles(math.rad(20), 0, 0),
			METAL,
			{ Material = Enum.Material.Metal }
		)
	)
	for _, sx in { -1, 1 } do
		attach(tube(model, "Frame", Vector3.new(sx * 0.3, 3.5, -1.85), Vector3.new(sx * 0.35, 1.9, 0.6), 0.2, TRIM))
		attach(tube(model, "SubFrame", Vector3.new(sx * 0.3, 2.3, 0.4), Vector3.new(sx * 0.3, 2.85, 2.3), 0.14, TRIM))
		attach(tube(model, "Swingarm", Vector3.new(sx * 0.42, 1.75, 0.55), Vector3.new(sx * 0.42, R, zR), 0.24, METAL, {
			Material = Enum.Material.Metal,
		}))
	end
	attach(part(model, "Footpegs", Vector3.new(1.7, 0.12, 0.12), CFrame.new(0, 1.45, 0.35), TRIM))
	-- exhaust on the right
	attach(tube(model, "Exhaust", Vector3.new(0.4, 1.3, -0.5), Vector3.new(0.55, 1.55, 1.2), 0.22, CHROME, {
		Material = Enum.Material.Metal,
	}))
	attach(tube(model, "Muffler", Vector3.new(0.55, 1.55, 1.2), Vector3.new(0.62, 2.05, 2.55), 0.45, CHROME, {
		Material = Enum.Material.Metal,
	}))

	-- Bodywork --------------------------------------------------------------------------
	attach(painted(part(model, "Tank", Vector3.new(1.35, 0.85, 1.7), CFrame.new(0, 3.2, -0.85), paint), "body"))
	attach(painted(part(model, "TankTop", Vector3.new(1.1, 0.25, 1.4), CFrame.new(0, 3.72, -0.8), paint), "body"))
	attach(part(model, "SeatPad", Vector3.new(1.05, 0.3, 1.5), CFrame.new(0, 2.95, 0.55), TRIM, {
		Material = Enum.Material.Leather,
	}))
	attach(part(model, "PillionPad", Vector3.new(0.95, 0.3, 1.0), CFrame.new(0, 3.1, 1.65), TRIM, {
		Material = Enum.Material.Leather,
	}))
	attach(painted(part(model, "Tail", Vector3.new(0.9, 0.5, 1.4), CFrame.new(0, 2.72, 2.1), paint), "body"))
	attach(painted(part(model, "RearFender", Vector3.new(0.7, 0.12, 1.1), CFrame.new(0, 2.42, 2.9), paint), "body"))
	for _, sx in { -1, 1 } do
		attach(
			painted(
				part(model, "SidePanel", Vector3.new(0.1, 0.75, 1.6), CFrame.new(sx * 0.6, 2.45, 0.9), paint),
				"panel"
			)
		)
	end
	-- front cowl (frame mounted, like a touring bike) + windscreen
	attach(painted(part(model, "Fairing", Vector3.new(1.6, 1.25, 0.9), CFrame.new(0, 3.35, -2.15), paint), "fairing"))
	for _, sx in { -1, 1 } do
		attach(
			painted(
				part(model, "FairingSide", Vector3.new(0.1, 1.0, 1.2), CFrame.new(sx * 0.8, 3.0, -1.6), paint),
				"fairing"
			)
		)
	end
	attach(wedge(model, "Windshield", Vector3.new(1.4, 0.9, 0.5), CFrame.new(0, 4.42, -2.35), GLASS, {
		Transparency = 0.45,
		Material = Enum.Material.Glass,
	}))

	-- Lights + plate --------------------------------------------------------------------
	local head = attach(
		part(
			model,
			"Headlight",
			Vector3.new(0.9, 0.45, 0.1),
			CFrame.new(0, 3.4, -2.62),
			Color3.fromRGB(230, 230, 220),
			{
				Material = Enum.Material.Glass,
			}
		)
	)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Range = 60
	spot.Angle = 60
	spot.Brightness = 3
	spot.Enabled = false
	spot.Parent = head
	attach(part(model, "Taillight", Vector3.new(0.7, 0.25, 0.1), CFrame.new(0, 2.8, 2.82), Color3.fromRGB(120, 0, 0), {
		Material = Enum.Material.Glass,
	}))
	for _, sx in { -1, 1 } do
		local name = if sx < 0 then "IndicatorL" else "IndicatorR"
		local amber = Color3.fromRGB(120, 70, 0)
		attach(part(model, name, Vector3.new(0.25, 0.2, 0.3), CFrame.new(sx * 0.92, 3.3, -2.3), amber, {
			Material = Enum.Material.Glass,
		}))
		attach(part(model, name, Vector3.new(0.25, 0.2, 0.25), CFrame.new(sx * 0.45, 2.55, 2.85), amber, {
			Material = Enum.Material.Glass,
		}))
		-- mirrors on the cowl
		attach(
			tube(model, "MirrorArm", Vector3.new(sx * 0.7, 3.9, -2.0), Vector3.new(sx * 0.95, 4.15, -2.0), 0.08, TRIM)
		)
		attach(part(model, "Mirror", Vector3.new(0.45, 0.28, 0.12), CFrame.new(sx * 1.05, 4.2, -2.0), TRIM))
	end
	local rearPlate =
		plate(model, "PlateRear", CFrame.new(0, 2.25, 3.0) * CFrame.Angles(math.rad(-10), 0, 0), Enum.NormalId.Back)
	rearPlate.Size = Vector3.new(1.5, 0.62, 0.08)
	attach(rearPlate)

	-- Livery: side cases + top case with the job's name, reflective bands ------------------
	if scheme then
		local text = TEXT_BY_JOB[def.job or ""] or scheme.text
		local top = attach(
			painted(part(model, "TopCase", Vector3.new(1.4, 1.0, 1.1), CFrame.new(0, 3.75, 2.45), paint), "panel")
		)
		attach(part(model, "CaseRack", Vector3.new(1.0, 0.12, 1.0), CFrame.new(0, 3.2, 2.45), TRIM))
		for _, sx in { -1, 1 } do
			local case = attach(
				painted(
					part(model, "Pannier", Vector3.new(0.5, 1.0, 1.4), CFrame.new(sx * 0.95, 2.6, 1.9), paint),
					"panel"
				)
			)
			if scheme.stripe then
				stripe("Stripe", Vector3.new(0.06, 0.22, 1.4), CFrame.new(sx * 1.23, 2.35, 1.9), scheme.stripe)
				stripe("Stripe", Vector3.new(0.06, 0.18, 1.2), CFrame.new(sx * 0.87, 2.75, -1.6), scheme.stripe)
			end
			if scheme.stripe2 then
				stripe("Stripe2", Vector3.new(0.06, 0.12, 1.2), CFrame.new(sx * 0.87, 3.2, -1.6), scheme.stripe2)
			end
			if text then
				textPanel(
					case,
					if sx < 0 then Enum.NormalId.Left else Enum.NormalId.Right,
					text,
					scheme.textColor or TRIM
				)
			end
		end
		if text then
			textPanel(top, Enum.NormalId.Back, text, scheme.textColor or TRIM)
			textPanel(top, Enum.NormalId.Left, text, scheme.textColor or TRIM)
			textPanel(top, Enum.NormalId.Right, text, scheme.textColor or TRIM)
		end
	end

	-- Blue lights + siren ----------------------------------------------------------------
	if def.emergency then
		local function blue(cf: CFrame, size: Vector3, side: number, light: boolean)
			local bl = attach(part(model, "Bluelight", size, cf, Color3.fromRGB(20, 40, 120), {
				Material = Enum.Material.Glass,
				Transparency = 0.1,
			}))
			bl:SetAttribute("Side", side)
			if light then
				local pl = Instance.new("PointLight")
				pl.Color = Color3.fromRGB(40, 90, 255)
				pl.Range = 18
				pl.Brightness = 4
				pl.Enabled = false
				pl.Parent = bl
			end
		end
		for _, sx in { -1, 1 } do
			blue(CFrame.new(sx * 0.55, 3.88, -2.62), Vector3.new(0.3, 0.22, 0.1), sx, false) -- front flashers
			attach(
				tube(model, "LightPole", Vector3.new(sx * 0.4, 4.25, 2.6), Vector3.new(sx * 0.4, 4.8, 2.6), 0.08, TRIM)
			)
			blue(CFrame.new(sx * 0.4, 4.95, 2.6), Vector3.new(0.32, 0.32, 0.32), -sx, true)
		end
		local siren = Instance.new("Sound")
		siren.Name = "Siren"
		siren.Looped = true
		siren.Volume = 1.2
		siren.RollOffMaxDistance = 400
		siren.SoundId = if Config.Sounds.Martinshorn ~= 0 then "rbxassetid://" .. Config.Sounds.Martinshorn else ""
		siren.Parent = chassis
	end

	-- Seats ------------------------------------------------------------------------------
	local driverSeat = Instance.new("VehicleSeat")
	driverSeat.Name = "DriveSeat"
	driverSeat.Size = Vector3.new(1.0, 0.3, 1.2)
	driverSeat.CFrame = CFrame.new(0, 3.0, 0.45)
	driverSeat.Transparency = 1
	driverSeat.Massless = true
	driverSeat.CanCollide = false
	driverSeat.MaxSpeed = 0 -- legacy drive disabled; our controller drives
	driverSeat.Torque = 0
	driverSeat.HeadsUpDisplay = false
	driverSeat.Parent = model
	attach(driverSeat)
	local pillion = Instance.new("Seat")
	pillion.Name = "Seat"
	pillion.Size = Vector3.new(0.9, 0.3, 0.9)
	pillion.CFrame = CFrame.new(0, 3.15, 1.65)
	pillion.Transparency = 1
	pillion.Massless = true
	pillion.CanCollide = false
	pillion.Parent = model
	attach(pillion)

	-- Physics: two narrow pairs of hidden wheels -------------------------------------------
	local px, pw = 0.45, 0.6
	local wheelSpecs = {
		{ name = "WheelFL", x = -px, y = R, z = zF, r = R, w = pw, front = true },
		{ name = "WheelFR", x = px, y = R, z = zF, r = R, w = pw, front = true },
		{ name = "WheelRL", x = -px, y = R, z = zR, r = R, w = pw, front = false },
		{ name = "WheelRR", x = px, y = R, z = zR, r = R, w = pw, front = false },
	}
	local mass = 1.4 * 0.8 * 5 * 3 + 4 * (math.pi * R * R * pw * 1.2) + 60
	VehicleBuilder.AddPhysics(model, chassis, def, wheelSpecs, mass, false)

	-- Steering parts follow the left front knuckle, wheels spin with the left wheels
	local knuckle: BasePart? = nil
	for _, k in model:GetChildren() do
		if k.Name == "Knuckle" and k:IsA("BasePart") and k.CFrame.Position.X < 0 then
			knuckle = k
		end
	end
	local steer = knuckle :: BasePart
	local function onFork(p: BasePart)
		weld(steer, p)
	end
	for _, sx in { -1, 1 } do
		onFork(tube(model, "Fork", Vector3.new(sx * 0.38, R, zF), Vector3.new(sx * 0.32, 3.75, -2.0), 0.22, CHROME, {
			Material = Enum.Material.Metal,
		}))
		onFork(part(model, "Grip", Vector3.new(0.4, 0.2, 0.2), CFrame.new(sx * 1.0, 3.95, -1.7), TRIM, {
			Material = Enum.Material.Rubber,
		}))
	end
	onFork(part(model, "TripleClamp", Vector3.new(0.9, 0.2, 0.35), CFrame.new(0, 3.75, -1.98), METAL, {
		Material = Enum.Material.Metal,
	}))
	onFork(tube(model, "Handlebar", Vector3.new(-1.15, 3.95, -1.7), Vector3.new(1.15, 3.95, -1.7), 0.14, TRIM))
	local fender =
		painted(part(model, "FrontFender", Vector3.new(0.6, 0.12, 1.0), CFrame.new(0, R * 2 + 0.15, zF), paint), "body")
	onFork(fender)
	visualWheel(model, model:FindFirstChild("WheelFL") :: BasePart, R, zF, R, true)
	visualWheel(model, model:FindFirstChild("WheelRL") :: BasePart, R, zR, R, false)

	model:SetAttribute("Bike", true)
	return model
end

return VehicleBuilder
