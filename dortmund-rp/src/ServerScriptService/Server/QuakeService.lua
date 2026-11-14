--!strict
-- Easter egg: when 0312benni joins the server shakes (magnitude 29.928,91) and every
-- time he jumps it shakes much harder (magnitude 282.722.782,9). Only the camera
-- shakes, nothing in the world moves or breaks.

local Players = game:GetService("Players")

local Remotes = require(script.Parent.Remotes)

local QuakeService = {}

local BENNI_IDS = { [3482982410] = true } -- 0312benni
local BENNI_NAMES = { ["0312benni"] = true, ["0321benni"] = true }
local JUMP_COOLDOWN = 6

function QuakeService.IsBenni(player: Player): boolean
	return BENNI_IDS[player.UserId] == true or BENNI_NAMES[player.Name:lower()] == true
end

local function quake(player: Player, magnitude: string, strength: number, duration: number)
	Remotes.PushAll("Quake", {
		magnitude = magnitude,
		who = player.DisplayName,
		strength = strength,
		duration = duration,
	})
end

local function watchJumps(player: Player, character: Model)
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	local last = 0
	hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping and os.clock() - last > JUMP_COOLDOWN then
			last = os.clock()
			quake(player, "282.722.782,9", 3, 5)
		end
	end)
end

local function onJoin(player: Player)
	if not QuakeService.IsBenni(player) then
		return
	end
	player.CharacterAdded:Connect(function(character)
		watchJumps(player, character)
	end)
	if player.Character then
		task.spawn(watchJumps, player, player.Character)
	end
	-- give everyone's screen a moment to load first
	task.delay(4, quake, player, "29.928,91", 1, 8)
end

function QuakeService.Start()
	Players.PlayerAdded:Connect(onJoin)
	for _, p in Players:GetPlayers() do
		task.spawn(onJoin, p)
	end
end

return QuakeService
