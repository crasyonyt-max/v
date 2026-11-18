--!strict
-- Kofferraum: how many items fit in a car, by body type (RealisticCars CarType).
-- Every car with the same body has the same trunk, also job and admin cars.

local Trunk = {}

Trunk.Limits = {
	Supercar = 14, -- Koenigshaus & co.
	Hatchback = 50, -- Kupra Formentor VZ5 & co.
	Sedan = 45, -- BMV M4 & co.
	Van = 500, -- Mercator Sprintor & co.
	Bus = 5, -- driver only
	Motorbike = 10,
	-- not set by the owner yet
	Sports = 20,
	Muscle = 40,
	SUV = 80,
	Pickup = 150,
	Police = 45,
	Truck = 800,
} :: { [string]: number }

Trunk.Default = 30

function Trunk.LimitFor(carType: string?): number
	return (carType and Trunk.Limits[carType]) or Trunk.Default
end

return Trunk
