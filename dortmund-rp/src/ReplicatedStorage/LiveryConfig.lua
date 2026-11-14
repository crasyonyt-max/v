--[[
	LiveryConfig (ReplicatedStorage)

	Reusable livery presets. A job vehicle in VehicleConfig names a preset and
	only lists what it changes, e.g. { Preset = "POLICE", Lettering = "AUTOBAHNPOLIZEI" }.

	Preset fields:
	  Colors            { Body, Stripe, Accent } -> paints parts tagged with that name
	  Lettering         text on parts tagged "Lettering" (false = no lettering)
	  SecondaryLettering  text on Lettering parts with attribute LetteringSlot = "Secondary"
	  LetteringColor    text color
	  LightType         "none" | "blue" | "orange" | "hidden_blue"
	  Inherit           name of another preset to start from
	  TrailerPresets    list of preset names; a random one paints the model's "Trailer"

	A Stripe or Accent color that is left out uses the Body color.
	No logos or symbols anywhere: everything is plain text lettering.
]]

local hex = Color3.fromHex

local LiveryConfig = {}

-- Part tags that receive colors. Lettering is handled separately.
LiveryConfig.ColorSlots = { "Body", "Stripe", "Accent" }

-- Slots players may change when repainting their own cars.
LiveryConfig.RepaintableSlots = { "Body", "Stripe", "Accent" }

LiveryConfig.LightTypes = { none = true, blue = true, orange = true, red = true, hidden_blue = true }
LiveryConfig.LightColors = {
	blue = hex("#1E6BFF"),
	orange = hex("#FF8C00"),
	red = hex("#FF1E1E"), -- admin cars
}

LiveryConfig.Presets = {
	-- Emergency services --------------------------------------------------
	POLICE = {
		Colors = { Body = hex("#C0C4C8"), Accent = hex("#1F4E9C"), Stripe = hex("#FFFFFF") },
		Lettering = "POLIZEI",
		LetteringColor = hex("#1F4E9C"),
		LightType = "blue",
	},
	POLICE_UNMARKED = {
		Colors = { Body = hex("#3A3D42"), Accent = hex("#3A3D42"), Stripe = hex("#3A3D42") },
		Lettering = false,
		LightType = "hidden_blue",
	},
	FIRE = {
		Colors = { Body = hex("#AF2B1E"), Stripe = hex("#FFFFFF") },
		Lettering = "FEUERWEHR DORTMUND",
		LetteringColor = hex("#FFFFFF"),
		LightType = "blue",
	},
	AIRPORT_FIRE = {
		Colors = { Body = hex("#C8E600"), Stripe = hex("#AF2B1E") },
		Lettering = "FLUGHAFEN FEUERWEHR",
		LetteringColor = hex("#AF2B1E"),
		LightType = "blue",
	},
	EMS = {
		Colors = { Body = hex("#F4F4F4"), Accent = hex("#EDFF21"), Stripe = hex("#C1121F") },
		Lettering = "RETTUNGSDIENST",
		SecondaryLettering = "DRH", -- organisation name as text, no symbol / no red cross
		LetteringColor = hex("#C1121F"),
		LightType = "blue",
	},
	NOTARZT = {
		Inherit = "EMS",
		Lettering = "NOTARZT",
	},

	-- Public transport ----------------------------------------------------
	BUS = {
		Colors = { Body = hex("#F4F4F4"), Accent = hex("#0B6E8A"), Stripe = hex("#F2B705") },
		Lettering = "STADTBUS DORTMUND",
		LetteringColor = hex("#0B6E8A"),
		LightType = "none",
	},

	-- Services ------------------------------------------------------------
	ADMC = {
		Colors = { Body = hex("#F5C400"), Stripe = hex("#111111") },
		Lettering = "ADMC",
		LetteringColor = hex("#111111"),
		LightType = "orange",
	},
	DXL = {
		Colors = { Body = hex("#F2C200"), Accent = hex("#1B2A6B") },
		Lettering = "DXL",
		LetteringColor = hex("#1B2A6B"),
		LightType = "none",
	},
	LKW = {
		Colors = { Body = hex("#FFFFFF") }, -- cab
		Lettering = false,
		LightType = "none",
		TrailerPresets = { "LINDL", "ALDA", "REWO", "IKORA" },
	},

	-- Admin cars (Dortmund RP): orange with black, red sirens ------------------
	ADMIN = {
		Colors = { Body = hex("#FF7300"), Stripe = hex("#141414"), Accent = hex("#141414") },
		Lettering = "ADMIN",
		LetteringColor = hex("#141414"),
		LightType = "red",
	},

	-- Supermarket trailer liveries (own colors, not the real brands') ------
	LINDL = {
		Colors = { Body = hex("#FFFFFF"), Stripe = hex("#1A8C7A"), Accent = hex("#1A8C7A") },
		Lettering = "LINDL",
		LetteringColor = hex("#1A8C7A"),
	},
	ALDA = {
		Colors = { Body = hex("#5B2A86"), Stripe = hex("#F2E6D0"), Accent = hex("#F2E6D0") },
		Lettering = "ALDA",
		LetteringColor = hex("#F2E6D0"),
	},
	REWO = {
		Colors = { Body = hex("#1F5D3A"), Stripe = hex("#F5F1E6"), Accent = hex("#F5F1E6") },
		Lettering = "REWO",
		LetteringColor = hex("#F5F1E6"),
	},
	IKORA = {
		Colors = { Body = hex("#2B2B2B"), Stripe = hex("#8BC34A"), Accent = hex("#8BC34A") },
		Lettering = "IKORA",
		LetteringColor = hex("#8BC34A"),
	},
}

-- Factory paints for dealership, gamepass, starter and admin cars.
-- Two-tone paints use Accent for the second color.
LiveryConfig.Paints = {
	White = { Body = hex("#F2F2F2") },
	Red = { Body = hex("#B3121B") },
	Yellow = { Body = hex("#F2C318") },
	Silver = { Body = hex("#C0C4C8") },
	Blue = { Body = hex("#1E4FA3") },
	DarkBlue = { Body = hex("#1A2540") },
	LightBlue = { Body = hex("#8DB8E0") },
	FrozenBlue = { Body = hex("#7FB6D9") },
	Grey = { Body = hex("#6E7378") },
	Green = { Body = hex("#2E6B3A") },
	DarkGreen = { Body = hex("#1E3B2A") },
	RacingGreen = { Body = hex("#004225") },
	OliveGreen = { Body = hex("#5B6236") },
	ArmyGreen = { Body = hex("#4B5320") },
	Black = { Body = hex("#141414") },
	MatteBlack = { Body = hex("#1E1E1E") },
	Orange = { Body = hex("#E8641B") },
	PapayaOrange = { Body = hex("#FF7A1A") },
	BlackSilver = { Body = hex("#141414"), Accent = hex("#C0C4C8") },
	BlueBlack = { Body = hex("#1E3F8C"), Accent = hex("#141414") },
	CarbonSilver = { Body = hex("#1C1C1E"), Accent = hex("#C0C4C8") },
	CopperGrey = { Body = hex("#B87333"), Accent = hex("#6E7378") },
	GreyRed = { Body = hex("#6E7378"), Accent = hex("#B3121B") },
	OrangeBlack = { Body = hex("#E8641B"), Accent = hex("#141414") },
	CarbonOrange = { Body = hex("#151515"), Accent = hex("#FF6A00") },
}

local function copy(t)
	local out = {}
	for k, v in pairs(t or {}) do
		out[k] = v
	end
	return out
end

-- Builds a full livery from a preset (following Inherit) plus overrides.
-- Returns nil and an error message if the preset doesn't exist.
function LiveryConfig.Resolve(presetName, overrides)
	local chain = {}
	local name = presetName
	while name do
		local preset = LiveryConfig.Presets[name]
		if not preset then
			return nil, ("unknown livery preset %q"):format(tostring(name))
		end
		if #chain > 10 then
			return nil, "livery preset Inherit loop at " .. tostring(name)
		end
		table.insert(chain, 1, preset)
		name = preset.Inherit
	end
	if overrides then
		table.insert(chain, overrides)
	end

	local livery = { Preset = presetName, Colors = {}, Lettering = false }
	for _, layer in ipairs(chain) do
		for k, v in pairs(layer) do
			if k == "Colors" then
				for slot, color in pairs(v) do
					livery.Colors[slot] = color
				end
			elseif k ~= "Inherit" and k ~= "Preset" then
				livery[k] = v
			end
		end
	end
	return livery
end

-- Livery for a plain painted car (no lettering).
function LiveryConfig.FromPaint(paintName)
	local paint = LiveryConfig.Paints[paintName]
	if not paint then
		return nil, ("unknown paint %q"):format(tostring(paintName))
	end
	return { Paint = paintName, Colors = copy(paint), Lettering = false }
end

return LiveryConfig
