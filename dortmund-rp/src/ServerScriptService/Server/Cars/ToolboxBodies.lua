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

	local body = templates[id]:Clone()
	body.WorldPivot = CFrame.new()
	body:ScaleTo(s)
	body:PivotTo(CFrame.lookAt(mid, mid + fwd.Unit))
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

	-- hide the generated look (keep the physics parts, wheels and emergency lights)
	local generated = model:FindFirstChild("Body")
	if generated then
		for _, p in generated:GetDescendants() do
			if p:IsA("BasePart") then
				p.Transparency = 1
				CollectionService:RemoveTag(p, "Body")
				CollectionService:RemoveTag(p, "Stripe")
				CollectionService:RemoveTag(p, "Accent")
				CollectionService:RemoveTag(p, "Lettering")
			elseif p:IsA("SurfaceGui") or p:IsA("Decal") then
				p:Destroy()
			end
		end
	end
	local lights = model:FindFirstChild("Lights")
	if lights then
		for _, p in lights:GetDescendants() do
			if p:IsA("BasePart") and not CollectionService:HasTag(p, "EmergencyLight") then
				p.Transparency = 1
			end
		end
	end

	-- light bar onto the new roof
	local roofY = mid.Y + info.max[2] * s
	local lightbar = model:FindFirstChild("Lightbar")
	if lightbar then
		local lowest = math.huge
		for _, p in lightbar:GetDescendants() do
			if p:IsA("BasePart") then
				lowest = math.min(lowest, p.Position.Y - p.Size.Y / 2)
			end
		end
		if lowest < math.huge then
			local dy = roofY + 0.05 - lowest
			for _, p in lightbar:GetDescendants() do
				if p:IsA("BasePart") then
					moveWelded(p, Vector3.new(0, dy, 0))
				end
			end
		end
	end

	-- lettering panels on both sides (the livery writes POLIZEI / NOTARZT / ... on them)
	local frame = CFrame.lookAt(mid, mid + fwd.Unit)
	local half = math.max(math.abs(info.min[1]), math.abs(info.max[1])) * s
	local height = (info.max[2] - info.min[2]) * s
	local length = (info.max[3] - info.min[3]) * s
	local zc = (info.min[3] + info.max[3]) / 2 * s
	for _, side in { -1, 1 } do
		local panel = Instance.new("Part")
		panel.Name = "LetteringPanel"
		panel.Size = Vector3.new(0.05, height * 0.18, length * 0.5)
		panel.CFrame = frame * CFrame.new(side * (half + 0.03), info.min[2] * s + height * 0.42, zc)
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
	model:SetAttribute("ToolboxBody", id)
	return true
end

return ToolboxBodies
