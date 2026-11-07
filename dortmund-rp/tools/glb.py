"""Minimal binary glTF (.glb) writer: named mesh nodes with flat colours and smooth normals.

Coordinates are Roblox studs (x right, y up, z back). glTF is metres, but Roblox's
importer uses the file's numbers as studs when the scale is left at 1.
"""
import json
import math
import struct


def _normals(positions, indices):
    acc = [[0.0, 0.0, 0.0] for _ in positions]
    for i in range(0, len(indices), 3):
        a, b, c = indices[i], indices[i + 1], indices[i + 2]
        pa, pb, pc = positions[a], positions[b], positions[c]
        u = [pb[k] - pa[k] for k in range(3)]
        v = [pc[k] - pa[k] for k in range(3)]
        n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
        for idx in (a, b, c):
            for k in range(3):
                acc[idx][k] += n[k]
    # smooth shading: average normals of vertices that share a position
    groups = {}
    for i, p in enumerate(positions):
        groups.setdefault((round(p[0], 3), round(p[1], 3), round(p[2], 3)), []).append(i)
    for members in groups.values():
        if len(members) > 1:
            s = [sum(acc[i][k] for i in members) for k in range(3)]
            for i in members:
                acc[i] = list(s)
    out = []
    for n in acc:
        length = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) or 1.0
        out.append([n[0] / length, n[1] / length, n[2] / length])
    return out


def write_glb(path, meshes):
    """meshes: list of dicts {name, positions:[[x,y,z]], indices:[int], color:(r,g,b) 0-1,
    metallic, roughness, alpha (optional)}"""
    buffer = bytearray()
    gltf = {
        "asset": {"version": "2.0", "generator": "EmergencyDortmund"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(meshes)))}],
        "nodes": [],
        "meshes": [],
        "materials": [],
        "accessors": [],
        "bufferViews": [],
        "buffers": [],
    }

    def add_view(data, target):
        while len(buffer) % 4:
            buffer.append(0)
        offset = len(buffer)
        buffer.extend(data)
        gltf["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        return len(gltf["bufferViews"]) - 1

    for i, m in enumerate(meshes):
        pos, idx = m["positions"], m["indices"]
        nrm = m.get("normals") or _normals(pos, idx)
        pv = add_view(b"".join(struct.pack("<3f", *p) for p in pos), 34962)
        nv = add_view(b"".join(struct.pack("<3f", *n) for n in nrm), 34962)
        iv = add_view(b"".join(struct.pack("<I", j) for j in idx), 34963)
        mins = [min(p[k] for p in pos) for k in range(3)]
        maxs = [max(p[k] for p in pos) for k in range(3)]
        a0 = len(gltf["accessors"])
        gltf["accessors"] += [
            {"bufferView": pv, "componentType": 5126, "count": len(pos), "type": "VEC3", "min": mins, "max": maxs},
            {"bufferView": nv, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": iv, "componentType": 5125, "count": len(idx), "type": "SCALAR"},
        ]
        r, g, b = m.get("color", (0.8, 0.8, 0.8))
        mat = {
            "name": m["name"] + "_mat",
            "pbrMetallicRoughness": {
                "baseColorFactor": [r, g, b, m.get("alpha", 1.0)],
                "metallicFactor": m.get("metallic", 0.0),
                "roughnessFactor": m.get("roughness", 0.6),
            },
            "doubleSided": False,
        }
        if m.get("alpha", 1.0) < 1.0:
            mat["alphaMode"] = "BLEND"
        gltf["materials"].append(mat)
        gltf["meshes"].append(
            {"name": m["name"], "primitives": [{"attributes": {"POSITION": a0, "NORMAL": a0 + 1}, "indices": a0 + 2, "material": i}]}
        )
        gltf["nodes"].append({"name": m["name"], "mesh": i})

    while len(buffer) % 4:
        buffer.append(0)
    gltf["buffers"].append({"byteLength": len(buffer)})
    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(buffer)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(buffer), 0x004E4942))
        f.write(buffer)
