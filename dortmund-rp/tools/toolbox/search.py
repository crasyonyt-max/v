#!/usr/bin/env python3
"""Search the Creator Store and build a labelled thumbnail contact sheet.
   python3 tools/toolbox/search.py "<query>" out.png [count]"""
import io, json, subprocess, sys, urllib.request
from PIL import Image, ImageDraw


def get(url):
    return json.loads(subprocess.run(["curl", "-sS", "-m", "30", url], capture_output=True, text=True, check=True).stdout)


def search(query, count=24):
    q = urllib.parse.quote(query)
    ids = [d["id"] for d in get(f"https://apis.roblox.com/toolbox-service/v1/marketplace/10?keyword={q}&limit={count}")["data"]]
    det = get("https://apis.roblox.com/toolbox-service/v1/items/details?assetIds=" + ",".join(map(str, ids)))["data"]
    return [(it["asset"]["id"], it["asset"]["name"], it["creator"]["name"], it.get("voting", {}), it["asset"].get("hasScripts"), it["asset"].get("isEndorsed")) for it in det]


def sheet(items, out):
    ids = ",".join(str(i[0]) for i in items)
    th = {t["targetId"]: t.get("imageUrl") for t in get(f"https://thumbnails.roblox.com/v1/assets?assetIds={ids}&size=420x420&format=Png")["data"]}
    cols, S = 6, 210
    img = Image.new("RGB", (cols * S, ((len(items) + cols - 1) // cols) * (S + 34)), (30, 30, 34))
    d = ImageDraw.Draw(img)
    for k, (aid, name, creator, vote, scripts, endorsed) in enumerate(items):
        x, y = (k % cols) * S, (k // cols) * (S + 34)
        url = th.get(aid)
        if url:
            try:
                data = subprocess.run(["curl", "-sS", "-m", "20", url], capture_output=True, check=True).stdout
                im = Image.open(io.BytesIO(data)).convert("RGB").resize((S, S))
                img.paste(im, (x, y))
            except Exception:
                pass
        up, down = vote.get("upVotes", 0), vote.get("downVotes", 0)
        d.text((x + 3, y + S + 2), f"{k + 1}. {aid}", fill=(255, 255, 255))
        d.text((x + 3, y + S + 16), f"{name[:26]} {'★' if endorsed else ''} +{up}/-{down}", fill=(190, 190, 190))
    img.save(out)


if __name__ == "__main__":
    import urllib.parse
    items = search(sys.argv[1], int(sys.argv[3]) if len(sys.argv) > 3 else 24)
    sheet(items, sys.argv[2])
    for k, it in enumerate(items):
        print(k + 1, it[0], it[1][:50], "by", it[2], it[3].get("upVotes"), "/", it[3].get("downVotes"), "scripts" if it[4] else "", "ENDORSED" if it[5] else "")
