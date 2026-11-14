--[[
	AdminConfig (server only)

	Game Admins: whitelisted by UserId, valid in every server.
	Server Admins (private server owners and the admins they appoint) are
	handled separately in ServerAdmins.
]]

local AdminConfig = {}

AdminConfig.GameAdminUserIds = {
	-- 123456789, -- name (for your own reference)
}

local lookup = {}
for _, id in ipairs(AdminConfig.GameAdminUserIds) do
	lookup[id] = true
end

function AdminConfig.IsGameAdmin(userId)
	return lookup[userId] == true
end

return AdminConfig
