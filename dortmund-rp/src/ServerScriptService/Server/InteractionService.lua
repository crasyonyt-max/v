--!strict
-- World interactions. Map parts with an "Interaction" attribute get a ProximityPrompt.
-- The server handles the trigger, so opening a shop is proof the player stood there.
-- Purchases re-check distance with Interaction.IsNear.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Remotes = require(script.Parent.Remotes)

local Interaction = {}

local TAG = "Interaction"
local handlers: { [string]: (Player, BasePart) -> () } = {}

-- Default: open a client UI named by the marker's "UI" attribute.
local function openUI(player: Player, marker: BasePart)
	Remotes.Push(player, "OpenUI", {
		ui = marker:GetAttribute("UI"),
		arg = marker:GetAttribute("Arg"),
	})
end

function Interaction.OnTrigger(kind: string, fn: (Player, BasePart) -> ())
	handlers[kind] = fn
end

-- Distance check for purchases and other location-bound actions.
function Interaction.IsNear(
	player: Player,
	kind: string,
	maxDistance: number?,
	attrName: string?,
	attrValue: any?
): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local limit = maxDistance or 25
	for _, marker in CollectionService:GetTagged(TAG) do
		if marker:IsA("BasePart") and marker:GetAttribute("Interaction") == kind then
			if attrName == nil or marker:GetAttribute(attrName) == attrValue then
				if (marker.Position - root.Position).Magnitude <= limit then
					return true
				end
			end
		end
	end
	return false
end

local function setup(marker: Instance)
	if not marker:IsA("BasePart") then
		return
	end
	local kind = marker:GetAttribute("Interaction")
	if typeof(kind) ~= "string" then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = tostring(marker:GetAttribute("ActionText") or "Öffnen")
	prompt.ObjectText = tostring(marker:GetAttribute("ObjectText") or "")
	prompt.HoldDuration = tonumber(marker:GetAttribute("Hold")) or 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = marker
	prompt.Triggered:Connect(function(player)
		if player.Parent ~= Players then
			return
		end
		local fn = handlers[kind] or openUI
		local ok, err = pcall(fn, player, marker)
		if not ok then
			warn("[Interaction] " .. kind .. ": " .. tostring(err))
		end
	end)
end

function Interaction.Start()
	for _, marker in CollectionService:GetTagged(TAG) do
		setup(marker)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(setup)
end

-- Helper for the map builder.
function Interaction.Mark(part: BasePart, kind: string, attrs: { [string]: any })
	part:SetAttribute("Interaction", kind)
	for k, v in attrs do
		part:SetAttribute(k, v)
	end
	CollectionService:AddTag(part, TAG)
end

return Interaction
