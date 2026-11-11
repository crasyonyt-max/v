#!/usr/bin/env python3
"""Render a top-down city map PNG from src/ServerStorage/CityData (for the AA drop map).

Output: build/map.png. Pixel (0,0) = Locations.Bounds minX/minZ (north = -Z is up).
"""
import json, re, sys
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SIZE = 1024

def lua_table(text):
    # chunk files are flat Lua tables of number arrays: turn them into JSON
    body = text[text.index("return {") + len("return ") :]
    body = re.sub(r"\n\t(\w+) = ", r'\n"\1": ', body)
    body = body.replace("{", "[").replace("}", "]")
    body = "{" + body.strip()[1:-1] + "}"
    body = re.sub(r",\s*([\]}])", r"\1", body)
    return json.loads(body)

loc = (ROOT / "src/ReplicatedStorage/Shared/Locations.lua").read_text()
minx, minz, maxx, maxz = map(float, re.search(r"Locations.Bounds = \{([^}]*)\}", loc).group(1).split(","))
span = max(maxx - minx, maxz - minz)
s = SIZE / span
def px(x, z):
    return ((x - minx) * s, (z - minz) * s)

img = Image.new("RGB", (SIZE, SIZE), (38, 44, 40))
d = ImageDraw.Draw(img)
AREA = {1: (60, 92, 58), 2: (60, 92, 58), 3: (70, 70, 74), 4: (52, 84, 120), 5: (52, 84, 120)}
chunks = sorted((ROOT / "src/ServerStorage/CityData").glob("Chunk_*.lua"))
data = [lua_table(c.read_text()) for c in chunks]
for ch in data:
    for a in ch.get("a", []):
        col = AREA.get(a[0], (58, 70, 58))
        f = a[1:]
        for i in range(0, len(f) - 5, 6):
            d.polygon([px(f[i], f[i + 1]), px(f[i + 2], f[i + 3]), px(f[i + 4], f[i + 5])], fill=col)
for ch in data:
    for b in ch.get("b", []):
        col = (96, 96, 100)
        if b[0] == 1:
            import math
            rx, rz, sx, sz, ang = b[4:9]
            a = math.radians(ang)
            ca, sa = math.cos(a), math.sin(a)
            pts = []
            for dx, dz in ((-sx / 2, -sz / 2), (sx / 2, -sz / 2), (sx / 2, sz / 2), (-sx / 2, sz / 2)):
                pts.append(px(rx + dx * ca + dz * sa, rz - dx * sa + dz * ca))
            d.polygon(pts, fill=col)
        else:
            f = b[4:]
            for i in range(0, len(f) - 5, 6):
                d.polygon([px(f[i], f[i + 1]), px(f[i + 2], f[i + 3]), px(f[i + 4], f[i + 5])], fill=col)
roads = [r for ch in data for r in ch.get("r", [])]
for r in sorted(roads, key=lambda r: -r[0]):
    t, w = r[0], r[1]
    if t >= 15:  # paths / footways: skip, too busy
        continue
    pts = [px(r[i], r[i + 1]) for i in range(4, len(r) - 1, 2)]
    col = (250, 200, 90) if t <= 2 else (235, 235, 235) if t <= 10 else (190, 190, 190)
    d.line(pts, fill=col, width=max(1, round(w * s)))
out = ROOT / "build/map.png"
out.parent.mkdir(exist_ok=True)
img.save(out)
print(out, img.size, "span", span, "bounds", minx, minz)
