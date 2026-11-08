#!/usr/bin/env python3
"""Vet a Creator Store car: download, export, find emblem pieces, render with and without them.
   python3 tools/toolbox/vet.py <assetId> <out.png> [title]
Prints JSON: {id, size, forward, badges:[paths], scripts, decals}"""
import json, math, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from fetch import fetch
import render_model as R
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
LUNE = str(Path.home() / ".cargo/bin/lune")


def export(asset_id):
    rbxm = fetch(asset_id)
    js = rbxm.with_suffix(".json")
    if not js.exists():
        subprocess.run([LUNE, "run", str(ROOT / "tools/toolbox/export.luau"), str(rbxm), str(js)], check=True, capture_output=True)
    return json.loads(js.read_text()), js


def frame(parts):
    """Car frame from its driver seat: forward = seat look, up = seat up."""
    seat = next((p for p in parts if p["class"] == "VehicleSeat"), None)
    if not seat:
        return None
    c = seat["cf"]
    # CFrame components: x y z R00 R01 R02 R10 R11 R12 R20 R21 R22; look = -column 2
    look = (-c[5], -c[8], -c[11])
    up = (c[4], c[7], c[10])
    return (c[0], c[1], c[2]), look, up


def local_bounds(parts, fr):
    (ox, oy, oz), f, u = fr
    r = (u[1] * f[2] - u[2] * f[1], u[2] * f[0] - u[0] * f[2], u[0] * f[1] - u[1] * f[0])  # right = up x fwd... sign irrelevant for size
    pts = []
    for p in parts:
        if p["transparency"] >= 0.95:
            continue
        c = p["cf"]
        x, y, z = c[0] - ox, c[1] - oy, c[2] - oz
        pts.append((p, x * r[0] + y * r[1] + z * r[2], x * u[0] + y * u[1] + z * u[2], x * f[0] + y * f[1] + z * f[2]))
    return pts


def main():
    aid = int(sys.argv[1])
    out = sys.argv[2]
    title = sys.argv[3] if len(sys.argv) > 3 else str(aid)
    parts, js = export(aid)
    fr = frame(parts)
    info = {"id": aid, "parts": len(parts)}
    badges = []
    if fr:
        pts = local_bounds(parts, fr)
        xs = [q[1] for q in pts]; ys = [q[2] for q in pts]; zs = [q[3] for q in pts]
        width = max(xs) - min(xs); length = max(zs) - min(zs)
        info["approx_size"] = [round(width, 1), round(max(ys) - min(ys), 1), round(length, 1)]
        for p, x, y, z in pts:
            big = max(p["size"])
            near_end = z > max(zs) - length * 0.1 or z < min(zs) + length * 0.1
            lname = p["name"].lower()
            if any(w in lname for w in ("logo", "badge", "emblem", "brand", "letter", "lettering")) or (
                big < 1.6 and abs(x) < width * 0.18 and near_end and p["class"] == "MeshPart"
            ):
                badges.append(p["path"])
    info["badges"] = badges
    # renders: highlighted, and with badges removed
    hl = []
    for p in parts:
        q = dict(p)
        if p["path"] in badges:
            q["color"] = [1.0, 0.0, 1.0]
        hl.append(q)
    tmp = js.with_name(js.stem + "_hl.json")
    tmp.write_text(json.dumps(hl))
    tris_hl = R.load_model(tmp)
    clean = [p for p in parts if p["path"] not in badges]
    tmp2 = js.with_name(js.stem + "_clean.json")
    tmp2.write_text(json.dumps(clean))
    tris_clean = R.load_model(tmp2)
    sheet = Image.new("RGB", (1040, 640), (255, 255, 255))
    views = [(0, math.radians(6)), (math.pi, math.radians(6))]
    for k, (yw, pt) in enumerate(views):
        sheet.paste(R.render(tris_hl, yw, pt, label=f"{title} — emblem pieces pink"), (k * 520, 0))
        sheet.paste(R.render(tris_clean, yw, pt, label=f"{title} — emblems removed"), (k * 520, 320))
    sheet.save(out)
    print(json.dumps(info))


if __name__ == "__main__":
    main()
