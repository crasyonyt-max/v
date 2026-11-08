--!strict
-- Builds vehicles that use a cleaned Creator Store body (ServerStorage.ToolboxCars,
-- mapping in CarModels). The body is scaled to the real car's length; its own wheels
-- turn with our physics wheels, our seats sit where the model's seats were, and we add
-- lights, plates, a parody badge over each emblem spot, blue lights and liveries.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CarModels = require(script.Parent.CarModels)
local ToolboxCars = require(ServerStorage.ToolboxCars)

local ToolboxBuilder = {}

local templates: { [number]: Model } = {}

local loading: { [number]: boolean } = {}

local function loadOne(modelId: number, assetId: number)
	loading[modelId] = true
	for attempt = 1, 4 do
		local ok, asset = pcall(function()
			return InsertService:LoadAsset(assetId)
		end)
		if ok and asset then
			local car = asset:FindFirstChild("Car", true)
			if car and car:IsA("Model") then
				car.Parent = nil
				templates[modelId] = car
				loading[modelId] = nil
				return
			end
		end
		warn(string.format("[ToolboxBuilder] body %d load attempt %d failed: %s", modelId, attempt, tostring(asset)))
		task.wait(2 * attempt)
	end
	loading[modelId] = nil
end

function ToolboxBuilder.Start()
	for modelId, info in ToolboxCars :: any do
		if info.assetId and info.assetId ~= 0 then
			task.spawn(loadOne, modelId, info.assetId)
		end
	end
end

-- Spawning waits for a mapped body so the same car never looks different between spawns.
function ToolboxBuilder.WaitFor(vehicleId: string, timeout: number)
	local map = (CarModels :: any)[vehicleId]
	if not map then
		return
	end
	local deadline = os.clock() + timeout
	while not templates[map[1]] and loading[map[1]] and os.clock() < deadline do
		task.wait(0.2)
	end
end

-- For tests: register a template directly.
function ToolboxBuilder._inject(modelId: number, car: Model)
	templates[modelId] = car
end

function ToolboxBuilder.Available(vehicleId: string): boolean
	local map = (CarModels :: any)[vehicleId]
	return map ~= nil and templates[map[1]] ~= nil
end

local TRIM = Color3.fromRGB(20, 20, 22)

local function part(
	model: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	props: { [string]: any }?
): Part
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
	p.Massless = true
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- `builder` is VehicleBuilder (passed in to avoid a require cycle); `schemes` its livery colours.
function ToolboxBuilder.Build(
	def: any,
	color: Color3?,
	builder: any,
	schemes: { [string]: any },
	liveryText: { [string]: any }
): Model?
	local map = (CarModels :: any)[def.id]
	if not map then
		return nil
	end
	local modelId, lengthM = map[1], map[2]
	local template = templates[modelId]
	local info = (ToolboxCars :: any)[modelId]
	if not template or not info then
		return nil
	end

	local s = lengthM * Config.StudsPerMeter / info.size[3] -- uniform scale to real length
	local W, H, L = info.size[1] * s, info.size[2] * s, info.size[3] * s
	local paint = color or def.color
	local scheme = def.livery and schemes[def.livery]

	local model = Instance.new("Model")
	model.Name = def.name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- wheels: centred on the model's own tyres (measured from the template, scaled)
	local wheelR = 0
	local specs = {}
	local trackHalf = W * 0.4
	local liftFromInfo = info.wheels.FL and (info.wheels.FL[4] * s - info.wheels.FL[2] * s) or 0
	for _, tag in { "FL", "FR", "RL", "RR" } do
		local w = info.wheels[tag]
		if w then
			-- centre and radius from the tagged tyre / rim pieces themselves
			local minV, maxV = nil, nil
			for _, src in template:GetChildren() do
				if src:IsA("BasePart") and src:GetAttribute("Wheel") == tag then
					local n = string.lower(src.Name)
					if not (string.find(n, "caliper") or string.find(n, "brake") or string.find(n, "fixed")) then
						local c, sz = src.CFrame.Position * s, src.Size * s
						local half = math.max(sz.X, sz.Y, sz.Z) / 2
						local lo, hi = c - Vector3.one * half, c + Vector3.one * half
						minV = if minV then minV:Min(lo) else lo
						maxV = if maxV then maxV:Max(hi) else hi
					end
				end
			end
			local cx, cy, cz, r = w[1] * s, w[2] * s, w[3] * s, w[4] * s
			if minV and maxV then
				local ctr = (minV + maxV) / 2
				-- trust the measured centre only if it agrees with the analysis (guards odd models)
				if (Vector3.new(ctr.X, 0, ctr.Z) - Vector3.new(cx, 0, cz)).Magnitude < r * 1.2 then
					cx, cy, cz = ctr.X, ctr.Y, ctr.Z
				end
			end
			wheelR = math.max(wheelR, r)
			trackHalf = math.max(trackHalf, math.abs(cx))
			table.insert(specs, {
				name = "Wheel" .. tag,
				tag = tag,
				x = cx,
				y = r,
				z = cz,
				r = r,
				w = math.max(0.8, r * 0.55),
				front = string.sub(tag, 1, 1) == "F",
				centreY = cy,
			})
		end
	end
	if #specs ~= 4 then
		return nil
	end
	-- the body sits so the wheels touch the ground at y = 0
	local lift = specs[1].r - specs[1].centreY
	if math.abs(lift - liftFromInfo) > specs[1].r then
		lift = liftFromInfo
	end

	-- collision / mass chassis (invisible)
	local clear = wheelR * 0.55
	local bodyH = math.max(1.2, H * 0.42)
	local chassis =
		part(model, "Chassis", Vector3.new(W * 0.92, bodyH, L * 0.94), CFrame.new(0, clear + bodyH / 2, 0), TRIM, {
			Transparency = 1,
			CanCollide = true,
			Massless = false,
			CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.3, 0.1),
		})
	model.PrimaryPart = chassis

	-- body pieces
	for _, src in template:GetChildren() do
		if src:IsA("BasePart") then
			local p = src:Clone()
			local cf = src.CFrame
			p.Size = src.Size * s
			p.CFrame = CFrame.new(cf.Position * s + Vector3.new(0, lift, 0)) * cf.Rotation
			for _, m in p:GetChildren() do
				if m:IsA("SpecialMesh") then
					m.Scale *= s
					m.Offset *= s
				end
			end
			p.Anchored = false
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = true
			if p:GetAttribute("Paint") then
				p.Color = if scheme then (scheme.ToolboxPaint or scheme.Body) else paint
				if scheme then
					p:SetAttribute("Paint", nil)
				end
			end
			p.Parent = model
		end
	end

	-- seats where the model had them (invisible; the model's own seats are visible)
	local driverPlaced = false
	-- Germany drives on the right: the driver always gets the front-left seat,
	-- whatever the model marked (some models put their drive seat on the right)
	local driverIndex: number? = nil
	do
		local frontZ = math.huge
		for _, st in info.seats do
			frontZ = math.min(frontZ, st[3])
		end
		local bestX = math.huge
		for i, st in info.seats do
			if st[3] < frontZ + 2.5 and st[1] < bestX then
				bestX = st[1]
				driverIndex = i
			end
		end
	end
	for i, st in info.seats do
		local isDriver = i == driverIndex and not driverPlaced
		local seat = Instance.new(if isDriver then "VehicleSeat" else "Seat") :: BasePart
		seat.Name = if isDriver then "DriveSeat" else "Seat"
		seat.Size = Vector3.new(1.6, 0.4, 1.6)
		seat.CFrame = CFrame.new(st[1] * s, st[2] * s + lift - 0.6, st[3] * s)
		seat.Transparency = 1
		seat.CanCollide = false
		seat.Massless = true
		if isDriver then
			driverPlaced = true
			local vs = seat :: VehicleSeat
			vs.MaxSpeed = 0
			vs.Torque = 0
			vs.HeadsUpDisplay = false
		end
		seat.Parent = model
		weld(chassis, seat)
		local _ = i
	end
	if not driverPlaced then
		-- models without seat data: driver behind the front axle, left-hand drive
		local seat = Instance.new("VehicleSeat")
		seat.Name = "DriveSeat"
		seat.Size = Vector3.new(1.6, 0.4, 1.6)
		seat.CFrame = CFrame.new(-W * 0.2, clear + bodyH * 0.6, specs[1].z + L * 0.22)
		seat.Transparency = 1
		seat.CanCollide = false
		seat.Massless = true
		seat.MaxSpeed = 0
		seat.Torque = 0
		seat.HeadsUpDisplay = false
		seat.Parent = model
		weld(chassis, seat)
	end

	-- lights (driven by the client like on every other car)
	local bf, br = info.badgeFront, info.badgeRear
	local fz, rz = -L / 2, L / 2
	local fy = bf[2] * s + lift
	local ry = br[2] * s + lift
	for _, side in { -1, 1 } do
		local head = part(
			model,
			"Headlight",
			Vector3.new(1.2, 0.4, 0.1),
			CFrame.new(side * W * 0.33, fy + 0.2, fz + 0.15),
			Color3.fromRGB(230, 230, 220),
			{ Transparency = 1 }
		)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Range = 60
		spot.Angle = 70
		spot.Brightness = 3
		spot.Enabled = false
		spot.Parent = head
		weld(chassis, head)
		local tail = part(
			model,
			"Taillight",
			Vector3.new(1.1, 0.35, 0.1),
			CFrame.new(side * W * 0.34, ry, rz - 0.15),
			Color3.fromRGB(120, 0, 0),
			{ Transparency = 1 }
		)
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 30, 30)
		glow.Range = 6
		glow.Enabled = false
		glow.Parent = tail
		weld(chassis, tail)
		for _, z in { fz + 0.15, rz - 0.15 } do
			weld(
				chassis,
				part(
					model,
					if side < 0 then "IndicatorL" else "IndicatorR",
					Vector3.new(0.3, 0.2, 0.1),
					CFrame.new(side * W * 0.42, (if z < 0 then fy else ry), z),
					Color3.fromRGB(120, 70, 0),
					{ Transparency = 1 }
				)
			)
		end
	end

	-- parody badge over the emblem spots (front + rear)
	local CHROME = Color3.fromRGB(200, 202, 206)
	for _, spot in { { bf, -1 }, { br, 1 } } do
		local b = spot[1]
		local disc = part(
			model,
			"Badge",
			Vector3.new(0.08, 0.5 * s * 3.5, 0.5 * s * 3.5),
			CFrame.new(0, b[2] * s + lift, b[3] * s + spot[2] * 0.05) * CFrame.Angles(0, math.rad(90), 0),
			CHROME,
			{
				Shape = Enum.PartType.Cylinder,
				Material = Enum.Material.Metal,
			}
		)
		disc.Size = Vector3.new(0.08, math.clamp(0.45 * s * 3.6, 0.35, 0.8), math.clamp(0.45 * s * 3.6, 0.35, 0.8))
		weld(chassis, disc)
	end

	-- plates
	builder.MakePlate(
		model,
		"PlateFront",
		CFrame.new(0, math.max(clear + 0.4, fy - 0.9), fz - 0.06),
		Enum.NormalId.Front
	)
	weld(chassis, model:FindFirstChild("PlateFront") :: BasePart)
	builder.MakePlate(model, "PlateRear", CFrame.new(0, math.max(clear + 0.5, ry - 0.7), rz + 0.06), Enum.NormalId.Back)
	weld(chassis, model:FindFirstChild("PlateRear") :: BasePart)

	-- (no side stripes / text on Creator Store bodies: their curved sides are unknown,
	-- so stripes would float. The livery colour goes on the paint instead.)
	local _ = trackHalf
	local _ = liveryText

	-- blue lights + siren on emergency vehicles (roof bar)
	if def.emergency then
		local roofY = H + lift
		local barZ = -L * 0.06
		if def.livery ~= "Unmarked" then
			weld(
				chassis,
				part(model, "LightbarBase", Vector3.new(W * 0.55, 0.2, 0.9), CFrame.new(0, roofY + 0.1, barZ), TRIM)
			)
			for _, side in { -1, 1 } do
				local bl = part(
					model,
					"Bluelight",
					Vector3.new(W * 0.24, 0.4, 0.8),
					CFrame.new(side * W * 0.14, roofY + 0.4, barZ),
					Color3.fromRGB(20, 40, 120),
					{ Material = Enum.Material.Glass, Transparency = 0.1 }
				)
				bl:SetAttribute("Side", side)
				local light = Instance.new("PointLight")
				light.Color = Color3.fromRGB(40, 90, 255)
				light.Range = 22
				light.Brightness = 4
				light.Enabled = false
				light.Parent = bl
				weld(chassis, bl)
			end
		end
		for _, side in { -1, 1 } do
			local fl = part(
				model,
				"Bluelight",
				Vector3.new(0.5, 0.2, 0.1),
				CFrame.new(side * W * 0.15, fy - 0.3, fz - 0.05),
				Color3.fromRGB(20, 40, 120),
				{ Material = Enum.Material.Glass }
			)
			fl:SetAttribute("Side", -side)
			weld(chassis, fl)
		end
		local siren = Instance.new("Sound")
		siren.Name = "Siren"
		siren.Looped = true
		siren.Volume = 1.2
		siren.RollOffMaxDistance = 400
		siren.SoundId = if Config.Sounds.Martinshorn ~= 0 then "rbxassetid://" .. Config.Sounds.Martinshorn else ""
		siren.Parent = chassis
	end

	-- weld body pieces: wheel pieces to their physics wheel (so they turn), the rest to the chassis
	local mass = W * bodyH * L * 0.6 + 60
	builder.AddPhysics(model, chassis, def, specs, mass, false)
	local byTag = {}
	for _, sp in specs do
		byTag[sp.tag] = sp
	end
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p ~= chassis and not p:FindFirstChildOfClass("WeldConstraint") then
			if p.Name ~= "Knuckle" and not string.match(p.Name, "^Wheel[FR][LR]$") then
				local tag = p:GetAttribute("Wheel")
				local sp = if typeof(tag) == "string" then byTag[tag] else nil
				local target: BasePart = chassis
				if sp then
					local n = string.lower(p.Name)
					local wheelPart = model:FindFirstChild(sp.name) :: BasePart?
					local fixed = string.find(n, "caliper") or string.find(n, "brake") or string.find(n, "fixed")
					local dist = (p.CFrame.Position - Vector3.new(sp.x, sp.y, sp.z)).Magnitude
					if wheelPart and not fixed and dist < sp.r * 1.1 then
						target = wheelPart -- turns with the wheel
					else
						-- fixed parts ride on the knuckle (front, steers) or the chassis (rear)
						local knuckle = wheelPart and wheelPart:FindFirstChild("NoCollisionConstraint")
						local _ = knuckle
						target = chassis
					end
				end
				weld(target, p)
			end
		end
	end
	model:SetAttribute("Realistic", true)
	model:SetAttribute("Toolbox", tostring(modelId))
	return model
end

return ToolboxBuilder
