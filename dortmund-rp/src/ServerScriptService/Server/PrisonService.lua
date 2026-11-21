--!strict
-- V1.0 prison "JVA Dortmund" (Locations.Sites.Prison): wall with watch towers and a
-- gate, a cell block with 8 cells, a yard. Jailed players are kept inside.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Locations = require(ReplicatedStorage.Shared.Locations)
local CityBuilder = require(script.Parent.CityBuilder)

local PrisonService = {}

PrisonService.Cells = {} :: { CFrame }
PrisonService.Exit = nil :: CFrame?
PrisonService.Bounds = nil :: { cf: CFrame, size: Vector3 }?

local WALL = Color3.fromRGB(150, 148, 140)
local DARK = Color3.fromRGB(55, 58, 62)
local BAR = Color3.fromRGB(70, 72, 78)

local function box(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Concrete
	p.TopSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sign(p: BasePart, face: Enum.NormalId, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = Color3.fromRGB(0, 60, 110)
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	l.Font = Enum.Font.GothamBlack
	l.Text = text
	l.Parent = gui
end

local function lamp(parent: Instance, cf: CFrame)
	local p = box(parent, "Lamp", Vector3.new(4, 0.3, 4), cf, Color3.fromRGB(250, 248, 240), Enum.Material.Neon)
	p.CanCollide = false
	local l = Instance.new("PointLight")
	l.Range = 26
	l.Brightness = 0.6
	l.Parent = p
end

-- is a position inside the prison wall?
function PrisonService.Inside(pos: Vector3): boolean
	local b = PrisonService.Bounds
	if not b then
		return false
	end
	local rel = b.cf:PointToObjectSpace(pos)
	return math.abs(rel.X) < b.size.X / 2 and math.abs(rel.Z) < b.size.Z / 2 and rel.Y > -10 and rel.Y < 60
end

function PrisonService.Build()
	if not Config.V10 then
		return
	end
	local site = (Locations.Sites :: any).Prison
	if not site then
		return
	end
	local y0 = CityBuilder.GroundY(site.x, site.z) + 0.05
	local origin = CFrame.new(site.x, y0, site.z) * CFrame.Angles(0, math.rad(site.yaw), 0)
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end
	local m = Instance.new("Model")
	m.Name = "JVA Dortmund"
	local W, D, H = 220, 200, 26
	-- yard + perimeter wall with a gate in the front (-Z)
	box(m, "Yard", Vector3.new(W, 0.4, D), at(0, 0.2, 0), Color3.fromRGB(120, 118, 112), Enum.Material.Asphalt)
	box(m, "Wall", Vector3.new(W, H, 3), at(0, H / 2, D / 2), WALL)
	for _, sx in { -1, 1 } do
		box(m, "Wall", Vector3.new(3, H, D), at(sx * W / 2, H / 2, 0), WALL)
		box(m, "Wall", Vector3.new((W - 24) / 2, H, 3), at(sx * (12 + (W - 24) / 4), H / 2, -D / 2), WALL)
	end
	box(m, "Gate", Vector3.new(24, H - 4, 1.5), at(0, (H - 4) / 2, -D / 2), BAR, Enum.Material.DiamondPlate)
	box(m, "GateTop", Vector3.new(24, 4, 3), at(0, H - 2, -D / 2), WALL)
	local plate = box(m, "Sign", Vector3.new(40, 6, 0.6), at(-40, H - 5, -D / 2 - 1.8), Color3.fromRGB(0, 60, 110))
	sign(plate, Enum.NormalId.Front, "JVA DORTMUND")
	-- barbed wire + watch towers in the corners
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(m, "Tower", Vector3.new(10, H + 14, 10), at(sx * (W / 2 - 4), (H + 14) / 2, sz * (D / 2 - 4)), WALL)
			local cab = box(
				m,
				"TowerCab",
				Vector3.new(14, 8, 14),
				at(sx * (W / 2 - 4), H + 18, sz * (D / 2 - 4)),
				DARK,
				Enum.Material.Glass
			)
			cab.Transparency = 0.3
			lamp(m, at(sx * (W / 2 - 4), H + 22.4, sz * (D / 2 - 4)))
		end
	end
	for _, sx in { -1, 1 } do
		box(m, "Wire", Vector3.new(1, 1, D), at(sx * W / 2, H + 1, 0), BAR, Enum.Material.Metal)
	end
	box(m, "Wire", Vector3.new(W, 1, 1), at(0, H + 1, D / 2), BAR, Enum.Material.Metal)

	-- cell block: 8 cells along the back wall, a corridor in front of them
	local cellW, cellD, cellH = 14, 16, 12
	local blockZ = D / 2 - 30
	local n = 8
	local blockW = n * cellW
	box(m, "BlockFloor", Vector3.new(blockW + 4, 1, cellD + 14), at(0, 0.5, blockZ), Color3.fromRGB(190, 188, 180))
	box(m, "BlockRoof", Vector3.new(blockW + 4, 1.5, cellD + 14), at(0, cellH + 1.2, blockZ), DARK)
	box(m, "BlockBack", Vector3.new(blockW + 4, cellH, 1.5), at(0, cellH / 2 + 0.5, blockZ + (cellD + 14) / 2), WALL)
	for _, sx in { -1, 1 } do
		box(
			m,
			"BlockSide",
			Vector3.new(1.5, cellH, cellD + 14),
			at(sx * (blockW / 2 + 2), cellH / 2 + 0.5, blockZ),
			WALL
		)
	end
	local cellFront = blockZ + (cellD + 14) / 2 - cellD
	for i = 0, n do
		local x = -blockW / 2 + i * cellW
		box(m, "CellWall", Vector3.new(1, cellH, cellD), at(x, cellH / 2 + 0.5, cellFront + cellD / 2), WALL)
	end
	for i = 1, n do
		local cx = -blockW / 2 + (i - 0.5) * cellW
		-- bars in front of the cell
		for b = -5, 5 do
			box(
				m,
				"Bar",
				Vector3.new(0.3, cellH, 0.3),
				at(cx + b * 1.2, cellH / 2 + 0.5, cellFront),
				BAR,
				Enum.Material.Metal
			)
		end
		box(
			m,
			"Bed",
			Vector3.new(4, 1.5, 8),
			at(cx - 3.5, 1.75, cellFront + cellD - 5),
			Color3.fromRGB(110, 110, 120),
			Enum.Material.Fabric
		)
		box(
			m,
			"Toilet",
			Vector3.new(2, 2.4, 2),
			at(cx + 4.5, 1.7, cellFront + cellD - 2),
			Color3.fromRGB(235, 235, 235),
			Enum.Material.Marble
		)
		lamp(m, at(cx, cellH, cellFront + cellD / 2))
		table.insert(PrisonService.Cells, at(cx, 3.5, cellFront + cellD / 2) * CFrame.Angles(0, math.pi, 0))
	end
	-- the corridor front wall (closed: nobody walks out of the block)
	box(m, "BlockFront", Vector3.new(blockW + 4, cellH, 1.5), at(0, cellH / 2 + 0.5, blockZ - (cellD + 14) / 2), WALL)
	-- guard house at the gate (outside)
	box(m, "GuardHouse", Vector3.new(16, 10, 12), at(30, 5, -D / 2 - 10), WALL)
	PrisonService.Exit = at(0, 3.5, -D / 2 - 12) * CFrame.Angles(0, math.pi, 0)
	PrisonService.Bounds = { cf = at(0, 0, 0), size = Vector3.new(W, 60, D) }
	m.Parent = Workspace
end

function PrisonService.Start() end

return PrisonService
