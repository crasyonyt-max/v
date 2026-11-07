--!strict
-- Fly + noclip for admins. The server decides who may use them by setting the
-- AdminFly / AdminNoclip attributes; the client only carries out the movement.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local AdminController = {}

local FLY_SPEED = 90

local flyVelocity: LinearVelocity? = nil
local flyAlign: AlignOrientation? = nil
local flyAttachment: Attachment? = nil

local function rootAndHumanoid(): (BasePart?, Humanoid?)
	local c = player.Character
	if not c then
		return nil, nil
	end
	return c:FindFirstChild("HumanoidRootPart") :: BasePart?, c:FindFirstChildOfClass("Humanoid")
end

local function stopFly()
	if flyVelocity then
		flyVelocity:Destroy()
		flyVelocity = nil
	end
	if flyAlign then
		flyAlign:Destroy()
		flyAlign = nil
	end
	if flyAttachment then
		flyAttachment:Destroy()
		flyAttachment = nil
	end
	local _, hum = rootAndHumanoid()
	if hum then
		hum.PlatformStand = false
	end
end

local function startFly()
	local root, hum = rootAndHumanoid()
	if not root or not hum then
		return
	end
	stopFly()
	local att = Instance.new("Attachment")
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = math.huge
	lv.VectorVelocity = Vector3.zero
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = 30
	ao.Parent = root
	flyAttachment, flyVelocity, flyAlign = att, lv, ao
	hum.PlatformStand = true
end

RunService.RenderStepped:Connect(function()
	local wantFly = player:GetAttribute("AdminFly") == true
	if wantFly and not flyVelocity then
		startFly()
	elseif not wantFly and flyVelocity then
		stopFly()
	end
	if flyVelocity and flyAlign then
		local camera = Workspace.CurrentCamera
		local _, hum = rootAndHumanoid()
		local move = if hum then hum.MoveDirection else Vector3.zero
		local look = camera.CFrame.LookVector
		local dir = Vector3.zero
		if move.Magnitude > 0.05 then
			-- follow the camera pitch so you fly where you look
			local flat = Vector3.new(look.X, 0, look.Z)
			local forwardAmount = if flat.Magnitude > 0 then move:Dot(flat.Unit) else 0
			dir = move + Vector3.new(0, look.Y * forwardAmount, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			dir += Vector3.yAxis
		elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			dir -= Vector3.yAxis
		end
		local fast = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		flyVelocity.VectorVelocity = if dir.Magnitude > 0
			then dir.Unit * FLY_SPEED * (if fast then 3 else 1)
			else Vector3.zero
		flyAlign.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(look.X, 0, look.Z) + Vector3.new(0, 0, 1e-3))
	end
end)

RunService.Stepped:Connect(function()
	if player:GetAttribute("AdminNoclip") ~= true then
		return
	end
	local c = player.Character
	if c then
		for _, d in c:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
			end
		end
	end
end)

player.CharacterAdded:Connect(function()
	flyVelocity, flyAlign, flyAttachment = nil, nil, nil
end)

-- F toggles fly for admins (asks the server, which checks the role).
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.F then
		return
	end
	if (player:GetAttribute("Role") or "") == "" then
		return
	end
	local Net = require(script.Parent.Parent.Net)
	Net.Request("Admin.Do", "fly", {})
end)

return AdminController
