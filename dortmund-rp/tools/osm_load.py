"""Shared OSM loader: merges tiles, returns nodes/ways/relations with tags."""
import xml.etree.ElementTree as ET
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data" / "osm"

def load():
    nodes, ways, rels = {}, {}, {}
    for f in sorted(DATA.glob("tile_*.osm")):
        for el in ET.parse(f).getroot():
            tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
            i = int(el.get("id", 0))
            if el.tag == "node":
                nodes[i] = (float(el.get("lat")), float(el.get("lon")), tags)
            elif el.tag == "way":
                ways[i] = ([int(n.get("ref")) for n in el.findall("nd")], tags)
            elif el.tag == "relation":
                rels[i] = ([(m.get("type"), int(m.get("ref")), m.get("role")) for m in el.findall("member")], tags)
    return nodes, ways, rels
