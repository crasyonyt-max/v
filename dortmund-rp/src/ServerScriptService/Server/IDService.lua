--!strict
-- Digital ID (Personalausweis) with certificates (Shared/Certificates).
--   * every player who ever joined has one (own DataStore, so admins can read and
--     change it while the player is offline or on another server)
--   * who can see it: the owner, Police on duty standing next to the person,
--     Game Admins (any player, also offline)
--   * Game Admins give / take certificates; the "owner" ones only the Owner.
--     W4 bans the player for good; kicks and bans add the "previously" ones.

local Players = game:GetService("Players")
local DataStoreService = require(script.Parent.Sandbox).DataStoreService -- local only on the testing server
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Certificates = require(ReplicatedStorage.Shared.Certificates)
local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local GameLog = require(script.Parent.GameLog)
local JobService = require(script.Parent.JobService)
local Remotes = require(script.Parent.Remotes)
local Roles = require(script.Parent.Roles)

local IDService = {}

local INSPECT_DISTANCE = 15 -- studs: Police must stand next to the person

export type Card = {
	userId: number,
	name: string,
	display: string,
	joinday: number,
	certs: { [string]: { by: string, t: number } },
}

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName .. "_IDs")
end)
local cache: { [number]: Card } = {}

local function key(userId: number): string
	return "id_" .. userId
end

-- what the client gets: certificates in list order
local function view(card: Card): { [string]: any }
	local certs = {}
	for _, c in Certificates.List do
		local got = card.certs[c.code]
		if got then
			table.insert(certs, { code = c.code, by = got.by, t = got.t })
		end
	end
	return {
		userId = card.userId,
		name = card.name,
		display = card.display,
		number = Certificates.IdNumber(card.userId),
		joinday = card.joinday,
		residence = "Dortmund",
		certs = certs,
	}
end
IDService.View = view

local function load(userId: number): Card?
	if cache[userId] then
		return cache[userId]
	end
	if not store then
		return nil
	end
	local ok, data = pcall(function()
		return (store :: DataStore):GetAsync(key(userId))
	end)
	if ok and typeof(data) == "table" then
		data.certs = data.certs or {}
		cache[userId] = data :: any
		return data :: any
	end
	return nil
end
IDService.Load = load

-- change a card safely (also when another server changes it at the same time)
local function update(userId: number, fn: (Card) -> ()): Card?
	local result: Card? = nil
	if store then
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key(userId), function(old: any)
				local card = if typeof(old) == "table"
					then old
					else { userId = userId, name = "?", display = "?", joinday = os.time(), certs = {} }
				card.certs = card.certs or {}
				fn(card)
				result = card
				return card
			end)
		end)
		if not ok then
			warn("[ID] save failed for " .. userId .. ": " .. tostring(err))
			return nil
		end
	else
		-- Studio without DataStores: memory only
		local card = cache[userId] or { userId = userId, name = "?", display = "?", joinday = os.time(), certs = {} }
		fn(card)
		result = card
	end
	if result then
		cache[userId] = result
		local online = Players:GetPlayerByUserId(userId)
		if online then
			Remotes.Push(online, "IDUpdated", view(result))
		end
	end
	return result
end

-- the player's own card: created on the first join, name kept up to date
local function ensure(player: Player, firstJoin: number?)
	update(player.UserId, function(card)
		card.name = player.Name
		card.display = player.DisplayName
		if firstJoin and (not card.joinday or firstJoin < card.joinday) then
			card.joinday = firstJoin
		end
	end)
end

-- give a certificate without permission checks (kicks / bans / warnings)
function IDService.AddCert(userId: number, code: string, by: string): boolean
	if not Certificates.ByCode[code] then
		return false
	end
	return update(userId, function(card)
		if not card.certs[code] then
			card.certs[code] = { by = by, t = os.time() }
		end
	end) ~= nil
end

local function banForWarnings(actor: Player, userId: number)
	if Config.Testing then
		-- testing server: nothing global, only a kick
		local target = game:GetService("Players"):GetPlayerByUserId(userId)
		if target then
			target:Kick("🧪 Testserver – 4 Verwarnungen / 4 warnings")
		end
		return
	end
	local ok, err = pcall(function()
		Players:BanAsync({
			UserIds = { userId },
			ApplyToUniverse = true,
			Duration = -1,
			DisplayReason = "4 Verwarnungen / 4 warnings",
			PrivateReason = "W4 given by " .. actor.Name .. " (" .. actor.UserId .. ")",
			ExcludeAltAccounts = false,
		})
	end)
	if not ok then
		warn("[ID] W4 ban failed: " .. tostring(err))
	end
	IDService.AddCert(userId, Certificates.BANNED, "System")
	GameLog.Add("admin", actor, ("W4 -> banned %d"):format(userId))
end

-- Game Admins only; owner certificates only for the Owner
local function mayChange(actor: Player, userId: number, code: string): (boolean, string?)
	local cert = Certificates.ByCode[code]
	if not cert then
		return false, "bad_request"
	end
	if not Roles.IsGameAdmin(actor) then
		return false, "no_permission"
	end
	if cert.owner and Roles.Rank(actor) < Roles.OWNER then
		return false, "id_owner_only"
	end
	if userId ~= actor.UserId and not Roles.CanTargetUserId(actor, userId) then
		return false, "no_permission"
	end
	return true, nil
end
IDService.MayChange = mayChange

function IDService.Give(actor: Player, userId: number, code: string): (boolean, string?)
	local ok, err = mayChange(actor, userId, code)
	if not ok then
		return false, err
	end
	local card = update(userId, function(c)
		c.certs[code] = { by = actor.Name, t = os.time() }
	end)
	if not card then
		return false, "error"
	end
	GameLog.Add("admin", actor, ("certificate %s -> %d"):format(code, userId))
	if code == Certificates.WARN_BAN then
		task.spawn(banForWarnings, actor, userId)
	end
	return true, nil
end

function IDService.Remove(actor: Player, userId: number, code: string): (boolean, string?)
	local ok, err = mayChange(actor, userId, code)
	if not ok then
		return false, err
	end
	if not update(userId, function(c)
		c.certs[code] = nil
	end) then
		return false, "error"
	end
	GameLog.Add("admin", actor, ("certificate %s removed from %d"):format(code, userId))
	return true, nil
end

local function targetId(v: any): number?
	if typeof(v) == "number" then
		return Remotes.Check.Int(v, 1, 1e12)
	end
	local name = Remotes.Check.String(v, 20)
	if not name then
		return nil
	end
	local online = Players:FindFirstChild(name)
	if online and online:IsA("Player") then
		return online.UserId
	end
	local ok, id = pcall(function()
		return Players:GetUserIdFromNameAsync(name)
	end)
	return if ok then id else nil
end

-- Police on duty right next to the person (or a Game Admin)
function IDService.MayInspect(viewer: Player, target: Player): boolean
	if viewer == target or Roles.IsGameAdmin(viewer) then
		return true
	end
	if JobService.Get(viewer) ~= "Police" then
		return false
	end
	local a = viewer.Character and viewer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local b = target.Character and target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return a ~= nil and b ~= nil and (a.Position - b.Position).Magnitude <= INSPECT_DISTANCE
end

function IDService.Start()
	DataService.Loaded:Connect(function(player, data)
		task.spawn(ensure, player, tonumber(data.firstJoin))
	end)
	Players.PlayerRemoving:Connect(function(player)
		cache[player.UserId] = nil
	end)

	Remotes.Handle("ID.Mine", function(player)
		local card = load(player.UserId)
		if not card then
			ensure(player, tonumber((DataService.Get(player) or {}).firstJoin))
			card = load(player.UserId)
		end
		return if card then Remotes.Ok({ card = view(card) }) else Remotes.Fail("error")
	end, { rate = 10 })

	Remotes.Handle("ID.Inspect", function(player, userId: any)
		local id = Remotes.Check.Int(userId, 1, 1e12)
		local target = id and Players:GetPlayerByUserId(id)
		if not target then
			return Remotes.Fail("target_offline")
		end
		if not IDService.MayInspect(player, target) then
			return Remotes.Fail("id_not_allowed")
		end
		local card = load(target.UserId)
		if not card then
			return Remotes.Fail("error")
		end
		GameLog.Add("police", player, "checked the ID of " .. target.Name)
		Remotes.Push(target, "Notify", { key = "id_checked", args = { player.DisplayName } })
		return Remotes.Ok({ card = view(card) })
	end, { rate = 10 })

	-- Game Admins: any player's ID (by id or name), also offline
	Remotes.Handle("ID.Get", function(player, who: any)
		if not Roles.IsGameAdmin(player) then
			return Remotes.Fail("no_permission")
		end
		local id = targetId(who)
		local card = id and load(id)
		if not card then
			return Remotes.Fail("id_unknown")
		end
		return Remotes.Ok({ card = view(card) })
	end, { rate = 20 })

	-- Game Admins: everyone who ever joined, 20 per page
	Remotes.Handle("ID.List", function(player, cursor: any)
		if not Roles.IsGameAdmin(player) then
			return Remotes.Fail("no_permission")
		end
		if not store then
			local rows = {}
			for _, card in cache do
				table.insert(rows, view(card))
			end
			return Remotes.Ok({ rows = rows })
		end
		local ok, result = pcall(function()
			local pages = (store :: DataStore):ListKeysAsync(
				"id_",
				20,
				if typeof(cursor) == "string" and #cursor < 2000 then cursor else ""
			)
			local rows = {}
			for _, k in pages:GetCurrentPage() do
				local id = tonumber(string.sub((k :: any).KeyName, 4))
				local card = id and load(id)
				if card then
					table.insert(rows, view(card))
				end
			end
			return { rows = rows, cursor = if pages.IsFinished then nil else pages.Cursor }
		end)
		if not ok then
			warn("[ID] list failed: " .. tostring(result))
			return Remotes.Fail("error")
		end
		return Remotes.Ok(result)
	end, { rate = 6 })

	Remotes.Handle("ID.Give", function(player, who: any, code: any)
		local id = targetId(who)
		if not id or typeof(code) ~= "string" then
			return Remotes.Fail("bad_target")
		end
		local ok, err = IDService.Give(player, id, code)
		return if ok then Remotes.Ok() else Remotes.Fail(err or "error")
	end, { rate = 10 })

	Remotes.Handle("ID.Remove", function(player, who: any, code: any)
		local id = targetId(who)
		if not id or typeof(code) ~= "string" then
			return Remotes.Fail("bad_target")
		end
		local ok, err = IDService.Remove(player, id, code)
		return if ok then Remotes.Ok() else Remotes.Fail(err or "error")
	end, { rate = 10 })
end

return IDService
