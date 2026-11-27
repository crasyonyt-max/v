--!strict
-- 📝 Bewerbungen (Config.Applications, testing server first): apply as Admin or as
-- Official Content Creator. 7-12 sentences about: why, what you would do, when you
-- are online, your age, how you feel about the game. Your applications and the answers
-- are listed below (the answer also comes as a ChatsApp message from the admin team).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Make = require(script.Parent.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.Parent.UI.Notify)
local Net = require(script.Parent.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Parent.Store)
local Phone = require(script.Parent.Parent.Phone)

local New, T = Make.New, Make.Theme

if not Config.On(Config.Applications) then
	return nil
end

local ROLES = {
	{ id = "admin", icon = "🛡️", name = "Admin" },
	{ id = "creator", icon = "🎬", name = "Official Content Creator" },
}

-- the same counting as the server: runs of text ending in . ! or ?
local function sentences(text: string): number
	local n = 0
	for chunk in string.gmatch(text, "[^%.!%?]+[%.!%?]+") do
		if string.find(chunk, "%a") then
			n += 1
		end
	end
	return n
end

Phone.Register({
	id = "applications",
	icon = "📝",
	color = Color3.fromRGB(120, 70, 200),
	order = 10,
	build = function(container, arg)
		local root = Make.Scroll({ Parent = container })
		local role = if typeof(arg) == "string" then arg else nil

		if not role then
			Make.Label(Store.T("apply_title"), 16, T.text, T.black, { LayoutOrder = 1, Parent = root })
			for i, r in ROLES do
				Make.Button(r.icon .. " " .. r.name, Color3.fromRGB(120, 70, 200), function()
					Phone.Replace("applications", r.id)
				end, { LayoutOrder = 1 + i, Size = UDim2.new(1, 0, 0, 44), Parent = root })
			end
			-- my applications
			local mine = Make.Card({ LayoutOrder = 10, Parent = root })
			Make.Label(Store.T("apply_mine"), 13, T.sub, T.bold, { Parent = mine })
			task.spawn(function()
				local r = Net.Request("Apply.Mine")
				if not r.ok or not mine.Parent then
					return
				end
				if #r.list == 0 then
					Make.Label(Store.T("apply_none"), 12, T.sub, T.font, { Parent = mine })
				end
				for _, a in r.list do
					local roleName = if a.role == "admin" then "Admin" else "Official Content Creator"
					local status = Store.T("apply_status_" .. tostring(a.status))
					Make.Label(
						("%s · %s · %s"):format(roleName, os.date("%d.%m.%Y", a.t) :: string, status)
							.. (if a.reason then "\n" .. Store.T("apply_reason", a.reason) else ""),
						12,
						if a.status == "accepted"
							then Color3.fromRGB(80, 220, 120)
							elseif a.status == "declined" then Color3.fromRGB(240, 90, 90)
							else T.text,
						T.font,
						{ Parent = mine }
					)
				end
			end)
			return nil
		end

		-- the form
		local info = ROLES[1]
		for _, r in ROLES do
			if r.id == role then
				info = r
			end
		end
		Make.Label(info.icon .. " " .. info.name, 16, T.text, T.black, { LayoutOrder = 1, Parent = root })
		Make.Label(Store.T("apply_howto"), 12, T.sub, T.font, { LayoutOrder = 2, Parent = root })
		for i, key in
			{
				if role == "creator" then "apply_q_why_creator" else "apply_q_why",
				if role == "creator" then "apply_q_do_creator" else "apply_q_do",
				"apply_q_online",
				"apply_q_age",
				"apply_q_feel",
			}
		do
			Make.Label("• " .. Store.T(key), 12, T.text, T.font, { LayoutOrder = 2 + i, Parent = root })
		end
		local box = Make.TextBox(Store.T("apply_placeholder"), {
			LayoutOrder = 10,
			Size = UDim2.new(1, 0, 0, 200),
			MultiLine = true,
			TextWrapped = true,
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = root,
		})
		local counter = Make.Label("", 12, T.sub, T.bold, { LayoutOrder = 11, Parent = root })
		local function count()
			local n = sentences(box.Text)
			local ok = n >= 7 and n <= 12
			counter.Text = Store.T("apply_count", n)
			counter.TextColor3 = if ok then Color3.fromRGB(80, 220, 120) else Color3.fromRGB(240, 160, 60)
		end
		box:GetPropertyChangedSignal("Text"):Connect(count)
		count()
		Make.Button("📨 " .. Store.T("apply_send"), Color3.fromRGB(120, 70, 200), function()
			local text = box.Text
			task.spawn(function()
				local r = Net.Request("Apply.Submit", role, text)
				if r.ok then
					Notify.Show(Store.T("apply_sent"), false, 6)
					Phone.Replace("applications", nil)
				else
					Notify.Error(r.err)
				end
			end)
		end, { LayoutOrder = 12, Size = UDim2.new(1, 0, 0, 40), Parent = root })
		Make.Button("← " .. Store.T("back"), T.panel, function()
			Phone.Replace("applications", nil)
		end, { LayoutOrder = 13, Parent = root })
		local _ = New
		return nil
	end,
})

return nil
