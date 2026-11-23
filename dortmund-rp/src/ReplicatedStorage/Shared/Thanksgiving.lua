--!strict
-- Thanksgiving event (an AA dropper event, DropEvents id "thanksgiving"):
--   * dropper multiplier 10x with a 0.05 % chance per drop
--   * while it runs: every 2 minutes 1–10 live turkeys on the server, on random streets
--     and in parks (uncollected ones walk off when the next ones come); collect them
--     (they're a normal carried item, so they also fit in a car trunk)
--   * put a live turkey in an oven (Swedea furniture): it comes out as a golden roast
--     (no gore, it simply turns into a baked one) plus a random item, XP or cash

local Thanksgiving = {}

Thanksgiving.EVENT = "thanksgiving"
Thanksgiving.ALIVE = "turkey" -- Items id
Thanksgiving.BAKED = "turkey_baked" -- Items id
Thanksgiving.OVEN = "oven" -- Furniture id

Thanksgiving.SPAWN_EVERY = 120 -- seconds
Thanksgiving.SPAWN_MIN, Thanksgiving.SPAWN_MAX = 1, 10
Thanksgiving.LIFETIME = 10 * 60 -- safety: an uncollected turkey walks off after this
Thanksgiving.BAKE_SECONDS = 6

-- the bonus for baking: one of these, picked at random
Thanksgiving.XP = { 50, 1500 }
Thanksgiving.CASH = { 250, 7500 }

-- Models (pivot = bottom centre, front = -Z, `scale` 1 = about 3 studs long). All parts
-- anchored; `Body` is the main part. Live: feathers, head, tail fan. Baked: a golden
-- roast with drumsticks on a plate. Cartoon look, nothing gory.
local function part(
	m: Model,
	name: string,
	size: Vector3,
	pos: Vector3,
	color: Color3,
	shape: Enum.PartType?,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new(pos)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = m
	return p
end

function Thanksgiving.BuildTurkey(baked: boolean, scale: number?): Model
	local k = scale or 1
	local v = function(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y, z) * k
	end
	local m = Instance.new("Model")
	m.Name = if baked then "BakedTurkey" else "Turkey"
	local BALL = Enum.PartType.Ball
	if baked then
		local plate =
			part(m, "Plate", v(2.8, 0.15, 2.8), v(0, 0.075, 0), Color3.fromRGB(245, 245, 240), Enum.PartType.Cylinder)
		plate.CFrame = CFrame.new(v(0, 0.075, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		plate.Size = v(0.15, 2.8, 2.8)
		local body = part(m, "Body", v(1.9, 1.2, 2.2), v(0, 0.75, 0), Color3.fromRGB(200, 120, 40), BALL)
		m.PrimaryPart = body
		part(m, "Glaze", v(1.5, 0.5, 1.7), v(0, 1.2, 0), Color3.fromRGB(225, 150, 60), BALL, Enum.Material.Glass)
		for _, sx in { -1, 1 } do
			part(m, "Drumstick", v(0.5, 0.5, 0.9), v(sx * 0.7, 0.75, 0.9), Color3.fromRGB(185, 105, 35), BALL)
			part(m, "Bone", v(0.18, 0.18, 0.45), v(sx * 0.75, 0.8, 1.35), Color3.fromRGB(250, 245, 230))
		end
		for _, x in { -1.1, 1.1 } do
			part(m, "Herb", v(0.3, 0.2, 0.3), v(x, 0.25, -0.9), Color3.fromRGB(70, 150, 60), BALL)
		end
	else
		local brown = Color3.fromRGB(110, 70, 40)
		local body = part(m, "Body", v(1.6, 1.5, 2), v(0, 1.35, 0), brown, BALL)
		m.PrimaryPart = body
		part(m, "Neck", v(0.35, 0.9, 0.35), v(0, 2.1, -0.75), Color3.fromRGB(150, 110, 90))
		part(m, "Head", v(0.5, 0.5, 0.5), v(0, 2.6, -0.85), Color3.fromRGB(170, 140, 120), BALL)
		part(m, "Beak", v(0.15, 0.15, 0.3), v(0, 2.6, -1.15), Color3.fromRGB(240, 180, 40))
		part(m, "Wattle", v(0.15, 0.35, 0.15), v(0, 2.35, -1.05), Color3.fromRGB(200, 40, 40))
		for _, sx in { -1, 1 } do
			part(m, "Eye", v(0.08, 0.08, 0.08), v(sx * 0.18, 2.7, -1.05), Color3.new(0, 0, 0), BALL)
			part(m, "Leg", v(0.15, 0.7, 0.15), v(sx * 0.35, 0.35, 0), Color3.fromRGB(230, 150, 40))
		end
		-- tail fan
		local fan = { Color3.fromRGB(150, 70, 20), Color3.fromRGB(220, 130, 40), Color3.fromRGB(180, 40, 30) }
		for i = -3, 3 do
			local f = part(m, "Feather", v(0.5, 1.9, 0.12), Vector3.zero, fan[(i % 3) + 1])
			f.CFrame = CFrame.new(v(0, 1.6, 0.95)) * CFrame.Angles(-0.25, 0, i * 0.32) * CFrame.new(v(0, 0.9, 0))
		end
	end
	return m
end

return Thanksgiving
