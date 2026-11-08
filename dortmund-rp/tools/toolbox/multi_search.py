#!/usr/bin/env python3
"""One row of top Creator Store results per car: multi_search.py out.png "label=query" ..."""
import io, json, subprocess, sys, urllib.parse
from PIL import Image, ImageDraw


def get(url):
    return json.loads(subprocess.run(["curl", "-sS", "-m", "30", url], capture_output=True, text=True, check=True).stdout)


def main():
    out = sys.argv[1]
    rows = [a.split("=", 1) for a in sys.argv[2:]]
    N, S = 8, 160
    img = Image.new("RGB", (120 + N * S, len(rows) * (S + 30)), (30, 30, 34))
    d = ImageDraw.Draw(img)
    listing = {}
    for r, (label, query) in enumerate(rows):
        y = r * (S + 30)
        d.text((6, y + 6), label, fill=(255, 255, 255))
        try:
            data = get(f"https://apis.roblox.com/toolbox-service/v1/marketplace/10?keyword={urllib.parse.quote(query)}&limit={N}")["data"]
        except Exception:
            continue
        ids = [x["id"] for x in data][:N]
        if not ids:
            continue
        det = {it["asset"]["id"]: it for it in get("https://apis.roblox.com/toolbox-service/v1/items/details?assetIds=" + ",".join(map(str, ids)))["data"]}
        th = {t["targetId"]: t.get("imageUrl") for t in get(f"https://thumbnails.roblox.com/v1/assets?assetIds={','.join(map(str, ids))}&size=420x420&format=Png")["data"]}
        listing[label] = []
        for k, aid in enumerate(ids):
            x = 120 + k * S
            if th.get(aid):
                try:
                    data = subprocess.run(["curl", "-sS", "-m", "20", th[aid]], capture_output=True, check=True).stdout
                    img.paste(Image.open(io.BytesIO(data)).convert("RGB").resize((S, S)), (x, y))
                except Exception:
                    pass
            name = det.get(aid, {}).get("asset", {}).get("name", "")
            d.text((x + 2, y + S + 2), f"{k + 1}.{aid}", fill=(230, 230, 230))
            d.text((x + 2, y + S + 15), name[:24], fill=(170, 170, 170))
            listing[label].append((aid, name))
    img.save(out)
    print(json.dumps(listing))


if __name__ == "__main__":
    main()
