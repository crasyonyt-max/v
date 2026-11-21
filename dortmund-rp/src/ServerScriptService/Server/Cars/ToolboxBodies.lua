--!strict
-- V1.0: real car bodies (cleaned Creator Store models, ServerStorage.ToolboxBodies)
-- on top of the RealisticCars physics. The generated body is hidden; the cleaned body
-- is scaled so its wheel arches sit on our wheels, welded to the chassis, and its
-- paint parts get the "Body" tag so every livery recolours it. The light bar moves up
-- onto the new roof and two lettering panels carry the livery text.
-- Bodies load from the group (InsertService) once their asset id is set.

local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Bodies = require(ServerStorage:WaitForChild("ToolboxBodies")) :: any

local ToolboxBodies = {}

local templates: { [number]: Model } = {}
local loading: { [number]: boolean } = {}

local function load(id: number, assetId: number)
	loading[id] = true
	for attempt = 1, 4 do
		local ok, asset = pcall(function()
			return InsertService:LoadAsset(assetId)
		end)
		if ok and asset then
			local car = asset:FindFirstChild("Car", true)
			if car and car:IsA("Model") then
				car.Parent = nil
				templates[id] = car
				loading[id] = nil
				return
			end
		end
		warn(("[ToolboxBodies] %d (asset %d) load attempt %d failed: %s"):format(id, assetId, attempt, tostring(asset)))
		task.wait(2 * attempt)
	end
	loading[id] = nil
end

function ToolboxBodies.Start()
	if not Config.V10 then
		return
	end
	for id, info in Bodies do
		if info.assetId and info.assetId ~= 0 then
			task.spawn(load, id, info.assetId)
		end
	end
end

-- is the body for this vehicle ready (waits a little while it is loading)?
function ToolboxBodies.Ready(id: number, timeout: number?): boolean
	local deadline = os.clock() + (timeout or 0)
	while not templates[id] and loading[id] and os.clock() < deadline do
		task.wait(0.2)
	end
	return templates[id] ~= nil
end

local function wheelPos(model: Model, name: string): Vector3?
	local w = model:FindFirstChild("Wheel" .. name)
	return if w and w:IsA("BasePart") then w.Position else nil
end

local function moveWelded(p: BasePart, offset: Vector3)
	p.CFrame += offset
	for _, j in p:GetChildren() do
		if j:IsA("Weld") and j.Part0 and j.Part1 == p then
			j.C0 = j.Part0.CFrame:ToObjectSpace(p.CFrame)
		end
	end
end

-- Measures the real body with rays (it sits alone, anchored, far away for a moment):
-- where the bumpers, sides and roof really are, so plates, indicators, the light bar,
-- lettering and bus parts go onto the body instead of floating in the air.
-- All results are in the body's own frame (-Z = front), already scaled.
local PROBE = CFrame.new(0, 40000, 0)
type Cast = (from: Vector3, dir: Vector3) -> Vector3?
local function measure(body: Model): (Vector3, Vector3, Cast, () -> ())
	body:PivotTo(PROBE)
	local saved: { [BasePart]: boolean } = {}
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") then
			saved[p] = p.CanQuery
			p.CanQuery = true
		end
	end
	body.Parent = workspace
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { body }
	local function cast(from: Vector3, dir: Vector3): Vector3?
		local r = workspace:Raycast(PROBE * from, PROBE:VectorToWorldSpace(dir), params)
		return if r then PROBE:PointToObjectSpace(r.Position) else nil
	end
	local bbCf, bbSize = body:GetBoundingBox()
	local lo = PROBE:PointToObjectSpace(bbCf.Position) - bbSize / 2
	local function done()
		body.Parent = nil
		for p, q in saved do
			p.CanQuery = q
		end
		body:PivotTo(CFrame.new())
	end
	return lo, lo + bbSize, cast, done
end

-- the car's own wheels go onto the physics wheels (they turn and steer with them).
-- `center` = the wheel's axle point in world space, `bodyR` its scaled radius.
local function fitWheel(model: Model, wm: Model, corner: string, center: Vector3, bodyR: number)
	local tire = model:FindFirstChild("Wheel" .. corner)
	if not tire or not tire:IsA("BasePart") then
		wm:Destroy()
		return
	end
	wm.WorldPivot = CFrame.new(center)
	local ratio = (tire.Size.Y / 2) / math.max(bodyR, 0.05)
	if ratio > 0.5 and ratio < 2 then
		wm:ScaleTo(wm:GetScale() * ratio) -- same size as the physics wheel: no floating / sinking
	end
	wm:PivotTo(CFrame.new(tire.Position) * (wm:GetPivot() - wm:GetPivot().Position))
	for _, p in wm:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = tire
			weld.Part1 = p
			weld.Parent = p
		end
	end
	wm.Name = "BodyWheel" .. corner -- not "Wheel..": the sim looks those up by name
	wm.Parent = model
	-- hide the plain physics wheel
	tire.Transparency = 1
	for _, d in tire:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
		end
	end
end

local function setTransparent(root: Instance?)
	if not root then
		return
	end
	for _, p in root:GetDescendants() do
		if p:IsA("BasePart") then
			p.Transparency = 1
			for _, tag in { "Body", "Stripe", "Accent", "Lettering" } do
				CollectionService:RemoveTag(p, tag)
			end
		elseif p:IsA("SurfaceGui") or p:IsA("Decal") then
			p:Destroy()
		end
	end
end

-- puts the cleaned body on a freshly built car model (not parented yet). false = the
-- body isn't available, the car keeps its generated body.
function ToolboxBodies.Apply(model: Model, vehicle: any): boolean
	local id = vehicle.Toolbox
	local info = id and Bodies[id]
	if not info or not ToolboxBodies.Ready(id, 8) then
		return false
	end
	local chassis = model:FindFirstChild("Chassis") :: BasePart?
	local fl, fr, rl, rr = wheelPos(model, "FL"), wheelPos(model, "FR"), wheelPos(model, "RL"), wheelPos(model, "RR")
	if not chassis or not fl or not fr or not rl or not rr then
		return false
	end
	local front, rear = (fl + fr) / 2, (rl + rr) / 2
	local mid = (front + rear) / 2
	local fwd = (front - rear) * Vector3.new(1, 0, 1)
	if fwd.Magnitude < 0.1 then
		return false
	end
	local genBase = fwd.Magnitude
	local w = info.wheels
	local bodyBase = math.abs(w.FL[3] - w.RL[3])
	local s = genBase / math.max(bodyBase, 0.1)
	local frame = CFrame.lookAt(mid, mid + fwd.Unit)

	local body = templates[id]:Clone()
	body.WorldPivot = CFrame.new()
	body:ScaleTo(s)

	-- the car's own wheels come out of the body first
	local wheelModels: { [string]: Model } = {}
	for _, corner in { "FL", "FR", "RL", "RR" } do
		local wm = body:FindFirstChild("Wheel" .. corner)
		if wm and wm:IsA("Model") then
			wm.Parent = nil
			wheelModels[corner] = wm
		end
	end

	-- measure the body (rays), all in the body frame
	local lo, hi, cast, done = measure(body)
	local H = hi.Y - lo.Y
	local half = math.max(math.abs(lo.X), math.abs(hi.X))
	local function roofAt(x: number, z: number): number?
		local h = cast(Vector3.new(x, hi.Y + 2, z), Vector3.new(0, -(H + 4), 0))
		return h and h.Y
	end
	local function frontAt(x: number, y: number): Vector3?
		return cast(Vector3.new(x, y, lo.Z - 2), Vector3.new(0, 0, (hi.Z - lo.Z) / 2 + 2))
	end
	local function rearAt(x: number, y: number): Vector3?
		return cast(Vector3.new(x, y, hi.Z + 2), Vector3.new(0, 0, -((hi.Z - lo.Z) / 2 + 2)))
	end
	local function sideAt(side: number, y: number, z: number): number?
		local h = cast(Vector3.new(side * (half + 2), y, z), Vector3.new(-side * (half + 2), 0, 0))
		return h and math.abs(h.X)
	end

	local zc = (lo.Z + hi.Z) / 2
	-- spots for plates, indicators, grille flashers (VehicleService reads them)
	local spots: { [string]: Vector3? } = {
		PlateF = frontAt(0, lo.Y + H * 0.22),
		PlateR = rearAt(0, lo.Y + H * 0.3),
		IndFL = frontAt(-half * 0.68, lo.Y + H * 0.4),
		IndFR = frontAt(half * 0.68, lo.Y + H * 0.4),
		IndRL = rearAt(-half * 0.68, lo.Y + H * 0.5),
		IndRR = rearAt(half * 0.68, lo.Y + H * 0.5),
		FlashL = frontAt(-half * 0.3, lo.Y + H * 0.3),
		FlashR = frontAt(half * 0.3, lo.Y + H * 0.3),
	}
	-- the real outline at mid height / near the roof (mirrors don't count)
	local sideX = sideAt(1, lo.Y + H * 0.45, zc) or half
	local roofC = roofAt(0, zc) or hi.Y
	local upper = lo.Y + (roofC - lo.Y) * 0.8
	local frontZ = (frontAt(0, upper) or Vector3.new(0, 0, lo.Z)).Z
	local rearZ = (rearAt(0, upper) or Vector3.new(0, 0, hi.Z)).Z

	-- light bar: the roof right under it
	local lightbar = model:FindFirstChild("Lightbar")
	local lbDy: number? = nil
	if lightbar then
		local lowest, sum, n = math.huge, Vector3.zero, 0
		for _, p in lightbar:GetDescendants() do
			if p:IsA("BasePart") then
				lowest = math.min(lowest, p.Position.Y - p.Size.Y / 2)
				sum += p.Position
				n += 1
			end
		end
		if n > 0 then
			local c = frame:PointToObjectSpace(sum / n)
			local roof = roofAt(c.X, c.Z) or roofAt(0, c.Z) or hi.Y
			lbDy = (mid.Y + roof + 0.04) - lowest
		end
	end
	-- lettering height: where the side really is
	local letterY = lo.Y + H * 0.42
	local letterX = sideAt(1, letterY, zc) or half
	done()

	body:PivotTo(frame)
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			if p:GetAttribute("Paint") then
				CollectionService:AddTag(p, "Body")
			end
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = chassis
			weld.Part1 = p
			weld.Parent = p
		end
	end
	body.Name = "ToolboxBody"
	body.Parent = model

	-- own wheels onto the physics wheels
	for corner, wm in wheelModels do
		for _, p in wm:GetDescendants() do
			if p:IsA("BasePart") then
				p.CFrame = frame * p.CFrame -- body frame -> world, like the body
			end
		end
		local c = w[corner]
		fitWheel(model, wm, corner, frame * (Vector3.new(c[1], c[2], c[3]) * s), c[4] * s)
	end

	-- hide the generated look (keep the physics parts, wheels and emergency lights)
	setTransparent(model:FindFirstChild("Body"))
	setTransparent(model:FindFirstChild("Trailer"))
	local grilles = model:FindFirstChild("WindowGrilles")
	if grilles then
		grilles:Destroy()
	end
	local lights = model:FindFirstChild("Lights")
	if lights then
		for _, p in lights:GetDescendants() do
			if p:IsA("BasePart") and not CollectionService:HasTag(p, "EmergencyLight") then
				p.Transparency = 1
			end
		end
		-- grille flashers into the real front
		for _, p in lights:GetChildren() do
			if p:IsA("BasePart") and p.Name == "GrilleFlasher" then
				local l = frame:PointToObjectSpace(p.Position)
				local spot = if l.X < 0 then spots.FlashL else spots.FlashR
				if spot then
					p.CFrame = frame * CFrame.new(spot + Vector3.new(0, 0, -0.03))
					local wj = p:FindFirstChildOfClass("Weld")
					if wj and wj.Part0 then
						wj.C0 = wj.Part0.CFrame:ToObjectSpace(p.CFrame)
					end
				end
			end
		end
	end
	if lightbar and lbDy then
		for _, p in lightbar:GetDescendants() do
			if p:IsA("BasePart") then
				moveWelded(p, Vector3.new(0, lbDy, 0))
			end
		end
	end

	-- lettering panels on both sides (the livery writes POLIZEI / NOTARZT / ... on them)
	local length = rearZ - frontZ
	for _, side in { -1, 1 } do
		local panel = Instance.new("Part")
		panel.Name = "LetteringPanel"
		panel.Size = Vector3.new(0.05, H * 0.16, length * 0.5)
		panel.CFrame = frame * CFrame.new(side * (letterX + 0.03), letterY, (frontZ + rearZ) / 2)
		panel.Transparency = 1
		panel.CanCollide = false
		panel.CanQuery = false
		panel.CanTouch = false
		panel.Massless = true
		panel.Anchored = false
		panel:SetAttribute("LetteringFaces", if side < 0 then "Left" else "Right")
		CollectionService:AddTag(panel, "Lettering")
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = chassis
		weld.Part1 = panel
		weld.Parent = panel
		panel.Parent = model
	end

	-- for VehicleService (plates, indicators) and BusService (doors, displays, lounge)
	model:SetAttribute("BodyFrame", chassis.CFrame:ToObjectSpace(frame))
	model:SetAttribute("BodyMin", Vector3.new(-sideX, lo.Y, frontZ))
	model:SetAttribute("BodyMax", Vector3.new(sideX, roofC, rearZ))
	for k, v in spots do
		model:SetAttribute("Spot" .. k, v)
	end
	model:SetAttribute("ToolboxBody", id)
	return true
end

return ToolboxBodies
