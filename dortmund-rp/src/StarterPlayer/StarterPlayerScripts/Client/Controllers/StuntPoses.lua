--!strict
-- Motorbike stunt poses: one arm or both arms up. The server puts the "BikeHands"
-- attribute on the rider's character; every client raises that character's arms.

local Players = game:GetService("Players")

local StuntPoses = {}

-- joint -> original C0, per character
local saved: { [Model]: { [Motor6D]: CFrame } } = {}
local applied: { [Model]: string } = {}

-- the joints and how to swing each arm up (R15 and R6)
local ARMS = {
	right = {
		{ "RightUpperArm", "RightShoulder", CFrame.Angles(math.rad(155), 0, math.rad(-12)) },
		{ "Torso", "Right Shoulder", CFrame.Angles(0, 0, math.rad(155)) },
	},
	left = {
		{ "LeftUpperArm", "LeftShoulder", CFrame.Angles(math.rad(155), 0, math.rad(12)) },
		{ "Torso", "Left Shoulder", CFrame.Angles(0, 0, math.rad(-155)) },
	},
}

local function joint(character: Model, partName: string, jointName: string): Motor6D?
	local p = character:FindFirstChild(partName)
	local j = p and p:FindFirstChild(jointName)
	return if j and j:IsA("Motor6D") then j else nil
end

local function restore(character: Model)
	for j, c0 in saved[character] or {} do
		if j.Parent then
			j.C0 = c0
		end
	end
	saved[character] = nil
	applied[character] = nil
end

local function raise(character: Model, side: string)
	saved[character] = saved[character] or {}
	for _, spec in ARMS[side] do
		local j = joint(character, spec[1], spec[2])
		if j then
			local store = saved[character] :: { [Motor6D]: CFrame }
			store[j] = store[j] or j.C0
			j.C0 = store[j] * spec[3]
		end
	end
end

local function update(character: Model)
	local hum = character:FindFirstChildOfClass("Humanoid")
	local mode = character:GetAttribute("BikeHands")
	if typeof(mode) ~= "string" or not hum or not hum.Sit then
		mode = ""
	end
	if (applied[character] or "") == mode then
		return
	end
	restore(character)
	if mode == "OneHand" then
		raise(character, "right")
	elseif mode == "NoHands" then
		raise(character, "right")
		raise(character, "left")
	end
	applied[character] = if mode == "" then nil else mode :: string
end

task.spawn(function()
	while true do
		for _, p in Players:GetPlayers() do
			local c = p.Character
			if c then
				update(c)
			end
		end
		for c in applied do
			if not c.Parent then
				saved[c], applied[c] = nil, nil
			end
		end
		task.wait(0.15)
	end
end)

return StuntPoses
