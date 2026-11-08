#!/usr/bin/env python3
"""Analyse a downloaded Creator Store car (export JSON) and write data/toolbox/<id>.meta.json:
car frame (forward/up), size, wheels (FL/FR/RL/RR centre + radius), seats, emblem cover
points and light positions, all in the car's local space
(origin = ground centre, forward = -Z, right = +X, up = +Y, studs, unscaled)."""
import json, math, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import render_model as R

DATA = Path(__file__).resolve().parents[2] / "data" / "toolbox"

# Models without usable wheels / seats: forward given by hand as a world direction.
FORWARD_OVERRIDE = {
    1868047596: (0, 0, -1),
}


def norm(v):
    l = math.sqrt(sum(c * c for c in v)) or 1
    return tuple(c / l for c in v)


def sub(a, b):
    return tuple(a[i] - b[i] for i in range(3))


def dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def wheel_tag(path):
    p = path.lower().replace("_", ".").split(".")
    for tag in ("fl", "fr", "rl", "rr"):
        if tag in p:
            return tag.upper()
    return None


def analyse(aid):
    parts = json.loads((DATA / f"{aid}.json").read_text())
    vis = [p for p in parts if p["transparency"] < 0.95]

    # wheel groups by FL/FR/RL/RR in the path (A-Chassis layout)
    groups = {}
    for p in vis:
        if any(w in p["path"].lower() for w in ("wheel", "tire", "tyre", "rim")) or wheel_tag(p["path"]):
            t = wheel_tag(p["path"])
            if t:
                groups.setdefault(t, []).append(p)

    def centre(ps):
        xs = [q["cf"][0] for q in ps]; ys = [q["cf"][1] for q in ps]; zs = [q["cf"][2] for q in ps]
        return (sum(xs) / len(xs), sum(ys) / len(ys), sum(zs) / len(zs))

    up = (0.0, 1.0, 0.0)
    if aid in FORWARD_OVERRIDE:
        fwd = norm(FORWARD_OVERRIDE[aid])
    elif all(k in groups for k in ("FL", "FR", "RL", "RR")):
        front = tuple((a + b) / 2 for a, b in zip(centre(groups["FL"]), centre(groups["FR"])))
        rear = tuple((a + b) / 2 for a, b in zip(centre(groups["RL"]), centre(groups["RR"])))
        f = sub(front, rear)
        fwd = norm((f[0], 0, f[2]))
    else:
        seat = next((p for p in parts if p["class"] == "VehicleSeat"), None)
        if not seat:
            raise SystemExit(f"{aid}: no wheels/seat, add FORWARD_OVERRIDE")
        c = seat["cf"]
        fwd = norm((-c[5], 0, -c[11]))
    right = cross(fwd, up)  # forward x up = right (right-handed, y up)

    tris = R.load_model(DATA / f"{aid}.json")
    pts = [v for t, _ in tris for v in t]
    # local coords: x = right, y = up, z = -forward
    def to_local(v):
        return (dot(v, right), v[1], -dot(v, fwd))
    loc = [to_local(v) for v in pts]
    xs = [p[0] for p in loc]; ys = [p[1] for p in loc]; zs = [p[2] for p in loc]
    ox, oz = (max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2
    oy = min(ys)
    W, H, L = max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)
    origin_world = tuple(right[i] * ox + up[i] * oy - fwd[i] * oz for i in range(3))

    def lp(v):
        l = to_local(v)
        return [l[0] - ox, l[1] - oy, l[2] - oz]

    wheels = {}
    for tag, ps in groups.items():
        wpts = []
        for p in ps:
            for t, _ in R.load_model_parts([p]):
                wpts.extend(t)
        if not wpts:
            continue
        lw = [lp(v) for v in wpts]
        cx = (max(v[0] for v in lw) + min(v[0] for v in lw)) / 2
        cy = (max(v[1] for v in lw) + min(v[1] for v in lw)) / 2
        cz = (max(v[2] for v in lw) + min(v[2] for v in lw)) / 2
        r = (max(v[1] for v in lw) - min(v[1] for v in lw)) / 2
        wheels[tag] = [round(cx, 3), round(cy, 3), round(cz, 3), round(r, 3)]

    # emblem cover points: centre-line surface in the grille / tailgate height band
    def surface(front, lo, hi):
        band = [p for p in loc if abs(p[0] - ox) < W * 0.06 and oy + H * lo < p[1] < oy + H * hi]
        if not band:
            return None
        z = min(p[2] for p in band) if front else max(p[2] for p in band)
        ys_ = [p[1] for p in band if abs(p[2] - z) < 0.6]
        y = sum(ys_) / len(ys_)
        return [0.0, round(y - oy, 3), round(z - oz, 3)]

    seats = []
    for p in parts:
        if p["class"] in ("VehicleSeat", "Seat"):
            l = lp((p["cf"][0], p["cf"][1], p["cf"][2]))
            seats.append({"driver": p["class"] == "VehicleSeat" and not seats_has_driver(seats), "pos": [round(c, 3) for c in l]})
    meta = {
        "id": aid,
        "frame": {"origin": origin_world, "right": right, "up": up, "back": tuple(-c for c in fwd)},
        "size": [round(W, 3), round(H, 3), round(L, 3)],
        "wheels": wheels,
        "seats": seats,
        "badgeFront": surface(True, 0.3, 0.6),
        "badgeRear": surface(False, 0.35, 0.7),
    }
    (DATA / f"{aid}.meta.json").write_text(json.dumps(meta, indent=1))
    return meta


def seats_has_driver(seats):
    return any(s["driver"] for s in seats)


if __name__ == "__main__":
    for a in sys.argv[1:]:
        m = analyse(int(a))
        print(a, "size", m["size"], "wheels", sorted(m["wheels"]), "seats", len(m["seats"]), "badgeF", m["badgeFront"], "badgeR", m["badgeRear"])
