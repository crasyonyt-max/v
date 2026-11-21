--!strict
-- V1.0 crime HUD:
--   * "🚨 GESUCHT 4:12" while you are a criminal, "🔒 GEFÄNGNIS 1:23" in prison
--   * robbery progress bar
--   * Police: alerts with a Navi point, a red "GESUCHT" sign over criminals and a
--     "Festnehmen" prompt next to them (only on police screens)
--   * the "Ausrauben" prompt is hidden for emergency jobs

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Make = require(script.Parent.Parent.UI.Make)
local Net = require(script.Parent.Parent.Net)
local Notify = require(script.Parent.Parent.UI.Notify)
local Store = require(script.Parent.Parent.Store)
local Waypoint = require(script.Parent.Parent.UI.Waypoint)

local New, T = Make.New, Make.Theme
local me = Players.LocalPlayer

if not Config.V10 then
	return {}
end

local EMERGENCY = { Police = true, Fire = true, Rettungsdienst = true, Notarzt = true }

local gui = New("ScreenGui", {
	Name = "CrimeHUD",
	ResetOnSpawn = false,
	DisplayOrder = 12,
	Parent = me:WaitForChild("PlayerGui"),
})
local banner = New("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 120),
	Size = UDim2.fromOffset(300, 44),
	BackgroundColor3 = Color3.fromRGB(190, 20, 20),
	TextColor3 = Color3.new(1, 1, 1),
	Font = T.black,
	TextSize = 22,
	Visible = false,
	Parent = gui,
}, { Make.Corner(12), Make.Stroke(Color3.fromRGB(255, 220, 0), 2) })
local robFrame = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 172),
	Size = UDim2.fromOffset(300, 34),
	BackgroundColor3 = T.bg,
	Visible = false,
	Parent = gui,
}, { Make.Corner(10) })
local robFill = New("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.fromRGB(240, 180, 20),
	Parent = robFrame,
}, { Make.Corner(10) })
local robText = Make.Label("", 14, Color3.new(1, 1, 1), T.bold, {
	Size = UDim2.fromScale(1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = robFrame,
})
local robEnd = 0
local robTotal = 1

local function mmss(s: number): string
	s = math.max(0, math.floor(s))
	return ("%d:%02d"):format(s // 60, s % 60)
end

Net.On("Robbery", function(p)
	if typeof(p) ~= "table" then
		return
	end
	if (p.seconds or 0) <= 0 then
		robFrame.Visible = false
		robEnd = 0
		return
	end
	robTotal = p.seconds
	robEnd = os.clock() + p.seconds
	robText.Text = "💰 " .. tostring(p.store)
	robFrame.Visible = true
end)

Net.On("CrimeAlert", function(p)
	if typeof(p) ~= "table" then
		return
	end
	Notify.Show(tostring(p.text), true, 6)
	if typeof(p.pos) == "Vector3" then
		Waypoint.Set(p.pos, tostring(p.text), Color3.fromRGB(220, 30, 30))
	end
end)

Net.On("Hit", function(p)
	-- a short red flash when you are hit
	local flash = New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(200, 0, 0),
		BackgroundTransparency = 0.6,
		Parent = gui,
	})
	task.delay(0.15, function()
		flash:Destroy()
	end)
end)

-- police screens: sign + arrest prompt on criminals --------------------------------------
local marks: { [Player]: { sign: BillboardGui, prompt: ProximityPrompt } } = {}

local function isPolice(): boolean
	return me:GetAttribute("Job") == "Police"
end

local function unmark(p: Player)
	local m = marks[p]
	if m then
		m.sign:Destroy()
		m.prompt:Destroy()
		marks[p] = nil
	end
end

local function mark(p: Player)
	if marks[p] then
		return
	end
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local sign = New("BillboardGui", {
		Name = "WantedSign",
		Size = UDim2.fromOffset(120, 30),
		StudsOffset = Vector3.new(0, 4.2, 0),
		AlwaysOnTop = true,
		MaxDistance = 400,
		Adornee = root,
		Parent = gui,
	})
	Make.Label("🚨 GESUCHT", 16, Color3.new(1, 1, 1), T.black, {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(190, 20, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = sign,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Arrest"
	prompt.ActionText = "Festnehmen"
	prompt.ObjectText = p.DisplayName
	prompt.HoldDuration = 1
	prompt.KeyboardKeyCode = Enum.KeyCode.T
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function()
		local r = Net.Request("Crime.Arrest", p.UserId)
		if not r.ok then
			Notify.Error(r.err)
		end
	end)
	marks[p] = { sign = sign, prompt = prompt }
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	-- robbery bar
	if robEnd > 0 then
		local left = robEnd - os.clock()
		robFill.Size = UDim2.fromScale(math.clamp(1 - left / robTotal, 0, 1), 1)
	end
	acc += dt
	if acc < 0.25 then
		return
	end
	acc = 0
	local now = Workspace:GetServerTimeNow()
	-- my own status
	local jail = me:GetAttribute("JailedUntil")
	local crim = me:GetAttribute("CriminalUntil")
	if typeof(jail) == "number" and jail > now then
		banner.Visible = true
		banner.BackgroundColor3 = Color3.fromRGB(30, 60, 120)
		banner.Text = "🔒 " .. Store.T("crime_prison") .. " " .. mmss(jail - now)
	elseif typeof(crim) == "number" and crim > now then
		banner.Visible = true
		banner.BackgroundColor3 = Color3.fromRGB(190, 20, 20)
		banner.Text = "🚨 " .. Store.T("crime_wanted_hud") .. " " .. mmss(crim - now)
	else
		banner.Visible = false
	end
	-- police: mark criminals
	local police = isPolice()
	for _, p in Players:GetPlayers() do
		local until_ = p:GetAttribute("CriminalUntil")
		local wanted = p ~= me and police and typeof(until_) == "number" and until_ > now
		if wanted then
			mark(p)
		else
			unmark(p)
		end
	end
	-- emergency jobs don't see "Ausrauben"
	local canRob = not EMERGENCY[tostring(me:GetAttribute("Job"))]
	for _, marker in CollectionService:GetTagged("Interaction") do
		local rob = marker:FindFirstChild("Rob")
		if rob and rob:IsA("ProximityPrompt") then
			rob.Enabled = canRob
		end
	end
end)
Players.PlayerRemoving:Connect(unmark)

return {}
