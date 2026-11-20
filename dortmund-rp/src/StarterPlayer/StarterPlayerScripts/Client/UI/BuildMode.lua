--!strict
-- v0.4 build mode ("Einrichten") for a house: pick furniture from your storage, a
-- see-through preview follows the mouse (PC) or the middle of the screen (touch),
-- ⟲ turns it, ✅ / click places it. 🗑 mode picks placed furniture up again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Furniture = require(ReplicatedStorage.Shared.Furniture)
local Make = require(script.Parent.Make)
local Notify = require(script.Parent.Notify)
local Net = require(script.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme
local player = Players.LocalPlayer

local BuildMode = {}

local GRID = 0.5
local ROT_STEP = 45

local gui = New("ScreenGui", {
	Name = "BuildMode",
	ResetOnSpawn = false,
	DisplayOrder = 20,
	Enabled = false,
	Parent = player:WaitForChild("PlayerGui"),
})
local bar = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.new(0.9, 0, 0, 150),
	BackgroundColor3 = T.bg,
	BackgroundTransparency = 0.1,
	Parent = gui,
}, { Make.Corner(14), New("UISizeConstraint", { MaxSize = Vector2.new(820, 150) }) })
local status = Make.Label("", 13, T.text, T.bold, {
	Position = UDim2.fromOffset(12, 6),
	Size = UDim2.new(1, -24, 0, 18),
	Parent = bar,
})
local itemsList = New("ScrollingFrame", {
	Position = UDim2.fromOffset(8, 28),
	Size = UDim2.new(1, -16, 0, 66),
	BackgroundTransparency = 1,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	ScrollingDirection = Enum.ScrollingDirection.X,
	ScrollBarThickness = 4,
	Parent = bar,
}, { Make.List(6, true) })
local buttons = New("Frame", {
	Position = UDim2.new(0, 8, 1, -50),
	Size = UDim2.new(1, -16, 0, 42),
	BackgroundTransparency = 1,
	Parent = bar,
}, { Make.List(6, true) })
-- crosshair for touch (the preview follows the middle of the screen)
local cross = Make.Label("+", 30, Color3.new(1, 1, 1), T.black, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(30, 30),
	TextXAlignment = Enum.TextXAlignment.Center,
	Visible = false,
	Parent = gui,
})

-- state
local ownerId: number? = nil
local plotCf = CFrame.new()
local half = Vector3.zero
local maxY = 40
local storage: { [string]: number } = {}
local selected: string? = nil
local rotation = 0
local removing = false
local ghost: Model? = nil
local target: { x: number, y: number, z: number, ok: boolean }? = nil
local hovered: Model? = nil
local highlight = New(
	"Highlight",
	{ FillTransparency = 0.6, OutlineColor = Color3.fromRGB(255, 80, 80), Enabled = false, Parent = gui }
)
local conn: RBXScriptConnection? = nil
local isTouch = UserInputService.TouchEnabled

local function houseModel(): Model?
	local estate = Workspace:FindFirstChild("Wohngebiet")
	local m = estate and ownerId and estate:FindFirstChild("Haus_" .. ownerId)
	return if m and m:IsA("Model") then m else nil
end

local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	target = nil
end

local function setGhost(id: string?)
	clearGhost()
	if not id then
		return
	end
	local m = Furniture.Build(id)
	if not m then
		return
	end
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			if p.Name ~= "Hitbox" then
				p.Transparency = math.max(p.Transparency, 0.45)
			end
		end
	end
	local hb = m.PrimaryPart
	if hb then
		hb.Transparency = 0.8
	end
	m.Parent = Workspace
	ghost = m
end

local renderItems: () -> ()
local renderButtons: () -> ()

renderItems = function()
	Make.Clear(itemsList)
	local any = false
	for i, it in Furniture.List do
		local n = storage[it.id] or 0
		if n > 0 then
			any = true
			local b = Make.Button(
				("%s\n%s ×%d"):format(it.name, it.kind, n),
				if selected == it.id then T.good else T.card,
				function()
					removing = false
					selected = if selected == it.id then nil else it.id
					setGhost(selected)
					renderItems()
					renderButtons()
				end,
				{ LayoutOrder = i, Size = UDim2.fromOffset(110, 62), TextSize = 11, Parent = itemsList }
			)
			b.TextWrapped = true
		end
	end
	if not any then
		Make.Label(Store.T("build_empty"), 12, T.sub, T.font, { Size = UDim2.fromOffset(400, 60), Parent = itemsList })
	end
end

local function place()
	local t = target
	if not ownerId or not selected or not t or not t.ok then
		Notify.Error("build_bad_spot")
		return
	end
	local id = selected
	task.spawn(function()
		local r = Net.Request("Build.Place", ownerId, id, t.x, t.y, t.z, rotation)
		if r.ok then
			storage = r.items or storage
			if (storage[id] or 0) <= 0 then
				selected = nil
				setGhost(nil)
			end
			status.Text = Store.T("build_status", r.placed or 0)
			renderItems()
		else
			Notify.Error(r.err)
		end
	end)
end

local function pickUp()
	local m = hovered
	if not ownerId or not m then
		return
	end
	local index, id = m:GetAttribute("Index"), m:GetAttribute("Furniture")
	task.spawn(function()
		local r = Net.Request("Build.Remove", ownerId, index, id)
		if r.ok then
			storage = r.items or storage
			status.Text = Store.T("build_status", r.placed or 0)
			renderItems()
		else
			Notify.Error(r.err)
		end
	end)
end

renderButtons = function()
	Make.Clear(buttons)
	Make.Button("⟲ " .. Store.T("build_rotate"), T.panel, function()
		rotation = (rotation + ROT_STEP) % 360
	end, { LayoutOrder = 1, Size = UDim2.fromOffset(110, 40), Parent = buttons })
	Make.Button(
		"✅ " .. Store.T("build_place"),
		T.good,
		place,
		{ LayoutOrder = 2, Size = UDim2.fromOffset(120, 40), Parent = buttons }
	)
	Make.Button("🗑 " .. Store.T("build_pickup"), if removing then T.bad else T.panel, function()
		if removing then
			pickUp()
		else
			removing = true
			selected = nil
			setGhost(nil)
			renderItems()
			renderButtons()
		end
	end, { LayoutOrder = 3, Size = UDim2.fromOffset(120, 40), Parent = buttons })
	Make.Button("✕ " .. Store.T("build_done"), T.card, function()
		BuildMode.Stop()
	end, { LayoutOrder = 4, Size = UDim2.fromOffset(100, 40), Parent = buttons })
end

local function screenRay(): (Vector3, Vector3)
	local camera = Workspace.CurrentCamera
	local pos = if isTouch then camera.ViewportSize / 2 else UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(pos.X, pos.Y)
	return ray.Origin, ray.Direction * 200
end

local function step()
	local house = houseModel()
	if not house then
		BuildMode.Stop()
		return
	end
	local origin, dir = screenRay()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	if removing then
		local f = house:FindFirstChild("Furniture")
		params.FilterDescendantsInstances = if f then { f } else {}
		local hit = Workspace:Raycast(origin, dir, params)
		local m = hit and hit.Instance:FindFirstAncestorOfClass("Model")
		hovered = if m and m:GetAttribute("Furniture") then m else nil
		highlight.Adornee = hovered
		highlight.Enabled = hovered ~= nil
		return
	end
	highlight.Enabled = false
	hovered = nil
	local g = ghost
	if not g or not selected then
		return
	end
	-- floors, lawn, other furniture (stack on tables) – not the preview itself
	params.FilterDescendantsInstances = { house }
	local hit = Workspace:Raycast(origin, dir, params)
	if not hit then
		target = nil
		return
	end
	local rel = plotCf:PointToObjectSpace(hit.Position)
	local x = math.floor(rel.X / GRID + 0.5) * GRID
	local z = math.floor(rel.Z / GRID + 0.5) * GRID
	local y = math.floor(rel.Y * 10 + 0.5) / 10
	local ok = Furniture.Fits(selected, x, y, z, rotation, half, maxY)
	target = { x = x, y = y, z = z, ok = ok }
	g:PivotTo(plotCf * CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(rotation), 0))
	local hb = g.PrimaryPart
	if hb then
		hb.Color = if ok then Color3.fromRGB(60, 220, 90) else Color3.fromRGB(230, 60, 60)
	end
end

function BuildMode.Start(houseOwner: number)
	local r = Net.Request("Build.Begin", houseOwner)
	if not r.ok then
		Notify.Error(r.err)
		return
	end
	ownerId = houseOwner
	plotCf = r.plot
	half = r.half
	maxY = r.maxY
	storage = r.items or {}
	selected, removing, rotation = nil, false, 0
	status.Text = Store.T("build_status", r.placed or 0)
	renderItems()
	renderButtons()
	cross.Visible = isTouch
	gui.Enabled = true
	if conn then
		conn:Disconnect()
	end
	conn = RunService.RenderStepped:Connect(step)
end

function BuildMode.Stop()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	clearGhost()
	highlight.Enabled = false
	ownerId = nil
	gui.Enabled = false
end

function BuildMode.IsActive(): boolean
	return ownerId ~= nil
end

-- PC: click places / picks up, R turns
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not ownerId then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if removing then
			pickUp()
		elseif selected then
			place()
		end
	elseif input.KeyCode == Enum.KeyCode.R then
		rotation = (rotation + ROT_STEP) % 360
	end
end)

return BuildMode
