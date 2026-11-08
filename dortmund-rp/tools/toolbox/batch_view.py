#!/usr/bin/env python3
"""3/4 renders of several Creator Store models on one sheet: batch_view.py out.png id:label ..."""
import json, math, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import render_model as R
from vet import export
from PIL import Image

out = sys.argv[1]
items = [a.split(":", 1) for a in sys.argv[2:]]
cols = 3
sheet = Image.new("RGB", (cols * 420, ((len(items) + cols - 1) // cols) * 260), (255, 255, 255))
for k, (aid, label) in enumerate(items):
    try:
        parts, js = export(int(aid))
        img = R.render(R.load_model(js), math.radians(35), math.radians(14), W=420, H=260, label=f"{aid} {label}")
    except Exception as e:  # noqa: BLE001
        from PIL import ImageDraw
        img = Image.new("RGB", (420, 260), (255, 220, 220))
        ImageDraw.Draw(img).text((8, 8), f"{aid} {label}\n{e}"[:200], fill=(0, 0, 0))
    sheet.paste(img, ((k % cols) * 420, (k // cols) * 260))
sheet.save(out)
