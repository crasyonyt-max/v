--[[
	Builds a car Model out of ordinary Parts from a config in Configs.lua.

	Structure of a built car:
	  Model (tag "RealisticCar", attribute CarType)
	    Chassis        invisible root that carries all the mass (sets centre of mass + inertia)
	      MountFL..RR  suspension top mounts (Attachments)
	    Hitbox, CabinHitbox   invisible collision boxes
	    Body           visual parts, all massless and welded to Chassis
	    WheelFL..RR    tires driven by a Motor6D named "Motor" (spring + steer + spin)
	    DriverSeat (VehicleSeat), Seat2..n (Seats), each with a ProximityPrompt
]]

local CollectionService = game:GetService("CollectionService")

local Configs = require(script.Parent.Configs)
local Layout = require(script.Parent.Layout)

local MPS = Configs.METERS_PER_STUD
local Builder = {}

local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass
local PAINT = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal

function Builder.build(cfg, base)
	local L = Layout.compute(cfg)
	local b = cfg.body
	local col = cfg.colors
	local r, ww = cfg.wheelRadius, cfg.wheelWidth
	local W, H, clear = b.width, b.height, b.clearance
	local fz, rz = L.frontZ, L.rearZ
	local wbh = cfg.wheelbase / 2
	local paint = cfg.color
	local accent = cfg.accentColor or paint

	local model = Instance.new("Model")
	model.Name = cfg.displayName
	model:SetAttribute("CarType", cfg.key)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = L.ballastSize
	chassis.CFrame = base * CFrame.new(L.com / MPS)
	chassis.Transparency = 1
	chassis.CanCollide = false
	chassis.CanQuery = false
	chassis.CanTouch = false
	chassis.CustomPhysicalProperties = PhysicalProperties.new(8, 0.3, 0, 1, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local bodyModel = Instance.new("Model")
	bodyModel.Name = "Body"
	bodyModel.Parent = model

	-- Classic Welds with explicit offsets, so nothing depends on the order the
	-- engine activates joints in (the wheel Motor6Ds move the tires).
	local function weld(p, to)
		to = to or chassis
		local w = Instance.new("Weld")
		w.Part0 = to
		w.Part1 = p
		w.C0 = to.CFrame:ToObjectSpace(p.CFrame)
		w.Parent = p
	end

	-- size and center in meters, car space
	local function box(name, size, center, color, material, opts)
		opts = opts or {}
		local p = Instance.new(opts.class or "Part")
		p.Name = name
		p.Size = size / MPS
		p.CFrame = base * CFrame.new(center / MPS) * (opts.rot or CFrame.identity)
		p.Color = color
		p.Material = material or PAINT
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		if opts.shape then
			p.Shape = opts.shape
		end
		if opts.transparency then
			p.Transparency = opts.transparency
		end
		if opts.reflectance then
			p.Reflectance = opts.reflectance
		end
		p.Parent = opts.parent or bodyModel
		weld(p, opts.weldTo)
		return p
	end
	local function v(x, y, z)
		return Vector3.new(x, y, z)
	end
	local function zbox(name, z0, z1, y0, y1, width, color, material, opts)
		if z1 - z0 < 0.005 or y1 - y0 < 0.005 then
			return nil
		end
		return box(name, v(width, y1 - y0, z1 - z0), v(0, (y0 + y1) / 2, (z0 + z1) / 2), color, material, opts)
	end

	---------------------------------------------------------------- lower body
	local fenderBottom = 2 * r + 0.06
	local belt = math.max(b.belt, fenderBottom + 0.12)
	local well = r + 0.08
	local coreW = W - 2 * (ww + 0.1)
	local bedZ = b.bedStart and L.z(b.bedStart) or nil
	local noseLen = b.noseLength or 0.32

	-- Layer A (sills, bumpers, floor) with cut-outs for the wheel wells.
	zbox("Nose", fz, -wbh - well, clear, fenderBottom, W, paint)
	zbox("FrontWellCore", -wbh - well, -wbh + well, clear + 0.05, fenderBottom, coreW, col.trim)
	zbox("Sill", -wbh + well, wbh - well, clear, fenderBottom, W, paint)
	zbox("RearWellCore", wbh - well, wbh + well, clear + 0.05, fenderBottom, coreW, col.trim)
	zbox("Tail", wbh + well, rz, clear, fenderBottom, W, paint)

	-- Layer B (fenders, doors, hood, trunk) from the wheel tops to the belt line.
	box("HoodEdge", v(W, belt - fenderBottom, noseLen), v(0, (fenderBottom + belt) / 2, fz + noseLen / 2), paint, PAINT, { class = "WedgePart" })
	local doorFront, doorRear = -wbh + well, math.min(wbh - well, bedZ or math.huge)
	zbox("FrontFenders", fz + noseLen, doorFront, fenderBottom, belt, W, paint)
	local doors = zbox("Doors", doorFront, doorRear, fenderBottom, belt, W, accent)
	zbox("RearQuarters", doorRear, bedZ or rz, fenderBottom, belt, W, paint)

	if bedZ then
		-- Pickup bed: floor at the fender line, thin walls and a tailgate.
		local t = 0.06
		for _, side in ipairs({ -1, 1 }) do
			box("BedSide", v(t, belt - fenderBottom, rz - bedZ), v(side * (W / 2 - t / 2), (fenderBottom + belt) / 2, (bedZ + rz) / 2), paint)
		end
		zbox("Tailgate", rz - t, rz, fenderBottom, belt, W - 2 * t, paint)
		zbox("BedFront", bedZ, bedZ + t, fenderBottom, belt, W - 2 * t, paint)
		zbox("BedLiner", bedZ + t, rz - t, fenderBottom, fenderBottom + 0.01, W - 2 * t, col.trim)
	end

	---------------------------------------------------------------- cabin
	local zW, zRF, zRR, zRB = L.z(b.windshieldBase), L.z(b.roofFront), L.z(b.roofRear), L.z(b.rearBase)
	local cw = W - 2 * b.cabinInset
	local ch = H - belt
	local glassOpts = { transparency = 0.35, reflectance = 0.15 }
	local function glass(name, size, center, rot, class)
		return box(name, size, center, col.glass, GLASS, {
			transparency = glassOpts.transparency, reflectance = glassOpts.reflectance, rot = rot, class = class,
		})
	end
	glass("Windshield", v(cw, ch, zRF - zW), v(0, belt + ch / 2, (zW + zRF) / 2), nil, "WedgePart")
	glass("SideGlass", v(cw, ch - 0.05, zRR - zRF), v(0, belt + (ch - 0.05) / 2, (zRF + zRR) / 2))
	if zRB - zRR > 0.02 then
		glass("RearGlass", v(cw, ch, zRB - zRR), v(0, belt + ch / 2, (zRR + zRB) / 2), CFrame.Angles(0, math.pi, 0), "WedgePart")
	end
	box("Roof", v(cw + 0.02, 0.05, zRR - zRF + 0.03), v(0, H - 0.025, (zRF + zRR) / 2), paint)

	-- Pillars
	local function pillar(z0, y0, z1, y1, x)
		local dz, dy = z1 - z0, y1 - y0
		local len = math.sqrt(dz * dz + dy * dy)
		local angle = -math.atan2(dy, dz)
		box("Pillar", v(0.05, 0.06, len), v(x, (y0 + y1) / 2, (z0 + z1) / 2), paint, PAINT, { rot = CFrame.Angles(angle, 0, 0) })
	end
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (cw / 2)
		pillar(zW, belt, zRF, H - 0.02, x) -- A
		if zRB - zRR > 0.02 then
			pillar(zRR, H - 0.02, zRB, belt, x) -- C
		end
		box("BPillar", v(0.04, ch - 0.05, 0.09), v(x, belt + (ch - 0.05) / 2, zRF + math.min(1.0, (zRR - zRF) * 0.45)), col.trim)
		-- mirror
		box("Mirror", v(0.13, 0.1, 0.17), v(side * (cw / 2 + 0.1), belt + 0.09, zW + 0.18), paint)
	end

	---------------------------------------------------------------- doors & trim
	local nDoors = cfg.doors or 2
	local frontDoorLen = nDoors == 4 and 1.05 or 1.3
	local seamZ = { doorFront + 0.04, doorFront + 0.04 + frontDoorLen }
	if nDoors == 4 then
		table.insert(seamZ, math.min(doorRear - 0.04, seamZ[2] + 0.9))
	end
	for _, side in ipairs({ -1, 1 }) do
		for i, z in ipairs(seamZ) do
			box("DoorSeam", v(0.012, belt - clear - 0.14, 0.012), v(side * (W / 2 + 0.003), (clear + 0.1 + belt) / 2, z), col.trim)
			if i < #seamZ or nDoors == 2 then
				box("Handle", v(0.02, 0.03, 0.13), v(side * (W / 2 + 0.008), belt - 0.1, (i < #seamZ and seamZ[i + 1] or z) - 0.2), col.trim, METAL)
			end
		end
	end
	if cfg.police and doors then
		for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = "POLICE"
			label.TextScaled = true
			label.Font = Enum.Font.GothamBlack
			label.TextColor3 = Color3.fromRGB(20, 22, 26)
			label.Parent = gui
			gui.Parent = doors
		end
	end

	-- Bumpers, grille, plates, exhaust
	box("FrontBumper", v(W + 0.03, 0.2, 0.1), v(0, clear + 0.12, fz - 0.03), col.trim)
	box("RearBumper", v(W + 0.03, 0.2, 0.1), v(0, clear + 0.12, rz + 0.03), col.trim)
	box("Grille", v(W * 0.42, 0.15, 0.03), v(0, fenderBottom - 0.16, fz - 0.012), col.trim)
	box("FrontPlate", v(0.52, 0.11, 0.02), v(0, clear + 0.27, fz - 0.085), Color3.fromRGB(235, 235, 230))
	box("RearPlate", v(0.52, 0.11, 0.02), v(0, clear + 0.33, rz + 0.01), Color3.fromRGB(235, 235, 230))
	local pipes = (cfg.key == "Sports" or cfg.key == "Muscle" or cfg.key == "Supercar") and { -1, 1 } or { 1 }
	for _, side in ipairs(pipes) do
		box("Exhaust", v(0.2, 0.085, 0.085), v(side * (W / 2 - 0.35), clear + 0.05, rz - 0.04), Color3.fromRGB(120, 120, 125), METAL, {
			shape = Enum.PartType.Cylinder, rot = CFrame.Angles(0, math.pi / 2, 0),
		})
	end

	---------------------------------------------------------------- lights
	local lights = Instance.new("Model")
	lights.Name = "Lights"
	lights.Parent = model
	local lightY = fenderBottom - 0.1
	local tailY = belt - 0.17
	for _, side in ipairs({ -1, 1 }) do
		local head = box("Headlight", v(0.34, 0.12, 0.04), v(side * (W / 2 - 0.23), lightY, fz - 0.005), Color3.fromRGB(205, 205, 200), NEON, { parent = lights })
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Front
		beam.Range = 60
		beam.Angle = 75
		beam.Brightness = 4
		beam.Shadows = true
		beam.Enabled = false
		beam.Parent = head
		box("Taillight", v(0.32, 0.12, 0.04), v(side * (W / 2 - 0.21), tailY, rz + 0.005), Color3.fromRGB(110, 10, 10), NEON, { parent = lights })
		box("ReverseLight", v(0.1, 0.08, 0.035), v(side * (W / 2 - 0.44), tailY, rz + 0.005), Color3.fromRGB(110, 110, 110), GLASS, { parent = lights })
	end

	if cfg.police then
		local zc = (zRF + zRR) / 2 - 0.1
		box("LightbarBase", v(cw * 0.8, 0.06, 0.24), v(0, H + 0.03, zc), col.trim, PAINT, { parent = lights })
		for _, side in ipairs({ -1, 1 }) do
			local name = side < 0 and "SirenRed" or "SirenBlue"
			local color = side < 0 and Color3.fromRGB(90, 0, 0) or Color3.fromRGB(0, 0, 90)
			local p = box(name, v(cw * 0.38, 0.07, 0.2), v(side * cw * 0.2, H + 0.095, zc), color, NEON, { parent = lights })
			local glow = Instance.new("PointLight")
			glow.Range = 24
			glow.Brightness = 5
			glow.Color = side < 0 and Color3.fromRGB(255, 30, 30) or Color3.fromRGB(40, 80, 255)
			glow.Enabled = false
			glow.Parent = p
		end
	end

	---------------------------------------------------------------- interior & seats
	box("Dashboard", v(cw - 0.08, 0.16, 0.3), v(0, belt - 0.02, zW + 0.22), col.trim)
	local floorY = clear + 0.12
	box("Floor", v(cw - 0.05, 0.03, zRB - zW), v(0, floorY, (zW + zRB) / 2), col.trim)

	local seatTop = math.max(floorY + 0.08, math.min(clear + 0.33, H - 0.78))
	local frontZ = zRF + 0.32
	local positions = { { -1, frontZ }, { 1, frontZ } }
	if cfg.seats >= 4 then
		local rearZ = math.min(frontZ + 0.85, zRR - 0.1)
		table.insert(positions, { -1, rearZ })
		table.insert(positions, { 1, rearZ })
	end
	local seatX = cw * 0.24
	for i, pos in ipairs(positions) do
		local x, z = pos[1] * seatX, pos[2]
		box("SeatCushion", v(0.46, 0.1, 0.46), v(x, seatTop - 0.05, z), Color3.fromRGB(45, 45, 48))
		box("SeatBack", v(0.46, 0.58, 0.1), v(x, seatTop + 0.27, z + 0.26), Color3.fromRGB(45, 45, 48), PAINT, { rot = CFrame.Angles(math.rad(-12), 0, 0) })

		local seat = Instance.new(i == 1 and "VehicleSeat" or "Seat")
		seat.Name = i == 1 and "DriverSeat" or ("Seat" .. i)
		seat.Size = v(0.44, 0.06, 0.44) / MPS
		seat.CFrame = base * CFrame.new(v(x, seatTop - 0.03, z) / MPS)
		seat.Transparency = 1
		seat.CanCollide = false
		seat.Massless = true
		if seat:IsA("VehicleSeat") then
			seat.HeadsUpDisplay = false
			seat.MaxSpeed = 0
			seat.Torque = 0
			seat.TurnSpeed = 0
		end
		seat.Parent = model
		weld(seat)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "EnterPrompt"
		prompt.ActionText = i == 1 and "Drive" or "Ride"
		prompt.ObjectText = cfg.displayName
		prompt.HoldDuration = 0.15
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = i == 1 and Enum.KeyCode.E or Enum.KeyCode.Q
		prompt.Parent = seat

		if i == 1 then
			box("SteeringWheel", v(0.035, 0.36, 0.36), v(x, seatTop + 0.36, z - 0.42), Color3.fromRGB(30, 30, 32), PAINT, {
				shape = Enum.PartType.Cylinder, rot = CFrame.Angles(math.rad(-22), math.pi / 2, 0),
			})
		end
	end

	---------------------------------------------------------------- collision
	local function hitbox(name, size, center)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size / MPS
		p.CFrame = base * CFrame.new(center / MPS)
		p.Transparency = 1
		p.Massless = true
		p.CanTouch = false
		p.CustomPhysicalProperties = PhysicalProperties.new(1, 0.15, 0.1, 1, 1)
		p.Parent = model
		weld(p)
	end
	hitbox("Hitbox", v(W, belt - clear - 0.1, b.length), v(0, (clear + 0.1 + belt) / 2, (fz + rz) / 2))
	hitbox("CabinHitbox", v(cw, ch, zRB - zW), v(0, belt + ch / 2, (zW + zRB) / 2))

	---------------------------------------------------------------- wheels
	for name, wl in pairs(L.wheels) do
		local side = name:sub(2, 2) == "L" and -1 or 1
		local center = wl.rest
		local tire = box("Wheel" .. name, v(ww, 2 * r, 2 * r), center, Color3.fromRGB(24, 24, 24), PAINT, {
			shape = Enum.PartType.Cylinder, parent = model,
		})
		tire:FindFirstChildOfClass("Weld"):Destroy()
		local function onWheel(partName, size, offsetX, color, material, rot, shape)
			box(partName, size, center + v(offsetX, 0, 0), color, material, {
				parent = tire, weldTo = tire, rot = rot, shape = shape,
			})
		end
		onWheel("Rim", v(ww + 0.012, 2 * r * 0.66, 2 * r * 0.66), 0, col.rim, METAL, nil, Enum.PartType.Cylinder)
		onWheel("Hub", v(ww + 0.03, 0.11, 0.11), 0, col.trim, METAL, nil, Enum.PartType.Cylinder)
		for k = 0, 2 do
			onWheel("Spoke", v(0.014, 2 * r * 0.62, 0.055), side * (ww / 2 + 0.004), col.rim, METAL, CFrame.Angles(k * math.pi / 3, 0, 0))
		end

		local mount = Instance.new("Attachment")
		mount.Name = "Mount" .. name
		mount.Position = wl.mountLocal
		mount.Parent = chassis

		local motor = Instance.new("Motor6D")
		motor.Name = "Motor"
		motor.Part0 = chassis
		motor.Part1 = tire
		motor.C0 = CFrame.new(wl.mountLocal)
		motor.C1 = CFrame.identity
		motor.Parent = tire
	end

	---------------------------------------------------------------- sound & state
	if Configs.ENGINE_SOUND_ID ~= "" then
		local sound = Instance.new("Sound")
		sound.Name = "Engine"
		sound.SoundId = Configs.ENGINE_SOUND_ID
		sound.Looped = true
		sound.Volume = 0.5
		sound.RollOffMaxDistance = 250
		sound.Parent = chassis
	end

	model:SetAttribute("Steer", 0)
	model:SetAttribute("RPM", cfg.engine.idleRPM)
	model:SetAttribute("Throttle", 0)
	model:SetAttribute("Gear", 0)
	model:SetAttribute("Brake", false)
	model:SetAttribute("Headlights", false)
	model:SetAttribute("Siren", false)
	CollectionService:AddTag(model, "RealisticCar")
	return model
end

return Builder
