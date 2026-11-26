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
                    headers={"User-Agent": "osm-tile-fetch/0.1"},
                )
                with urllib.request.urlopen(req, timeout=120) as r:
                    name.write_bytes(r.read())
                print("got", name.name, bbox, name.stat().st_size // 1024, "KB", flush=True)
                time.sleep(1.5)
            i += 1
            lon += STEP_LON
        lat += STEP_LAT

# extra tiles for the bigger map (ED_MAP=xl): a band in the south, a thin one in the
# east and one in the north (bbox = west, south, east, north)
EXTRA = [(round(7.440 + i * 0.01, 3), 51.4960, round(min(7.440 + (i + 1) * 0.01, 7.492), 3), 51.5000) for i in range(6)] + [
    (7.490, 51.5000, 7.492, 51.5130),
    (7.490, 51.5130, 7.492, 51.5260),
    (7.440, 51.5250, 7.466, 51.5260),
    (7.466, 51.5250, 7.492, 51.5260),
    # the Stadthafen (port) north-west of the city, for the port annex
    (7.429, 51.5250, 7.439, 51.5293),
    (7.439, 51.5250, 7.449, 51.5293),
    (7.429, 51.5293, 7.439, 51.5336),
    (7.439, 51.5293, 7.449, 51.5336),
]


def extra():
    OUT.mkdir(parents=True, exist_ok=True)
    for i, (w, s_, e, n) in enumerate(EXTRA):
        name = OUT / f"tile_{20 + i:02d}.osm"
        if name.exists():
            continue
        bbox = f"{w:.5f},{s_:.5f},{e:.5f},{n:.5f}"
        req = urllib.request.Request(
            f"https://api.openstreetmap.org/api/0.6/map?bbox={bbox}",
            headers={"User-Agent": "osm-tile-fetch/0.1"},
        )
        with urllib.request.urlopen(req, timeout=120) as r:
            name.write_bytes(r.read())
        print("got", name.name, bbox, name.stat().st_size // 1024, "KB", flush=True)
        time.sleep(1.5)


if __name__ == "__main__":
    import sys

    extra() if "--extra" in sys.argv else main()
