--!strict
-- v0.4: house front doors open only for the players allowed in (owner, co-owners,
-- guests): on THEIR screen the door turns see-through and lets them pass when
-- they stand right in front of it. Everyone else finds it closed.
-- The mailbox prompt "Haus verwalten" is shown to the owner + co-owners only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local me = Players.LocalPlayer
local OPEN_DISTANCE = 9

local doors: { [BasePart]: boolean } = {}
local mailboxes: { [BasePart]: boolean } = {}

local function track(d: Instance)
	if d:IsA("BasePart") and d.Name == "Mailbox" then
		mailboxes[d] = true
		d.AncestryChanged:Connect(function()
			if not d:IsDescendantOf(Workspace) then
				mailboxes[d] = nil
			end
		end)
	end
	if d:IsA("BasePart") and d.Name == "Door" and d:GetAttribute("HouseOwner") ~= nil then
		doors[d] = false
		d.AncestryChanged:Connect(function()
			if not d:IsDescendantOf(Workspace) then
				doors[d] = nil
			end
		end)
	end
end

local function watch(folder: Instance)
	for _, d in folder:GetDescendants() do
		track(d)
	end
	folder.DescendantAdded:Connect(track)
end

task.spawn(function()
	local folder = Workspace:WaitForChild("Wohngebiet", 120)
	if folder then
		watch(folder)
	end
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.15 then
		return
	end
	acc = 0
	local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	for door, isOpen in doors do
		local allowed = string.find(tostring(door:GetAttribute("Allowed") or ""), "," .. me.UserId .. ",", 1, true)
			~= nil
		local near = root ~= nil and (root.Position - door.Position).Magnitude < OPEN_DISTANCE
		local open = allowed and near
		if open ~= isOpen then
			doors[door] = open
			door.CanCollide = not open -- only on this screen
			door.Transparency = if open then 0.7 else 0
		end
	end
	-- "Haus verwalten" at the mailbox: owner + co-owners only
	for box in mailboxes do
		local prompt = box:FindFirstChild("Manage")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = string.find(tostring(box:GetAttribute("Builders") or ""), "," .. me.UserId .. ",", 1, true)
				~= nil
		end
	end
end)

return {}
