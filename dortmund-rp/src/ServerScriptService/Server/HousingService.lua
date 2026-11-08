--!strict
-- Free apartments in the Dortmund Tower. Moving in is free; one flat per player.
-- Each server has its own tower: your flat is remembered and you get the same number
-- back when it is free on the server you join (otherwise the next free one).

local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)
local Interaction = require(script.Parent.InteractionService)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local TowerBuilder = require(script.Parent.TowerBuilder)

local HousingService = {}

local owner: { [number]: Player } = {} -- unit -> player (this server)
local unitOf: { [Player]: number } = {}
local doorBusy: { [number]: boolean } = {}

local function unitInfo(n: number): TowerBuilder.Unit?
	for _, u in TowerBuilder.Units do
		if u.number == n then
			return u
		end
	end
	return nil
end

local function refreshLabel(n: number)
	local u = unitInfo(n)
	if not u then
		return
	end
	local p = owner[n]
	u.label.Text = string.format("Wohnung %d\n%s", n, if p then p.DisplayName else "Frei")
end

local function assign(player: Player, n: number)
	owner[n] = player
	unitOf[player] = n
	player:SetAttribute("Apartment", n)
	refreshLabel(n)
end

local function release(player: Player)
	local n = unitOf[player]
	if n then
		owner[n] = nil
		unitOf[player] = nil
		player:SetAttribute("Apartment", nil)
		refreshLabel(n)
	end
end

local function firstFree(preferred: number?): number?
	if preferred and not owner[preferred] and unitInfo(preferred) then
		return preferred
	end
	for _, u in TowerBuilder.Units do
		if not owner[u.number] then
			return u.number
		end
	end
	return nil
end

local function openDoor(n: number)
	local u = unitInfo(n)
	if not u or doorBusy[n] then
		return
	end
	doorBusy[n] = true
	u.door.CanCollide = false
	u.door.Transparency = 0.7
	task.delay(4, function()
		u.door.CanCollide = true
		u.door.Transparency = 0
		doorBusy[n] = nil
	end)
end

function HousingService.Start()
	DataService.Loaded:Connect(function(player, data)
		if data.home and data.home.tower then
			local n = firstFree(tonumber(data.home.unit))
			if n then
				assign(player, n)
				data.home.unit = n
			end
		end
	end)
	Players.PlayerRemoving:Connect(release)

	Interaction.OnTrigger("AptDoor", function(player, door)
		local n = door:GetAttribute("Unit")
		if typeof(n) ~= "number" then
			return
		end
		local data = DataService.Get(player)
		if not data then
			return
		end
		local mine = unitOf[player]
		if owner[n] == player then
			openDoor(n)
		elseif owner[n] then
			Remotes.Push(player, "Notify", { key = "apt_taken", args = { owner[n].DisplayName }, error = true })
		elseif mine then
			Remotes.Push(player, "Notify", { key = "apt_have_one", args = { mine }, error = true })
		else
			assign(player, n)
			data.home = { tower = true, unit = n }
			State.MarkDirty(player)
			Remotes.Push(player, "Notify", { key = "apt_moved_in", args = { n } })
			openDoor(n)
		end
	end)

	Remotes.Handle("Housing.MoveOut", function(player)
		local data = DataService.Get(player) :: { [string]: any }
		if not unitOf[player] then
			return Remotes.Fail("no_apartment")
		end
		release(player)
		data.home = nil
		State.MarkDirty(player)
		return Remotes.Ok()
	end, { rate = 3 })

	Remotes.Handle("Tower.Go", function(player, floor: any)
		local f = Remotes.Check.Int(floor, 0, TowerBuilder.FLOORS)
		if f == nil then
			return Remotes.Fail("bad_request")
		end
		if not Interaction.IsNear(player, "Elevator", 14) then
			return Remotes.Fail("not_near")
		end
		local spot = TowerBuilder.FloorSpots[f]
		local character = player.Character
		if not spot or not character then
			return Remotes.Fail("error")
		end
		character:PivotTo(spot)
		return Remotes.Ok()
	end, { rate = 6 })
end

-- For the phone / Navi: where is this player's flat?
function HousingService.UnitOf(player: Player): number?
	return unitOf[player]
end

return HousingService
