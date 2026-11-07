--!strict
-- Always-visible HUD: money, level + XP bar, job, phone button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Jobs = require(ReplicatedStorage.Shared.Jobs)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Make = require(script.Parent.Make)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme

local HUD = {}

local gui = New("ScreenGui", {
	Name = "HUD",
	ResetOnSpawn = false,
	DisplayOrder = 5,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})
HUD.Gui = gui

local box = New("Frame", {
	Position = UDim2.new(0, 10, 0, 10),
	Size = UDim2.new(0, 220, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = T.bg,
	BackgroundTransparency = 0.25,
	Parent = gui,
}, { Make.Corner(12), Make.Padding(10), Make.List(4) })
box:FindFirstChildOfClass("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Left

local money = Make.Label("…", 20, Color3.fromRGB(120, 230, 140), T.black, { LayoutOrder = 1 })
money.Parent = box
local job = Make.Label("", 13, T.sub, T.bold, { LayoutOrder = 2 })
job.Parent = box
local levelLabel = Make.Label("", 13, T.text, T.bold, { LayoutOrder = 3 })
levelLabel.Parent = box
local barBack = New("Frame", {
	LayoutOrder = 4,
	Size = UDim2.new(1, 0, 0, 8),
	BackgroundColor3 = T.card,
	Parent = box,
}, { Make.Corner(4) })
local bar = New(
	"Frame",
	{ Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.accent, Parent = barBack },
	{ Make.Corner(4) }
)

-- Phone button (bottom right) – opens the phone on mobile and PC.
HUD.PhoneButton = New("TextButton", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -12),
	Size = UDim2.fromOffset(56, 56),
	BackgroundColor3 = T.bg,
	BackgroundTransparency = 0.15,
	Text = "📱",
	TextSize = 28,
	Parent = gui,
}, { Make.Corner(28), Make.Stroke(T.accent, 2) })

Make.Label("© OpenStreetMap", 10, Color3.fromRGB(200, 200, 200), T.font, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 8, 1, -4),
	Size = UDim2.fromOffset(120, 14),
	TextTransparency = 0.3,
	Parent = gui,
})

function HUD.Render(s: { [string]: any })
	money.Text = Locale.Euro(s.bank or 0)
	local jobDef = Jobs.ById[s.job or "Unemployed"]
	job.Text = Jobs.Name(s.job or "Unemployed", Store.Lang())
	job.TextColor3 = if jobDef then jobDef.color:Lerp(Color3.new(1, 1, 1), 0.35) else T.sub
	levelLabel.Text = Store.T("level", s.level or 1)
		.. string.format("  ·  %d / %d XP", s.levelXP or 0, s.levelNeed or 100)
	local pct = if (s.levelNeed or 0) > 0 then (s.levelXP or 0) / s.levelNeed else 0
	TweenService:Create(bar, TweenInfo.new(0.4), { Size = UDim2.fromScale(math.clamp(pct, 0, 1), 1) }):Play()
	local phoneAccent = s.phone == "nvdr_p1" and Color3.fromRGB(57, 255, 20) or T.accent
	local stroke = HUD.PhoneButton:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = phoneAccent
	end
end

Store.Changed:Connect(HUD.Render)
if Store.state then
	HUD.Render(Store.state)
end

return HUD
