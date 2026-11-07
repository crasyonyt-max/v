--!strict
-- Toast notifications + big announcement banner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Jobs = require(ReplicatedStorage.Shared.Jobs)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Make = require(script.Parent.Make)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme

local Notify = {}

local gui = New("ScreenGui", {
	Name = "Notifications",
	ResetOnSpawn = false,
	DisplayOrder = 50,
	IgnoreGuiInset = false,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})

local stack = New("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.new(0.9, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Parent = gui,
}, { Make.List(6) })
New("UISizeConstraint", { MaxSize = Vector2.new(420, math.huge), Parent = stack })

function Notify.Show(text: string, isError: boolean?, duration: number?)
	local toast = New("TextLabel", {
		BackgroundColor3 = if isError then Color3.fromRGB(120, 30, 30) else T.panel,
		BackgroundTransparency = 0.05,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		TextWrapped = true,
		TextSize = 15,
		Font = T.bold,
		TextColor3 = T.text,
		Parent = stack,
	}, { Make.Corner(10), Make.Padding(10), Make.Stroke(if isError then T.bad else T.accent, 1, 0.4) })
	task.delay(duration or 4, function()
		local tween =
			TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1, TextTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		toast:Destroy()
	end)
end

-- Server sends { key, args, error }. Money args are formatted as €.
local EURO_ARGS: { [string]: { number } } = {
	paycheck = { 1 },
	transfer_in = { 1 },
	refueled = { 2 },
}

function Notify.Key(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.key) ~= "string" then
		return
	end
	local args = if typeof(payload.args) == "table" then table.clone(payload.args) else {}
	for _, i in EURO_ARGS[payload.key] or {} do
		if typeof(args[i]) == "number" then
			args[i] = Locale.Euro(args[i])
		end
	end
	if payload.key == "job_changed" and typeof(args[1]) == "string" then
		args[1] = Jobs.Name(args[1], Store.Lang())
	end
	Notify.Show(Store.T(payload.key, table.unpack(args)), payload.error == true)
end

function Notify.Error(err: string?)
	Notify.Show(Store.T(err or "error"), true)
end

function Notify.Announce(text: string, from: string?)
	local banner = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -120),
		Size = UDim2.new(0.9, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(15, 15, 18),
		Parent = gui,
	}, {
		Make.Corner(12),
		Make.Padding(14),
		Make.Stroke(Color3.fromRGB(250, 200, 0), 2),
		Make.List(4),
		New("UISizeConstraint", { MaxSize = Vector2.new(600, math.huge) }),
		Make.Label(
			Store.T("announce") .. (if from then " – " .. from else ""),
			14,
			Color3.fromRGB(250, 200, 0),
			T.bold
		),
		Make.Label(text, 18, T.text, T.bold),
	})
	TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 70) })
		:Play()
	task.delay(8, function()
		local tween = TweenService:Create(banner, TweenInfo.new(0.4), { Position = UDim2.new(0.5, 0, 0, -200) })
		tween:Play()
		tween.Completed:Wait()
		banner:Destroy()
	end)
end

return Notify
