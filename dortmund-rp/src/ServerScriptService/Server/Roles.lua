--!strict
-- Who is allowed to do what. Always decided on the server.
--   Rank 4: experience owner
--   Rank 3: Game Admin (Config.GameAdmins / group owner) -> whole game
--   Rank 2: server owner (private server) -> own server only
--   Rank 1: appointed Server Admin -> own server only
--   Rank 0: player

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Roles = {}

Roles.OWNER = 4
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

function Roles.CanTargetUserId(actor: Player, userId: number): boolean
	if actor.UserId == userId then
		return false
	end
	if whitelist[userId] then
		return Roles.Rank(actor) >= Roles.OWNER
	end
	if game.CreatorType == Enum.CreatorType.User and userId == game.CreatorId then
		return false
	end
	if Roles.ServerOwnerId() == userId then
		return Roles.Rank(actor) >= Roles.GAME_ADMIN
	end
	return Roles.Rank(actor) >= Roles.SERVER_ADMIN
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
	local label = if rank >= Roles.GAME_ADMIN
		then "GameAdmin"
		elseif rank >= Roles.SERVER_ADMIN then "ServerAdmin"
		else ""
	player:SetAttribute("Role", label)
end

Players.PlayerRemoving:Connect(function(player)
	gameAdminCache[player.UserId] = nil
end)

return Roles
