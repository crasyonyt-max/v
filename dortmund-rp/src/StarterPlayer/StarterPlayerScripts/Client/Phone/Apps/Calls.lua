--!strict
-- Einsätze: open 110/112 calls for Police / Fire / Rettungsdienst / Notarzt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Jobs = require(ReplicatedStorage.Shared.Jobs)
local Make = require(script.Parent.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.Parent.UI.Notify)
local Waypoint = require(script.Parent.Parent.Parent.UI.Waypoint)
local Net = require(script.Parent.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Parent.Store)
local Phone = require(script.Parent.Parent.Phone)

local T = Make.Theme

local refreshOpen: (() -> ())? = nil

local function isEmergencyJob(state: { [string]: any }): boolean
	local job = Jobs.ById[state.job or ""]
	return job ~= nil and job.emergency
end

Phone.Register({
	id = "calls",
	icon = "🚨",
	color = Color3.fromRGB(200, 30, 30),
	order = 6,
	visible = isEmergencyJob,
	build = function(container)
		local root = Make.Scroll({ Parent = container })
		local function load()
			Make.Clear(root)
			if not isEmergencyJob(Store.Get()) then
				Make.Label(Store.T("not_emergency_job"), 13, T.sub, T.font, { Parent = root })
				return
			end
			local r = Net.Request("Call.List")
			if not r.ok then
				Notify.Error(r.err)
				return
			end
			if #r.calls == 0 then
				Make.Label(
					Store.T("no_calls"),
					13,
					T.sub,
					T.font,
					{ Parent = root, TextXAlignment = Enum.TextXAlignment.Center }
				)
			end
			for i, call in r.calls do
				local card = Make.Card({
					LayoutOrder = i,
					Parent = root,
					BackgroundColor3 = if call.mine then Color3.fromRGB(70, 25, 25) else T.card,
				})
				Make.Label(
					string.format("%s  ·  %s  ·  %s", call.number, call.callerName, os.date("%H:%M", call.created)),
					12,
					T.sub,
					T.bold,
					{ Parent = card }
				)
				Make.Label(call.text, 14, T.text, T.font, { Parent = card })
				if call.mine then
					Make.Row({
						Make.Button("🧭 " .. Store.T("navigate"), T.panel, function()
							Waypoint.Set(call.position, "🚨 " .. call.number, Color3.fromRGB(200, 30, 30))
						end, { Size = UDim2.new(0.5, -3, 1, 0) }),
						Make.Button(Store.T("complete"), T.good, function()
							local res = Net.Request("Call.Complete", call.id)
							if res.ok then
								Waypoint.Clear()
								load()
							else
								Notify.Error(res.err)
							end
						end, { Size = UDim2.new(0.5, -3, 1, 0) }),
					}, 34).Parent =
						card
				else
					Make.Button(Store.T("accept"), T.bad, function()
						local res = Net.Request("Call.Accept", call.id)
						if res.ok then
							Waypoint.Set(res.position, "🚨 " .. call.number, Color3.fromRGB(200, 30, 30))
							load()
						else
							Notify.Error(res.err)
						end
					end, { Parent = card })
				end
			end
		end
		load()
		refreshOpen = load
		root.Destroying:Connect(function()
			if refreshOpen == load then
				refreshOpen = nil
			end
		end)
		return nil
	end,
})

local function onCallEvent(call: any)
	if refreshOpen then
		refreshOpen()
	end
	return call
end

Net.On("CallNew", function(call)
	Notify.Show(Store.T("call_new", tostring(call.number), tostring(call.text)), false, 6)
	onCallEvent(call)
end)
Net.On("CallUpdate", onCallEvent)
Net.On("CallClosed", onCallEvent)

return nil
