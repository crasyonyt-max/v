--!strict
-- Loads the generated car body / wheel models (uploaded by tools/car_meshes.py) and
-- aligns them to VehicleBuilder model space using the invisible marker points in each
-- file, so it does not matter how Roblox's importer scaled, centred or rotated them.

local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

local CarMeshes = require(ServerStorage.CarMeshes)

local MeshLibrary = {}

export type Piece = { name: string, template: MeshPart, cf: CFrame, size: Vector3 }
export type Entry = { pieces: { Piece }, anchors: { [string]: number }? }

local loaded: { [string]: Entry } = {}

local function align(root: Instance, length: number, markerY: number): { Piece }?
	local front = root:FindFirstChild("MarkerFront", true) :: BasePart?
	local rear = root:FindFirstChild("MarkerRear", true) :: BasePart?
	local top = root:FindFirstChild("MarkerTop", true) :: BasePart?
	if not (front and rear and top) then
		return nil
	end
	local fp, rp, tp = front.CFrame.Position, rear.CFrame.Position, top.CFrame.Position
	local origin = (fp + rp) / 2
	local fwd = fp - rp
	local scale = fwd.Magnitude / length
	if scale <= 0 then
		return nil
	end
	fwd = fwd.Unit
	local up = tp - origin
	up = (up - fwd * up:Dot(fwd)).Unit
	local back = -fwd
	local right = up:Cross(back)
	-- imported frame -> our frame (forward = -Z, up = +Y, origin at marker height)
	local frame = CFrame.fromMatrix(origin, right, up, back)
	local pieces: { Piece } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("MeshPart") and not string.find(d.Name, "^Marker") then
			local rel = frame:ToObjectSpace(d.CFrame)
			local cf = CFrame.new(0, markerY, 0) * (CFrame.new(rel.Position / scale) * rel.Rotation)
			table.insert(pieces, { name = d.Name, template = d, cf = cf, size = d.Size / scale })
		end
	end
	return pieces
end

local function load(key: string, info: any)
	if not info.assetId or info.assetId == 0 then
		return
	end
	local ok, model = pcall(function()
		return InsertService:LoadAsset(info.assetId)
	end)
	if not ok or not model then
		warn("[MeshLibrary] could not load " .. key .. ": " .. tostring(model))
		return
	end
	local length = if key == "wheel" then 2 else (info.anchors.rearZ - info.anchors.frontZ)
	local pieces = align(model, length, info.markerY or 0)
	if not pieces or #pieces == 0 then
		warn("[MeshLibrary] markers missing in " .. key)
		return
	end
	for _, piece in pieces do
		local t = piece.template
		t.Parent = nil
		-- paint and glass are set by the builder, not by imported textures
		for _, c in t:GetChildren() do
			if c:IsA("SurfaceAppearance") then
				c:Destroy()
			end
		end
		pcall(function()
			t.TextureID = ""
		end)
	end
	loaded[key] = { pieces = pieces, anchors = info.anchors }
end

function MeshLibrary.Start()
	for key, info in CarMeshes :: any do
		task.spawn(load, key, info)
	end
end

function MeshLibrary.Body(bodyName: string): Entry?
	return loaded["body_" .. bodyName]
end

function MeshLibrary.Wheel(): Entry?
	return loaded.wheel
end

-- Anchors are available before the models finish loading (they come from the data file).
function MeshLibrary.Anchors(bodyName: string): { [string]: number }?
	local info = (CarMeshes :: any)["body_" .. bodyName]
	return if info and info.assetId ~= 0 then info.anchors else nil
end

-- Clone a piece into `parent`, placed relative to `base` (model space -> world via base).
function MeshLibrary.Place(piece: Piece, parent: Instance, base: CFrame, scale: Vector3?): MeshPart
	local p = piece.template:Clone()
	local s = scale or Vector3.one
	p.Size = piece.size * s
	local pos = piece.cf.Position * s
	p.CFrame = base * (CFrame.new(pos) * piece.cf.Rotation)
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.Parent = parent
	return p
end

-- for tests
MeshLibrary._align = align
function MeshLibrary._inject(key: string, entry: Entry)
	loaded[key] = entry
end

return MeshLibrary
