-- lune run tools/toolbox/prepare.luau <in.rbxm> <meta.json> <out.rbxm>
-- Cleans a Creator Store car for the game: only visible body parts, moved into the car's
-- local frame (ground centre, forward -Z), no scripts / decals / welds / constraints /
-- sounds / lights / GUIs / seats, emblem parts removed, wheel parts tagged FL/FR/RL/RR.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance, CFrame, Vector3 = roblox.Instance, roblox.CFrame, roblox.Vector3

local insts = roblox.deserializeModel(fs.readFile(process.args[1]))
local meta = serde.decode("json", fs.readFile(process.args[2]))
local f = meta.frame
local frame = CFrame.fromMatrix(
	Vector3.new(f.origin[1], f.origin[2], f.origin[3]),
	Vector3.new(f.right[1], f.right[2], f.right[3]),
	Vector3.new(f.up[1], f.up[2], f.up[3]),
	Vector3.new(f.back[1], f.back[2], f.back[3])
)
local inv = frame:Inverse()

local KEEP_CHILD = { SurfaceAppearance = true, SpecialMesh = true, Texture = true }
local BADGE_WORDS = { "badge", "logo", "emblem", "brand", "lettering" }

local function tagOf(path: string): string?
	local lower = string.lower(string.gsub(path, "_", "."))
	for _, t in { "fl", "fr", "rl", "rr" } do
		if string.find("." .. lower .. ".", "%." .. t .. "%.") then
			return string.upper(t)
		end
	end
	return nil
end

local car = Instance.new("Model")
car.Name = "Car"
local kept, dropped = 0, 0
local function visit(i)
	if i:IsA("BasePart") then
		local okT, tr = pcall(function()
			return i.Transparency
		end)
		local transparency = if okT then tr else 0
		local lname = string.lower(i.Name)
		local isBadge = false
		for _, w in BADGE_WORDS do
			if string.find(lname, w) then
				isBadge = true
			end
		end
		if transparency < 0.95 and not isBadge and not i:IsA("Seat") and not i:IsA("VehicleSeat") then
			local c = i:Clone()
			for _, d in c:GetChildren() do
				if not KEEP_CHILD[d.ClassName] then
					d:Destroy()
				end
			end
			c.CFrame = inv * i.CFrame
			c.Anchored = true
			c.CanCollide = false
			c.Massless = true
			local path = i:GetFullName()
			local lpath = string.lower(path)
			if string.find(lpath, "wheel") or string.find(lpath, "tire") or string.find(lpath, "rim") then
				local tag = tagOf(path)
				if tag then
					c:SetAttribute("Wheel", tag)
				end
			end
			c.Parent = car
			kept += 1
		else
			dropped += 1
		end
	end
	for _, ch in i:GetChildren() do
		visit(ch)
	end
end
for _, i in insts do
	visit(i)
end
-- paint = the most common colour among large, opaque, non-wheel parts (by surface area)
local buckets: { [string]: { area: number, color: any } } = {}
local function key(c)
	return string.format("%d,%d,%d", math.floor(c.R * 255 / 12), math.floor(c.G * 255 / 12), math.floor(c.B * 255 / 12))
end
for _, p in car:GetChildren() do
	if p:IsA("BasePart") and not p:GetAttribute("Wheel") then
		local okT, tr = pcall(function()
			return p.Transparency
		end)
		local c = p.Color
		local bright = math.max(c.R, c.G, c.B)
		local sat = bright - math.min(c.R, c.G, c.B)
		-- skip glass and near-black trim (but allow black / dark paint if it dominates)
		if (not okT or tr < 0.2) and (bright > 0.12 or sat > 0.05) then
			local s = p.Size
			local area = s.X * s.Y + s.Y * s.Z + s.X * s.Z
			local k = key(c)
			buckets[k] = buckets[k] or { area = 0, color = c }
			buckets[k].area += area
		end
	end
end
local best, bestArea = nil, 0
for k, b in buckets do
	if b.area > bestArea then
		best, bestArea = k, b.area
	end
end
local painted = 0
for _, p in car:GetChildren() do
	if p:IsA("BasePart") and not p:GetAttribute("Wheel") and key(p.Color) == best then
		p:SetAttribute("Paint", true)
		painted += 1
	end
end
print("paint parts", painted)
fs.writeFile(process.args[3], roblox.serializeModel({ car }))
print(string.format("%s: kept %d parts, dropped %d", process.args[3], kept, dropped))
