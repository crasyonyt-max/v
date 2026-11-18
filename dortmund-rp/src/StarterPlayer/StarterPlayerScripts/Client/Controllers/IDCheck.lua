--!strict
-- Police on duty: "Ausweis kontrollieren" (I) next to any other player shows that
-- player's ID. The prompts exist only on this client; the server checks job + distance.

local Players = game:GetService("Players")

local IDCard = require(script.Parent.Parent.UI.IDCard)
local Net = require(script.Parent.Parent.Net)
local Notify = require(script.Parent.Parent.UI.Notify)

local me = Players.LocalPlayer
local prompts: { [Player]: ProximityPrompt } = {}

local function isPolice(): boolean
	return me:GetAttribute("Job") == "Police"
end

local function attach(p: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local old = prompts[p]
	if old then
		old:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "IDCheck"
	prompt.ActionText = "Ausweis kontrollieren"
	prompt.ObjectText = p.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.I
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Enabled = isPolice()
	prompt.Parent = root
	prompt.Triggered:Connect(function()
		local r = Net.Request("ID.Inspect", p.UserId)
		if r.ok then
			IDCard.Show(r.card)
		else
			Notify.Error(r.err)
		end
	end)
	prompts[p] = prompt
end

local function watch(p: Player)
	if p == me then
		return
	end
	p.CharacterAdded:Connect(function(c)
		attach(p, c)
	end)
	if p.Character then
		task.spawn(attach, p, p.Character)
	end
end

for _, p in Players:GetPlayers() do
	watch(p)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(p)
	prompts[p] = nil
end)
me:GetAttributeChangedSignal("Job"):Connect(function()
	local on = isPolice()
	for _, prompt in prompts do
		prompt.Enabled = on
	end
end)

-- someone changed my certificates: open card refreshes next time; tell me
Net.On("IDUpdated", function() end)

return {}
