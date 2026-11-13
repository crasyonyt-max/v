--!strict
-- Who is allowed to do what. Always decided on the server.
--   Rank 6: owner (Config.OwnerId / experience or group owner) -> nobody can target them
--   Rank 5: Co-Owner (Config.CoOwners) -> Game Admin powers + AA tab
--   Rank 4: second Co-Owner (Config.SecondCoOwners) -> Game Admin powers, outranks Game Admins
--   Rank 3: Game Admin (Config.GameAdmins) -> whole game
--   Rank 2: server owner (private server) -> own server only
--   Rank 1: appointed Server Admin -> own server only
--   Rank 0: player

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Roles = {}

Roles.OWNER = 6
Roles.CO_OWNER = 5
Roles.SECOND_CO_OWNER = 4
Roles.GAME_ADMIN = 3
Roles.SERVER_OWNER = 2
Roles.SERVER_ADMIN = 1
Roles.PLAYER = 0

local gameAdminCache: { [number]: boolean } = {}
local appointed: { [number]: boolean } = {} -- Server Admins appointed on this server
local reservedOwnerId: number? = nil -- set by the server browser (phase 2) for reserved private servers

local whitelist: { [number]: boolean } = {}
for _, id in Config.GameAdmins do
	whitelist[id] = true
end
local coOwners: { [number]: boolean } = {}
for _, id in Config.CoOwners do
	coOwners[id] = true
end
local secondCoOwners: { [number]: boolean } = {}
for _, id in Config.SecondCoOwners do
	secondCoOwners[id] = true
end

-- Rank from the UserId alone (also for offline players, e.g. bans).
local function staticRank(id: number): number
	if id == Config.OwnerId or (game.CreatorType == Enum.CreatorType.User and id == game.CreatorId) then
		return Roles.OWNER
	end
	if coOwners[id] then
		return Roles.CO_OWNER
	end
	if secondCoOwners[id] then
		return Roles.SECOND_CO_OWNER
	end
	if whitelist[id] then
		return Roles.GAME_ADMIN
	end
	if Roles.ServerOwnerId() == id then
		return Roles.SERVER_OWNER
	end
	if appointed[id] then
		return Roles.SERVER_ADMIN
	end
	return Roles.PLAYER
end

local function isOwner(player: Player): boolean
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank == 255
end

function Roles.IsPrivateServer(): boolean
	return game.PrivateServerId ~= "" or reservedOwnerId ~= nil
end

function Roles.ServerOwnerId(): number?
	if reservedOwnerId then
		return reservedOwnerId
	end
	if game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0 then
		return game.PrivateServerOwnerId
	end
	return nil
end

function Roles.SetReservedOwner(userId: number)
	reservedOwnerId = userId
end

function Roles.Rank(player: Player): number
	local id = player.UserId
	local cached = gameAdminCache[id]
	if cached == nil then
		cached = isOwner(player)
		gameAdminCache[id] = cached
	end
	if cached then
		return Roles.OWNER
	end
	return staticRank(id)
end

-- AA tab: Owner, both Co-Owner ranks, and the Game Admins in Config.AAExtra.
function Roles.HasAA(player: Player): boolean
	if Roles.Rank(player) >= Roles.SECOND_CO_OWNER then
		return true
	end
	return Roles.IsGameAdmin(player) and table.find(Config.AAExtra, player.UserId) ~= nil
end

function Roles.IsGameAdmin(player: Player): boolean
	return Roles.Rank(player) >= Roles.GAME_ADMIN
end

function Roles.IsServerAdmin(player: Player): boolean
	return Roles.Rank(player) >= Roles.SERVER_ADMIN
end

-- actor may act on target only if they outrank them (or it is themselves).
function Roles.CanTarget(actor: Player, target: Player): boolean
	if actor == target then
		return true
	end
	return Roles.Rank(actor) > Roles.Rank(target)
end

-- For bans by UserId (target may be offline): only someone of a higher rank.
function Roles.CanTargetUserId(actor: Player, userId: number): boolean
	if actor.UserId == userId then
		return false
	end
	local online = Players:GetPlayerByUserId(userId)
	local target = if online then Roles.Rank(online) else staticRank(userId)
	return Roles.Rank(actor) > math.max(target, Roles.PLAYER)
end

function Roles.Appoint(userId: number, value: boolean)
	appointed[userId] = if value then true else nil
	local player = Players:GetPlayerByUserId(userId)
	if player then
		Roles.Refresh(player)
	end
end

function Roles.IsAppointed(userId: number): boolean
	return appointed[userId] == true
end

-- Public role label for UI (purely cosmetic on the client).
function Roles.Refresh(player: Player)
	local rank = Roles.Rank(player)
	local label = if rank >= Roles.OWNER
		then "Owner"
		elseif rank >= Roles.SECOND_CO_OWNER then "CoOwner"
		elseif rank >= Roles.GAME_ADMIN then "GameAdmin"
		elseif rank >= Roles.SERVER_ADMIN then "ServerAdmin"
		else ""
	player:SetAttribute("Role", label)
end

Players.PlayerRemoving:Connect(function(player)
	gameAdminCache[player.UserId] = nil
end)

return Roles
