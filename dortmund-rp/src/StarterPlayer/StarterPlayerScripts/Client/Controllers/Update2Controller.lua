--!strict
-- Update 2 (Config.Update2, testing server first), on the client:
--   * job waypoints from the server (patients -> Klinikum, taxi fares, towing)
--   * "STOP – POLIZEI" for drivers who are pulled over
--   * the police panel (👮): pull over, check, fine
--   * voice calls: incoming call (answer / decline), the call bar (hang up)
--   * the job rank under the job on the HUD

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VoiceChatService = game:GetService("VoiceChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Make = require(script.Parent.Parent.UI.Make)
local Net = require(script.Parent.Parent.Net)
local Notify = require(script.Parent.Parent.UI.Notify)
local Store = require(script.Parent.Parent.Store)
local Waypoint = require(script.Parent.Parent.UI.Waypoint)

local New, T = Make.New, Make.Theme
local me = Players.LocalPlayer

local Update2 = {}

if not Config.On(Config.Update2) then
	function Update2.Call(_numbers: { string }, _group: boolean?) end
	return Update2
end

Config.EmergencyNumbers[Config.TaxiNumber] = { "Taxi" } -- call a taxi like 110 / 112

local gui = New("ScreenGui", {
	Name = "Update2HUD",
	ResetOnSpawn = false,
	DisplayOrder = 15,
	Parent = me:WaitForChild("PlayerGui"),
})

-- waypoints from the server ---------------------------------------------------------------
Net.On("Waypoint", function(p)
	if typeof(p) == "table" and typeof(p.pos) == "Vector3" then
		Waypoint.Set(p.pos, tostring(p.title or ""), Color3.fromRGB(60, 150, 255))
	else
		Waypoint.Clear()
	end
end)

-- pulled over -----------------------------------------------------------------------------
local stopSign = Make.Label("", 26, Color3.new(1, 1, 1), T.black, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 150),
	Size = UDim2.fromOffset(460, 70),
	BackgroundTransparency = 0,
	BackgroundColor3 = Color3.fromRGB(20, 60, 160),
	TextXAlignment = Enum.TextXAlignment.Center,
	Visible = false,
	Parent = gui,
}, { Make.Corner(12), Make.Stroke(Color3.new(1, 1, 1), 3) })
Net.On("PoliceStop", function(p)
	if typeof(p) ~= "table" then
		return
	end
	stopSign.Text = Store.T("police_stop_sign", tostring(p.by))
	stopSign.Visible = true
	local blink = true
	task.spawn(function()
		for _ = 1, (tonumber(p.seconds) or 20) * 2 do
			blink = not blink
			stopSign.BackgroundColor3 = if blink then Color3.fromRGB(20, 60, 160) else Color3.fromRGB(190, 20, 20)
			task.wait(0.5)
		end
		stopSign.Visible = false
	end)
end)

-- police panel ------------------------------------------------------------------------------
local policeButton = Make.Button("👮", Color3.fromRGB(20, 60, 160), function() end, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -230),
	Size = UDim2.fromOffset(56, 56),
	TextSize = 26,
	Visible = false,
	Parent = gui,
})
local panel = New("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 76, 1, -170),
	Size = UDim2.fromOffset(330, 320),
	BackgroundColor3 = T.bg,
	Visible = false,
	Parent = gui,
}, { Make.Corner(12), Make.Stroke(Color3.fromRGB(20, 60, 160), 2) })
local list = Make.Scroll({ Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), Parent = panel })

local function req(name: string, ...: any)
	local args = { ... }
	task.spawn(function()
		local r = Net.Request(name, table.unpack(args))
		if not r.ok then
			Notify.Error(r.err)
		elseif name == "Police.Check" then
			Notify.Show(
				Store.T(
					"police_check_result",
					tostring(r.name),
					tostring(r.job),
					Store.T(if r.wanted then "police_wanted_yes" else "police_wanted_no")
				),
				r.wanted == true,
				8
			)
		elseif name == "Police.Fine" then
			Notify.Show(Store.T("police_fine_done", r.paid or 0))
		else
			Notify.Show(Store.T("done"))
		end
	end)
end

local function renderPanel()
	Make.Clear(list)
	local myRoot = me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not myRoot then
		return
	end
	local order = 0
	for _, p in Players:GetPlayers() do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if p ~= me and r and (r.Position - myRoot.Position).Magnitude <= 80 then
			order += 1
			local card = Make.Card({ LayoutOrder = order, Parent = list })
			Make.Label(
				("%s · %d m"):format(p.DisplayName, math.floor((r.Position - myRoot.Position).Magnitude * 0.28)),
				13,
				T.text,
				T.bold,
				{ Parent = card }
			)
			local id = p.UserId
			local row = New(
				"Frame",
				{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Parent = card },
				{ Make.List(4, true) }
			)
			Make.Button("🛑", T.bad, function()
				req("Police.Stop", id)
			end, { Size = UDim2.fromOffset(44, 30), Parent = row })
			Make.Button("🪪", T.panel, function()
				req("Police.Check", id)
			end, { Size = UDim2.fromOffset(44, 30), Parent = row })
			for _, a in { 30, 80, 150, 300 } do
				Make.Button(a .. "€", Color3.fromRGB(200, 120, 20), function()
					req("Police.Fine", id, a)
				end, { Size = UDim2.fromOffset(44, 30), TextSize = 11, Parent = row })
			end
		end
	end
	if order == 0 then
		Make.Label(Store.T("police_nobody_near"), 13, T.sub, T.font, { Parent = list })
	end
end
policeButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		renderPanel()
	end
end)
local function refreshJob()
	local police = me:GetAttribute("Job") == "Police"
	policeButton.Visible = police
	if not police then
		panel.Visible = false
	end
end
me:GetAttributeChangedSignal("Job"):Connect(refreshJob)
refreshJob()
task.spawn(function()
	while true do
		task.wait(2)
		if panel.Visible then
			renderPanel()
		end
	end
end)

-- rank on the HUD ------------------------------------------------------------------------------
local rankLabel = Make.Label("", 12, Color3.fromRGB(255, 210, 90), T.bold, {
	Position = UDim2.fromOffset(16, 152),
	Size = UDim2.fromOffset(300, 18),
	Parent = gui,
})
local function refreshRank()
	local r = me:GetAttribute("JobRank")
	rankLabel.Text = if typeof(r) == "string" then "⭐ " .. r else ""
end
me:GetAttributeChangedSignal("JobRank"):Connect(refreshRank)
refreshRank()

-- voice calls ------------------------------------------------------------------------------
task.spawn(function()
	local ok, enabled = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(me.UserId)
	end)
	Net.Request("Voice.Report", ok and enabled == true)
end)

local incoming = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.fromOffset(320, 110),
	BackgroundColor3 = Color3.fromRGB(20, 24, 30),
	Visible = false,
	Parent = gui,
}, { Make.Corner(16), Make.Stroke(Color3.fromRGB(0, 160, 110), 2) })
local incomingText = Make.Label("", 15, T.text, T.bold, {
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -24, 0, 44),
	TextWrapped = true,
	Parent = incoming,
})
local incomingId: string? = nil
local function answer(accept: boolean)
	local id = incomingId
	incoming.Visible = false
	incomingId = nil
	if id then
		task.spawn(function()
			local r = Net.Request("Voice.Answer", id, accept)
			if not r.ok then
				Notify.Error(r.err)
			end
		end)
	end
end
Make.Button("📞 " .. Store.T("voice_accept"), Color3.fromRGB(0, 160, 80), function()
	answer(true)
end, { Position = UDim2.new(0, 12, 1, -48), Size = UDim2.new(0.5, -18, 0, 38), Parent = incoming })
Make.Button("✕ " .. Store.T("voice_decline"), T.bad, function()
	answer(false)
end, { Position = UDim2.new(0.5, 6, 1, -48), Size = UDim2.new(0.5, -18, 0, 38), Parent = incoming })
local ring = Instance.new("Sound")
ring.SoundId = "rbxasset://sounds/electronicpingshort.wav"
ring.Volume = 0.8
ring.Parent = gui

Net.On("VoiceIncoming", function(p)
	if typeof(p) ~= "table" then
		return
	end
	incomingId = tostring(p.id)
	local contacts = Store.Get().contacts or {}
	local who = contacts[tostring(p.number)] or tostring(p.from)
	incomingText.Text = if p.group
		then Store.T("voice_incoming_group", who, tonumber(p.count) or 2)
		else Store.T("voice_incoming", who)
	incoming.Visible = true
	task.spawn(function()
		for _ = 1, 10 do
			if not incoming.Visible then
				break
			end
			ring:Play()
			task.wait(1.5)
		end
	end)
end)

local bar = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.fromOffset(360, 46),
	BackgroundColor3 = Color3.fromRGB(0, 120, 80),
	Visible = false,
	Parent = gui,
}, { Make.Corner(23) })
local barText = Make.Label("", 13, Color3.new(1, 1, 1), T.bold, {
	Position = UDim2.fromOffset(16, 0),
	Size = UDim2.new(1, -110, 1, 0),
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = bar,
})
Make.Button("📵", T.bad, function()
	task.spawn(function()
		Net.Request("Voice.HangUp")
	end)
	bar.Visible = false
end, {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -6, 0.5, 0),
	Size = UDim2.fromOffset(80, 36),
	TextSize = 18,
	Parent = bar,
})

Net.On("VoiceState", function(p)
	if typeof(p) ~= "table" then
		return
	end
	if p.state == "ended" then
		bar.Visible = false
		if incomingId == p.id then
			incoming.Visible = false
			incomingId = nil
		end
		return
	end
	local names = table.concat(p.members or {}, ", ")
	barText.Text = if p.state == "ringing" then "📞 " .. Store.T("voice_ringing") else "🎙️ " .. names
	bar.Visible = incomingId ~= p.id
end)

-- start a call (Contacts / Dialer / ChatsApp; groups only from ChatsApp)
function Update2.Call(numbers: { string }, group: boolean?)
	task.spawn(function()
		local r = Net.Request("Voice.Call", numbers, group == true)
		if not r.ok then
			Notify.Error(r.err)
		end
	end)
end

return Update2
