--!strict
-- Builds a drivable vehicle from parts (no meshes needed), including interior.
-- Model space: forward = -Z, right = +X, ground = y 0.
--
-- Physics layout
--   Chassis (lower body, PrimaryPart) <- everything decorative is welded to it (Massless)
--   rear wheels  : HingeConstraint (Motor) chassis -> wheel
--   front wheels : HingeConstraint (Servo, vertical) chassis -> knuckle, then Motor knuckle -> wheel
-- The driver's client sets motor speed + steering angle (it owns the physics);
-- see StarterPlayerScripts/Client/Controllers/VehicleController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local VehicleBuilder = {}

type Body = {
	L: number, -- length
	W: number, -- width
	lower: number, -- lower body height
	cab: number, -- cabin (glass area) height
	cabStart: number, -- cabin start (fraction of length from the front)
	cabEnd: number, -- cabin end
	ws: number, -- windshield slope length
	rs: number, -- rear window slope length
	wheelR: number,
	clear: number, -- ground clearance (bottom of body)
	seats: number,
	glassEnd: number?, -- vans: glass stops here, solid box behind
	rear: string?, -- "box" | "bed" | "flat" | "fifth" | "ladder"
	rearH: number?, -- height of box body
}

local function b(t: Body): Body
	return t
end

VehicleBuilder.BodyTypes = {
	hatch = b({
		L = 13,
		W = 6,
		lower = 2.4,
		cab = 2.4,
		cabStart = 0.36,
		cabEnd = 0.97,
		ws = 2.6,
		rs = 1.0,
		wheelR = 1.25,
		clear = 0.9,
		seats = 5,
	}),
	hatch_small = b({
		L = 12,
		W = 5.6,
		lower = 2.3,
		cab = 2.4,
		cabStart = 0.34,
		cabEnd = 0.97,
		ws = 2.4,
		rs = 0.9,
		wheelR = 1.15,
		clear = 0.85,
		seats = 4,
	}),
	sedan = b({
		L = 14.5,
		W = 6.2,
		lower = 2.3,
		cab = 2.2,
		cabStart = 0.33,
		cabEnd = 0.78,
		ws = 2.8,
		rs = 2.0,
		wheelR = 1.3,
		clear = 0.9,
		seats = 5,
	}),
	sedan_long = b({
		L = 15.5,
		W = 6.3,
		lower = 2.3,
		cab = 2.2,
		cabStart = 0.32,
		cabEnd = 0.79,
		ws = 3.0,
		rs = 2.2,
		wheelR = 1.35,
		clear = 0.9,
		seats = 5,
	}),
	sedan_sport = b({
		L = 15,
		W = 6.4,
		lower = 2.0,
		cab = 1.9,
		cabStart = 0.33,
		cabEnd = 0.82,
		ws = 3.2,
		rs = 3.0,
		wheelR = 1.35,
		clear = 0.7,
		seats = 4,
	}),
	sedan_xl = b({
		L = 17,
		W = 6.5,
		lower = 2.5,
		cab = 2.3,
		cabStart = 0.32,
		cabEnd = 0.8,
		ws = 2.8,
		rs = 1.8,
		wheelR = 1.45,
		clear = 0.9,
		seats = 4,
	}),
	kombi = b({
		L = 14.5,
		W = 6.2,
		lower = 2.3,
		cab = 2.3,
		cabStart = 0.33,
		cabEnd = 0.97,
		ws = 2.8,
		rs = 0.6,
		wheelR = 1.3,
		clear = 0.9,
		seats = 5,
	}),
	kombi_long = b({
		L = 15.5,
		W = 6.3,
		lower = 2.3,
		cab = 2.3,
		cabStart = 0.32,
		cabEnd = 0.97,
		ws = 3.0,
		rs = 0.7,
		wheelR = 1.35,
		clear = 0.9,
		seats = 5,
	}),
	mpv = b({
		L = 14.5,
		W = 6.3,
		lower = 2.6,
		cab = 2.9,
		cabStart = 0.28,
		cabEnd = 0.97,
		ws = 3.6,
		rs = 0.5,
		wheelR = 1.35,
		clear = 0.95,
		seats = 7,
	}),
	suv = b({
		L = 14.5,
		W = 6.6,
		lower = 2.9,
		cab = 2.5,
		cabStart = 0.33,
		cabEnd = 0.96,
		ws = 2.8,
		rs = 0.8,
		wheelR = 1.5,
		clear = 1.3,
		seats = 5,
	}),
	suv_long = b({
		L = 16.5,
		W = 6.8,
		lower = 3.0,
		cab = 2.6,
		cabStart = 0.32,
		cabEnd = 0.96,
		ws = 2.8,
		rs = 0.6,
		wheelR = 1.6,
		clear = 1.3,
		seats = 5,
	}),
	coupe = b({
		L = 14,
		W = 6.3,
		lower = 2.1,
		cab = 1.9,
		cabStart = 0.38,
		cabEnd = 0.8,
		ws = 3.0,
		rs = 2.6,
		wheelR = 1.3,
		clear = 0.8,
		seats = 4,
	}),
	coupe_sport = b({
		L = 14,
		W = 6.5,
		lower = 1.9,
		cab = 1.7,
		cabStart = 0.38,
		cabEnd = 0.84,
		ws = 3.2,
		rs = 3.0,
		wheelR = 1.35,
		clear = 0.65,
		seats = 2,
	}),
	super = b({
		L = 14.5,
		W = 6.8,
		lower = 1.7,
		cab = 1.6,
		cabStart = 0.35,
		cabEnd = 0.7,
		ws = 3.2,
		rs = 2.2,
		wheelR = 1.35,
		clear = 0.55,
		seats = 2,
	}),
	beetle = b({
		L = 12.5,
		W = 5.8,
		lower = 2.2,
		cab = 2.3,
		cabStart = 0.3,
		cabEnd = 0.8,
		ws = 2.6,
		rs = 3.2,
		wheelR = 1.2,
		clear = 0.9,
		seats = 4,
	}),
	offroad = b({
		L = 14,
		W = 6.5,
		lower = 3.0,
		cab = 2.8,
		cabStart = 0.32,
		cabEnd = 0.95,
		ws = 0.8,
		rs = 0,
		wheelR = 1.7,
		clear = 1.6,
		seats = 5,
	}),
	offroad_long = b({
		L = 15.5,
		W = 6.5,
		lower = 3.0,
		cab = 2.8,
		cabStart = 0.3,
		cabEnd = 0.95,
		ws = 0.8,
		rs = 0,
		wheelR = 1.7,
		clear = 1.6,
		seats = 7,
	}),
	pickup = b({
		L = 18,
		W = 7,
		lower = 3.1,
		cab = 2.6,
		cabStart = 0.3,
		cabEnd = 0.6,
		ws = 2.4,
		rs = 0,
		wheelR = 1.8,
		clear = 1.6,
		seats = 5,
		rear = "bed",
	}),
	unimug = b({
		L = 17,
		W = 7.2,
		lower = 3.2,
		cab = 3.0,
		cabStart = 0.04,
		cabEnd = 0.36,
		ws = 0.6,
		rs = 0,
		wheelR = 2.4,
		clear = 2.4,
		seats = 2,
		rear = "bed",
	}),
	van_small = b({
		L = 14.5,
		W = 6.2,
		lower = 2.6,
		cab = 3.4,
		cabStart = 0.26,
		cabEnd = 0.98,
		ws = 3.0,
		rs = 0.3,
		wheelR = 1.3,
		clear = 0.95,
		seats = 2,
		glassEnd = 0.5,
	}),
	van = b({
		L = 16.5,
		W = 6.8,
		lower = 2.8,
		cab = 3.8,
		cabStart = 0.2,
		cabEnd = 0.99,
		ws = 3.0,
		rs = 0,
		wheelR = 1.4,
		clear = 1.0,
		seats = 3,
		glassEnd = 0.42,
	}),
	bigvan = b({
		L = 21,
		W = 7,
		lower = 2.8,
		cab = 5,
		cabStart = 0.17,
		cabEnd = 0.99,
		ws = 2.6,
		rs = 0,
		wheelR = 1.5,
		clear = 1.0,
		seats = 3,
		glassEnd = 0.32,
	}),
	rtw = b({
		L = 21,
		W = 7.4,
		lower = 2.8,
		cab = 3.6,
		cabStart = 0.15,
		cabEnd = 0.36,
		ws = 2.4,
		rs = 0,
		wheelR = 1.5,
		clear = 1.0,
		seats = 3,
		rear = "box",
		rearH = 6.2,
	}),
	truck = b({
		L = 26,
		W = 8,
		lower = 3.4,
		cab = 4.2,
		cabStart = 0.0,
		cabEnd = 0.26,
		ws = 0.6,
		rs = 0,
		wheelR = 2.0,
		clear = 2.0,
		seats = 6,
		rear = "box",
		rearH = 6.5,
	}),
	truck_box = b({
		L = 26,
		W = 8,
		lower = 3.4,
		cab = 4.0,
		cabStart = 0.0,
		cabEnd = 0.24,
		ws = 0.6,
		rs = 0,
		wheelR = 2.0,
		clear = 2.0,
		seats = 3,
		rear = "box",
		rearH = 8,
	}),
	truck_ladder = b({
		L = 30,
		W = 8,
		lower = 3.4,
		cab = 4.0,
		cabStart = 0.0,
		cabEnd = 0.22,
		ws = 0.6,
		rs = 0,
		wheelR = 2.0,
		clear = 2.0,
		seats = 3,
		rear = "ladder",
		rearH = 3.5,
	}),
	truck_airport = b({
		L = 36,
		W = 10,
		lower = 4.2,
		cab = 4.4,
		cabStart = 0.02,
		cabEnd = 0.24,
		ws = 1.2,
		rs = 0,
		wheelR = 2.6,
		clear = 2.6,
		seats = 3,
		rear = "box",
		rearH = 7.5,
	}),
	tow_small = b({
		L = 22,
		W = 7,
		lower = 2.8,
		cab = 3.6,
		cabStart = 0.12,
		cabEnd = 0.36,
		ws = 2.4,
		rs = 0,
		wheelR = 1.5,
		clear = 1.0,
		seats = 3,
		rear = "flat",
	}),
	tow = b({
		L = 27,
		W = 8,
		lower = 3.4,
		cab = 4.0,
		cabStart = 0.0,
		cabEnd = 0.25,
		ws = 0.6,
		rs = 0,
		wheelR = 2.0,
		clear = 2.0,
		seats = 3,
		rear = "flat",
	}),
	tow_heavy = b({
		L = 32,
		W = 8.4,
		lower = 3.8,
		cab = 4.4,
		cabStart = 0.0,
		cabEnd = 0.24,
		ws = 0.6,
		rs = 0,
		wheelR = 2.3,
		clear = 2.3,
		seats = 3,
		rear = "flat",
	}),
	semi = b({
		L = 21,
		W = 8,
		lower = 3.6,
		cab = 5.2,
		cabStart = 0.0,
		cabEnd = 0.4,
		ws = 0.6,
		rs = 0,
		wheelR = 2.0,
		clear = 2.0,
		seats = 2,
		rear = "fifth",
	}),
}

local GLASS = Color3.fromRGB(25, 35, 45)
local TRIM = Color3.fromRGB(20, 20, 22)
local INTERIOR = Color3.fromRGB(35, 35, 38)

local LIVERY = {
	Police = {
		stripe = Color3.fromRGB(20, 70, 170),
		text = "POLIZEI",
		textColor = Color3.fromRGB(20, 70, 170),
		roof = true,
	},
	Fire = {
		stripe = Color3.fromRGB(240, 240, 240),
		text = "FEUERWEHR",
		textColor = Color3.fromRGB(240, 240, 240),
		roof = true,
	},
	Rescue = {
		stripe = Color3.fromRGB(230, 30, 30),
		stripe2 = Color3.fromRGB(250, 200, 0),
		text = "RETTUNGSDIENST · DRH",
		textColor = Color3.fromRGB(200, 20, 20),
		roof = true,
	},
	ADMC = { stripe = TRIM, text = "ADMC Pannenhilfe", textColor = TRIM, roof = true },
	DXL = { stripe = Color3.fromRGB(210, 20, 30), text = "DXL", textColor = Color3.fromRGB(210, 20, 30), roof = false },
	Unmarked = { roof = false },
}

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

-- Returns the model (unparented). `def` is a Vehicles catalog entry.
function VehicleBuilder.Build(def: any, color: Color3?): Model
	local body: Body = VehicleBuilder.BodyTypes[def.body] or VehicleBuilder.BodyTypes.hatch
	local paint = color or def.color
	local model = Instance.new("Model")
	model.Name = def.name

	local L, W = body.L, body.W
	local y0 = body.clear
	local y1 = y0 + body.lower -- top of lower body
	local zFront = -L / 2
	local zRear = L / 2
	local cabFront = zFront + body.cabStart * L
	local cabRear = zFront + body.cabEnd * L
	local isTruck = body.rear ~= nil and body.cabStart <= 0.05

	-- Chassis / lower body (collides, carries all the mass)
	local chassis =
		part(model, "Chassis", Vector3.new(W, body.lower, L), CFrame.new(0, y0 + body.lower / 2, 0), paint, {
			CanCollide = true,
			Massless = false,
			CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.3, 0.1),
		})
	chassis:SetAttribute("Paint", true)
	model.PrimaryPart = chassis

	local function attach(p: BasePart)
		weld(chassis, p)
	end

	-- Bumpers, grille, lights -------------------------------------------------
	attach(part(model, "BumperFront", Vector3.new(W + 0.1, 0.7, 0.5), CFrame.new(0, y0 + 0.35, zFront - 0.15), TRIM))
	attach(part(model, "BumperRear", Vector3.new(W + 0.1, 0.7, 0.5), CFrame.new(0, y0 + 0.35, zRear + 0.15), TRIM))
	attach(
		part(
			model,
			"Grille",
			Vector3.new(W * 0.45, body.lower * 0.35, 0.1),
			CFrame.new(0, y0 + body.lower * 0.55, zFront - 0.05),
			TRIM
		)
	)

	for _, side in { -1, 1 } do
		local hx = side * (W / 2 - 0.9)
		local head = part(
			model,
			"Headlight",
			Vector3.new(1.3, 0.45, 0.1),
			CFrame.new(hx, y0 + body.lower * 0.72, zFront - 0.06),
			Color3.fromRGB(230, 230, 220),
			{ Material = Enum.Material.Glass }
		)
		attach(head)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Range = 60
		spot.Angle = 70
		spot.Brightness = 3
		spot.Enabled = false
		spot.Parent = head

		local tail = part(
			model,
			"Taillight",
			Vector3.new(1.2, 0.45, 0.1),
			CFrame.new(hx, y0 + body.lower * 0.72, zRear + 0.06),
			Color3.fromRGB(120, 0, 0),
			{ Material = Enum.Material.Glass }
		)
		attach(tail)

		for _, z in { zFront - 0.06, zRear + 0.06 } do
			local ind = part(
				model,
				if side < 0 then "IndicatorL" else "IndicatorR",
				Vector3.new(0.45, 0.3, 0.1),
				CFrame.new(side * (W / 2 - 0.2), y0 + body.lower * 0.72, z),
				Color3.fromRGB(120, 70, 0),
				{ Material = Enum.Material.Glass }
			)
			attach(ind)
		end
	end

	plate(model, "PlateFront", CFrame.new(0, y0 + 0.75, zFront - 0.45), Enum.NormalId.Front)
	attach(model:FindFirstChild("PlateFront") :: BasePart)
	plate(model, "PlateRear", CFrame.new(0, y0 + body.lower * 0.4, zRear + 0.06), Enum.NormalId.Back)
	attach(model:FindFirstChild("PlateRear") :: BasePart)

	-- Cabin -------------------------------------------------------------------
	local cabH = body.cab
	local cy = y1 + cabH / 2
	-- keep at least 1 stud of flat roof: shrink both window slopes if the cabin is short
	local slopeFit = math.min(1, (cabRear - cabFront - 1) / math.max(body.ws + body.rs, 0.01))
	local ws, rs = body.ws * slopeFit, body.rs * slopeFit
	local coreFront = cabFront + ws
	local coreRear = cabRear - rs
	local glassProps = { Transparency = 0.45, Material = Enum.Material.Glass }

	-- windshield
	if ws > 0.1 then
		attach(
			wedge(
				model,
				"Windshield",
				Vector3.new(W - 0.4, cabH, ws),
				CFrame.new(0, cy, cabFront + ws / 2),
				GLASS,
				glassProps
			)
		)
	end
	-- rear window
	if rs > 0.1 then
		attach(
			wedge(
				model,
				"RearWindow",
				Vector3.new(W - 0.4, cabH, rs),
				CFrame.new(0, cy, cabRear - rs / 2) * CFrame.Angles(0, math.pi, 0),
				GLASS,
				glassProps
			)
		)
	end

	local glassEndZ = if body.glassEnd then zFront + body.glassEnd * L else coreRear
	glassEndZ = math.clamp(glassEndZ, coreFront, coreRear)
	-- glass core (side windows) and solid box (vans)
	if glassEndZ - coreFront > 0.1 then
		attach(
			part(
				model,
				"Windows",
				Vector3.new(W - 0.3, cabH - 0.25, glassEndZ - coreFront),
				CFrame.new(0, cy - 0.125, (coreFront + glassEndZ) / 2),
				GLASS,
				glassProps
			)
		)
	end
	if coreRear - glassEndZ > 0.1 then
		local box = part(
			model,
			"CargoBox",
			Vector3.new(W - 0.1, cabH, coreRear - glassEndZ),
			CFrame.new(0, cy, (glassEndZ + coreRear) / 2),
			paint
		)
		box:SetAttribute("Paint", true)
		attach(box)
	end
	-- roof
	local roof = part(
		model,
		"Roof",
		Vector3.new(W - 0.2, 0.25, coreRear - coreFront + 0.2),
		CFrame.new(0, y1 + cabH - 0.125, (coreFront + coreRear) / 2),
		paint
	)
	roof:SetAttribute("Paint", true)
	attach(roof)
	-- pillars
	for _, side in { -1, 1 } do
		local x = side * (W / 2 - 0.2)
		attach(
			part(
				model,
				"PillarA",
				Vector3.new(0.25, cabH, 0.3),
				CFrame.new(x, cy, coreFront),
				paint,
				{ Name = "PillarA" }
			)
		)
		attach(part(model, "PillarC", Vector3.new(0.25, cabH, 0.4), CFrame.new(x, cy, coreRear - 0.2), paint))
		-- side mirrors
		attach(
			part(
				model,
				"Mirror",
				Vector3.new(0.7, 0.45, 0.25),
				CFrame.new(side * (W / 2 + 0.3), y1 + 0.35, coreFront + 0.2),
				paint
			)
		)
	end

	-- Rear bodies (trucks etc.) --------------------------------------------------
	local rearStart = cabRear + 0.2
	local rearLen = zRear - rearStart
	if body.rear == "box" and rearLen > 1 then
		local h = body.rearH or 6
		local box = part(
			model,
			"Body",
			Vector3.new(W, h, rearLen),
			CFrame.new(0, y1 + h / 2 - 0.2, rearStart + rearLen / 2),
			paint
		)
		box:SetAttribute("Paint", true)
		attach(box)
		for i = 1, 3 do
			local shutterZ = rearStart + rearLen * (i / 4)
			for _, side in { -1, 1 } do
				attach(
					part(
						model,
						"Shutter",
						Vector3.new(0.05, h * 0.7, rearLen / 5),
						CFrame.new(side * (W / 2 + 0.03), y1 + h / 2 - 0.2, shutterZ),
						Color3.fromRGB(200, 200, 205)
					)
				)
			end
		end
	elseif body.rear == "bed" and rearLen > 1 then
		for _, side in { -1, 1 } do
			attach(
				part(
					model,
					"BedWall",
					Vector3.new(0.3, 1.2, rearLen),
					CFrame.new(side * (W / 2 - 0.15), y1 + 0.6, rearStart + rearLen / 2),
					paint
				)
			)
		end
		attach(part(model, "Tailgate", Vector3.new(W, 1.2, 0.3), CFrame.new(0, y1 + 0.6, zRear - 0.15), paint))
	elseif body.rear == "flat" and rearLen > 1 then
		attach(
			part(
				model,
				"Flatbed",
				Vector3.new(W, 0.4, rearLen),
				CFrame.new(0, y1 + 0.2, rearStart + rearLen / 2),
				Color3.fromRGB(70, 70, 75),
				{ Material = Enum.Material.DiamondPlate }
			)
		)
		local tow = part(model, "TowHook", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, y0 + 0.3, zRear + 0.5), TRIM)
		attach(tow)
	elseif body.rear == "ladder" and rearLen > 1 then
		local h = body.rearH or 3.5
		local base = part(
			model,
			"Body",
			Vector3.new(W, h, rearLen),
			CFrame.new(0, y1 + h / 2 - 0.2, rearStart + rearLen / 2),
			paint
		)
		base:SetAttribute("Paint", true)
		attach(base)
		local ladderLen = L * 0.85
		local ladderZ = zFront + ladderLen / 2 + 1
		for _, side in { -1, 1 } do
			attach(
				part(
					model,
					"LadderRail",
					Vector3.new(0.3, 0.4, ladderLen),
					CFrame.new(side * 1.3, y1 + math.max(h, body.cab) + 0.6, ladderZ),
					Color3.fromRGB(200, 200, 205),
					{ Material = Enum.Material.Metal }
				)
			)
		end
		for i = 0, math.floor(ladderLen / 1.5) do
			attach(
				part(
					model,
					"LadderRung",
					Vector3.new(2.6, 0.15, 0.15),
					CFrame.new(0, y1 + math.max(h, body.cab) + 0.6, zFront + 1 + i * 1.5),
					Color3.fromRGB(200, 200, 205),
					{ Material = Enum.Material.Metal }
				)
			)
		end
	elseif body.rear == "fifth" and rearLen > 1 then
		attach(
			part(
				model,
				"Frame",
				Vector3.new(W * 0.6, 0.6, rearLen),
				CFrame.new(0, y1 - 0.3, rearStart + rearLen / 2),
				TRIM
			)
		)
		attach(
			part(
				model,
				"FifthWheel",
				Vector3.new(3, 0.3, 3),
				CFrame.new(0, y1 + 0.15, rearStart + rearLen * 0.55),
				Color3.fromRGB(60, 60, 60),
				{ Material = Enum.Material.Metal }
			)
		)
	end

	-- Interior ------------------------------------------------------------------
	local seatY = y1 - 0.55
	local frontRowZ = coreFront + (if isTruck then 1.4 else 1.6)
	local driverX = -W / 4 + 0.15 -- left-hand drive
	local dash =
		part(model, "Dashboard", Vector3.new(W - 0.6, 0.8, 1.0), CFrame.new(0, y1 + 0.1, coreFront - 0.1), INTERIOR)
	attach(dash)
	local screen = part(
		model,
		"NaviScreen",
		Vector3.new(1.2, 0.7, 0.08),
		CFrame.new(0, y1 + 0.55, coreFront + 0.35) * CFrame.Angles(math.rad(-15), 0, 0),
		Color3.fromRGB(10, 10, 10),
		{ Material = Enum.Material.Neon }
	)
	attach(screen)
	local wheelCf = CFrame.new(driverX, y1 + 0.55, coreFront + 0.65) * CFrame.Angles(math.rad(-25), 0, 0)
	local steer =
		part(model, "SteeringWheel", Vector3.new(1.3, 1.3, 0.15), wheelCf, TRIM, { Shape = Enum.PartType.Cylinder })
	-- cylinder axis is X; turn it so the wheel faces the driver
	steer.CFrame = wheelCf * CFrame.Angles(0, math.rad(90), 0)
	steer.Size = Vector3.new(0.15, 1.3, 1.3)
	attach(steer)

	local driverSeat = Instance.new("VehicleSeat")
	driverSeat.Name = "DriveSeat"
	driverSeat.Size = Vector3.new(1.8, 0.4, 1.8)
	driverSeat.CFrame = CFrame.new(driverX, seatY, frontRowZ)
	driverSeat.Color = INTERIOR
	driverSeat.Transparency = 0
	driverSeat.Massless = true
	driverSeat.CanCollide = false
	driverSeat.MaxSpeed = 0 -- legacy drive disabled; our controller drives
	driverSeat.Torque = 0
	driverSeat.HeadsUpDisplay = false
	driverSeat.Parent = model
	attach(driverSeat)

	local seatCount = math.max(1, body.seats)
	local rows = {}
	table.insert(rows, { z = frontRowZ, xs = { W / 4 - 0.15 } })
	local glassLimit = if body.glassEnd then glassEndZ else coreRear
	local rowZ = frontRowZ + 3
	local placed = 1
	while placed < seatCount and rowZ < glassLimit - 0.6 do
		local xs = { -W / 4 + 0.15, W / 4 - 0.15 }
		if W >= 6.2 and seatCount - placed >= 3 then
			table.insert(xs, 0)
		end
		table.insert(rows, { z = rowZ, xs = xs })
		placed += #xs
		rowZ += 2.8
	end
	for _, row in rows do
		for _, x in row.xs do
			local seat = Instance.new("Seat")
			seat.Name = "Seat"
			seat.Size = Vector3.new(1.6, 0.4, 1.6)
			seat.CFrame = CFrame.new(x, seatY, row.z)
			seat.Color = INTERIOR
			seat.Massless = true
			seat.CanCollide = false
			seat.Parent = model
			attach(seat)
		end
	end
	-- seat backs (driver + every seat)
	for _, s in model:GetChildren() do
		if s:IsA("Seat") or s:IsA("VehicleSeat") then
			local sp = s :: BasePart
			attach(
				part(
					model,
					"SeatBack",
					Vector3.new(sp.Size.X, 2.2, 0.35),
					sp.CFrame * CFrame.new(0, 1.1, sp.Size.Z / 2 + 0.1),
					INTERIOR
				)
			)
		end
	end

	-- Livery ------------------------------------------------------------------
	local livery = def.livery and LIVERY[def.livery]
	if livery and livery.stripe then
		for _, side in { -1, 1 } do
			local face = if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right
			local stripe = part(
				model,
				"Stripe",
				Vector3.new(0.06, body.lower * 0.35, L - 0.4),
				CFrame.new(side * (W / 2 + 0.03), y0 + body.lower * 0.55, 0),
				livery.stripe
			)
			attach(stripe)
			if livery.stripe2 then
				attach(
					part(
						model,
						"Stripe2",
						Vector3.new(0.06, body.lower * 0.18, L - 0.4),
						CFrame.new(side * (W / 2 + 0.035), y0 + body.lower * 0.3, 0),
						livery.stripe2
					)
				)
			end
			if livery.text then
				local panelZ = if body.rear == "box" then rearStart + rearLen / 2 else (coreFront + coreRear) / 2
				local panelH = if body.rear == "box" then 1.6 else body.lower * 0.3
				local panelY = if body.rear == "box" then y1 + (body.rearH or 6) * 0.6 else y0 + body.lower * 0.85
				local panel = part(
					model,
					"LiveryText",
					Vector3.new(0.05, panelH, math.min(L * 0.5, 9)),
					CFrame.new(side * (W / 2 + 0.06), panelY, panelZ),
					Color3.new(1, 1, 1),
					{ Transparency = 1 }
				)
				attach(panel)
				textPanel(panel, face, livery.text, livery.textColor)
			end
		end
	end

	-- Emergency lights --------------------------------------------------------
	if def.emergency then
		local roofY = y1 + cabH
		if body.rear == "box" then
			roofY = math.max(roofY, y1 + (body.rearH or 6) - 0.2)
		end
		local barZ = coreFront + 0.8
		if def.livery ~= "Unmarked" then
			attach(
				part(model, "LightbarBase", Vector3.new(W * 0.7, 0.2, 0.9), CFrame.new(0, y1 + cabH + 0.1, barZ), TRIM)
			)
			for _, side in { -1, 1 } do
				local bl = part(
					model,
					"Bluelight",
					Vector3.new(W * 0.3, 0.4, 0.8),
					CFrame.new(side * W * 0.18, y1 + cabH + 0.4, barZ),
					Color3.fromRGB(20, 40, 120),
					{ Material = Enum.Material.Glass, Transparency = 0.1 }
				)
				bl:SetAttribute("Side", side)
				attach(bl)
				local light = Instance.new("PointLight")
				light.Color = Color3.fromRGB(40, 90, 255)
				light.Range = 22
				light.Brightness = 4
				light.Enabled = false
				light.Parent = bl
			end
		end
		-- grille flashers (also on unmarked cars)
		for _, side in { -1, 1 } do
			local fl = part(
				model,
				"Bluelight",
				Vector3.new(0.6, 0.25, 0.1),
				CFrame.new(side * W * 0.15, y0 + body.lower * 0.45, zFront - 0.1),
				Color3.fromRGB(20, 40, 120),
				{ Material = Enum.Material.Glass }
			)
			fl:SetAttribute("Side", -side)
			attach(fl)
		end
		local siren = Instance.new("Sound")
		siren.Name = "Siren"
		siren.Looped = true
		siren.Volume = 1.2
		siren.RollOffMaxDistance = 400
		siren.SoundId = if Config.Sounds.Martinshorn ~= 0 then "rbxassetid://" .. Config.Sounds.Martinshorn else ""
		siren.Parent = chassis
	end

	-- Wheels ------------------------------------------------------------------
	local r = body.wheelR
	local wheelW = if body.L > 20 then 1.5 else 1.0
	local overhangF = if isTruck then r * 1.3 else r * 1.7
	local overhangR = if body.rear == "fifth" then r * 1.5 else r * 1.8
	local axleF = zFront + overhangF
	local axleR = zRear - overhangR
	local wheelX = W / 2 - wheelW / 2 + 0.15
	local wheelPhys = PhysicalProperties.new(1.2, 2, 0, 100, 1)

	local motors: { HingeConstraint } = {}
	local steering: { HingeConstraint } = {}

	local function makeWheel(name: string, x: number, z: number, front: boolean)
		local wheel = Instance.new("Part")
		wheel.Name = name
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(wheelW, r * 2, r * 2)
		wheel.CFrame = CFrame.new(x, r, z)
		wheel.Color = TRIM
		wheel.Material = Enum.Material.SmoothPlastic
		wheel.CustomPhysicalProperties = wheelPhys
		wheel.CanCollide = true
		wheel.Parent = model
		local rim = part(
			model,
			"Rim",
			Vector3.new(wheelW + 0.05, r * 1.2, r * 1.2),
			wheel.CFrame,
			Color3.fromRGB(180, 180, 185),
			{ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal }
		)
		weld(wheel, rim)

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
			knuckle.CFrame = CFrame.new(x, r, z)
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
			a0.Position = chassis.CFrame:PointToObjectSpace(Vector3.new(x, r, z))
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
		hubAtt.Position = hub.CFrame:PointToObjectSpace(Vector3.new(x, r, z))
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

	makeWheel("WheelFL", -wheelX, axleF, true)
	makeWheel("WheelFR", wheelX, axleF, true)
	makeWheel("WheelRL", -wheelX, axleR, false)
	makeWheel("WheelRR", wheelX, axleR, false)

	-- Driving parameters for the client controller -----------------------------
	local topSpeed = def.speed / 3.6 * Config.StudsPerMeter -- studs/s
	model:SetAttribute("WheelRadius", r)
	model:SetAttribute("TopSpeed", topSpeed)
	model:SetAttribute("Accel", def.accel or 1)
	model:SetAttribute("Wheelbase", axleR - axleF)
	model:SetAttribute("Emergency", def.emergency == true)
	model:SetAttribute("Headlights", false)
	model:SetAttribute("Indicator", "")
	model:SetAttribute("Bluelight", false)
	model:SetAttribute("Siren", false)
	model:SetAttribute("Brake", false)
	model:SetAttribute("Fuel", 100)

	-- Torque scales with mass so heavy trucks still move.
	-- chassis density 0.6, wheel density 1.2, plus ~60 for occupants
	local mass = W * body.lower * L * 0.6 + 4 * (math.pi * r * r * wheelW * 1.2) + 60
	local torquePerWheel = mass * 60 * r * math.max(0.6, def.accel or 1) / 4
	for _, m in motors do
		m.MotorMaxTorque = torquePerWheel
		m:SetAttribute("BaseTorque", torquePerWheel)
	end

	return model
end

return VehicleBuilder
