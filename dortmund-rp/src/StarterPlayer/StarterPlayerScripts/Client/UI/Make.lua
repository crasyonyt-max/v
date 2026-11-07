--!strict
-- Tiny UI construction helpers + the shared theme.

local Make = {}

Make.Theme = {
	bg = Color3.fromRGB(18, 19, 22),
	panel = Color3.fromRGB(30, 32, 37),
	card = Color3.fromRGB(42, 45, 52),
	text = Color3.fromRGB(240, 240, 240),
	sub = Color3.fromRGB(165, 168, 175),
	accent = Color3.fromRGB(0, 120, 255),
	good = Color3.fromRGB(40, 180, 90),
	bad = Color3.fromRGB(220, 60, 60),
	warn = Color3.fromRGB(240, 170, 30),
	font = Enum.Font.Gotham,
	bold = Enum.Font.GothamBold,
	black = Enum.Font.GothamBlack,
}
local T = Make.Theme

function Make.New(class: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(class)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local New = Make.New

function Make.Corner(radius: number?): UICorner
	return New("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function Make.Stroke(color: Color3, thickness: number?, transparency: number?): UIStroke
	return New("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Make.Padding(px: number): UIPadding
	local u = UDim.new(0, px)
	return New("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function Make.List(padding: number?, horizontal: boolean?): UIListLayout
	return New("UIListLayout", {
		Padding = UDim.new(0, padding or 6),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})
end

function Make.Label(text: string, size: number?, color: Color3?, font: Enum.Font?, props: { [string]: any }?): TextLabel
	local p: { [string]: any } = {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size or 14,
		TextColor3 = color or T.text,
		Font = font or T.font,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, (size or 14) + 6),
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	return New("TextLabel", p)
end

function Make.Button(text: string, color: Color3?, onClick: () -> (), props: { [string]: any }?): TextButton
	local p: { [string]: any } = {
		Text = text,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		Font = T.bold,
		BackgroundColor3 = color or T.accent,
		AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, 36),
		TextWrapped = true,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	local b = New("TextButton", p, { Make.Corner(8) })
	local busy = false
	b.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			local ok, err = pcall(onClick)
			if not ok then
				warn(err)
			end
			busy = false
		end)
	end)
	return b
end

function Make.TextBox(placeholder: string, props: { [string]: any }?): TextBox
	local p: { [string]: any } = {
		PlaceholderText = placeholder,
		Text = "",
		TextSize = 14,
		TextColor3 = T.text,
		PlaceholderColor3 = T.sub,
		Font = T.font,
		BackgroundColor3 = T.card,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, 0, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	return New("TextBox", p, { Make.Corner(8), Make.Padding(8) })
end

-- Vertical scrolling list that grows with its content.
function Make.Scroll(props: { [string]: any }?): ScrollingFrame
	local p: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	local s = New("ScrollingFrame", p, { Make.List(6), Make.Padding(2) })
	return s
end

-- A rounded card with automatic height.
function Make.Card(props: { [string]: any }?, children: { Instance }?): Frame
	local p: { [string]: any } = {
		BackgroundColor3 = T.card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	local kids: { Instance } = { Make.Corner(10), Make.Padding(10), Make.List(6) }
	if children then
		for _, c in children do
			table.insert(kids, c)
		end
	end
	return New("Frame", p, kids)
end

-- A card that is also a button.
function Make.CardButton(props: { [string]: any }?, children: { Instance }?, onClick: () -> ()): TextButton
	local p: { [string]: any } = {
		BackgroundColor3 = T.card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		AutoButtonColor = true,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	local kids: { Instance } = { Make.Corner(10), Make.Padding(10), Make.List(4) }
	if children then
		for _, c in children do
			table.insert(kids, c)
		end
	end
	local b = New("TextButton", p, kids)
	b.Activated:Connect(onClick)
	return b
end

function Make.Row(children: { Instance }, height: number?): Frame
	local kids: { Instance } = { Make.List(6, true) }
	for _, c in children do
		table.insert(kids, c)
	end
	return New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height or 36) }, kids)
end

function Make.Clear(container: Instance)
	for _, c in container:GetChildren() do
		if
			not c:IsA("UIListLayout")
			and not c:IsA("UIPadding")
			and not c:IsA("UICorner")
			and not c:IsA("UIGridLayout")
			and not c:IsA("UIStroke")
		then
			c:Destroy()
		end
	end
end

return Make
