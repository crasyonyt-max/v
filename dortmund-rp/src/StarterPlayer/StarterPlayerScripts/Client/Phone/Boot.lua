--!strict
-- Phone boot animations.
-- NVDR P1: recreation of the official boot video – two green light streaks orbit,
-- the ring around "NVDR" lights up, the glow pulses and "P1" fades in.
-- Built entirely from UI (no video upload needed). Tap to skip.

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Make = require(script.Parent.Parent.UI.Make)

local New = Make.New

local Boot = {}

local GREEN = Color3.fromRGB(57, 255, 20)
local TILT = -10 -- ring tilt in degrees (matches the logo)

local function tween(
	obj: Instance,
	t: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
)
	local tw = TweenService:Create(
		obj,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	tw:Play()
	return tw
end

-- Plays the NVDR boot inside `screen`. Yields until finished (or skipped).
function Boot.NVDR(screen: Frame)
	local overlay = New("TextButton", {
		Name = "Boot",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = screen,
	})

	local logo = New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromScale(0.86, 0.2),
		ZIndex = 51,
		Parent = overlay,
	}, { New("UIAspectRatioConstraint", { AspectRatio = 2.4 }) })

	local function ring(thickness: number, transparency: number): (Frame, UIStroke)
		local f = New("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.56),
			Size = UDim2.fromScale(1, 0.42),
			Rotation = TILT,
			ZIndex = 52,
			Parent = logo,
		}, { New("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		local stroke = New("UIStroke", {
			Color = GREEN,
			Thickness = thickness,
			Transparency = transparency,
			Parent = f,
		})
		-- bright at the lower left, fading towards the upper right (like the logo swoosh)
		New("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.55, 0.05),
				NumberSequenceKeypoint.new(0.8, 0.6),
				NumberSequenceKeypoint.new(1, 0.15),
			}),
			Rotation = 20,
			Parent = stroke,
		})
		return f, stroke
	end

	local glowFrame, glow = ring(10, 1)
	local ringFrame, ringStroke = ring(3, 1)
	local _ = glowFrame
	local _ = ringFrame

	local word = New("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.5),
		RichText = true,
		Text = '<font color="#F2F2F2">N</font><font color="#39FF14">V</font><font color="#F2F2F2">DR</font>',
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextTransparency = 1,
		ZIndex = 54,
		Parent = logo,
	})
	local wordScale = New("UIScale", { Scale = 0.88, Parent = word })
	New("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 205, 200)),
		Rotation = 90,
		Parent = word,
	})

	local p1 = New("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromScale(0.2, 0.045),
		Text = "P1",
		TextScaled = true,
		Font = Enum.Font.GothamMedium,
		TextColor3 = Color3.fromRGB(205, 205, 205),
		TextTransparency = 1,
		ZIndex = 54,
		Parent = overlay,
	})

	-- optional boot sound
	if Config.Sounds.NvdrBoot ~= 0 then
		local s =
			New("Sound", { SoundId = "rbxassetid://" .. Config.Sounds.NvdrBoot, Volume = 0.8, Parent = SoundService })
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
	end

	local skipped = false
	overlay.Activated:Connect(function()
		skipped = true
	end)

	-- Phase 1: two comets travel along the ellipse leaving fading trails.
	local trail: { Frame } = {}
	local start = os.clock()
	local DURATION = 1.4
	local theta = math.rad(TILT)
	local function pointOnRing(a: number): Vector2
		local size = logo.AbsoluteSize
		local rx = size.X * 0.5
		local ry = size.Y * 0.21
		local x = rx * math.cos(a)
		local y = ry * math.sin(a)
		local xr = x * math.cos(theta) - y * math.sin(theta)
		local yr = x * math.sin(theta) + y * math.cos(theta)
		return Vector2.new(size.X * 0.5 + xr, size.Y * 0.56 + yr)
	end
	local comets = {}
	for i = 1, 2 do
		comets[i] = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(7, 7),
			BackgroundColor3 = Color3.fromRGB(200, 255, 190),
			ZIndex = 56,
			Parent = logo,
		}, {
			New("UICorner", { CornerRadius = UDim.new(1, 0) }),
			New("UIStroke", { Color = GREEN, Thickness = 3, Transparency = 0.3 }),
		})
	end
	local conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / DURATION, 0, 1)
		local eased = 1 - (1 - t) ^ 2
		for i, comet in comets do
			-- start on the right side, sweep half a revolution each
			local a = (if i == 1 then -0.35 else math.pi - 0.35) + eased * math.pi * 1.05
			local p = pointOnRing(a)
			comet.Position = UDim2.fromOffset(p.X, p.Y)
			local dot = New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(p.X, p.Y),
				Size = UDim2.fromOffset(4, 4),
				BackgroundColor3 = GREEN,
				BorderSizePixel = 0,
				ZIndex = 55,
				Parent = logo,
			}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			table.insert(trail, dot)
			tween(dot, 0.45, { BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 1) })
		end
	end)

	local function waitOrSkip(seconds: number)
		local untilTime = os.clock() + seconds
		while os.clock() < untilTime and not skipped do
			task.wait()
		end
	end

	waitOrSkip(DURATION)
	conn:Disconnect()
	for _, comet in comets do
		comet:Destroy()
	end

	-- Phase 2: ring lights up, word appears.
	if not skipped then
		tween(ringStroke, 0.45, { Transparency = 0 })
		tween(glow, 0.6, { Transparency = 0.75 })
		waitOrSkip(0.15)
		tween(word, 0.6, { TextTransparency = 0 })
		tween(wordScale, 0.7, { Scale = 1 }, Enum.EasingStyle.Back)
		waitOrSkip(0.8)
	end

	-- Phase 3: glow pulse + P1.
	if not skipped then
		tween(glow, 0.35, { Thickness = 16, Transparency = 0.55 }, Enum.EasingStyle.Sine)
		waitOrSkip(0.35)
		tween(glow, 0.6, { Thickness = 10, Transparency = 0.78 }, Enum.EasingStyle.Sine)
		tween(p1, 0.6, { TextTransparency = 0 })
		waitOrSkip(1.6)
	end

	for _, d in trail do
		d:Destroy()
	end
	-- Fade out.
	tween(overlay, 0.35, { BackgroundTransparency = 1 })
	tween(word, 0.3, { TextTransparency = 1 })
	tween(p1, 0.3, { TextTransparency = 1 })
	tween(ringStroke, 0.3, { Transparency = 1 })
	tween(glow, 0.3, { Transparency = 1 })
	task.wait(0.36)
	overlay:Destroy()
end

-- Generic short boot for every other phone: brand name fades in and out.
function Boot.Simple(screen: Frame, brand: string, accent: Color3)
	local overlay = New("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = screen,
	})
	local label = New("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.7, 0.08),
		Text = brand,
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = accent,
		TextTransparency = 1,
		ZIndex = 51,
		Parent = overlay,
	})
	tween(label, 0.4, { TextTransparency = 0 })
	task.wait(0.9)
	tween(overlay, 0.3, { BackgroundTransparency = 1 })
	tween(label, 0.3, { TextTransparency = 1 })
	task.wait(0.32)
	overlay:Destroy()
end

return Boot
