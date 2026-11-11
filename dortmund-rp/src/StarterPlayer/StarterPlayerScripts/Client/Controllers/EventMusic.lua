--!strict
-- Plays the AA music (set by the Owner / Co-Owner, the same on every server).
-- Everyone is in sync: the song starts where it is "now", also for late joiners.
-- A small 🔊 button lets each player mute it for themselves.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Make = require(script.Parent.Parent.UI.Make)
local Net = require(script.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Store)

local New, T = Make.New, Make.Theme

local EventMusic = {}

local sound = New("Sound", { Name = "EventMusic", Parent = SoundService })
local playingKey = ""
local blockedKey = "" -- this song could not be loaded: keep showing the warning
local muted = false
local current: { [string]: any }? = nil

local gui = New("ScreenGui", {
	Name = "EventMusic",
	ResetOnSpawn = false,
	DisplayOrder = 5,
	Enabled = false,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})
local bar = New("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 8, 1, -24),
	Size = UDim2.fromOffset(230, 34),
	BackgroundColor3 = T.bg,
	BackgroundTransparency = 0.2,
	Parent = gui,
}, { Make.Corner(10) })
local title = Make.Label("", 12, T.text, T.bold, {
	Position = UDim2.fromOffset(40, 0),
	Size = UDim2.new(1, -46, 1, 0),
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextWrapped = false,
	Parent = bar,
})
local muteButton = Make.Button("🔊", T.card, function() end, {
	Position = UDim2.fromOffset(4, 4),
	Size = UDim2.fromOffset(30, 26),
	TextSize = 14,
	Parent = bar,
})

-- the touch steering buttons sit bottom-left while driving
local function place()
	local up = Players.LocalPlayer:GetAttribute("DrivingTouch") == true
	bar.Position = if up then UDim2.new(0, 8, 1, -132) else UDim2.new(0, 8, 1, -24)
end
Players.LocalPlayer:GetAttributeChangedSignal("DrivingTouch"):Connect(place)

local function applyVolume()
	local vol = if current then math.clamp(tonumber(current.vol) or 0.5, 0, 1) else 0.5
	sound.Volume = if muted then 0 else vol * 2 -- Sound volume goes to 10; 0..1 from the admin = 0..2 here
	muteButton.Text = if muted then "🔇" else "🔊"
end

muteButton.Activated:Connect(function()
	muted = not muted
	applyVolume()
end)

local function play(m: { [string]: any }?)
	current = m
	if not m then
		playingKey = ""
		sound:Stop()
		gui.Enabled = false
		return
	end
	local key = tostring(m.id) .. "@" .. tostring(m.started)
	if key ~= blockedKey then
		title.Text = "🎵 " .. tostring(m.name)
	end
	gui.Enabled = true
	applyVolume()
	if key == playingKey then
		sound.Looped = m.loop == true
		return
	end
	playingKey = key
	sound:Stop()
	sound.SoundId = "rbxassetid://" .. tostring(m.id)
	sound.Looped = m.loop == true
	task.spawn(function()
		-- load it and find out if Roblox lets this game use the audio
		local status: Enum.AssetFetchStatus? = nil
		pcall(function()
			ContentProvider:PreloadAsync({ sound }, function(_, fetchStatus)
				status = fetchStatus
			end)
		end)
		if playingKey ~= key then
			return
		end
		if status ~= nil and status ~= Enum.AssetFetchStatus.Success then
			blockedKey = key
			title.Text = "⚠️ " .. Store.T("music_blocked") .. " (" .. tostring(m.id) .. ")"
			warn("[Music] audio " .. tostring(m.id) .. " could not be loaded: " .. tostring(status))
			return
		end
		local waited = 0
		while not sound.IsLoaded and waited < 10 do
			waited += task.wait(0.25)
		end
		if playingKey ~= key then
			return
		end
		sound:Play()
		-- join in where everyone else is
		local offset = math.max(0, Workspace:GetServerTimeNow() - (tonumber(m.started) or 0))
		local length = sound.TimeLength
		if length > 0 then
			if m.loop then
				offset %= length
			elseif offset >= length then
				sound:Stop()
				gui.Enabled = false -- the song is already over
				return
			end
			if offset > 1 then
				sound.TimePosition = offset
			end
		end
	end)
end

sound.Ended:Connect(function()
	if not sound.Looped then
		gui.Enabled = false
	end
end)

local function onEvents(e: any)
	if typeof(e) == "table" then
		play(if typeof(e.music) == "table" then e.music else nil)
	end
end

Net.On("Events", onEvents)
task.spawn(function()
	local r = Net.Request("Events.Get")
	if r.ok then
		onEvents(r)
	end
end)

return EventMusic
