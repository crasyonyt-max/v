#!/usr/bin/env python3
"""Convert downloaded OpenStreetMap data into compact Luau data modules.

Output
  src/ServerStorage/CityData/Chunk_XX.lua   geometry, built at runtime by CityBuilder
  src/ReplicatedStorage/Shared/Locations.lua  stations, shops, spawn (real places)

Coordinates: 1 stud = 0.28 m, origin = Dortmund Hbf, north = -Z, east = +X.
Map data © OpenStreetMap contributors (ODbL).
"""
import math
import sys
from collections import defaultdict
from pathlib import Path

import mapbox_earcut as earcut
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from osm_load import load  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "src" / "ServerStorage" / "CityData"
LOC_FILE = ROOT / "src" / "ReplicatedStorage" / "Shared" / "Locations.lua"

# Play area (lon/lat) and projection origin (Dortmund Hbf)
WEST, EAST, SOUTH, NORTH = 7.446, 7.486, 51.4995, 51.5225
LAT0, LON0 = 51.51789, 7.45928
M_PER_STUD = 0.28
CHUNK = 1500  # studs per data chunk

KX = math.cos(math.radians(LAT0)) * 111320 / M_PER_STUD
KZ = 110540 / M_PER_STUD


def project(lat, lon):
    return ((lon - LON0) * KX, -(lat - LAT0) * KZ)


def inside_area(lat, lon):
    return WEST <= lon <= EAST and SOUTH <= lat <= NORTH


# ---------------------------------------------------------------- geometry helpers
def poly_area(pts):
    a = 0.0
    for i in range(len(pts)):
        x1, z1 = pts[i]
        x2, z2 = pts[(i + 1) % len(pts)]
        a += x1 * z2 - x2 * z1
    return a / 2


def simplify(pts, tol, closed=False):
    """Douglas-Peucker."""
    if len(pts) < 3:
        return pts

    def dp(seq):
        if len(seq) < 3:
            return seq
        (x1, z1), (x2, z2) = seq[0], seq[-1]
        dx, dz = x2 - x1, z2 - z1
        length = math.hypot(dx, dz) or 1e-9
        best, idx = -1, 0
        for i in range(1, len(seq) - 1):
            x, z = seq[i]
            d = abs(dz * x - dx * z + x2 * z1 - z2 * x1) / length
            if d > best:
                best, idx = d, i
        if best > tol:
            return dp(seq[: idx + 1])[:-1] + dp(seq[idx:])
        return [seq[0], seq[-1]]

    if closed:
        # split at the farthest point from the first to keep shape
        far = max(range(len(pts)), key=lambda i: (pts[i][0] - pts[0][0]) ** 2 + (pts[i][1] - pts[0][1]) ** 2)
        a = dp(pts[: far + 1])
        b = dp(pts[far:] + [pts[0]])
        out = a[:-1] + b[:-1]
        return out if len(out) >= 3 else pts
    return dp(pts)


def convex_hull(pts):
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def min_rect(pts):
    """Minimum-area bounding rectangle: (cx, cz, sx, sz, angle_rad)."""
    hull = convex_hull(pts)
    best = None
    for i in range(len(hull)):
        x1, z1 = hull[i]
        x2, z2 = hull[(i + 1) % len(hull)]
        ang = math.atan2(z2 - z1, x2 - x1)
        c, s = math.cos(-ang), math.sin(-ang)
        xs = [x * c - z * s for x, z in hull]
        zs = [x * s + z * c for x, z in hull]
        w, h = max(xs) - min(xs), max(zs) - min(zs)
        if best is None or w * h < best[0]:
            mx, mz = (max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2
            c2, s2 = math.cos(ang), math.sin(ang)
            best = (w * h, mx * c2 - mz * s2, mx * s2 + mz * c2, w, h, ang)
    return best[1:]


def triangulate(pts):
    verts = np.array(pts, dtype=np.float64).reshape(-1, 2)
    idx = earcut.triangulate_float64(verts, np.array([len(pts)], dtype=np.uint32))
    tris = []
    for i in range(0, len(idx), 3):
        a, b, c = (pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]])
        if abs(poly_area([a, b, c])) > 0.5:
            tris.append((a, b, c))
    return tris


def point_in_poly(x, z, pts):
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, zi = pts[i]
        xj, zj = pts[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def parse_len(v):
    if not v:
        return None
    try:
        return float(v.replace(",", ".").replace("m", "").strip())
    except ValueError:
        return None


# ---------------------------------------------------------------- styles
# Facade palette (index sent to Luau). Typical German inner-city colours.
PALETTE = [
    (232, 226, 212), (214, 205, 188), (196, 186, 170), (238, 236, 230), (176, 170, 162),
    (150, 146, 140), (164, 92, 70), (138, 76, 60), (205, 180, 140), (220, 200, 160),
    (120, 124, 130), (95, 100, 108), (186, 196, 200), (226, 214, 196),
]
BRICK = {6, 7}

ROAD_STYLE = {  # type: (width m, kind)  kind: 1 road, 2 path, 3 pedestrian zone
    "motorway": (16, 1), "trunk": (14, 1), "primary": (13, 1), "secondary": (11, 1), "tertiary": (9, 1),
    "motorway_link": (7, 1), "trunk_link": (7, 1), "primary_link": (7, 1), "secondary_link": (7, 1), "tertiary_link": (6, 1),
    "residential": (7, 1), "unclassified": (6.5, 1), "living_street": (5.5, 1), "service": (4.5, 1),
    "pedestrian": (9, 3), "footway": (2.6, 2), "path": (2, 2), "cycleway": (2.2, 2), "steps": (2.5, 2),
}
ROAD_TYPES = list(ROAD_STYLE)

GREEN = {"grass": 1, "garden": 1, "park": 1, "village_green": 1, "playground": 1, "common": 1,
         "meadow": 1, "scrub": 2, "wood": 3, "forest": 3, "pitch": 4, "cemetery": 1, "allotments": 2}


def building_height(t):
    h = parse_len(t.get("height"))
    if h is None:
        lv = parse_len(t.get("building:levels"))
        if lv is not None:
            h = lv * 3.2 + (parse_len(t.get("roof:levels")) or 0) * 2.5 + 1.0
    if h is None:
        kind = t.get("building", t.get("building:part", "yes"))
        h = {"garage": 3, "garages": 3, "shed": 3, "hut": 3, "roof": 4, "carport": 3, "kiosk": 3.5,
             "church": 22, "cathedral": 30, "train_station": 18, "commercial": 16, "retail": 12,
             "office": 20, "industrial": 10, "warehouse": 10, "apartments": 16, "house": 9,
             "residential": 15, "school": 13, "university": 18, "hospital": 22}.get(kind, 14)
    base = parse_len(t.get("min_height"))
    if base is None:
        ml = parse_len(t.get("building:min_level"))
        base = ml * 3.2 if ml is not None else 0
    return base / M_PER_STUD, max(h - base, 2.5) / M_PER_STUD


def colour_index(t, seed):
    c = t.get("building:colour") or t.get("colour")
    if c and c.startswith("#") and len(c) == 7:
        rgb = tuple(int(c[i: i + 2], 16) for i in (1, 3, 5))
        return min(range(len(PALETTE)), key=lambda i: sum((a - b) ** 2 for a, b in zip(PALETTE[i], rgb)))
    mat = t.get("building:material", "")
    if "brick" in mat:
        return 6 + seed % 2
    if t.get("building") in ("industrial", "warehouse", "garage", "garages"):
        return 10 + seed % 2
    return [0, 1, 2, 3, 4, 8, 9, 12, 13, 6, 0, 3][seed % 12]


def r1(v):
    return round(v, 1)


# ---------------------------------------------------------------- main
def main():
    nodes, ways, rels = load()
    P = {}
    for i, (lat, lon, _) in nodes.items():
        P[i] = project(lat, lon)

    def way_pts(i):
        return [P[n] for n in ways[i][0] if n in P]

    def centre_ll(i):
        pts = [nodes[n][:2] for n in ways[i][0] if n in nodes]
        if not pts:
            return None
        return sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)

    chunks = defaultdict(lambda: {"b": [], "r": [], "a": [], "t": [], "rail": []})

    def chunk_of(x, z):
        return (int(math.floor(x / CHUNK)), int(math.floor(z / CHUNK)))

    # --- buildings --------------------------------------------------------
    polys = []  # (pts, tags, is_part)
    for i, (nd, t) in ways.items():
        if len(nd) < 4 or nd[0] != nd[-1]:
            continue
        if t.get("building") in (None, "no") and "building:part" not in t:
            continue
        if t.get("layer", "0").startswith("-") or t.get("location") == "underground":
            continue
        c = centre_ll(i)
        if not c or not inside_area(*c):
            continue
        pts = way_pts(i)[:-1]
        if len(pts) < 3:
            continue
        polys.append((pts, t, "building:part" in t and "building" not in t, i))
    for i, (members, t) in rels.items():
        if t.get("type") != "multipolygon" or t.get("building") in (None, "no"):
            continue
        for mtype, ref, role in members:
            if mtype == "way" and role == "outer" and ref in ways:
                nd, _ = ways[ref]
                if len(nd) >= 4 and nd[0] == nd[-1]:
                    c = centre_ll(ref)
                    if c and inside_area(*c):
                        polys.append((way_pts(ref)[:-1], t, False, ref))

    # outlines that have building:part pieces inside are drawn by their parts only
    part_grid = defaultdict(list)
    for pts, t, is_part, _ in polys:
        if is_part:
            cx = sum(p[0] for p in pts) / len(pts)
            cz = sum(p[1] for p in pts) / len(pts)
            part_grid[(int(cx // 200), int(cz // 200))].append((cx, cz))

    def has_parts(pts):
        xs, zs = [p[0] for p in pts], [p[1] for p in pts]
        for gx in range(int(min(xs) // 200), int(max(xs) // 200) + 1):
            for gz in range(int(min(zs) // 200), int(max(zs) // 200) + 1):
                for cx, cz in part_grid.get((gx, gz), []):
                    if point_in_poly(cx, cz, pts):
                        return True
        return False

    road_rows = []
    for wid, (nd, t) in ways.items():
        if ROAD_STYLE.get(t.get("highway"), (0, 0))[1] == 1 and t.get("highway") != "service":
            pts = way_pts(wid)
            if len(pts) >= 2:
                road_rows.append([0, 0, 0, 0] + [v for p in pts for v in p])

    # --- enterable stores: real supermarkets / bakeries / kiosks -------------------
    BRANDS = [("REWE", "Rewo"), ("Rewe", "Rewo"), ("Lidl", "Lindl"), ("Aldi", "Alda"), ("ALDI", "Alda")]
    store_points = []
    for nid, (lat, lon, t) in nodes.items():
        if not inside_area(lat, lon):
            continue
        name = t.get("brand") or t.get("name") or ""
        kind = None
        if t.get("shop") == "supermarket":
            for real, parody in BRANDS:
                if name.startswith(real):
                    kind = parody
        elif t.get("shop") == "bakery":
            kind = "Baeckerei"
        elif t.get("shop") == "kiosk":
            kind = "Kiosk"
        if kind:
            store_points.append((kind, P[nid], t))
    for wid, (nd, t) in ways.items():
        if t.get("shop") == "supermarket" and "building" in t:
            name = t.get("brand") or t.get("name") or ""
            for real, parody in BRANDS:
                if name.startswith(real):
                    c = centre_ll(wid)
                    if c and inside_area(*c):
                        pts = way_pts(wid)
                        store_points.append((parody, (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)), t))
    building_polys = [(pts, t, wid) for pts, t, is_part, wid in polys if not is_part]
    stores, store_ways = [], set()
    per_kind = {"Rewo": 3, "Lindl": 2, "Alda": 2, "Baeckerei": 3, "Kiosk": 2}
    for kind, (sx0, sz0), t in store_points:
        if per_kind.get(kind, 0) <= 0:
            continue
        best = None
        for pts, bt, wid in building_polys:
            if wid in store_ways:
                continue
            xs = [p[0] for p in pts]
            zs = [p[1] for p in pts]
            if not (min(xs) <= sx0 <= max(xs) and min(zs) <= sz0 <= max(zs)):
                continue
            if point_in_poly(sx0, sz0, pts):
                best = (pts, bt, wid)
                break
        if not best:
            continue
        pts, bt, wid = best
        cx, cz, bx, bz, ang = min_rect(pts)
        area_m2 = abs(poly_area(pts)) * M_PER_STUD**2
        ratio = abs(poly_area(pts)) / max(bx * bz, 1e-6)
        if ratio < 0.8 or not (60 <= area_m2 <= 1600) or min(bx, bz) * M_PER_STUD < 7:
            continue
        # door on the side that faces the nearest real street
        best_side = None
        for lx, lz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            c, s_ = math.cos(ang), math.sin(ang)
            dx, dz = lx * c - lz * s_, lx * s_ + lz * c  # local axis -> world
            half = bx / 2 if lx else bz / 2
            mx, mz = cx + dx * half, cz + dz * half
            d = min(
                math.hypot(mx - x, mz - z)
                for r in road_rows
                for x, z in zip(r[4::2], r[5::2])
            ) if road_rows else 0
            if best_side is None or d < best_side[0]:
                best_side = (d, dx, dz, (bz if lx else bx), (bx if lx else bz))
        _, fx, fz, width, depth = best_side
        yaw = math.degrees(math.atan2(-fx, -fz))
        base, h = building_height(bt)
        per_kind[kind] -= 1
        store_ways.add(wid)
        label = {"Baeckerei": "Bäckerei", "Kiosk": "Kiosk"}.get(kind, kind)
        street = t.get("addr:street") or bt.get("addr:street") or ""
        stores.append((kind, f"{label} {street}".strip(), r1(cx), r1(cz), r1(width), r1(depth), round(yaw, 2), r1(base + h)))

    # --- custom building sites (stations, tower): cleared of OSM buildings / trees ----
    def nearest_on_roads(x, z):
        best = None
        for r in road_rows:
            pts = list(zip(r[4::2], r[5::2]))
            for (x1, z1), (x2, z2) in zip(pts, pts[1:]):
                dx, dz = x2 - x1, z2 - z1
                L2 = dx * dx + dz * dz or 1e-9
                u = max(0, min(1, ((x - x1) * dx + (z - z1) * dz) / L2))
                px, pz = x1 + u * dx, z1 + u * dz
                d = math.hypot(px - x, pz - z)
                if best is None or d < best[0]:
                    best = (d, px, pz, math.atan2(dz, dx))
        return best

    road_samples = []  # dense points along drivable roads (x, z, half width)
    for wid, (nd, t) in ways.items():
        hw = t.get("highway")
        if ROAD_STYLE.get(hw, (0, 0))[1] == 1 and hw != "service" and t.get("tunnel") != "yes":
            half = ROAD_STYLE[hw][0] / 2 / M_PER_STUD
            pts = way_pts(wid)
            for (x1, z1), (x2, z2) in zip(pts, pts[1:]):
                n_ = max(1, int(math.hypot(x2 - x1, z2 - z1) / 6))
                for k in range(n_ + 1):
                    road_samples.append((x1 + (x2 - x1) * k / n_, z1 + (z2 - z1) * k / n_, half))

    def in_site(site, x, z, margin=0.0):
        cx, cz, yaw, w, d = site
        a = math.radians(yaw)
        # local axes: right = (cos, -sin) ... (Roblox CFrame.Angles(0, yaw, 0))
        lx = (x - cx) * math.cos(a) - (z - cz) * math.sin(a)
        lz = (x - cx) * math.sin(a) + (z - cz) * math.cos(a)
        return abs(lx) <= w / 2 + margin and abs(lz) <= d / 2 + margin

    def site_clear(site):
        return not any(in_site(site, x, z, h) for x, z, h in road_samples)

    def site_at_road(px, pz, sizes_m):
        """Site whose front edge is on the pavement at (px, pz), facing the nearest road."""
        d, rx, rz, ang = nearest_on_roads(px, pz)
        nx, nz = px - rx, pz - rz
        ln = math.hypot(nx, nz) or 1
        nx, nz = nx / ln, nz / ln  # road -> place
        yaw = math.degrees(math.atan2(nx, nz))  # local -Z (front) points back to the road
        for wm, dm in sizes_m:
            w, dd = wm / M_PER_STUD, dm / M_PER_STUD
            for shift in (0, 1, -1, 2, -2):
                ox, oz = -nz * shift * w * 0.25, nx * shift * w * 0.25  # slide along the road
                cx = rx + nx * (d + dd / 2 + 1.5 / M_PER_STUD) + ox
                cz = rz + nz * (d + dd / 2 + 1.5 / M_PER_STUD) + oz
                site = (cx, cz, yaw, w, dd)
                if site_clear(site):
                    return site
        return None

    def poi(name, key=None):
        for wid, (nd, t) in ways.items():
            if t.get("name") == name and (key is None or key in t):
                pts = way_pts(wid)
                return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
        raise SystemExit("not found: " + name)

    sites = {}
    sizes = [(64, 48), (56, 44), (50, 40), (44, 34), (38, 30)]
    for key, name in (("Police", "Polizeipräsidium Dortmund"), ("FireRescue", "Feuer- und Rettungswache 1 - Stadtmitte")):
        site = site_at_road(*poi(name, "amenity" if key == "Police" else None), sizes)
        if site:
            sites[key] = site
        else:
            print("no clear site for", key)
    # residential tower on the biggest surface car park near the Hbf (not real, wished for)
    hbf_x, hbf_z = 0.0, 0.0
    best_tower = None
    tower_spots = []
    for wid, (nd, t) in ways.items():
        if t.get("amenity") == "parking" and t.get("parking", "surface") == "surface" and len(nd) > 3:
            c = centre_ll(wid)
            if not c or not inside_area(*c):
                continue
            pts = way_pts(wid)[:-1]
            cx, cz, sx, sz, ang = min_rect(pts)
            dist = math.hypot(cx - hbf_x, cz - hbf_z)
            side = 32 / M_PER_STUD
            if min(sx, sz) < side or dist > 2600:
                continue
            site = (cx, cz, -math.degrees(ang), side, side)
            if site_clear(site):
                tower_spots.append((dist, site))
                if best_tower is None or dist < best_tower[0]:
                    best_tower = (dist, site)
    if best_tower:
        tx, tz, tyaw, tw, td = best_tower[1]
        # front towards the nearest road
        dd, rx, rz, _ = nearest_on_roads(tx, tz)
        nx, nz = tx - rx, tz - rz
        yaw = math.degrees(math.atan2(nx / (math.hypot(nx, nz) or 1), nz / (math.hypot(nx, nz) or 1)))
        sites["Tower"] = (tx, tz, yaw, tw, td)
    else:
        print("no tower site found")

    # admin tower: the next free car park near the Hbf, away from the residential tower
    admin_tower = None
    if best_tower:
        for dist, site in sorted(tower_spots, key=lambda q: q[0]):
            if math.hypot(site[0] - best_tower[1][0], site[1] - best_tower[1][1]) > 60 / M_PER_STUD:
                admin_tower = site
                break
    if admin_tower:
        ax, az, _, aw, ad = admin_tower
        dd, rx, rz, _ = nearest_on_roads(ax, az)
        nx, nz = ax - rx, az - rz
        yaw = math.degrees(math.atan2(nx / (math.hypot(nx, nz) or 1), nz / (math.hypot(nx, nz) or 1)))
        sites["AdminTower"] = (ax, az, yaw, aw, ad)
    else:
        print("no admin tower site found")

    # shopping centre: a bigger free car park near the Hbf, away from both towers
    mall = None
    msize = 44 / M_PER_STUD
    best_m = None
    for wid, (nd, t) in ways.items():
        if t.get("amenity") == "parking" and t.get("parking", "surface") == "surface" and len(nd) > 3:
            c = centre_ll(wid)
            if not c or not inside_area(*c):
                continue
            cx, cz, sx, sz, ang = min_rect(way_pts(wid)[:-1])
            if min(sx, sz) < msize:
                continue
            site = (cx, cz, -math.degrees(ang), msize, msize)
            if not site_clear(site):
                continue
            far = all(math.hypot(cx - o[0], cz - o[1]) > 80 / M_PER_STUD for o in sites.values())
            dist = math.hypot(cx, cz)
            if far and dist < 3000 and (best_m is None or dist < best_m[0]):
                best_m = (dist, site)
    if best_m:
        mx_, mz_, _, mw, md = best_m[1]
        dd, rx, rz, _ = nearest_on_roads(mx_, mz_)
        nx, nz = mx_ - rx, mz_ - rz
        yaw = math.degrees(math.atan2(nx / (math.hypot(nx, nz) or 1), nz / (math.hypot(nx, nz) or 1)))
        sites["Mall"] = (mx_, mz_, yaw, mw, md)
    else:
        print("no mall site found")

    # ADMC / DXL / LKW: look inside real commercial / industrial areas for a free plot
    def overlaps(site):
        cx, cz, _, w, d = site
        r = math.hypot(w, d) / 2
        for o in sites.values():
            if math.hypot(o[0] - cx, o[1] - cz) < r + math.hypot(o[3], o[4]) / 2 + 4:
                return True
        for st in stores:
            if in_site(site, st[2], st[3], 10 / M_PER_STUD):
                return True
        return False

    def area_at(lat, lon):
        x0, z0 = project(lat, lon)
        best = None
        for wid, (nd, t) in ways.items():
            lu = t.get("landuse")
            if lu in ("industrial", "commercial", "retail") and len(nd) > 3:
                pts = way_pts(wid)
                if point_in_poly(x0, z0, pts):
                    a = abs(poly_area(pts))
                    if best is None or a < best[0]:
                        best = (a, pts)
        return best[1] if best else None

    for key, (lat, lon), sizes_k in (
        ("LKW", (51.51805, 7.48235), [(80, 60), (70, 54), (62, 48)]),
        ("DXL", (51.50310, 7.47774), [(62, 46), (56, 42), (50, 38)]),
        ("ADMC", (51.50056, 7.46886), [(58, 44), (52, 40), (46, 36), (40, 32)]),
    ):
        poly = area_at(lat, lon)
        if not poly:
            print("no area for", key)
            continue
        xs, zs = [p[0] for p in poly], [p[1] for p in poly]
        cx0, cz0 = project(lat, lon)
        step = 30 / M_PER_STUD
        cand = []
        gx = min(xs)
        while gx <= max(xs):
            gz = min(zs)
            while gz <= max(zs):
                if point_in_poly(gx, gz, poly):
                    cand.append((math.hypot(gx - cx0, gz - cz0), gx, gz))
                gz += step
            gx += step
        cand.sort()
        found = None
        for _, gx, gz in cand[:120]:
            site = site_at_road(gx, gz, sizes_k)
            if site and point_in_poly(site[0], site[1], poly) and not overlaps(site):
                found = site
                break
        if found:
            sites[key] = found
        else:
            print("no clear site for", key)

    def in_any_site(x, z):
        return any(in_site(st, x, z, 2 / M_PER_STUD) for st in sites.values())

    n_rect = n_tri = n_build = 0
    seen = set(store_ways)
    for pts, t, is_part, wid in polys:
        if wid in seen:
            continue
        seen.add(wid)
        if not is_part and part_grid and has_parts(pts):
            continue
        if any(in_any_site(x, z) for x, z in pts) or in_any_site(sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)):
            continue
        pts = simplify(pts, 0.35 / M_PER_STUD, closed=True)
        area = abs(poly_area(pts))
        if area < 10 / (M_PER_STUD**2) or len(pts) < 3:
            continue
        if poly_area(pts) < 0:
            pts = pts[::-1]
        base, h = building_height(t)
        col = colour_index(t, wid)
        cx = sum(p[0] for p in pts) / len(pts)
        cz = sum(p[1] for p in pts) / len(pts)
        ch = chunks[chunk_of(cx, cz)]
        rx, rz, sx, sz, ang = min_rect(pts)
        n_build += 1
        if area / max(sx * sz, 1e-6) > 0.93:
            ch["b"].append([1, r1(base), r1(h), col, r1(rx), r1(rz), r1(sx), r1(sz), round(math.degrees(ang), 2)])
            n_rect += 1
        else:
            tris = triangulate(pts)
            if not tris:
                continue
            flat = []
            for tri in tris:
                for x, z in tri:
                    flat += [r1(x), r1(z)]
            ch["b"].append([2, r1(base), r1(h), col] + flat)
            n_tri += len(tris)

    # --- roads, paths, rails ----------------------------------------------
    n_seg = 0
    for i, (nd, t) in ways.items():
        hw = t.get("highway")
        if t.get("tunnel") in ("yes", "building_passage") or t.get("layer", "0").startswith("-"):
            continue
        c = centre_ll(i)
        if not c or not inside_area(*c):
            continue
        rail = t.get("railway")
        if rail in ("rail", "light_rail", "tram") and t.get("tunnel") != "yes":
            pts = simplify(way_pts(i), 0.3 / M_PER_STUD)
            if len(pts) >= 2:
                flat = [v for p in pts for v in (r1(p[0]), r1(p[1]))]
                chunks[chunk_of(*pts[len(pts) // 2])]["rail"].append([1 if rail == "rail" else 2] + flat)
            continue
        if hw not in ROAD_STYLE:
            continue
        if hw == "pedestrian" and t.get("area") == "yes":
            pts = way_pts(i)[:-1]
            if len(pts) >= 3:
                flat = [v for tri in triangulate(simplify(pts, 0.3 / M_PER_STUD, True)) for p in tri for v in (r1(p[0]), r1(p[1]))]
                if flat:
                    chunks[chunk_of(*pts[0])]["a"].append([5] + flat)
            continue
        width, kind = ROAD_STYLE[hw]
        lanes = parse_len(t.get("lanes"))
        if kind == 1 and lanes:
            width = max(width, lanes * 3.25 + 0.5)
        w = parse_len(t.get("width"))
        if w and 1 < w < 30:
            width = w
        pts = simplify(way_pts(i), 0.4 / M_PER_STUD)
        if len(pts) < 2:
            continue
        flat = [v for p in pts for v in (r1(p[0]), r1(p[1]))]
        oneway = 1 if t.get("oneway") in ("yes", "1") or t.get("junction") == "roundabout" else 0
        chunks[chunk_of(*pts[len(pts) // 2])]["r"].append(
            [ROAD_TYPES.index(hw) + 1, r1(width / M_PER_STUD), oneway, 1 if t.get("footway") == "crossing" else 0] + flat
        )
        n_seg += len(pts) - 1

    # --- green areas, water, parking --------------------------------------
    for i, (nd, t) in ways.items():
        if len(nd) < 4 or nd[0] != nd[-1]:
            continue
        kind = GREEN.get(t.get("leisure") or t.get("landuse") or t.get("natural") or "")
        if t.get("natural") == "water" or t.get("water"):
            kind = 6
        if t.get("amenity") == "parking" and t.get("parking", "surface") == "surface":
            kind = 7
        if not kind:
            continue
        c = centre_ll(i)
        if not c or not inside_area(*c):
            continue
        pts = simplify(way_pts(i)[:-1], 0.5 / M_PER_STUD, True)
        if len(pts) < 3 or abs(poly_area(pts)) < 15 / M_PER_STUD**2:
            continue
        flat = [v for tri in triangulate(pts) for p in tri for v in (r1(p[0]), r1(p[1]))]
        if flat:
            chunks[chunk_of(*pts[0])]["a"].append([kind] + flat)

    # --- trees (never on a driving lane or a building site) ----------------------------
    n_trees = n_dropped = 0
    tree_grid = defaultdict(list)
    for x, z, h in road_samples:
        tree_grid[(int(x // 60), int(z // 60))].append((x, z, h))
    for i, (lat, lon, t) in nodes.items():
        if t.get("natural") == "tree" and inside_area(lat, lon):
            x, z = P[i]
            on_road = False
            for gx in (int(x // 60) - 1, int(x // 60), int(x // 60) + 1):
                for gz in (int(z // 60) - 1, int(z // 60), int(z // 60) + 1):
                    for rx, rz, h in tree_grid.get((gx, gz), []):
                        if math.hypot(rx - x, rz - z) < h + 0.4 / M_PER_STUD:
                            on_road = True
                            break
            if on_road or in_any_site(x, z):
                n_dropped += 1
                continue
            chunks[chunk_of(x, z)]["t"].append([r1(x), r1(z)])
            n_trees += 1
    print(f"trees kept {n_trees}, removed from roads/sites {n_dropped}")

    # --- write data modules -----------------------------------------------------
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for old in OUT_DIR.glob("Chunk_*.lua"):
        old.unlink()

    def lua(v):
        if isinstance(v, list):
            return "{" + ",".join(lua(x) for x in v) + "}"
        if isinstance(v, float):
            s = f"{v:.2f}".rstrip("0").rstrip(".")
            return s if s not in ("-0", "") else "0"
        return str(v)

    total = 0
    for n, (key, data) in enumerate(sorted(chunks.items())):
        body = ",\n".join(f"\t{k} = {lua(data[k])}" for k in ("b", "r", "a", "t", "rail"))
        text = (
            "-- Generated by tools/osm_convert.py. Do not edit.\n"
            "-- Map data © OpenStreetMap contributors (ODbL).\n"
            f"return {{\n{body},\n}}\n"
        )
        (OUT_DIR / f"Chunk_{n:02d}.lua").write_text(text, encoding="utf-8")
        total += len(text)

    meta = (
        "-- Generated by tools/osm_convert.py. Do not edit.\n"
        "return {\n"
        "\troadTypes = {" + ", ".join(f'"{t}"' for t in ROAD_TYPES) + "},\n"
        "\troadKinds = {" + ", ".join(str(ROAD_STYLE[t][1]) for t in ROAD_TYPES) + "},\n"
        "\tpalette = {" + ", ".join("{%d, %d, %d}" % c for c in PALETTE) + "},\n"
        "\tbrick = {" + ", ".join(str(i + 1) for i in sorted(BRICK)) + "},\n"
        "}\n"
    )
    (OUT_DIR.parent / "CityMeta.lua").write_text(meta, encoding="utf-8")

    # --- real locations -------------------------------------------------------
    def way_centre(wid):
        pts = way_pts(wid)
        return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))

    drivable = []
    for data in chunks.values():
        for r in data["r"]:
            if ROAD_STYLE[ROAD_TYPES[r[0] - 1]][1] == 1 and ROAD_TYPES[r[0] - 1] != "service":
                drivable.append(r)

    def nearest_road(x, z):
        best = None
        for r in drivable:
            pts = list(zip(r[4::2], r[5::2]))
            for (x1, z1), (x2, z2) in zip(pts, pts[1:]):
                dx, dz = x2 - x1, z2 - z1
                L = dx * dx + dz * dz or 1e-9
                u = max(0, min(1, ((x - x1) * dx + (z - z1) * dz) / L))
                px, pz = x1 + u * dx, z1 + u * dz
                d = math.hypot(px - x, pz - z)
                if best is None or d < best[0]:
                    best = (d, px, pz, r[1], math.atan2(dz, dx))
        return best

    def spot(x, z):
        """Marker spot: on the sidewalk between the place and its nearest road."""
        d, px, pz, width, ang = nearest_road(x, z)
        dirx, dirz = (x - px), (z - pz)
        ln = math.hypot(dirx, dirz) or 1
        off = width / 2 + 2.5 / M_PER_STUD
        sx, sz = px + dirx / ln * off, pz + dirz / ln * off
        gx, gz = px + dirx / ln * (width / 4), pz + dirz / ln * (width / 4)  # garage: kerb lane
        return (r1(sx), r1(sz)), (r1(gx), r1(gz)), round(math.degrees(ang), 1)

    def by_name(name, key=None):
        for wid, (nd, t) in ways.items():
            if t.get("name") == name and (key is None or key in t):
                return way_centre(wid)
        for nid, (lat, lon, t) in nodes.items():
            if t.get("name") == name and (key is None or key in t):
                return P[nid]
        raise SystemExit("not found: " + name)

    places = {
        "Police": ("Polizeipräsidium", by_name("Polizeipräsidium Dortmund", "amenity")),
        "Fire": ("Feuer- und Rettungswache 1", by_name("Feuer- und Rettungswache 1 - Stadtmitte")),
        "Rettungsdienst": ("Rettungswache 1 (DRH)", by_name("Feuer- und Rettungswache 1 - Stadtmitte")),
        "Notarzt": ("NEF-Standort Klinikum Mitte", by_name("Städtische Kliniken")),
        "ADMC": ("ADMC Stützpunkt Markgrafenstraße", by_name("Orlen", "amenity")),
        "DXL": ("DXL Zustellbasis Nord", by_name("Polizeiwache Nord")),
        "LKW": ("Spedition am Hafen", by_name("Brügmannplatz")),
        "Bus": ("Busbahnhof Hauptbahnhof", by_name("Busbahnhof Dortmund Hauptbahnhof")),
    }
    lines = []
    SITE_OF = {"Police": "Police", "Fire": "FireRescue", "Rettungsdienst": "FireRescue", "Notarzt": "FireRescue", "ADMC": "ADMC", "DXL": "DXL", "LKW": "LKW"}
    SITE_TITLE = {"Police": "Polizeiwache", "FireRescue": "Feuer- und Rettungswache 1", "ADMC": "ADMC Stützpunkt", "DXL": "DXL Paketzentrum", "LKW": "Spedition Dortmund"}
    for job, (title, (x, z)) in places.items():
        (mx, mz), (gx, gz), ang = spot(x, z)
        site = sites.get(SITE_OF.get(job, ""))
        if site:
            # navigation target = the station's entrance on the street side
            cx, cz, yaw, w_, d_ = site
            a = math.radians(yaw)
            fx, fz = -math.sin(a), -math.cos(a)  # local -Z in world space
            mx, mz = r1(cx + fx * (d_ / 2 + 3 / M_PER_STUD)), r1(cz + fz * (d_ / 2 + 3 / M_PER_STUD))
            gx, gz = mx, mz
            title = SITE_TITLE[SITE_OF[job]]
        lines.append(f'\t{job} = {{ title = "{title}", marker = {{ {mx}, {mz} }}, garage = {{ {gx}, {gz} }}, angle = {ang} }},')
    shops = {
        "Handyland": ("Handyland (Westenhellweg)", by_name("Thier-Galerie")),
        "Dealership": ("Autohaus Westfalendamm", by_name("Volkswagen Zentrum Dortmund")),
        "Hospital": ("Klinikum Dortmund Mitte", by_name("Städtische Kliniken")),
    }
    shop_lines = []
    for key, (title, (x, z)) in shops.items():
        (mx, mz), _, ang = spot(x, z)
        shop_lines.append(f'\t{key} = {{ title = "{title}", marker = {{ {mx}, {mz} }}, angle = {ang} }},')
    fuel_lines = []
    for wid, (nd, t) in ways.items():
        if t.get("amenity") == "fuel":
            c = centre_ll(wid)
            if c and inside_area(*c):
                (mx, mz), _, _ = spot(*way_centre(wid))
                fuel_lines.append(f"\t{{ {mx}, {mz} }},")
    hbf = by_name("Dortmund Hbf", "railway")
    # spawn: on the Königswall side of the station
    (sx, sz), _, sang = spot(hbf[0], hbf[1] + 60)
    LOC_FILE.write_text(
        "-- Generated by tools/osm_convert.py from real Dortmund locations.\n"
        "-- Positions are {x, z} in studs (1 stud = 0.28 m), origin = Dortmund Hbf.\n"
        "local Locations = {}\n\n"
        f"Locations.Spawn = {{ {sx}, {sz} }}\n\n"
        "Locations.Jobs = {\n" + "\n".join(lines) + "\n}\n\n"
        "Locations.Shops = {\n" + "\n".join(shop_lines) + "\n}\n\n"
        "Locations.Fuel = {\n" + "\n".join(fuel_lines) + "\n}\n\n"
        "-- Enterable stores: centre, width (door side), depth, yaw (door faces local -Z), building top\n"
        "Locations.Stores = {\n"
        + "\n".join(
            f'\t{{ kind = "{k}", name = "{nm}", x = {x}, z = {z}, width = {w_}, depth = {d_}, yaw = {y}, top = {tp} }},'
            for k, nm, x, z, w_, d_, y, tp in stores
        )
        + "\n}\n\n"
        "-- Custom building sites: centre x/z, yaw (front = local -Z faces the road), width, depth\n"
        "Locations.Sites = {\n"
        + "\n".join(f"\t{k} = {{ x = {r1(v[0])}, z = {r1(v[1])}, yaw = {round(v[2], 2)}, width = {r1(v[3])}, depth = {r1(v[4])} }}," for k, v in sites.items())
        + "\n}\n\n"
        f"Locations.Bounds = {{ {r1(project(SOUTH, WEST)[0])}, {r1(project(NORTH, WEST)[1])}, {r1(project(SOUTH, EAST)[0])}, {r1(project(SOUTH, WEST)[1])} }}\n\n"
        "return Locations\n",
        encoding="utf-8",
    )

    print(f"stores: {[(st[0], st[1]) for st in stores]}")
    print(f"buildings {n_build} (rect {n_rect}, triangles {n_tri}), road segments {n_seg}, trees {n_trees}")
    print(f"chunks {len(chunks)}, data {total // 1024} KB")


if __name__ == "__main__":
    main()
