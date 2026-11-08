#!/usr/bin/env python3
"""Render an exported Roblox model (export.luau JSON) from several angles, with real meshes.
   python3 tools/toolbox/render_model.py model.json out.png "title" """
import json, math, struct, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from fetch import fetch
from PIL import Image, ImageDraw


def parse_mesh(data):
    """Roblox .mesh v1-v5 -> (verts[(x,y,z)], faces[(a,b,c)])"""
    if data.startswith(b"version 1"):
        text = data.split(b"\n", 2)[2].decode()
        nums = [float(x) for x in text.replace("][", ",").replace("[", "").replace("]", "").split(",") if x.strip()]
        scale = 0.5 if data.startswith(b"version 1.00") else 1
        verts, faces = [], []
        for k in range(0, len(nums) - 8, 9):
            verts.append((nums[k] * scale, nums[k + 1] * scale, nums[k + 2] * scale))
        for k in range(0, len(verts) - 2, 3):
            faces.append((k, k + 1, k + 2))
        return verts, faces
    nl = data.index(b"\n")
    ver = data[8:nl].decode()
    o = nl + 1
    if ver.startswith("2") or ver.startswith("3"):
        hsize = struct.unpack_from("<H", data, o)[0]
        vsize = data[o + 2]
        if ver.startswith("2"):
            nv, nf = struct.unpack_from("<II", data, o + 4)
            lods = None
        else:
            nl_ = struct.unpack_from("<H", data, o + 6)[0]
            nv, nf = struct.unpack_from("<II", data, o + 8)
            lods = nl_
        o += hsize
    elif ver.startswith("4") or ver.startswith("5"):
        hsize = struct.unpack_from("<H", data, o)[0]
        nv, nf = struct.unpack_from("<II", data, o + 4)
        nlods, nbones = struct.unpack_from("<HH", data, o + 12)
        vsize = 40
        lods = nlods
        o += hsize
    else:
        raise ValueError("mesh " + ver)
    verts = []
    for k in range(nv):
        x, y, z = struct.unpack_from("<3f", data, o + k * vsize)
        verts.append((x, y, z))
    o += nv * vsize
    if ver.startswith("4") or ver.startswith("5"):
        o += nbones and 0  # skin data comes after LODs; we only need faces
    faces = [struct.unpack_from("<3I", data, o + k * 12) for k in range(nf)]
    o += nf * 12
    if lods and lods > 1:
        lodoff = struct.unpack_from(f"<{lods}I", data, o)
        faces = faces[lodoff[0]:lodoff[1]] if lodoff[1] > lodoff[0] else faces
    return verts, faces


BOX = [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]
BOX_F = [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4), (3, 7, 6), (3, 6, 2), (0, 4, 7), (0, 7, 3), (1, 2, 6), (1, 6, 5)]


def load_model(path):
    parts = json.loads(Path(path).read_text())
    mesh_cache = {}
    tris = []  # (world pts, colour)
    for p in parts:
        if p["transparency"] >= 0.95:
            continue
        c = p["cf"]
        pos = (c[0], c[1], c[2])
        R = ((c[3], c[4], c[5]), (c[6], c[7], c[8]), (c[9], c[10], c[11]))
        sx, sy, sz = p["size"]

        def world(v):
            x, y, z = v
            return (pos[0] + R[0][0] * x + R[0][1] * y + R[0][2] * z,
                    pos[1] + R[1][0] * x + R[1][1] * y + R[1][2] * z,
                    pos[2] + R[2][0] * x + R[2][1] * y + R[2][2] * z)

        col = tuple(p["color"])
        mesh = p.get("mesh")
        if mesh and (p["class"] == "MeshPart" or p.get("special") in ("Enum.MeshType.FileMesh", None)):
            if mesh not in mesh_cache:
                try:
                    mesh_cache[mesh] = parse_mesh(fetch(int(mesh)).read_bytes())
                except Exception as e:  # noqa: BLE001
                    mesh_cache[mesh] = None
            m = mesh_cache[mesh]
            if not m:
                continue
            verts, faces = m
            if not verts:
                continue
            mn = [min(v[k] for v in verts) for k in range(3)]
            mx = [max(v[k] for v in verts) for k in range(3)]
            ctr = [(mn[k] + mx[k]) / 2 for k in range(3)]
            if p["class"] == "MeshPart":
                ext = [max(mx[k] - mn[k], 1e-6) for k in range(3)]
                s = [p["size"][k] / ext[k] for k in range(3)]
            else:
                s = p.get("scale", [1, 1, 1])
                ctr = [0, 0, 0]
            W = [world(((v[0] - ctr[0]) * s[0], (v[1] - ctr[1]) * s[1], (v[2] - ctr[2]) * s[2])) for v in verts]
            for a, b, cc in faces:
                if a < len(W) and b < len(W) and cc < len(W):
                    tris.append(((W[a], W[b], W[cc]), col))
        else:
            V = [world((bx * sx / 2, by * sy / 2, bz * sz / 2)) for bx, by, bz in BOX]
            for a, b, cc in BOX_F:
                tris.append(((V[a], V[b], V[cc]), col))
    return tris


def render(tris, yaw, pitch, W=520, H=320, label=""):
    img = Image.new("RGB", (W, H), (236, 238, 242))
    d = ImageDraw.Draw(img)
    cy, sy_, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    light = (0.35, 0.85, -0.4)
    out = []
    for (a, b, c), col in tris:
        P = []
        for x, y, z in (a, b, c):
            x2 = x * cy - z * sy_
            z2 = x * sy_ + z * cy
            y2 = y * cp + z2 * sp
            z3 = -y * sp + z2 * cp
            P.append((x2, y2, z3))
        u = [b[k] - a[k] for k in range(3)]
        v = [c[k] - a[k] for k in range(3)]
        n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
        ln = math.sqrt(sum(t * t for t in n)) or 1
        n = [t / ln for t in n]
        sh = abs(sum(n[k] * light[k] for k in range(3))) * 0.7 + 0.3
        out.append((sum(p[2] for p in P) / 3, P, tuple(int(min(255, col[k] * 255 * sh)) for k in range(3))))
    if not out:
        return img
    xs = [p[0] for t in out for p in t[1]]
    ys = [p[1] for t in out for p in t[1]]
    s = min((W - 20) / (max(xs) - min(xs) + 1e-6), (H - 30) / (max(ys) - min(ys) + 1e-6))
    cx, cyy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    for _, P, col in sorted(out, key=lambda t: -t[0]):
        d.polygon([(W / 2 + (p[0] - cx) * s, H / 2 + 8 - (p[1] - cyy) * s) for p in P], fill=col)
    d.text((6, 4), label, fill=(20, 20, 20))
    return img


if __name__ == "__main__":
    tris = load_model(sys.argv[1])
    title = sys.argv[3] if len(sys.argv) > 3 else ""
    views = [(math.radians(30), math.radians(14), "3/4"), (0, math.radians(6), "view A"), (math.pi, math.radians(6), "view B"), (math.pi / 2, math.radians(4), "side")]
    sheet = Image.new("RGB", (1040, 640), (255, 255, 255))
    for k, (yw, pt, lab) in enumerate(views):
        sheet.paste(render(tris, yw, pt, label=f"{title} {lab}"), ((k % 2) * 520, (k // 2) * 320))
    sheet.save(sys.argv[2])
    print(len(tris), "triangles")
