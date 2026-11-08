#!/usr/bin/env python3
"""Download + export + analyse every model in picks.json (parallel). Writes data/toolbox/vet_report.json."""
import json, subprocess, sys, traceback
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from fetch import fetch
import analyze

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data" / "toolbox"
LUNE = str(Path.home() / ".cargo/bin/lune")


def one(mid):
    try:
        rbxm = fetch(mid)
        js = DATA / f"{mid}.json"
        if not js.exists():
            r = subprocess.run([LUNE, "run", str(ROOT / "tools/toolbox/export.luau"), str(rbxm), str(js)], capture_output=True, text=True)
            if r.returncode != 0:
                return mid, {"ok": False, "error": "export: " + (r.stderr or r.stdout)[-200:]}
        m = analyze.analyse(mid)
        ok = len(m["wheels"]) == 4
        return mid, {"ok": ok, "size": m["size"], "wheels": len(m["wheels"]), "seats": len(m["seats"]), "error": None if ok else "wheels not found"}
    except SystemExit as e:
        return mid, {"ok": False, "error": str(e)}
    except Exception as e:  # noqa: BLE001
        return mid, {"ok": False, "error": f"{type(e).__name__}: {e}"[:200]}


picks = json.loads((ROOT / "tools/toolbox/picks.json").read_text())
picks.pop("_note", None)
ids = sorted(set(picks.values()))
report = {}
with ThreadPoolExecutor(4) as ex:
    for mid, res in ex.map(one, ids):
        report[str(mid)] = res
        print(mid, "OK" if res["ok"] else "FAIL", res.get("size") or res.get("error"), flush=True)
(DATA / "vet_report.json").write_text(json.dumps(report, indent=1))
print("done", sum(1 for r in report.values() if r["ok"]), "/", len(report))
