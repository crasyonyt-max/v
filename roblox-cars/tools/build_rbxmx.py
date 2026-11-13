#!/usr/bin/env python3
"""Packs src/RealisticCars into RealisticCars.rbxmx (drag-and-drop into Studio).

    python3 tools/build_rbxmx.py

*.server.lua -> Script, RunContext = Server
*.client.lua -> Script, RunContext = Client
*.lua        -> ModuleScript
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src" / "RealisticCars"
OUT = ROOT / "RealisticCars.rbxmx"
RUN_CONTEXT = {"Server": 1, "Client": 2}


def cdata(text: str) -> str:
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def item(ref: int, cls: str, name: str, source: str, run_context=None) -> str:
    props = [f'<string name="Name">{name}</string>']
    if run_context is not None:
        props.append(f'<token name="RunContext">{run_context}</token>')
    props.append(f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>')
    return (
        f'    <Item class="{cls}" referent="RBX{ref}">\n'
        f"      <Properties>\n        " + "\n        ".join(props) + "\n      </Properties>\n"
        f"    </Item>\n"
    )


def main() -> None:
    children = []
    for i, path in enumerate(sorted(SRC.glob("*.lua")), start=1):
        source = path.read_text(encoding="utf-8")
        if path.name.endswith(".server.lua"):
            children.append(item(i, "Script", path.name[: -len(".server.lua")], source, RUN_CONTEXT["Server"]))
        elif path.name.endswith(".client.lua"):
            children.append(item(i, "Script", path.name[: -len(".client.lua")], source, RUN_CONTEXT["Client"]))
        else:
            children.append(item(i, "ModuleScript", path.stem, source))
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
        '  <Item class="Folder" referent="RBX0">\n'
        '    <Properties>\n      <string name="Name">RealisticCars</string>\n    </Properties>\n'
        + "".join(children)
        + "  </Item>\n</roblox>\n"
    )
    OUT.write_text(xml, encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(children)} scripts)")


if __name__ == "__main__":
    main()
