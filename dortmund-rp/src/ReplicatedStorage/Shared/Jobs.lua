--!strict
-- Job definitions. Paycheck = € per Config.PaycheckInterval.

export type Job = {
	id: string,
	de: string,
	en: string,
	paycheck: number,
	color: Color3,
	emergency: boolean,
}

local Jobs = {}

Jobs.List = {
	{
		id = "Unemployed",
		de = "Arbeitslos (Bürgergeld)",
		en = "Unemployed (Bürgergeld)",
		paycheck = 250,
		color = Color3.fromRGB(150, 150, 150),
		emergency = false,
	},
	{
		id = "Police",
		de = "Polizei",
		en = "Police",
		paycheck = 600,
		color = Color3.fromRGB(40, 90, 200),
		emergency = true,
	},
	{
		id = "Fire",
		de = "Feuerwehr",
		en = "Fire Department",
		paycheck = 600,
		color = Color3.fromRGB(200, 30, 30),
		emergency = true,
	},
	{
		id = "Rettungsdienst",
		de = "Rettungsdienst (DRH)",
		en = "Ambulance (DRH)",
		paycheck = 550,
		color = Color3.fromRGB(230, 120, 20),
		emergency = true,
	},
	{
		id = "Notarzt",
		de = "Notarzt (NEF)",
		en = "Emergency Doctor (NEF)",
		paycheck = 700,
		color = Color3.fromRGB(240, 200, 30),
		emergency = true,
	},
	{
		id = "ADMC",
		de = "Pannenhilfe (ADMC)",
		en = "Roadside Assistance (ADMC)",
		paycheck = 500,
		color = Color3.fromRGB(250, 210, 0),
		emergency = false,
	},
	{
		id = "DXL",
		de = "Paketzusteller (DXL)",
		en = "Parcel Delivery (DXL)",
		paycheck = 450,
		color = Color3.fromRGB(255, 200, 0),
		emergency = false,
	},
	{
		id = "LKW",
		de = "LKW-Fahrer",
		en = "Truck Driver",
		paycheck = 550,
		color = Color3.fromRGB(90, 140, 90),
		emergency = false,
	},
	{
		id = "Bus",
		de = "Busfahrer",
		en = "Bus Driver",
		paycheck = 500,
		color = Color3.fromRGB(11, 110, 138),
		emergency = false,
	},
} :: { Job }

Jobs.ById = {} :: { [string]: Job }
for _, job in Jobs.List do
	Jobs.ById[job.id] = job
end

function Jobs.Name(id: string, lang: string?): string
	local job = Jobs.ById[id]
	if not job then
		return id
	end
	return if lang == "en" then job.en else job.de
end

return Jobs
