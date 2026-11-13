--!strict
-- Sends each player a snapshot of their own private data whenever it changes.
-- Changes are batched so many updates in one frame produce one network message.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Levels = require(ReplicatedStorage.Shared.Levels)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local Roles = require(script.Parent.Roles)

local State = {}

local dirty: { [Player]: boolean } = {}
local passCache: { [Player]: { [string]: boolean } } = {}

function State.PhoneNumber(userId: number): string
	return "01" .. tostring(userId)
end

function State.UserIdFromNumber(number: string): number?
	local digits = string.match(number, "^01(%d+)$")
	return if digits then tonumber(digits) else nil
end

-- Gamepass ownership (cached). Game Admins own every pack.
function State.OwnsPack(player: Player, pack: string): boolean
	if Roles.IsGameAdmin(player) then
		return true
	end
	local cache = passCache[player]
	if not cache then
		cache = {}
		passCache[player] = cache
	end
	if cache[pack] ~= nil then
		return cache[pack]
	end
	local id = (Config.Gamepasses :: any)[pack]
	if not id or id == 0 then
		return false
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)
	if ok then
		cache[pack] = owns
		return owns
	end
	return false
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then
		return
	end
	for pack, id in Config.Gamepasses do
		if id == passId then
			passCache[player] = passCache[player] or {}
			passCache[player][pack] = true
			State.MarkDirty(player)
		end
	end
end)

function State.Snapshot(player: Player): { [string]: any }?
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local level, into, need = Levels.FromTotal(data.xp)
	local jobXP = data.jobXP[data.job] or 0
	local packs = {}
	for pack in Config.Gamepasses do
		packs[pack] = State.OwnsPack(player, pack)
	end
	local messages = {}
	local from = math.max(1, #data.messages - 79)
	for i = from, #data.messages do
		table.insert(messages, data.messages[i])
	end
	local tx = {}
	for i = math.max(1, #data.tx - 19), #data.tx do
		table.insert(tx, data.tx[i])
	end
	return {
		bank = data.bank,
		cash = data.cash,
		xp = data.xp,
		level = level,
		levelXP = into,
		levelNeed = need,
		job = data.job,
		jobXP = data.jobXP,
		currentJobXP = jobXP,
		vehicles = data.vehicles,
		starterChosen = data.starterChosen,
		phones = data.phones,
		phone = data.phone,
		wallpaper = data.wallpaper,
		language = data.language,
		messages = messages,
		tx = tx,
		number = State.PhoneNumber(player.UserId),
		rank = Roles.Rank(player),
		aa = Roles.HasAA(player),
		packs = packs,
		privateServer = Roles.IsPrivateServer(),
	}
end

function State.MarkDirty(player: Player)
	dirty[player] = true
end

function State.SendNow(player: Player)
	dirty[player] = nil
	local snap = State.Snapshot(player)
	if snap then
		Remotes.Push(player, "State", snap)
	end
end

function State.Start()
	task.spawn(function()
		while true do
			task.wait(0.2)
			for player in dirty do
				task.spawn(State.SendNow, player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		passCache[player] = nil
	end)
	Remotes.Handle("State.Get", function(player)
		return Remotes.Ok({ state = State.Snapshot(player) })
	end, { rate = 5 })
end

return State
