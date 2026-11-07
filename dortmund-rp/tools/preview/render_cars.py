"""Software-render generated car meshes to a PNG contact sheet (for checking shapes)."""
import json, math, struct, sys
from PIL import Image, ImageDraw

def load_glb(p):
    d = open(p, 'rb').read(); jl = struct.unpack('<I', d[12:16])[0]
    js = json.loads(d[20:20 + jl]); bin_ = d[20 + jl + 8:]
    out = []
    for m in js['meshes']:
        pr = m['primitives'][0]; acc = js['accessors']
        def read(ai, fmt):
            a = acc[ai]; bv = js['bufferViews'][a['bufferView']]; o = bv['byteOffset']; sz = struct.calcsize(fmt)
            return [struct.unpack_from(fmt, bin_, o + i * sz) for i in range(a['count'])]
        P = read(pr['attributes']['POSITION'], '<3f'); I = [x[0] for x in read(pr['indices'], '<I')]
        out.append((m['name'], P, I, js['materials'][pr['material']]['pbrMetallicRoughness']['baseColorFactor']))
    return out

def render(path, label, yaw_deg=35, W=420, H=260, paint=(0.75, 0.12, 0.12), scheme=None):
    img = Image.new('RGB', (W, H), (235, 238, 242)); d = ImageDraw.Draw(img)
    yaw, pitch = math.radians(yaw_deg), math.radians(16)
    def proj(p):
        x, y, z = p
        x2 = x * math.cos(yaw) - z * math.sin(yaw); z2 = x * math.sin(yaw) + z * math.cos(yaw)
        y2 = y * math.cos(pitch) + z2 * math.sin(pitch); z3 = -y * math.sin(pitch) + z2 * math.cos(pitch)
        return x2, y2, z3  # camera at -z3 looking +z3
    light = (0.35, 0.85, -0.4); ln = math.sqrt(sum(v * v for v in light)); light = [v / ln for v in light]
    tris = []
    for name, P, I, col in load_glb(path):
        if name.startswith('Marker'):
            continue
        if scheme and name in scheme:
            col = scheme[name]
        elif name in ('Body', 'SideLow', 'SideMid', 'SideHigh', 'Hood', 'Roof', 'Deck'):
            col = paint
        for i in range(0, len(I), 3):
            a, b, c = (P[I[i]], P[I[i + 1]], P[I[i + 2]])
            u = [b[k] - a[k] for k in range(3)]; v = [c[k] - a[k] for k in range(3)]
            n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
            nl = math.sqrt(sum(x * x for x in n)) or 1; n = [x / nl for x in n]
            pa, pb, pc = proj(a), proj(b), proj(c)
            # facing camera: rotated normal has negative z3 component
            nx = n[0] * math.cos(yaw) - n[2] * math.sin(yaw); nz2 = n[0] * math.sin(yaw) + n[2] * math.cos(yaw)
            nz3 = -n[1] * math.sin(pitch) + nz2 * math.cos(pitch)
            if nz3 >= 0:
                continue
            sh = max(0.0, sum(n[k] * light[k] for k in range(3))) * 0.75 + 0.25
            tris.append(((pa[2] + pb[2] + pc[2]) / 3, (pa, pb, pc), tuple(int(min(255, col[k] * 255 * sh)) for k in range(3))))
    xs = [p[0] for t in tris for p in t[1]]; ys = [p[1] for t in tris for p in t[1]]
    s = min((W - 40) / (max(xs) - min(xs)), (H - 40) / (max(ys) - min(ys)))
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    for _, pts, c in sorted(tris, key=lambda t: -t[0]):
        d.polygon([(W / 2 + (p[0] - cx) * s, H / 2 - (p[1] - cy) * s) for p in pts], fill=c)
    d.text((8, 6), label, fill=(20, 20, 20))
    return img

if __name__ == '__main__':
    names = sys.argv[2:]
    cols = 3
    sheet = Image.new('RGB', (420 * cols, 260 * ((len(names) + cols - 1) // cols)), (255, 255, 255))
    for i, n in enumerate(names):
        sheet.paste(render(f'build/meshes/{n}.glb', n), ((i % cols) * 420, (i // cols) * 260))
    sheet.save(sys.argv[1])
