--!strict
-- News app: posts from the Game Admins (written in the Admin app), newest first.

local Make = require(script.Parent.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.Parent.UI.Notify)
local Net = require(script.Parent.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Parent.Store)
local Phone = require(script.Parent.Parent.Phone)

local T = Make.Theme

local posts: { any } = {}
local loaded = false
local current: ((any) -> ())? = nil

local function load()
	local r = Net.Request("News.List")
	if r.ok then
		posts = r.posts or {}
		loaded = true
	end
end

-- Shows the posts in `root`; `onDelete` adds a delete button (Admin app).
local function renderPosts(root: Instance, onDelete: ((string) -> ())?, firstOrder: number?)
	local base = firstOrder or 0
	if #posts == 0 then
		Make.Label(Store.T("no_news"), 13, T.sub, T.font, { LayoutOrder = base + 1, Parent = root })
		return
	end
	for i, p in posts do
		local card = Make.Card({ LayoutOrder = base + i, Parent = root })
		Make.Label(tostring(p.title), 16, T.text, T.black, { Parent = card })
		Make.Label(
			string.format("%s  ·  %s", os.date("%d.%m.%Y %H:%M", tonumber(p.t) or 0), tostring(p.author)),
			11,
			T.sub,
			T.font,
			{ Parent = card }
		)
		Make.Label(tostring(p.text), 13, T.text, T.font, { Parent = card })
		if onDelete then
			local id = tostring(p.id)
			Make.Button("🗑 " .. Store.T("delete"), T.bad, function()
				onDelete(id)
			end, { Parent = card })
		end
	end
end

Net.On("News", function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	posts = if typeof(payload.posts) == "table" then payload.posts else posts
	loaded = true
	if typeof(payload.new) == "table" then
		Notify.Show("📰 " .. tostring(payload.new.title), false, 6)
	end
	if current then
		current(nil)
	end
end)

Phone.Register({
	id = "news",
	icon = "📰",
	color = Color3.fromRGB(200, 60, 40),
	order = 8,
	build = function(container)
		local root = Make.Scroll({ Parent = container })
		local function render()
			Make.Clear(root)
			Make.Label("📰 " .. Store.T("app_news"), 18, T.text, T.black, { LayoutOrder = 0, Parent = root })
			renderPosts(root, nil, 0)
		end
		current = render
		container.Destroying:Connect(function()
			if current == render then
				current = nil
			end
		end)
		render()
		if not loaded then
			task.spawn(function()
				load()
				if current == render then
					render()
				end
			end)
		end
		return nil
	end,
})

return {
	Load = load,
	RenderPosts = renderPosts,
	Posts = function()
		return posts
	end,
}
