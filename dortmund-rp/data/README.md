# Map data

`osm/` (not committed, re-download with `python3 tools/osm_fetch.py`) holds raw
OpenStreetMap extracts of Dortmund. `python3 tools/osm_convert.py` turns them into
`src/ServerStorage/CityData/*` and `src/ReplicatedStorage/Shared/Locations.lua`.

Map data © OpenStreetMap contributors, available under the Open Database License (ODbL):
https://www.openstreetmap.org/copyright — the converted data is a derived database under
the same licence. The game credits OpenStreetMap on the HUD and in the phone settings.
