-- lune run tools/toolbox/export.luau <model.rbxm> <out.json>
-- Dumps every visible part (world CFrame, size, colour, mesh id) for the renderer.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local insts = roblox.deserializeModel(fs.readFile(process.args[1]))
local out = {}
local function prop(i, name)
	local ok, v = pcall(function()
		return (i :: any)[name]
	end)
	return if ok then v else nil
end
local function contentId(v): string?
	if v == nil then
		return nil
	end
	local s = tostring(v)
	return string.match(s, "(%d+)")
end
local function visit(i)
	if i:IsA("BasePart") then
		local cf = i.CFrame
		local entry = {
			name = i.Name,
			path = i:GetFullName(),
			class = i.ClassName,
			cf = { cf:GetComponents() },
			size = { i.Size.X, i.Size.Y, i.Size.Z },
			color = { i.Color.R, i.Color.G, i.Color.B },
			transparency = prop(i, "Transparency") or 0,
		}
		if i:IsA("MeshPart") then
			entry.mesh = contentId(prop(i, "MeshContent")) or contentId(prop(i, "MeshId"))
			local init = prop(i, "InitialSize")
			if init then
				entry.initial = { init.X, init.Y, init.Z }
			end
		elseif i:IsA("Part") then
			entry.shape = tostring(prop(i, "Shape"))
		end
		for _, c in i:GetChildren() do
			if c:IsA("SpecialMesh") then
				entry.special = tostring(prop(c, "MeshType"))
				entry.mesh = contentId(prop(c, "MeshContent")) or contentId(prop(c, "MeshId"))
				local sc = prop(c, "Scale")
				entry.scale = if sc then { sc.X, sc.Y, sc.Z } else { 1, 1, 1 }
			end
		end
		table.insert(out, entry)
	end
	for _, c in i:GetChildren() do
		visit(c)
	end
end
for _, i in insts do
	visit(i)
end
fs.writeFile(process.args[2], serde.encode("json", out))
print(#out, "parts")
