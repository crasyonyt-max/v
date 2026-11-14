--[[
	LiveryApplier (server only)

	Paints a vehicle model from its livery, using CollectionService tags on the
	model's parts:
	  "Body", "Stripe", "Accent"  get the livery's colors
	  "Lettering"                 text from the livery. It uses TextLabels already in the part,
	                              or creates SurfaceGuis on the faces listed in the part's
	                              "LetteringFaces" attribute (default "Left,Right").
	                              Attribute LetteringSlot = "Secondary" uses SecondaryLettering.
	  "EmergencyLight"            colored by LightType. Hidden for "none" and "hidden_blue"
	                              (the model attribute LightsHidden tells your light script).
	  "Extra" + attribute ExtraName   kept only if the vehicle lists that extra.

	A child Model named "Trailer" gets a random trailer preset if the livery has
	TrailerPresets (LKW).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LiveryConfig = require(ReplicatedStorage:WaitForChild("LiveryConfig"))

local LiveryApplier = {}

local DEFAULT_FACES = { Enum.NormalId.Left, Enum.NormalId.Right }

local function letteringFaces(part)
	local attr = part:GetAttribute("LetteringFaces")
	if type(attr) ~= "string" then
		return DEFAULT_FACES
	end
	local faces = {}
	for name in attr:gmatch("[^,%s]+") do
		for _, face in ipairs(Enum.NormalId:GetEnumItems()) do
			if face.Name == name then
				table.insert(faces, face)
			end
		end
	end
	return #faces > 0 and faces or DEFAULT_FACES
end

local function applyLettering(part, text, color)
	local labels = {}
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("TextLabel") then
			table.insert(labels, d)
		end
	end
	if not text or text == "" then
		for _, label in ipairs(labels) do
			label.Visible = false
		end
		return
	end
	if #labels == 0 then
		for _, face in ipairs(letteringFaces(part)) do
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Lettering" .. face.Name
			gui.Face = face
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 50
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.Font = Enum.Font.GothamBlack
			label.Parent = gui
			gui.Parent = part
			table.insert(labels, label)
		end
	end
	for _, label in ipairs(labels) do
		label.Text = text
		label.Visible = true
		if color then
			label.TextColor3 = color
		end
	end
end

-- Paints every tagged part under `container`, skipping anything inside `skip`.
local function paint(container, livery, skip)
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") and not (skip and d:IsDescendantOf(skip)) then
			for _, slot in ipairs(LiveryConfig.ColorSlots) do
				local color = livery.Colors[slot]
				if color and CollectionService:HasTag(d, slot) then
					d.Color = color
				end
			end
			if CollectionService:HasTag(d, "Lettering") then
				local secondary = d:GetAttribute("LetteringSlot") == "Secondary"
				applyLettering(d, secondary and livery.SecondaryLettering or livery.Lettering, livery.LetteringColor)
			end
		end
	end
end

local function applyLights(model, lightType)
	model:SetAttribute("LightType", lightType)
	model:SetAttribute("LightsHidden", lightType == "none" or lightType == "hidden_blue")
	local color = lightType == "orange" and LiveryConfig.LightColors.orange or LiveryConfig.LightColors.blue
	for _, d in ipairs(model:GetDescendants()) do
		if CollectionService:HasTag(d, "EmergencyLight") then
			local parts = d:IsA("BasePart") and { d } or {}
			for _, sub in ipairs(d:GetDescendants()) do
				if sub:IsA("BasePart") then
					table.insert(parts, sub)
				end
			end
			for _, part in ipairs(parts) do
				if part:GetAttribute("BaseTransparency") == nil then
					part:SetAttribute("BaseTransparency", part.Transparency)
				end
				part.Color = color
				part.Transparency = (lightType == "none" or lightType == "hidden_blue") and 1 or part:GetAttribute("BaseTransparency")
				for _, light in ipairs(part:GetChildren()) do
					if light:IsA("Light") then
						light.Color = color
						light.Enabled = false
					end
				end
			end
		end
	end
end

local function applyExtras(model, extras)
	local wanted = {}
	for _, name in ipairs(extras or {}) do
		wanted[name] = true
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d.Parent and CollectionService:HasTag(d, "Extra") and not wanted[d:GetAttribute("ExtraName")] then
			d:Destroy()
		end
	end
end

-- Paints a model with any livery table ({ Colors, Lettering, ... }).
function LiveryApplier.Apply(model, livery)
	paint(model, livery)
end

--[[
	Applies a VehicleConfig entry to a spawned model.
	customColors ({ Body = Color3, ... }) are only used when the vehicle is
	Repaintable. Job vehicles always keep their livery.
]]
function LiveryApplier.ApplyVehicle(model, vehicle, customColors)
	local livery = vehicle.Livery
	if customColors and vehicle.Repaintable then
		livery = table.clone(livery)
		livery.Colors = table.clone(vehicle.Livery.Colors)
		for _, slot in ipairs(LiveryConfig.RepaintableSlots) do
			if customColors[slot] then
				livery.Colors[slot] = customColors[slot]
			end
		end
	end

	local trailer = model:FindFirstChild("Trailer")
	paint(model, livery, trailer)

	if trailer then
		local presets = livery.TrailerPresets
		local trailerLivery = livery
		if presets and #presets > 0 then
			local chosen = model:GetAttribute("TrailerLivery")
			if not table.find(presets, chosen) then
				chosen = presets[math.random(1, #presets)]
			end
			local resolved, err = LiveryConfig.Resolve(chosen)
			if resolved then
				trailerLivery = resolved
				model:SetAttribute("TrailerLivery", chosen)
			else
				warn("[LiveryApplier] " .. tostring(err))
			end
		end
		paint(trailer, trailerLivery)
	end

	applyLights(model, vehicle.LightType)
	applyExtras(model, vehicle.Extras)
	model:SetAttribute("LiveryLocked", not vehicle.Repaintable)
end

return LiveryApplier
