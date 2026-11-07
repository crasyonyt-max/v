--!strict
-- One navigation marker with live distance (used by Jobs "Navi" and emergency calls).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Make = require(script.Parent.Make)

local New = Make.New

local Waypoint = {}

local current: Part? = nil
local conn: RBXScriptConnection? = nil

function Waypoint.Clear()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if current then
		current:Destroy()
		current = nil
	end
end

function Waypoint.Set(position: Vector3, title: string, color: Color3?)
	Waypoint.Clear()
	local anchor = New("Part", {
		Name = "Waypoint",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.one,
		Position = position + Vector3.new(0, 6, 0),
		Parent = Workspace,
	})
	local billboard = New("BillboardGui", {
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(160, 50),
		LightInfluence = 0,
		Parent = anchor,
	})
	local label = New("TextLabel", {
		BackgroundColor3 = color or Color3.fromRGB(0, 120, 255),
		BackgroundTransparency = 0.1,
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = title,
		Parent = billboard,
	}, { Make.Corner(8), Make.Padding(4) })
	current = anchor
	conn = RunService.Heartbeat:Connect(function()
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local d = (root.Position - position).Magnitude * 0.28
			label.Text = string.format(
				"%s\n%s",
				title,
				if d >= 1000 then string.format("%.1f km", d / 1000) else string.format("%d m", d)
			)
			if d < 8 then
				Waypoint.Clear()
			end
		end
	end)
end

return Waypoint
