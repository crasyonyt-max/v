# Map data

`osm/` (not committed, re-download with `python3 tools/osm_fetch.py`) holds raw
OpenStreetMap extracts of Dortmund. `python3 tools/osm_convert.py` turns them into
`src/ServerStorage/CityData/*` and `src/ReplicatedStorage/Shared/Locations.lua`.

Map data © OpenStreetMap contributors, available under the Open Database License (ODbL):
https://www.openstreetmap.org/copyright — the converted data is a derived database under
the same licence. The game credits OpenStreetMap on the HUD and in the phone settings.

## Archived: real-body cars (V1.0)

Switched off with `Config.RealCars = false` (src/ReplicatedStorage/Shared/Config.lua);
the generated ("blocky") cars are the fleet again. Everything is kept:

- car list: `V10_CARS` in src/ReplicatedStorage/VehicleConfig.lua
- body data: src/ServerStorage/ToolboxBodies.lua (17 bodies, group asset ids)
- bodies on Roblox: group 35947661, ids in data/toolbox_uploads.txt
- code: src/ServerScriptService/Server/Cars/ToolboxBodies.lua, tools/toolbox/clean.luau

Players who owned a real-body civil car were refunded once (refund store key `rc_<userId>`).
Turning `RealCars` back on retires the blocky cars again; players already refunded for
blocky cars (`v1_` key) get no second refund for blocky cars bought since.
