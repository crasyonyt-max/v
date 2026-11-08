#!/usr/bin/env python3
"""Download Creator Store models (needs a key with legacy-assets) into data/toolbox/<id>.rbxm."""
import json, subprocess, sys
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "data" / "toolbox"


def fetch(asset_id: int) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{asset_id}.rbxm"
    if path.exists() and path.stat().st_size > 0:
        return path
    meta = subprocess.run(["curl", "-sS", "-m", "30", f"https://apis.roblox.com/asset-delivery-api/v1/assetId/{asset_id}",
                           "-H", "x-api-key: proxy-injected"], capture_output=True, text=True, check=True).stdout
    loc = json.loads(meta).get("location")
    if not loc:
        raise RuntimeError(f"{asset_id}: {meta[:200]}")
    subprocess.run(["curl", "-sS", "-m", "120", "-L", "--compressed", "-o", str(path), loc], check=True)
    return path


if __name__ == "__main__":
    for a in sys.argv[1:]:
        print(fetch(int(a)))
