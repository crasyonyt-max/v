#!/usr/bin/env python3
"""Side views of analysed models in their local frame (front = left) with emblem cover points."""
import json, math, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import render_model as R
from PIL import Image, ImageDraw
DATA = Path(__file__).resolve().parents[2] / "data" / "toolbox"
out, ids = sys.argv[1], sys.argv[2:]
cols, Wd, Hd = 3, 420, 200
sheet = Image.new("RGB", (cols * Wd, ((len(ids) + cols - 1) // cols) * Hd), (255, 255, 255))
for k, aid in enumerate(ids):
    m = json.loads((DATA / f"{aid}.meta.json").read_text())
    f = m["frame"]; o, r, u, b = f["origin"], f["right"], f["up"], f["back"]
    tris = R.load_model(DATA / f"{aid}.json")
    loc = []
    for t, col in tris:
        lt = tuple((sum((v[i] - o[i]) * r[i] for i in range(3)), sum((v[i] - o[i]) * u[i] for i in range(3)), sum((v[i] - o[i]) * b[i] for i in range(3))) for v in t)
        loc.append((lt, col))
    # side view from the right (+X): screen x = z (front = -z on the left), y = up
    img = R.render(loc, -math.pi / 2, 0.02, W=Wd, H=Hd, label=f"{aid} size {m['size']}")
    sheet.paste(img, ((k % cols) * Wd, (k // cols) * Hd))
sheet.save(out)
