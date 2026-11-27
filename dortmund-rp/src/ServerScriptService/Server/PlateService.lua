--!strict
-- "Kennzeichen-Service" at the ADMC station: the only place where plates can be
-- changed (choosing the first plate works anywhere, see PlatePrompt).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Locations = require(ReplicatedStorage.Shared.Locations)
local CityBuilder = require(script.Parent.CityBuilder)
local Interaction = require(script.Parent.InteractionService)
local StoreBuilder = require(script.Parent.StoreBuilder)

local PlateService = {}

local DARK = Color3.fromRGB(40, 40, 44)
local ADMC_YELLOW = Color3.fromRGB(250, 205, 0)

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
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

function PlateService.Build()
	local site = (Locations.Sites :: any).ADMC
	if not site then
		return
	end
	local gy = CityBuilder.GroundY(site.x, site.z)
	-- front-right corner, just outside the station plot
	local base = CFrame.new(site.x, gy, site.z)
		* CFrame.Angles(0, math.rad(site.yaw), 0)
		* CFrame.new(site.width / 2 + 10, 0, -site.depth / 2 + 8)
	local m = Instance.new("Model")
	m.Name = "Kennzeichen-Service"
	box(
		m,
		"Floor",
		Vector3.new(14, 0.4, 10),
		base * CFrame.new(0, 0.2, 0),
		Color3.fromRGB(200, 200, 200),
		Enum.Material.Concrete
	)
	box(m, "Back", Vector3.new(14, 9, 0.6), base * CFrame.new(0, 4.5, 5), ADMC_YELLOW)
	for _, sx in { -1, 1 } do
		box(m, "Side", Vector3.new(0.6, 9, 10), base * CFrame.new(sx * 7, 4.5, 0), ADMC_YELLOW)
	end
	box(m, "Roof", Vector3.new(15, 0.6, 11), base * CFrame.new(0, 9.3, 0), DARK)
	box(m, "Counter", Vector3.new(10, 3.4, 2), base * CFrame.new(0, 1.7, 0), DARK)
	local signPart = box(m, "Sign", Vector3.new(13, 2.4, 0.4), base * CFrame.new(0, 10.8, -5), DARK)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = signPart
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.TextScaled = true
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = ADMC_YELLOW
	l.Text = "🔢 KENNZEICHEN-SERVICE"
	l.Parent = gui
	pcall(
		StoreBuilder.Npc,
		m,
		"ADMC Kennzeichen",
		base * CFrame.new(0, 0.4, 2.5) * CFrame.Angles(0, math.pi, 0),
		ADMC_YELLOW
	)
	local marker = box(m, "Marker_Plates", Vector3.new(2, 2, 2), base * CFrame.new(0, 2.5, -2), Color3.new(1, 1, 1))
	marker.Transparency = 1
	marker.CanCollide = false
	Interaction.Mark(marker, "Shop", { UI = "Plates", ActionText = "Kennzeichen ändern", ObjectText = "ADMC" })
	m.Parent = Workspace
	PlateService.Position = base.Position

	-- the paint shop right next to it (Config.AdmcPaint: repaint your cars only here)
	if Config.On(Config.AdmcPaint) then
		local pb = base * CFrame.new(18, 0, 0)
		local p = Instance.new("Model")
		p.Name = "Lackiererei"
		box(
			p,
			"Floor",
			Vector3.new(14, 0.4, 10),
			pb * CFrame.new(0, 0.2, 0),
			Color3.fromRGB(200, 200, 200),
			Enum.Material.Concrete
		)
		box(p, "Back", Vector3.new(14, 9, 0.6), pb * CFrame.new(0, 4.5, 5), ADMC_YELLOW)
		for _, sx in { -1, 1 } do
			box(p, "Side", Vector3.new(0.6, 9, 10), pb * CFrame.new(sx * 7, 4.5, 0), ADMC_YELLOW)
		end
		box(p, "Roof", Vector3.new(15, 0.6, 11), pb * CFrame.new(0, 9.3, 0), DARK)
		-- spray booth look: colour buckets and a spray gun on the counter
		box(p, "Counter", Vector3.new(10, 3.4, 2), pb * CFrame.new(0, 1.7, 0), DARK)
		for k, c in
			{
				Color3.fromRGB(220, 40, 40),
				Color3.fromRGB(40, 110, 220),
				Color3.fromRGB(40, 170, 80),
				Color3.fromRGB(250, 200, 30),
			}
		do
			local bucket = box(
				p,
				"PaintBucket",
				Vector3.new(1.2, 1, 1),
				pb * CFrame.new(-4 + k * 1.6, 4, 0) * CFrame.Angles(0, 0, math.pi / 2),
				c,
				Enum.Material.SmoothPlastic
			)
			bucket.Shape = Enum.PartType.Cylinder
		end
		local sp = box(p, "Sign", Vector3.new(13, 2.4, 0.4), pb * CFrame.new(0, 10.8, -5), DARK)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 30
		sg.Parent = sp
		local sl = Instance.new("TextLabel")
		sl.Size = UDim2.fromScale(1, 1)
		sl.BackgroundTransparency = 1
		sl.TextScaled = true
		sl.Font = Enum.Font.GothamBlack
		sl.TextColor3 = ADMC_YELLOW
		sl.Text = "🎨 LACKIEREREI"
		sl.Parent = sg
		pcall(
			StoreBuilder.Npc,
			p,
			"ADMC Lackierer",
			pb * CFrame.new(0, 0.4, 2.5) * CFrame.Angles(0, math.pi, 0),
			ADMC_YELLOW
		)
		local pm = box(p, "Marker_Paint", Vector3.new(2, 2, 2), pb * CFrame.new(0, 2.5, -2), Color3.new(1, 1, 1))
		pm.Transparency = 1
		pm.CanCollide = false
		Interaction.Mark(pm, "Shop", { UI = "Paint", ActionText = "Auto lackieren", ObjectText = "ADMC" })
		p.Parent = Workspace
		PlateService.PaintPosition = pb.Position
	end
end
PlateService.PaintPosition = nil :: Vector3?

PlateService.Position = nil :: Vector3?

return PlateService
