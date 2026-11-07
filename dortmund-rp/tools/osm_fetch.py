#!/usr/bin/env python3
"""Download OpenStreetMap data for the playable Dortmund area in small tiles.
Data © OpenStreetMap contributors, ODbL (credited in-game)."""
import time, urllib.request
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "osm"
WEST, EAST, SOUTH, NORTH = 7.440, 7.490, 51.500, 51.525
STEP_LON, STEP_LAT = 0.0100, 0.00625

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    lat = SOUTH
    i = 0
    while lat < NORTH - 1e-9:
        lon = WEST
        while lon < EAST - 1e-9:
            name = OUT / f"tile_{i:02d}.osm"
            if not name.exists():
                bbox = f"{lon:.5f},{lat:.5f},{min(lon+STEP_LON,EAST):.5f},{min(lat+STEP_LAT,NORTH):.5f}"
                req = urllib.request.Request(
                    f"https://api.openstreetmap.org/api/0.6/map?bbox={bbox}",
                    headers={"User-Agent": "EmergencyDortmund-MapBuilder/0.1"},
                )
                with urllib.request.urlopen(req, timeout=120) as r:
                    name.write_bytes(r.read())
                print("got", name.name, bbox, name.stat().st_size // 1024, "KB", flush=True)
                time.sleep(1.5)
            i += 1
            lon += STEP_LON
        lat += STEP_LAT

if __name__ == "__main__":
    main()
