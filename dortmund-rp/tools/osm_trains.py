#!/usr/bin/env python3
"""Stadtbahn line(s) from OpenStreetMap route relations -> src/ReplicatedStorage/Shared/TrainData.lua

The route's ways are chained in relation order (reversed where needed), clipped to the
map, resampled (2..30 studs between points) and the stop nodes are put on the line as
distances along it. In game the line runs on an elevated viaduct above its real route
(the city centre part is a tunnel in reality).
"""
import math, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from osm_convert import project, inside_area  # noqa: E402
from osm_load import load  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "src" / "ReplicatedStorage" / "Shared" / "TrainData.lua"
LINES = [
    # relation id, line id, colour, shares (line, last shared station) or None
    (2675099, "U43", (0, 133, 199), None),
    (177501, "U44", (150, 45, 140), ("U43", "Reinoldikirche")),
]


def chain(rel, nodes, ways):
    mem, _ = rel
    seq = []
    for ty, r, role in mem:
        if ty != "way" or r not in ways or role in ("platform", "platform_entry_only", "platform_exit_only"):
            continue
        nd = [n for n in ways[r][0] if n in nodes]
        if len(nd) < 2:
            continue
        if not seq:
            seq = nd[:]
            continue
        # attach in the right direction (also flip the first way if needed)
        if nd[0] == seq[-1]:
            seq += nd[1:]
        elif nd[-1] == seq[-1]:
            seq += nd[::-1][1:]
        elif len(seq) == len(ways[mem[0][1]][0]) and nd[0] == seq[0]:
            seq = seq[::-1] + nd[1:]
        elif len(seq) == len(ways[mem[0][1]][0]) and nd[-1] == seq[0]:
            seq = seq[::-1] + nd[::-1][1:]
        else:
            # gap: jump to the nearer end
            a, b = project(*nodes[nd[0]][:2]), project(*nodes[nd[-1]][:2])
            last = project(*nodes[seq[-1]][:2])
            seq += nd if math.dist(last, a) <= math.dist(last, b) else nd[::-1]
    return seq


def project_on(path, cum, q):
    """distance along `path` of the point nearest q, and that distance to q"""
    best = (None, None)
    for i, (a, b) in enumerate(zip(path, path[1:])):
        ax, az = b[0] - a[0], b[1] - a[1]
        L2 = ax * ax + az * az
        f = max(0, min(1, ((q[0] - a[0]) * ax + (q[1] - a[1]) * az) / L2)) if L2 else 0
        d = math.dist(q, (a[0] + ax * f, a[1] + az * f))
        if best[1] is None or d < best[1]:
            best = (cum[i] + math.sqrt(L2) * f, d)
    return best


def share(base, last_shared, res, stations, cum):
    """Use the base line's track (exactly) up to where this line turns off after
    `last_shared`; from there this line's own points. Returns path, stations,
    cumulative distances and the distance where the own part starts."""
    bres, bst, bcum = base
    s_last = next(s for n, s in bst if n == last_shared)
    # first own point: past the shared station and > 6 studs off the base track
    start = None
    for i, p in enumerate(res):
        sb, d = project_on(bres, bcum, p)
        if sb >= s_last and d > 6:
            start = i
            break
    assert start, "line never leaves the shared track"
    s_join, _ = project_on(bres, bcum, res[start - 1])
    path = [p for p, c in zip(bres, bcum) if c < s_join]
    # the join point on the base track, then this line's own points
    for i, (a, b) in enumerate(zip(bres, bres[1:])):
        if bcum[i] <= s_join <= bcum[i + 1]:
            f = (s_join - bcum[i]) / max(bcum[i + 1] - bcum[i], 1e-6)
            path.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
            break
    path += res[start:]
    ncum = [0.0]
    for a, b in zip(path, path[1:]):
        ncum.append(ncum[-1] + math.dist(a, b))
    # shared stations keep the base line's distances; own stations are re-measured
    own = []
    old_cum = cum
    for name, s_old in stations:
        if any(n == name for n, s in bst if s <= s_last):
            continue
        # position of the old station on the old path -> new path
        for i, (a, b) in enumerate(zip(res, res[1:])):
            if old_cum[i] <= s_old <= old_cum[i + 1]:
                f = (s_old - old_cum[i]) / max(old_cum[i + 1] - old_cum[i], 1e-6)
                q = (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
                s_new, _ = project_on(path, ncum, q)
                if s_new > s_join + 100:
                    own.append((name, round(s_new, 1)))
                break
    shared = [(n, s) for n, s in bst if s <= s_last]
    return path, shared + own, ncum, s_join


def main():
    nodes, ways, rels = load()
    out = []
    by_id = {}
    for rid, line_id, color, shares in LINES:
        rel = rels[rid]
        seq = chain(rel, nodes, ways)
        # longest run of nodes inside the map
        best, cur = [], []
        for n in seq:
            if inside_area(*nodes[n][:2]):
                cur.append(n)
                if len(cur) > len(best):
                    best = cur[:]
            else:
                cur = []
        pts = [project(*nodes[n][:2]) for n in best]
        # resample
        res = [pts[0]]
        for p in pts[1:]:
            d = math.dist(res[-1], p)
            if d < 2:
                continue
            k = int(d // 30) + 1
            a = res[-1]
            for i in range(1, k + 1):
                f = i / k
                res.append((a[0] + (p[0] - a[0]) * f, a[1] + (p[1] - a[1]) * f))
        cum = [0.0]
        for a, b in zip(res, res[1:]):
            cum.append(cum[-1] + math.dist(a, b))
        # stops -> distance along the line (nearest point)
        stations = []
        for ty, r, role in rel[0]:
            if ty == "node" and r in nodes and role and role.startswith("stop"):
                q = project(*nodes[r][:2])
                bestd, bests = None, None
                for i, (a, b) in enumerate(zip(res, res[1:])):
                    ax, az = b[0] - a[0], b[1] - a[1]
                    L2 = ax * ax + az * az
                    f = max(0, min(1, ((q[0] - a[0]) * ax + (q[1] - a[1]) * az) / L2)) if L2 else 0
                    px, pz = a[0] + ax * f, a[1] + az * f
                    d = math.dist(q, (px, pz))
                    if bestd is None or d < bestd:
                        bestd, bests = d, cum[i] + math.sqrt(L2) * f
                if bestd is not None and bestd < 60:
                    name = nodes[r][2].get("name", "Halt").replace('"', "'")
                    if not stations or abs(stations[-1][1] - bests) > 150:
                        stations.append((name, round(bests, 1)))
        stations.sort(key=lambda s: s[1])
        # the next real stop lies just off the map: end the line at the map edge
        # under that stop's name (only if there is room for a station)
        names = [nodes[r][2].get("name") for ty, r, role in rel[0]
                 if ty == "node" and r in nodes and role and role.startswith("stop")]
        if stations and stations[-1][0] in names:
            k = names.index(stations[-1][0])
            if k + 1 < len(names) and cum[-1] - stations[-1][1] > 300:
                stations.append((names[k + 1].replace('"', "'"), round(cum[-1] - 70, 1)))
        branch_from = 0
        if shares:
            res, stations, cum, branch_from = share(by_id[shares[0]], shares[1], res, stations, cum)
        out.append((line_id, rel[1].get("name", line_id), color, res, round(cum[-1], 1), stations, round(branch_from, 1)))
        by_id[line_id] = (res, stations, cum)
        print(f"{line_id}: {len(res)} points, {cum[-1] * 0.28:.0f} m, own track from {branch_from * 0.28:.0f} m, stations: {stations}")
        
    lines = ["-- Generated by tools/osm_trains.py. Do not edit.", "-- Map data © OpenStreetMap contributors (ODbL).",
             "-- path = { x1, z1, x2, z2, ... } (studs); stations = { { name, distance along the path } }", "return {"]
    for line_id, name, color, res, length, stations, branch_from in out:
        lines.append(f'\t{{\n\t\tid = "{line_id}",\n\t\tname = "{name}",\n\t\tcolor = {{ {color[0]}, {color[1]}, {color[2]} }},\n\t\tlength = {length},\n\t\tbranchFrom = {branch_from},')
        lines.append("\t\tstations = {")
        lines += [f'\t\t\t{{ "{n}", {s} }},' for n, s in stations]
        lines.append("\t\t},")
        flat = ", ".join(f"{x:.1f}, {z:.1f}" for x, z in res)
        lines.append(f"\t\tpath = {{ {flat} }},")
        lines.append("\t},")
    lines += ["}", ""]
    OUT.write_text("\n".join(lines))


if __name__ == "__main__":
    main()
