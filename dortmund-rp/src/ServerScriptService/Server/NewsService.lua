--!strict
-- News for the phone's News app. Game Admins post and delete them in the Admin app
-- (see AdminService); they are saved and shared by every server.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)

local NewsService = {}

local MAX_POSTS = 30
local KEY = "posts"
local TOPIC = "News"

export type Post = { id: string, title: string, text: string, author: string, t: number }

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName .. "_News")
end)

local posts: { Post } = {} -- newest first

local function clean(list: any): { Post }
	local out = {}
	if typeof(list) == "table" then
		for _, p in list do
			if typeof(p) == "table" and typeof(p.id) == "string" and typeof(p.title) == "string" then
				table.insert(out, p)
			end
		end
	end
	return out
end

local function changed(notifyNew: Post?)
	Remotes.PushAll("News", { posts = posts, new = notifyNew })
end

local function reload()
	if not store then
		return
	end
	local ok, value = pcall(function()
		return (store :: DataStore):GetAsync(KEY)
	end)
	if ok then
		posts = clean(value)
	end
end

-- Runs `edit` on the saved list (atomic across servers) and tells everyone.
local function update(edit: ({ Post }) -> boolean): boolean
	local result: { Post }? = nil
	if store then
		local ok = pcall(function()
			(store :: DataStore):UpdateAsync(KEY, function(old: any)
				local list = clean(old)
				if not edit(list) then
					return nil
				end
				result = list
				return list
			end)
		end)
		if not ok then
			return false
		end
	else
		-- Studio without API access: keep it on this server only
		local list = table.clone(posts)
		if edit(list) then
			result = list
		end
	end
	if not result then
		return false
	end
	posts = result :: { Post }
	return true
end

function NewsService.List(): { Post }
	return posts
end

-- title/text must already be filtered.
function NewsService.Post(title: string, text: string, author: string): boolean
	local post: Post = {
		id = string.sub(HttpService:GenerateGUID(false), 1, 8),
		title = title,
		text = text,
		author = author,
		t = os.time(),
	}
	local ok = update(function(list)
		table.insert(list, 1, post)
		while #list > MAX_POSTS do
			table.remove(list)
		end
		return true
	end)
	if ok then
		changed(post)
		pcall(function()
			MessagingService:PublishAsync(TOPIC, { new = post, server = game.JobId })
		end)
	end
	return ok
end

function NewsService.Delete(id: string): boolean
	local ok = update(function(list)
		for i, p in list do
			if p.id == id then
				table.remove(list, i)
				return true
			end
		end
		return false
	end)
	if ok then
		changed(nil)
		pcall(function()
			MessagingService:PublishAsync(TOPIC, { server = game.JobId })
		end)
	end
	return ok
end

function NewsService.Start()
	task.spawn(reload)
	pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(message)
			local data = message.Data
			if typeof(data) == "table" and data.server == game.JobId then
				return -- our own post, already shown here
			end
			reload()
			changed(if typeof(data) == "table" and typeof(data.new) == "table" then data.new else nil)
		end)
	end)
	Remotes.Handle("News.List", function()
		return Remotes.Ok({ posts = posts })
	end, { rate = 10, needsData = false })
end

return NewsService
