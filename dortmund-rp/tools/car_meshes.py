#!/usr/bin/env python3
"""Generate smooth 3D car bodies (one per body type) + a wheel, upload them to Roblox
and write src/ServerStorage/CarMeshes.lua with the asset IDs and anchor points.

Body dimensions come from VehicleBuilder.BodyTypes so physics and looks always match.
Model space = VehicleBuilder space: studs, forward = -Z, right = +X, ground y = 0.

  python3 tools/car_meshes.py           build + upload changed meshes
  python3 tools/car_meshes.py --dry     build only (writes .glb files to build/meshes)
"""
import hashlib
import json
import math
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from glb import write_glb  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
BUILDER = ROOT / "src" / "ServerScriptService" / "Server" / "VehicleBuilder.lua"
OUT_LUA = ROOT / "src" / "ServerStorage" / "CarMeshes.lua"
CACHE = ROOT / "data" / "car_assets.json"
MESH_DIR = ROOT / "build" / "meshes"
GROUP_ID = "35947661"

GENERATOR_VERSION = 2


def body_types():
    text = BUILDER.read_text()
    out = {}
    for name, body in re.findall(r"(\w+) = b\(\{(.*?)\}\)", text, re.S):
        vals = {}
        for k, v in re.findall(r"(\w+) = ([^,\n]+)", body):
            v = v.strip()
            vals[k] = v.strip('"') if v.startswith('"') else float(v)
        out[name] = vals
    return out


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ body loft
def section_profile(b, z, axles):
    """Returns (half_width, bottom_y, belt_y, top_y, zone) for a cross-section at z.
    zone: 'body' (hood/trunk top), 'wind', 'roof', 'rear', 'box'."""
    L, W = b["L"], b["W"]
    r = b["wheelR"]
    y0 = b["clear"]
    y1 = y0 + b["lower"]
    yr = y1 + b["cab"]
    zf, zr = -L / 2, L / 2
    t = (z - zf) / L  # 0 front .. 1 rear
    cab_f = zf + b["cabStart"] * L
    cab_r = zf + b["cabEnd"] * L
    ws, rs = b["ws"], b["rs"]
    fit = min(1.0, (cab_r - cab_f - 1) / max(ws + rs, 0.01))
    ws, rs = ws * fit, rs * fit
    rear = b.get("rear")
    boxy = rear is not None or b.get("glassEnd") is not None or ws < 1.0

    # plan view: rounded corners
    nose = 0.10 if not boxy else 0.04
    tail = 0.06 if not boxy else 0.03
    wf = 1 - 0.10 * (1 - smooth(t / nose)) - 0.06 * (1 - smooth((1 - t) / tail))
    w = W / 2 * wf

    # side view: lower body / hood line
    hood_drop = 0.0 if boxy else b["lower"] * 0.28
    belt = y1 - hood_drop * (1 - smooth((z - zf) / max(cab_f - zf, 0.1))) if z < cab_f else y1
    # front/rear rounding of the lower body
    belt -= b["lower"] * 0.18 * (1 - smooth(t / nose)) + b["lower"] * 0.1 * (1 - smooth((1 - t) / tail))
    bottom = y0 + 0.15 * (1 - smooth(t / (nose * 1.4))) + 0.1 * (1 - smooth((1 - t) / (tail * 1.5)))

    # wheel arches: lift the bottom around each axle
    for ax in axles:
        d = abs(z - ax)
        R = r * 1.12
        if d < R:
            arch = ax_y = r + math.sqrt(R * R - d * d)
            bottom = max(bottom, min(arch, belt - 0.25))
            _ = ax_y

    top, zone = belt, "body"
    if cab_f <= z <= cab_r:
        if z < cab_f + ws:
            top = belt + (yr - belt) * smooth((z - cab_f) / max(ws, 0.01)) ** 0.8
            zone = "wind"
        elif z > cab_r - rs:
            top = belt + (yr - belt) * smooth((cab_r - z) / max(rs, 0.01)) ** 0.8
            zone = "rear"
        else:
            top, zone = yr, "roof"
        if b.get("glassEnd") is not None and z > zf + b["glassEnd"] * L and zone == "roof":
            zone = "van"  # solid cargo area
    if rear == "box" and z > cab_r + 0.2:
        top, zone = y1 + b.get("rearH", 6) - 0.2, "box"
    if rear in ("bed", "flat", "fifth", "ladder") and z > cab_r + 0.2:
        top, zone = belt, "body"
        belt = y1 - (0.0 if rear == "bed" else 0.6)
        top = belt
    return w, bottom, belt, top, zone


def door_seams(b):
    """z positions of door seams (front door front edge, B-pillar, rear edge)."""
    L = b["L"]
    zf = -L / 2
    cab_f, cab_r = zf + b["cabStart"] * L, zf + b["cabEnd"] * L
    ws, rs = b["ws"], b["rs"]
    fit = min(1.0, (cab_r - cab_f - 1) / max(ws + rs, 0.01))
    ws, rs = ws * fit, rs * fit
    core_f, core_r = cab_f + ws * 0.7, cab_r - max(rs, 0.4)
    if b.get("rear") or b.get("glassEnd") is not None:
        # vans / trucks: cab door only
        end = zf + (b.get("glassEnd") or b["cabEnd"]) * L
        return [core_f, min(end, core_f + 3.6)]
    if b.get("seats", 4) >= 5:
        mid = (core_f + core_r) / 2
        return [core_f, mid, min(core_r, mid + (mid - core_f))]
    return [core_f, min(core_r, core_f + 4.6)]


SIDE_MATS = {0: "Trim", 1: "Body", 2: "SideLow", 3: "SideMid", 4: "SideHigh", 5: "Body"}


def loft(b, axles, n_sections=72):
    """Body split into panels so liveries can colour them separately.
    Cross-section (right half, bottom -> roof centre), 11 points / 10 segments."""
    L = b["L"]
    zs = [-L / 2 + L * i / (n_sections - 1) for i in range(n_sections)]
    cab_f = -L / 2 + b["cabStart"] * L
    cab_r = -L / 2 + b["cabEnd"] * L
    sections = []
    for z in zs:
        w, yb, belt, top, zone = section_profile(b, z, axles)
        g = max(top - belt, 0.0)
        h = max(belt - yb, 0.01)
        greenhouse = zone in ("wind", "roof", "rear", "van") and g > 0.05
        tumble = (0.16 if zone != "van" else 0.05) * w if greenhouse else 0
        crown = 0.12 if not greenhouse else 0.06
        pts = [
            (0.0, yb),
            (w * 0.9, yb),
            (w, yb + h * 0.30),
            (w, yb + h * 0.47),
            (w, yb + h * 0.64),
            (w, belt - h * 0.10),
            (w * 0.97, belt),
            (w * 0.97 - tumble * 0.5, belt + g * 0.55),
            (w * 0.97 - tumble, top - g * 0.08 - (0.05 if greenhouse else 0.0)),
            (w * 0.97 - tumble - (0.12 * w if greenhouse else 0.06 * w), top),
            (0.0, top + crown),
        ]
        sections.append((z, pts, zone, greenhouse))

    names = ["Body", "SideLow", "SideMid", "SideHigh", "Hood", "Roof", "Deck", "Glass", "Trim", "Seams"]
    meshes = {n: ([], []) for n in names}
    seams = door_seams(b)

    def top_mat(zone, z):
        if zone in ("wind", "rear"):
            return "Glass"
        if zone in ("roof", "van", "box"):
            return "Roof"
        return "Hood" if z < cab_f else "Deck"

    def material(seg, zone_a, zone_b, gh, z):
        if seg in SIDE_MATS:
            return SIDE_MATS[seg]
        if seg in (6, 7):  # side windows
            if zone_a == "box" or zone_b == "box":
                return "Body"
            if not gh or zone_a == "van":
                return "Body" if seg == 6 else top_mat(zone_a, z) if not gh else "Body"
            # pillars: A at the windshield, B in the middle, C before the rear window
            core_f = cab_f + b["ws"] * 0.95
            core_r = cab_r - max(b["rs"], 0.4)
            for pz in (core_f, (core_f + core_r) / 2, core_r):
                if abs(z - pz) < 0.22:
                    return "Roof"
            return "Glass"
        return top_mat(zone_a if gh or zone_a == "box" else zone_a, z) if gh or zone_a in ("box",) else ("Hood" if z < cab_f else "Deck")

    def quad(mat, q, side):
        pos, idx = meshes[mat]
        base = len(pos)
        pos.extend([list(p) for p in q])
        if side == 1:
            idx.extend([base, base + 1, base + 2, base, base + 2, base + 3])
        else:
            idx.extend([base, base + 2, base + 1, base, base + 3, base + 2])

    for i in range(len(sections) - 1):
        za, pa, zone_a, gha = sections[i]
        zb, pb, zone_b, ghb = sections[i + 1]
        gh = gha and ghb
        zmid = (za + zb) / 2
        for seg in range(len(pa) - 1):
            mat = material(seg, zone_a, zone_b, gh, zmid)
            for side in (1, -1):
                quad(mat, [
                    (side * pa[seg][0], pa[seg][1], za),
                    (side * pa[seg + 1][0], pa[seg + 1][1], za),
                    (side * pb[seg + 1][0], pb[seg + 1][1], zb),
                    (side * pb[seg][0], pb[seg][1], zb),
                ], side)

    # door seams: thin dark strips just outside the side surface, sill to belt
    for zs_ in seams:
        w, yb, belt, top, zone = section_profile(b, zs_, axles)
        h = belt - yb
        pts = [(w * 0.9, yb), (w, yb + h * 0.3), (w, belt - h * 0.1), (w * 0.97, belt)]
        for side in (1, -1):
            for k in range(len(pts) - 1):
                (x1, y1), (x2, y2) = pts[k], pts[k + 1]
                o = 0.012
                quad("Seams", [
                    (side * (x1 + o), y1, zs_ - 0.035),
                    (side * (x2 + o), y2, zs_ - 0.035),
                    (side * (x2 + o), y2, zs_ + 0.035),
                    (side * (x1 + o), y1, zs_ + 0.035),
                ], side)

    # caps (front / rear faces)
    for (z, pts, _, _), facing in ((sections[0], -1), (sections[-1], 1)):
        pos, idx = meshes["Body"]
        ring = [(x, y) for x, y in pts] + [(-x, y) for x, y in reversed(pts)]
        cy = sum(y for _, y in ring) / len(ring)
        base = len(pos)
        pos.append([0.0, cy, z])
        for x, y in ring:
            pos.append([x, y, z])
        n = len(ring)
        for k in range(n):
            a, c = base + 1 + k, base + 1 + (k + 1) % n
            idx.extend([base, a, c] if facing == 1 else [base, c, a])
    return meshes


def flat_shade_split(positions, indices):
    """Seam-free smooth normals are fine; just return as is."""
    return positions, indices


def axles_for(b):
    L, r = b["L"], b["wheelR"]
    is_truck = b.get("rear") is not None and b["cabStart"] <= 0.05
    of = r * 1.3 if is_truck else r * 1.7
    orr = r * 1.5 if b.get("rear") == "fifth" else r * 1.8
    return [-L / 2 + of, L / 2 - orr]


def markers(b):
    """Tiny tetrahedra marking front / rear / top so the game can align the import."""
    L = b["L"]
    y = b["clear"] + b["lower"] / 2
    H = 4.0

    def tetra(cx, cy, cz, s=0.05):
        p = [[cx + s, cy, cz], [cx - s, cy, cz + s], [cx - s, cy, cz - s], [cx, cy + s, cz]]
        return {"positions": p, "indices": [0, 1, 2, 0, 3, 1, 1, 3, 2, 2, 3, 0], "color": (1, 0, 1)}

    out = []
    for name, (x, yy, z) in {
        "MarkerFront": (0, y, -L / 2),
        "MarkerRear": (0, y, L / 2),
        "MarkerTop": (0, y + H, 0),
    }.items():
        m = tetra(x, yy, z)
        m["name"] = name
        out.append(m)
    return out, y


def anchors(b, axles):
    """Points the builder needs to place lights, plates and stripes on the curved body."""
    L = b["L"]
    zf, zr = -L / 2, L / 2
    wf, ybf, beltf, _, _ = section_profile(b, zf + 0.05, axles)
    wr, ybr, beltr, _, _ = section_profile(b, zr - 0.05, axles)
    wm, ybm, beltm, topm, _ = section_profile(b, 0, axles)
    return {
        "frontZ": zf,
        "rearZ": zr,
        "frontBelt": beltf,
        "frontBottom": ybf,
        "frontHalfWidth": wf,
        "rearBelt": beltr,
        "rearBottom": ybr,
        "rearHalfWidth": wr,
        "sideHalfWidth": wm,
        "sideBelt": beltm,
        "sideBottom": ybm,
        "doors": door_seams(b),
    }


# ------------------------------------------------------------------ wheel
def wheel_meshes():
    """Unit wheel: radius 1, width 1, axle along X, centred at origin."""
    seg = 40

    def lathe(profile, color, name, metallic=0.0, rough=0.8):
        pos, idx = [], []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            for x, rad in profile:
                pos.append([x, rad * math.sin(a), rad * math.cos(a)])
        n = len(profile)
        for i in range(seg):
            j = (i + 1) % seg
            for k in range(n - 1):
                a0, a1 = i * n + k, i * n + k + 1
                b0, b1 = j * n + k, j * n + k + 1
                idx.extend([a0, b0, b1, a0, b1, a1])
        return {"name": name, "positions": pos, "indices": idx, "color": color, "metallic": metallic, "roughness": rough}

    tire_profile = [(-0.5, 0.66), (-0.5, 0.9), (-0.44, 0.98), (-0.3, 1.0), (0.3, 1.0), (0.44, 0.98), (0.5, 0.9), (0.5, 0.66)]
    # open rim barrel with an outer lip, and a small recessed hub; spokes connect them
    rim_profile = [(0.30, 0.60), (0.47, 0.62), (0.47, 0.69), (-0.35, 0.69), (-0.35, 0.60), (0.30, 0.60)]
    hub_profile = [(0.43, 0.0), (0.43, 0.17), (0.36, 0.2), (0.25, 0.2), (0.25, 0.0)]
    tire = lathe(tire_profile, (0.05, 0.05, 0.055), "Tire")
    rim = lathe(rim_profile, (0.72, 0.73, 0.76), "Rim", metallic=0.8, rough=0.3)
    hub = lathe(hub_profile, (0.6, 0.61, 0.64), "Hub", metallic=0.8, rough=0.35)
    # spokes
    spokes = {"name": "Spokes", "positions": [], "indices": [], "color": (0.6, 0.61, 0.64), "metallic": 0.8, "roughness": 0.35}
    for s in range(5):
        a = 2 * math.pi * s / 5
        ca, sa = math.cos(a), math.sin(a)
        for (w, r0, r1) in ((0.08, 0.17, 0.62),):
            corners = []
            for x in (0.47, 0.38):
                for rr in (r0, r1):
                    for off in (-w, w):
                        # point at radius rr along angle a, offset sideways
                        y = rr * sa + off * ca
                        z = rr * ca - off * sa
                        corners.append([x, y, z])
            base = len(spokes["positions"])
            spokes["positions"].extend(corners)
            faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 2, 6, 4), (1, 5, 7, 3), (0, 4, 5, 1), (2, 3, 7, 6)]
            for f in faces:
                spokes["indices"].extend([base + f[0], base + f[1], base + f[2], base + f[0], base + f[2], base + f[3]])
    mk = []
    for name, p in {"MarkerFront": (0, 0, -1), "MarkerRear": (0, 0, 1), "MarkerTop": (0, 1, 0)}.items():
        x, y, z = p
        s = 0.02
        mk.append({"name": name, "positions": [[x + s, y, z], [x - s, y, z + s], [x - s, y, z - s], [x, y + s, z]], "indices": [0, 1, 2, 0, 3, 1, 1, 3, 2, 2, 3, 0], "color": (1, 0, 1)})
    return [tire, rim, hub, spokes] + mk


# ------------------------------------------------------------------ upload
def upload(path, display):
    req = json.dumps({
        "assetType": "Model",
        "displayName": display,
        "description": "Emergency Dortmund vehicle mesh (generated)",
        "creationContext": {"creator": {"groupId": GROUP_ID}},
    })
    out = subprocess.run([
        "curl", "-sS", "-m", "180", "-X", "POST", "https://apis.roblox.com/assets/v1/assets",
        "-H", "x-api-key: proxy-injected",
        "-F", f"request={req};type=application/json",
        "-F", f"fileContent=@{path};type=model/gltf-binary",
    ], capture_output=True, text=True, check=True).stdout
    op = json.loads(out)
    if "operationId" not in op:
        raise SystemExit(f"upload failed for {display}: {out}")
    for _ in range(60):
        time.sleep(3)
        st = json.loads(subprocess.run([
            "curl", "-sS", "-m", "30", f"https://apis.roblox.com/assets/v1/operations/{op['operationId']}",
            "-H", "x-api-key: proxy-injected"], capture_output=True, text=True, check=True).stdout)
        if st.get("done"):
            resp = st.get("response", {})
            if "assetId" not in resp:
                raise SystemExit(f"upload error for {display}: {st}")
            state = resp.get("moderationResult", {}).get("moderationState")
            print(f"  uploaded {display}: {resp['assetId']} ({state})", flush=True)
            return int(resp["assetId"])
    raise SystemExit("upload timed out: " + display)


def main():
    dry = "--dry" in sys.argv
    MESH_DIR.mkdir(parents=True, exist_ok=True)
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    bodies = body_types()
    result = {}

    jobs = []
    for name, b in sorted(bodies.items()):
        axles = axles_for(b)
        parts = loft(b, axles)
        marks, mark_y = markers(b)
        colors = {"Glass": (0.1, 0.13, 0.16), "Trim": (0.06, 0.06, 0.07), "Seams": (0.05, 0.05, 0.05)}
        meshes = [
            {"name": k, "positions": v[0], "indices": v[1], "color": colors.get(k, (0.8, 0.8, 0.8)),
             "metallic": 0.3 if k not in colors else 0.0, "roughness": 0.1 if k == "Glass" else 0.4}
            for k, v in parts.items()
        ] + marks
        meshes = [m for m in meshes if m["positions"]]
        jobs.append((f"body_{name}", meshes, {"markerY": mark_y, "anchors": anchors(b, axles)}))
    jobs.append(("wheel", wheel_meshes(), {"markerY": 0}))

    for key, meshes, info in jobs:
        path = MESH_DIR / f"{key}.glb"
        write_glb(path, meshes)
        digest = hashlib.sha256(path.read_bytes() + str(GENERATOR_VERSION).encode()).hexdigest()[:16]
        entry = cache.get(key)
        if not dry and (not entry or entry.get("hash") != digest):
            asset = upload(path, f"ED {key}")
            entry = {"hash": digest, "assetId": asset}
            cache[key] = entry
            CACHE.write_text(json.dumps(cache, indent=1, sort_keys=True))
        result[key] = (entry["assetId"] if entry else 0, info)

    def lua(v):
        if isinstance(v, dict):
            return "{ " + ", ".join(f"{k} = {lua(x)}" for k, x in v.items()) + " }"
        if isinstance(v, list):
            return "{ " + ", ".join(lua(x) for x in v) + " }"
        if isinstance(v, float):
            return f"{v:.3f}"
        return str(v)

    lines = [
        "-- Generated by tools/car_meshes.py. Do not edit.",
        "-- Asset IDs of the uploaded car body / wheel models + anchor points (model space).",
        "return {",
    ]
    for key, (asset, info) in sorted(result.items()):
        lines.append(f"\t{key} = {{ assetId = {asset}, {lua(info)[2:-2]} }},")
    lines.append("}")
    OUT_LUA.write_text("\n".join(lines) + "\n")
    print(f"{len(result)} meshes, written {OUT_LUA.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
