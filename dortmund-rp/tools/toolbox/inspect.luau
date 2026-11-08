-- lune run tools/toolbox/inspect.luau <file.rbxm> ...
-- Prints what a model contains: size, part counts, scripts, decals/textures, seats.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

for _, path in process.args do
	local ok, insts = pcall(roblox.deserializeModel, fs.readFile(path))
	if not ok then
		print(path, "could not read:", insts)
		continue
	end
	local counts, scripts, images = {}, {}, {}
	local minV, maxV = nil, nil
	local seats = 0
	local function visit(inst)
		counts[inst.ClassName] = (counts[inst.ClassName] or 0) + 1
		if inst:IsA("LuaSourceContainer") then
			local src = inst.Source or ""
			local flags = {}
			for _, pat in { "require%s*%(", "getfenv", "loadstring", "HttpService", "MarketplaceService", "TeleportService", "Players:Kick" } do
				if string.find(src, pat) then
					table.insert(flags, pat)
				end
			end
			table.insert(scripts, inst.ClassName .. " " .. inst:GetFullName() .. " (" .. #src .. " chars" .. (if #flags > 0 then ", ⚠ " .. table.concat(flags, " ") else "") .. ")")
		end
		if inst:IsA("Decal") or inst:IsA("Texture") then
			table.insert(images, inst.ClassName .. " " .. inst.Name .. " on " .. (inst.Parent and inst.Parent.Name or "?"))
		end
		if inst:IsA("SurfaceAppearance") then
			table.insert(images, "SurfaceAppearance on " .. (inst.Parent and inst.Parent.Name or "?"))
		end
		local lname = string.lower(inst.Name)
		for _, w in { "logo", "badge", "emblem", "brand", "sign", "letter" } do
			if string.find(lname, w) then
				table.insert(images, "PART " .. inst.ClassName .. " " .. inst:GetFullName())
				break
			end
		end
		local okT, tex = pcall(function() return inst.TextureID end)
		if inst:IsA("MeshPart") and okT and tex ~= "" then
			counts.TexturedMesh = (counts.TexturedMesh or 0) + 1
		end
		if inst:IsA("Seat") or inst:IsA("VehicleSeat") then
			seats += 1
		end
		if inst:IsA("BasePart") then
			local cf, s = inst.CFrame, inst.Size
			for _, dx in { -1, 1 } do
				for _, dy in { -1, 1 } do
					for _, dz in { -1, 1 } do
						local p = cf * roblox.Vector3.new(dx * s.X / 2, dy * s.Y / 2, dz * s.Z / 2)
						minV = if minV then roblox.Vector3.new(math.min(minV.X, p.X), math.min(minV.Y, p.Y), math.min(minV.Z, p.Z)) else p
						maxV = if maxV then roblox.Vector3.new(math.max(maxV.X, p.X), math.max(maxV.Y, p.Y), math.max(maxV.Z, p.Z)) else p
					end
				end
			end
		end
		for _, c in inst:GetChildren() do
			visit(c)
		end
	end
	for _, i in insts do
		visit(i)
	end
	local size = if minV and maxV then maxV - minV else roblox.Vector3.zero
	local parts = (counts.Part or 0) + (counts.MeshPart or 0) + (counts.UnionOperation or 0) + (counts.WedgePart or 0)
	print(string.format("== %s  size %.1f x %.1f x %.1f studs  parts %d (MeshPart %d, textured %d, Union %d)  seats %d", path, size.X, size.Y, size.Z, parts, counts.MeshPart or 0, counts.TexturedMesh or 0, counts.UnionOperation or 0, seats))
	print("   scripts: " .. #scripts .. (if #scripts > 0 then "\n     " .. table.concat(scripts, "\n     ", 1, math.min(#scripts, 8)) else ""))
	print("   images: " .. #images .. (if #images > 0 then "\n     " .. table.concat(images, "\n     ", 1, math.min(#images, 10)) else ""))
end
