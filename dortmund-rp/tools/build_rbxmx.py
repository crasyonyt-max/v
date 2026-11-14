#!/usr/bin/env python3
"""Builds the drag-and-drop Studio files.

    python3 tools/build_rbxmx.py

  ReplicatedStorage.rbxmx  -> drag into ReplicatedStorage (VehicleConfig, LiveryConfig)
  VehicleSystem.rbxmx      -> drag into ServerScriptService (folder VehicleSystem)
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
HEADER = (
    '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
    'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
)
counter = 0


def ref() -> str:
    global counter
    counter += 1
    return f"RBX{counter}"


def cdata(text: str) -> str:
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def script_item(path: Path) -> str:
    name = path.name
    if name.endswith(".server.lua"):
        cls, name = "Script", name[: -len(".server.lua")]
    elif name.endswith(".client.lua"):
        cls, name = "LocalScript", name[: -len(".client.lua")]
    else:
        cls, name = "ModuleScript", path.stem
    source = path.read_text(encoding="utf-8")
    return (
        f'<Item class="{cls}" referent="{ref()}"><Properties>'
        f'<string name="Name">{name}</string>'
        f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
        f"</Properties></Item>\n"
    )


def write(out: Path, body: str) -> None:
    out.write_text(HEADER + body + "</roblox>\n", encoding="utf-8")
    print("wrote", out.relative_to(ROOT))


def main() -> None:
    rs = "".join(script_item(p) for p in sorted((SRC / "ReplicatedStorage").glob("*.lua")))
    write(ROOT / "ReplicatedStorage.rbxmx", rs)

    vs_dir = SRC / "ServerScriptService" / "VehicleSystem"
    inner = "".join(script_item(p) for p in sorted(vs_dir.glob("*.lua")))
    folder = (
        f'<Item class="Folder" referent="{ref()}"><Properties>'
        f'<string name="Name">VehicleSystem</string></Properties>\n{inner}</Item>\n'
    )
    write(ROOT / "VehicleSystem.rbxmx", folder)


if __name__ == "__main__":
    main()
