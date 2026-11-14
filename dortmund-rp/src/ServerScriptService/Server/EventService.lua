--!strict
-- AA events (Owner + Co-Owners, via the Admin app): cash / XP boosts with a time
-- limit, gifts to everyone, and pickups at a spot on the map. Global: saved in a
-- DataStore and announced to every server with MessagingService.
-- Plus the automatic weekly event (see Boosts.WeeklyEnds).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Phones = require(ReplicatedStorage.Shared.Phones)
local Boosts = require(script.Parent.Boosts)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local PhoneService = require(script.Parent.PhoneService)
local Remotes = require(script.Parent.Remotes)
local StoreService = require(script.Parent.StoreService)
local XPService = require(script.Parent.XPService)
local DropEventService = require(script.Parent.DropEventService)
local DropperService = require(script.Parent.DropperService)

local EventService = {}

local TOPIC = "AAEvents"
local KEY = "state"
local MAX_DROPS = 10
local MAX_SONGS = 60

export type Boost = { m: number, ends: number }
export type Drop = { id: string, x: number, z: number, kind: string, value: any, ends: number }
export type Song = { id: number, name: string }
export type Music = { id: number, name: string, started: number, vol: number, loop: boolean }
type Saved = {
	cash: Boost?,
	xp: Boost?,
	drops: { Drop },
	music: Music?,
	songs: { Song },
	defaultOff: boolean?,
	countdown: { title: string, at: number }?,
	dropEvent: { id: string, ends: number }?,
	droppersOff: boolean?,
}

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName .. "_Events")
end)

local saved: Saved = { drops = {}, songs = {} }

-- Rewards -------------------------------------------------------------------------

EventService.KINDS = { "cash", "xp", "item", "phone" }

-- Checks a reward; returns the cleaned value or nil.
function EventService.CheckReward(kind: any, value: any): any
	if kind == "cash" or kind == "xp" then
		local n = tonumber(value)
		if n and n == n and n >= 1 and n <= 1e6 then
			return math.floor(n)
		end
	elseif kind == "item" then
		return if typeof(value) == "string" and Items.ById[value] then value else nil
	elseif kind == "phone" then
		local phone = typeof(value) == "string" and Phones.ById[value] or nil
		return if phone and not phone.adminOnly then value else nil
	end
	return nil
end

function EventService.RewardName(kind: string, value: any): string
	if kind == "cash" then
		return Locale.Euro(value)
	elseif kind == "xp" then
		return tostring(value) .. " XP"
	elseif kind == "item" then
		return Items.ById[value] and Items.ById[value].name or tostring(value)
	elseif kind == "phone" then
		return Phones.ById[value] and Phones.ById[value].name or tostring(value)
	end
	return "?"
end

local function give(player: Player, kind: string, value: any, reason: string): boolean
	if kind == "cash" then
		return Economy.Add(player, value, reason)
	elseif kind == "xp" then
		XPService.Add(player, nil, value, reason)
		return true
	elseif kind == "item" then
		return StoreService.Give(player, value)
	elseif kind == "phone" then
		return PhoneService.Give(player, value)
	end
	return false
end

-- Remembers ids a player already got (gifts, pickups), so nobody gets one twice.
local function claimOnce(player: Player, id: string): boolean
	local data = DataService.Get(player)
	if not data then
		return false
	end
	data.eventClaims = data.eventClaims or {}
	local claims = data.eventClaims :: { string }
	if table.find(claims, id) then
		return false
	end
	table.insert(claims, id)
	while #claims > 60 do
		table.remove(claims, 1)
	end
	return true
end

-- Snapshot for the clients ---------------------------------------------------------

local lastSnapshot = ""
local function snapshot(): { [string]: any }
	local cashEnds, xpEnds = Boosts.Ends()
	local drops = {}
	for _, d in saved.drops do
		table.insert(
			drops,
			{ id = d.id, x = d.x, z = d.z, ends = d.ends, name = EventService.RewardName(d.kind, d.value) }
		)
	end
	return {
		cash = { m = Boosts.Cash(), ends = cashEnds },
		xp = { m = Boosts.XP(), ends = xpEnds },
		weekly = Boosts.WeeklyEnds(os.time()) ~= nil,
		drops = drops,
		music = saved.music,
		defaultOff = saved.defaultOff == true,
		countdown = saved.countdown,
		dropEvent = saved.dropEvent,
		droppersOff = saved.droppersOff == true,
		songs = saved.songs,
	}
end
EventService.Snapshot = snapshot

-- Boosts: the bigger of a running AA boost and the weekly event.
local function refreshBoosts()
	local now = os.time()
	local weekly = Boosts.WeeklyEnds(now)
	local function pick(b: Boost?): (number, number)
		local m, ends = 1, 0
		if b and b.ends > now and b.m > 1 then
			m, ends = b.m, b.ends
		end
		if weekly and Boosts.WEEKLY_MULT > m then
			m, ends = Boosts.WEEKLY_MULT, weekly
		end
		return m, ends
	end
	local cm, ce = pick(saved.cash)
	local xm, xe = pick(saved.xp)
	Boosts.Set(cm, ce, xm, xe)
end

-- Pickups in the world ---------------------------------------------------------------

local dropFolder = Instance.new("Folder")
dropFolder.Name = "EventDrops"
dropFolder.Parent = Workspace
local dropModels: { [string]: Model } = {}

-- Street level (ignores roofs, so a pickup placed on a building lands beside it on the ground)
local function groundY(x: number, z: number): number
	local city = Workspace:FindFirstChild("City")
	local params = RaycastParams.new()
	if city then
		params.FilterType = Enum.RaycastFilterType.Include
		local list = {}
		for _, name in { "Ground", "Roads", "Pavements", "Areas" } do
			local f = city:FindFirstChild(name)
			if f then
				table.insert(list, f)
			end
		end
		params.FilterDescendantsInstances = list
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { dropFolder }
	end
	local hit = Workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -1200, 0), params)
	return if hit then hit.Position.Y else 0
end

local function buildDrop(d: Drop)
	local model = Instance.new("Model")
	model.Name = "Drop_" .. d.id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- the marker is seen from anywhere
	local y = groundY(d.x, d.z)
	local crate = Instance.new("Part")
	crate.Name = "Crate"
	crate.Size = Vector3.new(3, 3, 3)
	crate.CFrame = CFrame.new(d.x, y + 2, d.z) * CFrame.Angles(0, math.rad(25), 0)
	crate.Anchored = true
	crate.CanCollide = false
	crate.Color = Color3.fromRGB(255, 170, 0)
	crate.Material = Enum.Material.Neon
	crate.Parent = model
	model.PrimaryPart = crate
	local light = Instance.new("PointLight")
	light.Color = crate.Color
	light.Range = 18
	light.Brightness = 3
	light.Parent = crate
	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Size = Vector3.new(0.6, 120, 0.6)
	beam.CFrame = CFrame.new(d.x, y + 62, d.z)
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Transparency = 0.5
	beam.Color = crate.Color
	beam.Material = Enum.Material.Neon
	beam.Parent = model

	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromOffset(170, 46)
	board.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	board.AlwaysOnTop = true
	board.MaxDistance = 1e6
	board.Parent = crate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(255, 200, 60)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "📦 " .. EventService.RewardName(d.kind, d.value)
	label.Parent = board
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Aufheben"
	prompt.ObjectText = EventService.RewardName(d.kind, d.value)
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = crate
	prompt.Triggered:Connect(function(player)
		if os.time() >= d.ends then
			return
		end
		if not claimOnce(player, "drop_" .. d.id) then
			Remotes.Push(player, "Notify", { key = "drop_taken", error = true })
			return
		end
		if not give(player, d.kind, d.value, "Fundstück") then
			-- full bag / phone already owned: let them try again later
			local data = DataService.Get(player)
			local claims = data and data.eventClaims
			local i = claims and table.find(claims, "drop_" .. d.id)
			if i then
				table.remove(claims, i)
			end
			Remotes.Push(player, "Notify", { key = "drop_cant", error = true })
			return
		end
		Remotes.Push(player, "Notify", { key = "drop_got", args = { EventService.RewardName(d.kind, d.value) } })
	end)
	model.Parent = dropFolder
	dropModels[d.id] = model
end

local function syncDrops()
	local now = os.time()
	local keep: { [string]: boolean } = {}
	for _, d in saved.drops do
		if d.ends > now then
			keep[d.id] = true
			if not dropModels[d.id] then
				local ok, err = pcall(buildDrop, d)
				if not ok then
					warn("[Events] drop failed: " .. tostring(err))
				end
			end
		end
	end
	for id, model in dropModels do
		if not keep[id] then
			model:Destroy()
			dropModels[id] = nil
		end
	end
end

-- Saving + sharing --------------------------------------------------------------------

local function clean(v: any): Saved
	local out: Saved = { drops = {}, songs = {} }
	if typeof(v) ~= "table" then
		return out
	end
	local now = os.time()
	for _, k in { "cash", "xp" } do
		local b = v[k]
		if typeof(b) == "table" and typeof(b.m) == "number" and typeof(b.ends) == "number" and b.ends > now then
			(out :: any)[k] = { m = b.m, ends = b.ends }
		end
	end
	if typeof(v.drops) == "table" then
		for _, d in v.drops do
			if typeof(d) == "table" and typeof(d.id) == "string" and typeof(d.ends) == "number" and d.ends > now then
				table.insert(out.drops, d)
			end
		end
	end
	local m = v.music
	if typeof(m) == "table" and typeof(m.id) == "number" and typeof(m.started) == "number" then
		out.music = {
			id = m.id,
			name = tostring(m.name or ""),
			started = m.started,
			vol = math.clamp(tonumber(m.vol) or 0.5, 0, 1),
			loop = m.loop == true,
		}
	end
	if v.defaultOff == true then
		out.defaultOff = true
	end
	local de = v.dropEvent
	if typeof(de) == "table" and typeof(de.id) == "string" and typeof(de.ends) == "number" and de.ends > now then
		out.dropEvent = { id = de.id, ends = de.ends }
	end
	if v.droppersOff == true then
		out.droppersOff = true
	end
	-- countdowns stay a few minutes after they hit zero ("now!")
	local c = v.countdown
	if typeof(c) == "table" and typeof(c.at) == "number" and c.at + 300 > now then
		out.countdown = { title = tostring(c.title or "AA"), at = c.at }
	end
	if typeof(v.songs) == "table" then
		for _, song in v.songs do
			if typeof(song) == "table" and typeof(song.id) == "number" and #out.songs < MAX_SONGS then
				table.insert(out.songs, { id = song.id, name = tostring(song.name or "") })
			end
		end
	end
	return out
end

local function apply()
	refreshBoosts()
	syncDrops()
	-- dropper event + dropper on/off, the same on every server
	local de = saved.dropEvent
	DropEventService.Set(if de then de.id else nil, if de then de.ends else nil)
	DropperService.SetEnabled(saved.droppersOff ~= true)
	local snap = snapshot()
	local json = HttpService:JSONEncode(snap)
	if json ~= lastSnapshot then
		lastSnapshot = json
		Remotes.PushAll("Events", snap)
	end
end

local function reload()
	if not store then
		return
	end
	local ok, v = pcall(function()
		-- never the cached copy: another server may just have changed it
		local okOpt, options = pcall(function()
			local o = Instance.new("DataStoreGetOptions")
			o.UseCache = false
			return o
		end)
		return (store :: DataStore):GetAsync(KEY, if okOpt then options else nil)
	end)
	if ok then
		saved = clean(v)
	end
end

local function broadcast(extra: { [string]: any }?)
	local msg = extra or {}
	msg.server = game.JobId
	pcall(function()
		MessagingService:PublishAsync(TOPIC, msg)
	end)
end

-- Edits the saved state on every server (atomic), then applies it here.
local function update(edit: (Saved) -> (), extra: { [string]: any }?): boolean
	if store then
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(KEY, function(old: any)
				local s = clean(old)
				edit(s)
				saved = s
				return s
			end)
		end)
		if not ok then
			warn("[Events] save failed: " .. tostring(err))
			return false
		end
	else
		edit(saved) -- Studio without API access: this server only
	end
	apply()
	broadcast(extra)
	return true
end

-- Gifts reach the players online on each server (once per player).
local function giveAll(gift: { [string]: any })
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			if claimOnce(player, "gift_" .. tostring(gift.id)) then
				if give(player, gift.kind, gift.value, "Event-Geschenk") then
					Remotes.Push(player, "Notify", {
						key = "gift_got",
						args = { EventService.RewardName(gift.kind, gift.value) },
					})
				end
			end
		end)
	end
end

-- API (AdminService checks the rank) ---------------------------------------------------

function EventService.SetBoost(kind: string, mult: number, minutes: number): boolean
	return update(function(s)
		(s :: any)[kind] = { m = mult, ends = os.time() + math.floor(minutes * 60) }
	end)
end

function EventService.StopBoost(kind: string): boolean
	return update(function(s)
		(s :: any)[kind] = nil
	end)
end

function EventService.Gift(kind: string, value: any): boolean
	local gift = { id = string.sub(HttpService:GenerateGUID(false), 1, 8), kind = kind, value = value }
	giveAll(gift)
	broadcast({ gift = gift })
	return true
end

function EventService.AddDrop(x: number, z: number, kind: string, value: any, minutes: number): (boolean, string?)
	if #saved.drops >= MAX_DROPS then
		return false, "too_many_drops"
	end
	local drop: Drop = {
		id = string.sub(HttpService:GenerateGUID(false), 1, 8),
		x = math.floor(x * 10) / 10,
		z = math.floor(z * 10) / 10,
		kind = kind,
		value = value,
		ends = os.time() + math.floor(minutes * 60),
	}
	local ok = update(function(s)
		table.insert(s.drops, drop)
	end, { newDrop = EventService.RewardName(kind, value) })
	if ok then
		Remotes.PushAll("Notify", { key = "drop_new", args = { EventService.RewardName(kind, value) } })
	end
	return ok, nil
end

function EventService.RemoveDrop(id: string): boolean
	return update(function(s)
		for i, d in s.drops do
			if d.id == id then
				table.remove(s.drops, i)
				return
			end
		end
	end)
end

-- Music (global boombox) -------------------------------------------------------------

-- Looks up a Roblox audio id. Returns its name, or nil if it isn't an audio asset.
local function audioName(id: number): string?
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(id, Enum.InfoType.Asset)
	end)
	if not ok or typeof(info) ~= "table" or info.AssetTypeId ~= 3 then
		return nil
	end
	return string.sub(tostring(info.Name or ("Audio " .. id)), 1, 60)
end

function EventService.PlayMusic(id: number, volume: number, loop: boolean): (boolean, string?)
	local name = audioName(id)
	if not name then
		return false, "not_audio"
	end
	local ok = update(function(s)
		s.music = { id = id, name = name, started = os.time(), vol = volume, loop = loop }
	end)
	return ok, nil
end

-- The 24/7 background playlist (Config.DefaultMusic): on or paused, on every server.
-- Countdown shown to everyone on every server (title already filtered, at = UTC).
-- Dropper event on every server for `minutes` (nil id = stop).
function EventService.SetDropEvent(id: string?, minutes: number?): boolean
	return update(function(s)
		s.dropEvent = if id then { id = id, ends = os.time() + math.floor((minutes or 5) * 60) } else nil
	end)
end

-- Dropper tycoons in the apartments: on / off for everyone.
function EventService.SetDroppers(on: boolean): boolean
	return update(function(s)
		s.droppersOff = if on then nil else true
	end)
end

function EventService.SetCountdown(title: string, at: number): boolean
	return update(function(s)
		s.countdown = { title = title, at = at }
	end)
end

function EventService.ClearCountdown(): boolean
	return update(function(s)
		s.countdown = nil
	end)
end

function EventService.SetDefaultMusic(on: boolean): boolean
	return update(function(s)
		s.defaultOff = if on then nil else true
	end)
end

function EventService.StopMusic(): boolean
	return update(function(s)
		s.music = nil
	end)
end

function EventService.AddSong(id: number): (boolean, string?)
	local name = audioName(id)
	if not name then
		return false, "not_audio"
	end
	local full = false
	local ok = update(function(s)
		for _, song in s.songs do
			if song.id == id then
				return
			end
		end
		if #s.songs >= MAX_SONGS then
			full = true
			return
		end
		table.insert(s.songs, { id = id, name = name })
	end)
	if full then
		return false, "too_many_songs"
	end
	return ok, nil
end

function EventService.RemoveSong(id: number): boolean
	return update(function(s)
		for i, song in s.songs do
			if song.id == id then
				table.remove(s.songs, i)
				return
			end
		end
	end)
end

function EventService.Start()
	task.spawn(function()
		reload()
		apply()
	end)
	pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(message)
			local data = message.Data
			if typeof(data) ~= "table" or data.server == game.JobId then
				return
			end
			if typeof(data.gift) == "table" then
				local g = data.gift
				local value = EventService.CheckReward(g.kind, g.value)
				if value ~= nil then
					giveAll({ id = tostring(g.id), kind = g.kind, value = value })
				end
				return
			end
			reload()
			apply()
			if typeof(data.newDrop) == "string" then
				Remotes.PushAll("Notify", { key = "drop_new", args = { data.newDrop } })
			end
		end)
	end)

	-- safety net: even if a message from another server got lost, every server
	-- picks up the shared state (countdown, boosts, music, …) within 30 seconds
	task.spawn(function()
		while true do
			task.wait(30)
			reload()
			apply()
		end
	end)

	-- expire boosts / drops, start and end the weekly event
	task.spawn(function()
		while true do
			task.wait(2)
			local before = lastSnapshot
			saved = clean(saved)
			refreshBoosts()
			syncDrops()
			local snap = snapshot()
			local now = HttpService:JSONEncode(snap)
			if now ~= before then
				lastSnapshot = now
				Remotes.PushAll("Events", snap)
			end
		end
	end)

	Remotes.Handle("Events.Get", function()
		return Remotes.Ok(snapshot())
	end, { rate = 6, needsData = false })
end

return EventService
