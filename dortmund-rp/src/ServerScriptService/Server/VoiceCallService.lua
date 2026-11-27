--!strict
-- Update 2 (Config.Update2, testing server first):
--   👤 Contacts: saved names for phone numbers (data.contacts), shared with ChatsApp
--   📞 Voice calls between players, anywhere on the map (not by distance): only when
--      BOTH have Roblox voice chat. 1:1 from Contacts / the Dialer / a chat, group calls
--      from ChatsApp only. Every member's microphone is wired straight to every other
--      member's speakers (Audio API: AudioDeviceInput -> Wire -> AudioDeviceOutput with
--      Player = the listener), so only the people in the call hear it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VoiceChatService = game:GetService("VoiceChatService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ChatService = require(script.Parent.ChatService)
local DataService = require(script.Parent.DataService)
local GameLog = require(script.Parent.GameLog)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local VoiceCallService = {}

VoiceCallService.MAX_CONTACTS = 100
VoiceCallService.MAX_GROUP = 8
VoiceCallService.RING_SECONDS = 30

type Call = {
	id: string,
	from: Player,
	members: { [Player]: boolean },
	invited: { [Player]: number }, -- ringing until
	group: boolean,
	wires: { Instance },
}
local calls: { [string]: Call } = {}
local callOf: { [Player]: string } = {}
local voiceReported: { [Player]: boolean } = {}
local nextId = 0

local function on(): boolean
	return Config.On(Config.Update2)
end

-- Contacts ------------------------------------------------------------------------------

-- a cleaned contact entry, or nil
function VoiceCallService.CleanNumber(n: any): string?
	if typeof(n) ~= "string" then
		return nil
	end
	local clean = string.gsub(n, "[%s%-/]", "")
	if #clean < 2 or #clean > 16 or not string.match(clean, "^%d+$") then
		return nil
	end
	return clean
end

-- Voice -----------------------------------------------------------------------------------

function VoiceCallService.HasVoice(p: Player): boolean
	local ok, enabled = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(p.UserId)
	end)
	if ok then
		return enabled == true
	end
	return voiceReported[p] == true -- the client told us (only used if the server can't ask)
end

local audioFolder: Folder? = nil
local function audio(): Folder
	if not audioFolder or not audioFolder.Parent then
		local f = Instance.new("Folder")
		f.Name = "PhoneAudio"
		f.Parent = Workspace
		audioFolder = f
	end
	return audioFolder :: Folder
end

local function inputOf(p: Player): Instance?
	local found = p:FindFirstChildOfClass("AudioDeviceInput")
	if found then
		return found
	end
	local ok, input = pcall(function()
		local i = Instance.new("AudioDeviceInput")
		i.Name = "PhoneMic"
		(i :: any).Player = p
		i.Parent = p
		return i
	end)
	return if ok then input else nil
end

local function outputOf(p: Player): Instance?
	local name = "Phone_" .. p.UserId
	local f = audio()
	local found = f:FindFirstChild(name)
	if found then
		return found
	end
	local ok, out = pcall(function()
		local o = Instance.new("AudioDeviceOutput")
		o.Name = name;
		(o :: any).Player = p -- only this player's device plays it
		o.Parent = f
		return o
	end)
	return if ok then out else nil
end

-- (re)wire every member to every other member
local function rewire(call: Call)
	for _, w in call.wires do
		w:Destroy()
	end
	table.clear(call.wires)
	for a in call.members do
		for b in call.members do
			if a ~= b then
				local src, dst = inputOf(a), outputOf(b)
				if src and dst then
					local ok, w = pcall(function()
						local wire = Instance.new("Wire");
						(wire :: any).SourceInstance = src;
						(wire :: any).TargetInstance = dst
						wire.Name = ("%d->%d"):format(a.UserId, b.UserId)
						wire.Parent = audio()
						return wire
					end)
					if ok and w then
						table.insert(call.wires, w)
					end
				end
			end
		end
	end
end

local function names(call: Call): { string }
	local out = {}
	for p in call.members do
		table.insert(out, p.DisplayName)
	end
	table.sort(out)
	return out
end

local function publish(call: Call, state: string)
	local list = names(call)
	for p in call.members do
		Remotes.Push(p, "VoiceState", { id = call.id, state = state, members = list, group = call.group })
	end
	for p in call.invited do
		Remotes.Push(p, "VoiceState", { id = call.id, state = state, members = list, group = call.group })
	end
end

local function leave(p: Player)
	local id = callOf[p]
	local call = id and calls[id]
	callOf[p] = nil
	if not call then
		return
	end
	call.members[p] = nil
	call.invited[p] = nil
	Remotes.Push(p, "VoiceState", { id = call.id, state = "ended" })
	local count = 0
	for _ in call.members do
		count += 1
	end
	local ringing = next(call.invited) ~= nil
	if count <= 1 and not (count == 1 and ringing) then
		-- nobody left to talk to: the call ends for everyone
		for m in call.members do
			callOf[m] = nil
			Remotes.Push(m, "VoiceState", { id = call.id, state = "ended" })
		end
		for m in call.invited do
			Remotes.Push(m, "VoiceState", { id = call.id, state = "ended" })
		end
		for _, w in call.wires do
			w:Destroy()
		end
		calls[call.id] = nil
	else
		rewire(call)
		publish(call, "active")
	end
end
VoiceCallService.Leave = leave

function VoiceCallService.Start()
	if not on() then
		return
	end

	Remotes.Handle("Contacts.Save", function(player, number: any, name: any)
		local data = DataService.Get(player)
		local n = VoiceCallService.CleanNumber(number)
		local raw = Remotes.Check.String(name, 24)
		if not data or not n or not raw or raw == "" then
			return Remotes.Fail("bad_request")
		end
		data.contacts = if typeof(data.contacts) == "table" then data.contacts else {}
		local count = 0
		for _ in data.contacts do
			count += 1
		end
		if not data.contacts[n] and count >= VoiceCallService.MAX_CONTACTS then
			return Remotes.Fail("contacts_full")
		end
		local clean = ChatService.Filter(raw, player.UserId)
		if not clean then
			return Remotes.Fail("filter_failed")
		end
		data.contacts[n] = clean
		State.MarkDirty(player)
		return Remotes.Ok()
	end, { rate = 6 })

	Remotes.Handle("Contacts.Delete", function(player, number: any)
		local data = DataService.Get(player)
		local n = VoiceCallService.CleanNumber(number)
		if not data or not n or typeof(data.contacts) ~= "table" then
			return Remotes.Fail("bad_request")
		end
		data.contacts[n] = nil
		State.MarkDirty(player)
		return Remotes.Ok()
	end, { rate = 6 })

	Remotes.Handle("Voice.Report", function(player, enabled: any)
		voiceReported[player] = enabled == true
		return Remotes.Ok({ voice = VoiceCallService.HasVoice(player) })
	end, { rate = 2, needsData = false })

	-- numbers = { "01…" } (1 = a normal call, more = a group call from ChatsApp)
	Remotes.Handle("Voice.Call", function(player, numbers: any, group: any)
		if typeof(numbers) ~= "table" or #numbers < 1 or #numbers > VoiceCallService.MAX_GROUP - 1 then
			return Remotes.Fail("bad_request")
		end
		if #numbers > 1 and group ~= true then
			return Remotes.Fail("voice_group_chatsapp")
		end
		if callOf[player] then
			return Remotes.Fail("voice_busy")
		end
		if not VoiceCallService.HasVoice(player) then
			return Remotes.Fail("voice_need_mine")
		end
		local targets: { Player } = {}
		for _, num in numbers do
			local n = VoiceCallService.CleanNumber(num)
			local userId = n and State.UserIdFromNumber(n)
			local t = userId and Players:GetPlayerByUserId(userId)
			if not t then
				return Remotes.Fail("voice_offline")
			end
			if t == player then
				return Remotes.Fail("bad_request")
			end
			if callOf[t] then
				return Remotes.Fail("voice_other_busy")
			end
			if not VoiceCallService.HasVoice(t) then
				return Remotes.Fail("voice_need_theirs")
			end
			table.insert(targets, t)
		end
		nextId += 1
		local call: Call = {
			id = tostring(nextId),
			from = player,
			members = { [player] = true },
			invited = {},
			group = #targets > 1 or group == true,
			wires = {},
		}
		calls[call.id] = call
		callOf[player] = call.id
		local myNumber = State.PhoneNumber(player.UserId)
		for _, t in targets do
			call.invited[t] = os.clock() + VoiceCallService.RING_SECONDS
			Remotes.Push(t, "VoiceIncoming", {
				id = call.id,
				from = player.DisplayName,
				number = myNumber,
				group = call.group,
				count = #targets + 1,
			})
		end
		publish(call, "ringing")
		GameLog.Add("chat", player, ("voice call to %d player(s)"):format(#targets))
		return Remotes.Ok({ id = call.id })
	end, { rate = 3 })

	Remotes.Handle("Voice.Answer", function(player, id: any, accept: any)
		local call = typeof(id) == "string" and calls[id] or nil
		if not call or not call.invited[player] then
			return Remotes.Fail("voice_gone")
		end
		call.invited[player] = nil
		if accept ~= true then
			if call.from.Parent then
				Remotes.Push(call.from, "Notify", { key = "voice_declined", args = { player.DisplayName } })
			end
			-- nobody else ringing and only the caller left: the call ends
			local count = 0
			for _ in call.members do
				count += 1
			end
			if count <= 1 and next(call.invited) == nil then
				leave(call.from)
			end
			return Remotes.Ok()
		end
		if callOf[player] then
			leave(player)
		end
		call.members[player] = true
		callOf[player] = call.id
		rewire(call)
		publish(call, "active")
		return Remotes.Ok()
	end, { rate = 4 })

	Remotes.Handle("Voice.HangUp", function(player)
		leave(player)
		return Remotes.Ok()
	end, { rate = 4, needsData = false })

	-- unanswered rings stop
	task.spawn(function()
		while true do
			task.wait(2)
			local now = os.clock()
			for _, call in calls do
				for p, untilT in call.invited do
					if now > untilT or not p.Parent then
						call.invited[p] = nil
						Remotes.Push(p, "VoiceState", { id = call.id, state = "ended" })
						local count = 0
						for _ in call.members do
							count += 1
						end
						if count <= 1 and next(call.invited) == nil then
							if call.from.Parent then
								Remotes.Push(call.from, "Notify", { key = "voice_no_answer" })
							end
							leave(call.from)
						end
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		leave(p)
		voiceReported[p] = nil
	end)
end

return VoiceCallService
