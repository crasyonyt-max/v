--!strict
-- Jobs: current job, job XP, next vehicle unlock, navigate to stations, quit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Jobs = require(ReplicatedStorage.Shared.Jobs)
local Locations = require(ReplicatedStorage.Shared.Locations)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local Make = require(script.Parent.Parent.Parent.UI.Make)
local Notify = require(script.Parent.Parent.Parent.UI.Notify)
local Waypoint = require(script.Parent.Parent.Parent.UI.Waypoint)
local Net = require(script.Parent.Parent.Parent.Net)
local Store = require(script.Parent.Parent.Parent.Store)
local Phone = require(script.Parent.Parent.Phone)

local T = Make.Theme

local function findStation(jobId: string): Vector3?
	local loc = (Locations.Jobs :: any)[jobId]
	return if loc then Vector3.new(loc.marker[1], 0, loc.marker[2]) else nil
end

Phone.Register({
	id = "jobs",
	icon = "💼",
	color = Color3.fromRGB(150, 100, 50),
	order = 4,
	build = function(container)
		local root = Make.Scroll({ Parent = container })
		local function render(state: { [string]: any })
			Make.Clear(root)
			local lang = Store.Lang()
			local job = state.job or "Unemployed"
			local current = Make.Card({
				LayoutOrder = 1,
				Parent = root,
				BackgroundColor3 = (Jobs.ById[job] or Jobs.ById.Unemployed).color:Lerp(Color3.new(0, 0, 0), 0.5),
			})
			Make.Label(Store.T("current_job"), 12, T.sub, T.bold, { Parent = current })
			Make.Label(Jobs.Name(job, lang), 18, T.text, T.black, { Parent = current })
			if job ~= "Unemployed" then
				local xp = (state.jobXP or {})[job] or 0
				Make.Label(Store.T("job_xp", xp), 13, T.text, T.font, { Parent = current })
				for _, v in Vehicles.ForJob(job) do
					if (v.xp or 0) > xp then
						Make.Label(Store.T("next_unlock", v.name, v.xp or 0), 12, T.sub, T.font, { Parent = current })
						break
					end
				end
				Make.Button(Store.T("quit_job"), T.bad, function()
					local r = Net.Request("Job.Quit")
					if not r.ok then
						Notify.Error(r.err)
					end
				end, { Parent = current })
			end

			Make.Label(Store.T("start_at_station"), 12, T.sub, T.font, { LayoutOrder = 2, Parent = root })
			for i, def in Jobs.List do
				if def.id ~= "Unemployed" then
					local card = Make.Card({ LayoutOrder = 10 + i, Parent = root })
					Make.Label(
						Jobs.Name(def.id, lang),
						14,
						def.color:Lerp(Color3.new(1, 1, 1), 0.4),
						T.bold,
						{ Parent = card }
					)
					Make.Label(
						Store.T("paycheck_short", Locale.Euro(def.paycheck)),
						12,
						T.sub,
						T.font,
						{ Parent = card }
					)
					Make.Button("🧭 " .. Store.T("navigate"), T.panel, function()
						local station = findStation(def.id)
						if station then
							Waypoint.Set(station, Jobs.Name(def.id, lang), def.color)
							Phone.Close()
						end
					end, { Size = UDim2.new(1, 0, 0, 30), Parent = card })
				end
			end
		end
		render(Store.Get())
		return render
	end,
})

return nil
