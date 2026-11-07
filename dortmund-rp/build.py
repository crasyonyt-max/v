#!/usr/bin/env python3
"""Build src/ into a Roblox place file (build/DortmundRP.rbxlx).

Same layout rules as Rojo:
  src/<Service>/...          top-level folders are Roblox services
  folder                     -> Folder
  name.server.lua            -> Script
  name.client.lua            -> LocalScript
  name.lua                   -> ModuleScript

Usage: python3 build.py
"""

from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
OUT = ROOT / "build" / "DortmundRP.rbxlx"

# Folders whose class is not "Folder".
SPECIAL_CLASSES = {
    ("StarterPlayer", "StarterPlayerScripts"): "StarterPlayerScripts",
    ("StarterPlayer", "StarterCharacterScripts"): "StarterCharacterScripts",
}

# Services always present in the place (even when src/ has nothing for them).
EXTRA_SERVICES = ["Workspace", "Lighting", "Players", "StarterGui", "Teams", "SoundService"]

_ref = 0


def ref() -> str:
    global _ref
    _ref += 1
    return f"RBX{_ref:08X}"


def cdata(text: str) -> str:
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def script_item(path: Path) -> str:
    name = path.name
    if name.endswith(".server.lua"):
        cls, inst = "Script", name[: -len(".server.lua")]
    elif name.endswith(".client.lua"):
        cls, inst = "LocalScript", name[: -len(".client.lua")]
    else:
        cls, inst = "ModuleScript", name[: -len(".lua")]
    source = path.read_text(encoding="utf-8")
    return (
        f'<Item class="{cls}" referent="{ref()}"><Properties>'
        f'<string name="Name">{escape(inst)}</string>'
        f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
        f"</Properties></Item>"
    )


def folder_item(path: Path, parents: tuple) -> str:
    cls = SPECIAL_CLASSES.get(parents + (path.name,), "Folder")
    children = "".join(item(child, parents + (path.name,)) for child in sorted(path.iterdir()))
    return (
        f'<Item class="{cls}" referent="{ref()}"><Properties>'
        f'<string name="Name">{escape(path.name)}</string>'
        f"</Properties>{children}</Item>"
    )


def item(path: Path, parents: tuple) -> str:
    if path.is_dir():
        return folder_item(path, parents)
    if path.suffix == ".lua":
        return script_item(path)
    return ""


SERVICE_PROPS = {
    # the real city is ~100k parts: stream it around each player
    "Workspace": '<bool name="StreamingEnabled">true</bool>'
    '<int name="StreamingTargetRadius">1400</int>'
    '<int name="StreamingMinRadius">256</int>'
    '<token name="StreamOutBehavior">2</token>',
}


def service(name: str, path: Path | None) -> str:
    children = ""
    if path is not None:
        children = "".join(item(child, (name,)) for child in sorted(path.iterdir()))
    return (
        f'<Item class="{name}" referent="{ref()}"><Properties>'
        f'<string name="Name">{name}</string>{SERVICE_PROPS.get(name, "")}'
        f"</Properties>{children}</Item>"
    )


def main() -> None:
    services = {p.name: p for p in sorted(SRC.iterdir()) if p.is_dir()}
    body = "".join(service(name, path) for name, path in services.items())
    body += "".join(service(name, None) for name in EXTRA_SERVICES if name not in services)
    xml = f'<roblox version="4">{body}</roblox>'
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(xml, encoding="utf-8")
    scripts = sum(1 for _ in SRC.rglob("*.lua"))
    print(f"Built {OUT.relative_to(ROOT)} ({scripts} scripts, {len(xml) // 1024} KB)")


if __name__ == "__main__":
    main()
