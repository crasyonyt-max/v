"""Writes a binary AndroidManifest.xml (no aapt2 needed)."""
import struct
import sys

ANDROID_NS = "http://schemas.android.com/apk/res/android"

# (name, resource id) for android: attributes, in resource-id order
ATTRS = {
    "theme": 0x01010000,
    "label": 0x01010001,
    "name": 0x01010003,
    "exported": 0x01010010,
    "minSdkVersion": 0x0101020C,
    "versionCode": 0x0101021B,
    "versionName": 0x0101021C,
    "targetSdkVersion": 0x01010270,
}
T_REF, T_STRING, T_INT, T_BOOL = 0x01, 0x03, 0x10, 0x12

# (tag, [(attr, type, value)], children)
TREE = ("manifest", [
    (None, "package", T_STRING, "com.novasystems.bruh"),
    (ANDROID_NS, "versionCode", T_INT, 1),
    (ANDROID_NS, "versionName", T_STRING, "1.0"),
], [
    ("uses-sdk", [
        (ANDROID_NS, "minSdkVersion", T_INT, 16),
        (ANDROID_NS, "targetSdkVersion", T_INT, 29),
    ], []),
    ("application", [
        (ANDROID_NS, "theme", T_REF, 0x01030007),  # Theme.NoTitleBar.Fullscreen
        (ANDROID_NS, "label", T_STRING, "bruh"),
    ], [
        ("activity", [
            (ANDROID_NS, "name", T_STRING, ".MainActivity"),
            (ANDROID_NS, "exported", T_BOOL, True),
        ], [
            ("intent-filter", [], [
                ("action", [(ANDROID_NS, "name", T_STRING, "android.intent.action.MAIN")], []),
                ("category", [(ANDROID_NS, "name", T_STRING, "android.intent.category.LAUNCHER")], []),
            ]),
        ]),
    ]),
])

# Attribute names with resource ids must come first in the string pool.
strings = list(ATTRS)
def intern(s):
    if s not in strings:
        strings.append(s)
    return strings.index(s)

for s in ("android", ANDROID_NS):
    intern(s)

def collect(node):
    tag, attrs, children = node
    intern(tag)
    for ns, name, typ, val in attrs:
        intern(name)
        if typ == T_STRING:
            intern(val)
    for c in children:
        collect(c)
collect(TREE)

def string_pool():
    offsets, data = [], b""
    for s in strings:
        offsets.append(len(data))
        enc = s.encode("utf-16-le")
        data += struct.pack("<H", len(s)) + enc + b"\0\0"
    data += b"\0" * (-len(data) % 4)
    header = 28
    strings_start = header + 4 * len(strings)
    body = b"".join(struct.pack("<I", o) for o in offsets) + data
    return struct.pack("<HHIIIIII", 0x0001, header, header + len(body),
                       len(strings), 0, 0, strings_start, 0) + body

def resource_map():
    ids = [ATTRS[n] for n in strings[:len(ATTRS)]]
    return struct.pack("<HHI", 0x0180, 8, 8 + 4 * len(ids)) + b"".join(struct.pack("<I", i) for i in ids)

NONE = 0xFFFFFFFF
line = [1]

def node_header(typ, size):
    line[0] += 1
    return struct.pack("<HHIII", typ, 16, size, line[0], NONE)

def namespace(typ):
    body = struct.pack("<II", intern("android"), intern(ANDROID_NS))
    return node_header(typ, 16 + len(body)) + body

def element(node):
    tag, attrs, children = node
    attrs = sorted(attrs, key=lambda a: ATTRS.get(a[1], 0) if a[0] else -1)
    ab = b""
    for ns, name, typ, val in attrs:
        ns_idx = intern(ns) if ns else NONE
        if typ == T_STRING:
            raw, data = intern(val), intern(val)
        elif typ == T_BOOL:
            raw, data = NONE, NONE if val else 0
        else:
            raw, data = NONE, val
        ab += struct.pack("<IIIHBBI", ns_idx, intern(name), raw, 8, 0, typ, data)
    start = struct.pack("<IIHHHHHH", NONE, intern(tag), 20, 20, len(attrs), 0, 0, 0) + ab
    out = node_header(0x0102, 16 + len(start)) + start
    for c in children:
        out += element(c)
    end = struct.pack("<II", NONE, intern(tag))
    return out + node_header(0x0103, 16 + len(end)) + end

body = namespace(0x0100) + element(TREE) + namespace(0x0101)
chunks = string_pool() + resource_map() + body
with open(sys.argv[1], "wb") as f:
    f.write(struct.pack("<HHI", 0x0003, 8, 8 + len(chunks)) + chunks)
