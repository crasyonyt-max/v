--!strict
-- The digital Personalausweis: front like the German ID card (photo, names,
-- "Joinday" instead of the birthday, Wohnort Dortmund, number, signature, MRZ),
-- back with all certificates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Certificates = require(ReplicatedStorage.Shared.Certificates)
local Make = require(script.Parent.Make)

local New, T = Make.New, Make.Theme

local IDCard = {}

local INK = Color3.fromRGB(25, 30, 45)
local LABEL = Color3.fromRGB(70, 80, 110)

local gui = New("ScreenGui", {
	Name = "IDCard",
	ResetOnSpawn = false,
	DisplayOrder = 45,
	Enabled = false,
	IgnoreGuiInset = true,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})
New("TextButton", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	Text = "",
	AutoButtonColor = false,
	Parent = gui,
}).Activated:Connect(function()
	gui.Enabled = false
end)
local holder = New("ScrollingFrame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 400, 0.9, 0),
	BackgroundTransparency = 1,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 4,
	Parent = gui,
}, { Make.List(10) })
local holderLayout = holder:FindFirstChildOfClass("UIListLayout") :: UIListLayout
holderLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local function text(
	parent: Instance,
	value: string,
	size: number,
	color: Color3,
	font: Enum.Font,
	props: { [string]: any }
): TextLabel
	local l = New("TextLabel", {
		BackgroundTransparency = 1,
		Text = value,
		TextSize = size,
		TextColor3 = color,
		Font = font,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Parent = parent,
	})
	for k, v in props do
		(l :: any)[k] = v
	end
	return l
end

local function field(parent: Instance, x: number, y: number, label: string, value: string, w: number?)
	text(parent, label, 8, LABEL, T.font, { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w or 200, 10) })
	text(
		parent,
		value,
		14,
		INK,
		T.bold,
		{ Position = UDim2.fromOffset(x, y + 10), Size = UDim2.fromOffset(w or 200, 17) }
	)
end

local function hex(c: Color3): string
	return c:ToHex()
end

local function mrz(s: string, n: number): string
	s = string.upper(s):gsub("[^A-Z0-9]", "<")
	if #s >= n then
		return string.sub(s, 1, n)
	end
	return s .. string.rep("<", n - #s)
end

-- card = IDService view; opts.onRemove(code) adds ✕ buttons (admin view)
function IDCard.Show(card: { [string]: any }, opts: { onRemove: ((string) -> ())?, title: string? }?)
	Make.Clear(holder)
	holder.CanvasPosition = Vector2.zero
	local o = opts or {}

	-- front ---------------------------------------------------------------------------
	local front = New("Frame", {
		LayoutOrder = 1,
		Size = UDim2.fromOffset(380, 240),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
		Parent = holder,
	}, {
		Make.Corner(14),
		Make.Stroke(Color3.fromRGB(150, 160, 175), 1),
		New("UIGradient", {
			Rotation = 25,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(214, 236, 226)),
				ColorSequenceKeypoint.new(0.45, Color3.fromRGB(236, 230, 240)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(246, 222, 222)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 232, 244)),
			}),
		}),
	})
	-- wavy security lines
	for i = 0, 5 do
		New("Frame", {
			Position = UDim2.fromOffset(-40, 60 + i * 26),
			Size = UDim2.fromOffset(480, 1),
			Rotation = -8 + i * 2,
			BackgroundColor3 = Color3.fromRGB(170, 190, 200),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Parent = front,
		})
	end
	-- black-red-gold strip
	for i, c in { Color3.fromRGB(20, 20, 20), Color3.fromRGB(221, 0, 0), Color3.fromRGB(255, 206, 0) } do
		New("Frame", {
			Position = UDim2.fromOffset(0, (i - 1) * 4),
			Size = UDim2.new(1, 0, 0, 4),
			BackgroundColor3 = c,
			BorderSizePixel = 0,
			Parent = front,
		})
	end
	text(
		front,
		"BUNDESREPUBLIK DEUTSCHLAND",
		13,
		INK,
		T.black,
		{ Position = UDim2.fromOffset(46, 16), Size = UDim2.fromOffset(260, 16) }
	)
	text(front, "PERSONALAUSWEIS · IDENTITY CARD · CARTE D'IDENTITÉ", 8, LABEL, T.bold, {
		Position = UDim2.fromOffset(46, 32),
		Size = UDim2.fromOffset(280, 12),
	})
	text(front, "🦅", 26, INK, T.font, { Position = UDim2.fromOffset(12, 14), Size = UDim2.fromOffset(32, 32) })
	text(front, tostring(card.number), 14, Color3.fromRGB(190, 30, 40), Enum.Font.Code, {
		Position = UDim2.fromOffset(270, 16),
		Size = UDim2.fromOffset(100, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	-- photo
	New("ImageLabel", {
		Position = UDim2.fromOffset(14, 52),
		Size = UDim2.fromOffset(92, 116),
		BackgroundColor3 = Color3.fromRGB(205, 215, 225),
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(card.userId) .. "&w=150&h=150",
		ScaleType = Enum.ScaleType.Crop,
		Parent = front,
	}, { Make.Corner(6) })
	field(front, 116, 50, "Name / Surname", string.upper(tostring(card.name)), 250)
	field(front, 116, 80, "Vornamen / Given names", tostring(card.display), 250)
	field(
		front,
		116,
		110,
		"Joinday / Date of first join",
		os.date("%d.%m.%Y", tonumber(card.joinday) or 0) :: string,
		130
	)
	field(front, 250, 110, "Staatsangehörigkeit", "DEUTSCH", 120)
	field(front, 116, 140, "Wohnort / Residence", string.upper(tostring(card.residence or "Dortmund")), 130)
	field(front, 250, 140, "Gültig bis / Expiry", "∞", 120)
	text(
		front,
		"Unterschrift / Signature",
		8,
		LABEL,
		T.font,
		{ Position = UDim2.fromOffset(14, 172), Size = UDim2.fromOffset(160, 10) }
	)
	text(front, tostring(card.display), 18, Color3.fromRGB(20, 40, 120), Enum.Font.Fondamento, {
		Position = UDim2.fromOffset(14, 180),
		Size = UDim2.fromOffset(200, 20),
	})
	-- machine readable zone
	local zone = New("Frame", {
		Position = UDim2.new(0, 0, 1, -34),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = front,
	})
	text(zone, "IDD<<" .. mrz(tostring(card.number), 9) .. "<<<<<<<<<<<<<<<<<<<<<<", 11, INK, Enum.Font.Code, {
		Position = UDim2.fromOffset(10, 3),
		Size = UDim2.new(1, -20, 0, 13),
	})
	text(zone, mrz(tostring(card.name) .. "<<" .. tostring(card.display), 40), 11, INK, Enum.Font.Code, {
		Position = UDim2.fromOffset(10, 17),
		Size = UDim2.new(1, -20, 0, 13),
	})

	-- back: certificates --------------------------------------------------------------
	local back = New("Frame", {
		LayoutOrder = 2,
		Size = UDim2.fromOffset(380, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(240, 242, 246),
		Parent = holder,
	}, { Make.Corner(14), Make.Padding(12), Make.List(6), Make.Stroke(Color3.fromRGB(150, 160, 175), 1) })
	text(back, "ZERTIFIKATE / CERTIFICATES", 12, INK, T.black, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 0 })
	local certs = card.certs or {}
	if #certs == 0 then
		text(
			back,
			"Keine Zertifikate / no certificates",
			12,
			LABEL,
			T.font,
			{ Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1 }
		)
	end
	for i, entry in certs do
		local cert = Certificates.ByCode[entry.code]
		if cert then
			local row = New("Frame", {
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundColor3 = cert.color,
			}, { Make.Corner(8) })
			row.Parent = back
			text(row, (if cert.owner then "👑 " else "✔ ") .. cert.name, 13, Color3.new(1, 1, 1), T.bold, {
				Position = UDim2.fromOffset(10, 4),
				Size = UDim2.new(1, -50, 0, 16),
			})
			text(
				row,
				('<font color="#%s">%s</font> · %s · %s'):format(
					hex(Color3.new(1, 1, 1)),
					cert.code,
					tostring(entry.by or "?"),
					os.date("%d.%m.%Y", tonumber(entry.t) or 0) :: string
				),
				10,
				Color3.fromRGB(240, 240, 240),
				Enum.Font.Code,
				{ Position = UDim2.fromOffset(10, 22), Size = UDim2.new(1, -50, 0, 14), RichText = true }
			)
			local onRemove = o.onRemove
			if onRemove then
				Make.Button("✕", Color3.fromRGB(30, 30, 30), function()
					onRemove(cert.code)
				end, {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -6, 0.5, 0),
					Size = UDim2.fromOffset(30, 28),
					TextSize = 13,
					Parent = row,
				})
			end
		end
	end
	text(back, "Ausgestellt von / Issued by: Emergency Dortmund · Stadt Dortmund", 9, LABEL, T.font, {
		Size = UDim2.new(1, 0, 0, 12),
		LayoutOrder = 999,
	})
	Make.Button("Schließen / Close", T.panel, function()
		gui.Enabled = false
	end, { LayoutOrder = 3, Size = UDim2.fromOffset(380, 34), Parent = holder })
	gui.Enabled = true
end

function IDCard.Hide()
	gui.Enabled = false
end

return IDCard
