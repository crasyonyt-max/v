--!strict
-- Phones: Handyland purchases, equipping, settings. NVDR P1 is Game-Admin-only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Phones = require(ReplicatedStorage.Shared.Phones)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.EconomyService)
local Interaction = require(script.Parent.InteractionService)
local Remotes = require(script.Parent.Remotes)
local Roles = require(script.Parent.Roles)
local State = require(script.Parent.State)

local PhoneService = {}

local function owns(data: { [string]: any }, id: string): boolean
	return table.find(data.phones, id) ~= nil
end

-- Grants / removes the admin phone to match the player's current role.
function PhoneService.SyncAdminPhone(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local id = Config.AdminPhoneId
	local isAdmin = Roles.IsGameAdmin(player)
	local index = table.find(data.phones, id)
	if isAdmin and not index then
		table.insert(data.phones, id)
		data.phone = id -- first time: give it to them in hand
	elseif not isAdmin and index then
		table.remove(data.phones, index)
		if data.phone == id then
			data.phone = Phones.StarterId
		end
	end
	if not owns(data, data.phone) then
		data.phone = Phones.StarterId
	end
	State.MarkDirty(player)
end

function PhoneService.Start()
	DataService.Loaded:Connect(function(player)
		PhoneService.SyncAdminPhone(player)
	end)

	Remotes.Handle("Phone.Buy", function(player, phoneId: any)
		local data = DataService.Get(player) :: { [string]: any }
		local phone = typeof(phoneId) == "string" and Phones.ById[phoneId] or nil
		if not phone or not phone.shop then
			return Remotes.Fail("bad_item")
		end
		if not Interaction.IsNear(player, "Shop", 30, "UI", "Handyland") then
			return Remotes.Fail("not_near")
		end
		if owns(data, phone.id) then
			return Remotes.Fail("already_owned")
		end
		if not Economy.TrySpend(player, phone.price, "Handyland: " .. phone.name) then
			return Remotes.Fail("no_money")
		end
		table.insert(data.phones, phone.id)
		data.phone = phone.id
		State.MarkDirty(player)
		return Remotes.Ok()
	end, { rate = 5 })

	Remotes.Handle("Phone.Equip", function(player, phoneId: any)
		local data = DataService.Get(player) :: { [string]: any }
		local phone = typeof(phoneId) == "string" and Phones.ById[phoneId] or nil
		if not phone or not owns(data, phone.id) then
			return Remotes.Fail("not_owned")
		end
		if phone.adminOnly and not Roles.IsGameAdmin(player) then
			return Remotes.Fail("no_permission")
		end
		data.phone = phone.id
		local maxWallpaper = phone.wallpapers
		if data.wallpaper > maxWallpaper then
			data.wallpaper = 1
		end
		State.MarkDirty(player)
		return Remotes.Ok()
	end, { rate = 10 })

	Remotes.Handle("Phone.SetWallpaper", function(player, index: any)
		local data = DataService.Get(player) :: { [string]: any }
		local phone = Phones.ById[data.phone]
		local n = Remotes.Check.Int(index, 1, phone and phone.wallpapers or 1)
		if not n then
			return Remotes.Fail("locked")
		end
		data.wallpaper = n
		State.MarkDirty(player)
		return Remotes.Ok()
	end, { rate = 10 })

	Remotes.Handle("Settings.Language", function(player, lang: any)
		local data = DataService.Get(player) :: { [string]: any }
		local value = Remotes.Check.OneOf(lang, { "de", "en" })
		if not value then
			return Remotes.Fail("bad_request")
		end
		data.language = value
		State.MarkDirty(player)
		return Remotes.Ok()
	end, { rate = 5 })
end

return PhoneService
