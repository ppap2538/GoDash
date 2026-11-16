"""Turn data/osm_raw.json (OpenStreetMap, ODbL) into the game's 1:1 road graph.

  python -I tools/osm_to_map.py

Writes src/shared/Config/Maps/KhonKaenData/*.luau  (compact strings, each under the 200 kB Source cap).
Scale: 1 stud = 0.28 m (a Roblox character is about 5 studs tall), so real metres / 0.28.
Axes: +X east, +Z south.
"""
import json
import math
import os
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "data", "osm_raw.json")
OUT = os.path.join(ROOT, "src", "shared", "Config", "Maps", "KhonKaenData")

STUD = 0.28
LAT0, LON0 = 16.4225, 102.8310
MX = 111320 * math.cos(math.radians(LAT0))
MZ = 110574
# play area in metres around the origin (x west..east, z north..south)
BX1, BX2, BZ1, BZ2 = -1300.0, 1150.0, -2000.0, 1800.0

CLASS = {
    "trunk": "highway", "primary": "highway",
    "secondary": "main", "tertiary": "street",
    "trunk_link": "street", "primary_link": "street", "secondary_link": "street", "tertiary_link": "street",
    "unclassified": "soi", "residential": "soi", "living_street": "soi",
}
CLASS_ID = {"highway": 1, "main": 2, "street": 3, "soi": 4}


def xy(lat, lon):
    return ((lon - LON0) * MX, -(lat - LAT0) * MZ)


def inside(p):
    return BX1 <= p[0] <= BX2 and BZ1 <= p[1] <= BZ2


def dp(points, tol):
    """Douglas-Peucker on a list of (x, z); returns kept indices."""
    if len(points) < 3:
        return list(range(len(points)))
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        ax, az = points[a]
        bx, bz = points[b]
        dx, dz = bx - ax, bz - az
        L = math.hypot(dx, dz) or 1e-9
        worst, wi = 0.0, -1
        for i in range(a + 1, b):
            px, pz = points[i]
            d = abs((px - ax) * dz - (pz - az) * dx) / L
            if d > worst:
                worst, wi = d, i
        if worst > tol and wi > 0:
            keep[wi] = True
            stack.append((a, wi))
            stack.append((wi, b))
    return [i for i, k in enumerate(keep) if k]


def main():
    data = json.load(open(RAW, encoding="utf-8"))
    pos = {}  # osm node id -> (x, z) metres
    ways = []
    use = defaultdict(int)
    names = {}
    name_list = []

    def name_id(t):
        n = t.get("name:en") or ""
        th = t.get("name") or ""
        if not n and not th:
            return 0
        if not n:
            n = th
        key = (n, th)
        if key not in names:
            name_list.append(key)
            names[key] = len(name_list)
        return names[key]

    for e in data["elements"]:
        t = e.get("tags", {})
        if e["type"] != "way" or t.get("highway") not in CLASS:
            continue
        ids = e["nodes"]
        geo = e["geometry"]
        cls = CLASS[t["highway"]]
        oneway = t.get("oneway") in ("yes", "1", "true")
        # cut the way into runs that are inside the play area
        run = []
        for nid, g in zip(ids, geo):
            p = xy(g["lat"], g["lon"])
            if inside(p):
                pos[nid] = p
                run.append(nid)
            else:
                if len(run) >= 2:
                    ways.append((run, cls, name_id(t), oneway))
                run = []
        if len(run) >= 2:
            ways.append((run, cls, name_id(t), oneway))

    for run, _, _, _ in ways:
        for i, nid in enumerate(run):
            use[nid] += 2 if i in (0, len(run) - 1) else 1
    # a junction = shared by ways, or a way end
    endpoints = defaultdict(int)
    for run, _, _, _ in ways:
        endpoints[run[0]] += 1
        endpoints[run[-1]] += 1
    count = defaultdict(int)
    for run, _, _, _ in ways:
        for nid in set(run):
            count[nid] += 1
    junction = {nid for nid in pos if count[nid] > 1 or endpoints[nid] > 0}

    # chains between junctions, simplified
    edges = []  # (a_id, b_id, cls, name)
    for run, cls, nm, oneway in ways:
        start = 0
        for i in range(1, len(run)):
            if run[i] in junction or i == len(run) - 1:
                chain = run[start:i + 1]
                pts = [pos[n] for n in chain]
                keep = dp(pts, 1.2)
                for a, b in zip(keep, keep[1:]):
                    if chain[a] != chain[b]:
                        edges.append((chain[a], chain[b], cls, nm, oneway))
                start = i

    # merge nodes closer than 5 m (tiny edges make ugly junctions)
    parent = {}

    def find(a):
        while parent.get(a, a) != a:
            parent[a] = parent.get(parent[a], parent[a])
            a = parent[a]
        return a

    changed = True
    while changed:
        changed = False
        for a, b, cls, nm, ow in edges:
            ra, rb = find(a), find(b)
            if ra != rb and math.dist(pos[ra], pos[rb]) < 5.0:
                parent[rb] = ra
                changed = True
    merged = {}
    for a, b, cls, nm, ow in edges:
        ra, rb = find(a), find(b)
        if ra == rb:
            continue
        k = (min(ra, rb), max(ra, rb))
        old = merged.get(k)
        if old is None or CLASS_ID[cls] < CLASS_ID[old[0]]:
            merged[k] = (cls, nm, ow)

    # largest connected component, and trim dead-end stubs shorter than 18 m
    for _ in range(3):
        adj = defaultdict(list)
        for (a, b) in merged:
            adj[a].append(b)
            adj[b].append(a)
        drop = []
        for (a, b) in merged:
            L = math.dist(pos[a], pos[b])
            if L < 18 and (len(adj[a]) == 1 or len(adj[b]) == 1):
                drop.append((a, b))
        for k in drop:
            del merged[k]
        if not drop:
            break
    adj = defaultdict(list)
    for (a, b) in merged:
        adj[a].append(b)
        adj[b].append(a)
    seen, best = set(), []
    for s in adj:
        if s in seen:
            continue
        comp, stack = [], [s]
        seen.add(s)
        while stack:
            u = stack.pop()
            comp.append(u)
            for v in adj[u]:
                if v not in seen:
                    seen.add(v)
                    stack.append(v)
        if len(comp) > len(best):
            best = comp
    keepnodes = set(best)
    merged = {k: v for k, v in merged.items() if k[0] in keepnodes and k[1] in keepnodes}

    index = {}
    node_out = []
    for (a, b) in merged:
        for n in (a, b):
            if n not in index:
                index[n] = len(node_out) + 1
                node_out.append(pos[n])
    edge_out = [(index[a], index[b], CLASS_ID[v[0]], v[1], 1 if v[2] else 0) for (a, b), v in merged.items()]

    def s(v):
        return str(int(round(v / STUD)))

    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        os.remove(os.path.join(OUT, f))

    def write_chunks(base, items):
        chunks, cur, size = [], [], 0
        for it in items:
            if size + len(it) + 1 > 180000:
                chunks.append(cur)
                cur, size = [], 0
            cur.append(it)
            size += len(it) + 1
        if cur:
            chunks.append(cur)
        for i, c in enumerate(chunks):
            with open(os.path.join(OUT, "%s%d.luau" % (base, i + 1)), "w", encoding="utf-8", newline="\n") as f:
                f.write('return "' + ";".join(c) + '"\n')
        return len(chunks)

    n_nodes = write_chunks("Nodes", [s(x) + "," + s(z) for x, z in node_out])
    n_edges = write_chunks("Edges", ["%d,%d,%d,%d,%d" % e for e in edge_out])

    # features: water / parks (polygons), rail (lines), points of interest (positions only)
    water, parks, rails, pois = [], [], [], []
    for e in data["elements"]:
        t = e.get("tags", {})
        if e["type"] == "way" and "geometry" in e:
            pts = [xy(g["lat"], g["lon"]) for g in e["geometry"]]
            if t.get("natural") == "water" or t.get("leisure") == "park":
                cx = sum(p[0] for p in pts) / len(pts)
                cz = sum(p[1] for p in pts) / len(pts)
                w = max(p[0] for p in pts) - min(p[0] for p in pts)
                h = max(p[1] for p in pts) - min(p[1] for p in pts)
                if not inside((cx, cz)) or max(w, h) < 40:
                    continue
                idx = dp(pts, 3.0)
                poly = [pts[i] for i in idx]
                (water if t.get("natural") == "water" else parks).append((t.get("name:en") or t.get("name") or "", poly))
            elif t.get("railway") == "rail":
                run = [p for p in pts if inside(p)]
                if len(run) >= 2:
                    idx = dp(run, 2.0)
                    rails.append([run[i] for i in idx])
        kind = None
        a, sh, tour, rw = t.get("amenity"), t.get("shop"), t.get("tourism"), t.get("railway")
        if a in ("restaurant", "fast_food"): kind = "restaurant"
        elif a == "cafe": kind = "cafe"
        elif a == "fuel": kind = "fuel"
        elif a == "hospital": kind = "hospital"
        elif a == "police": kind = "police"
        elif a == "bus_station": kind = "bus"
        elif a == "marketplace": kind = "market"
        elif a == "bank": kind = "bank"
        elif a == "pharmacy": kind = "pharmacy"
        elif a == "school" or a == "university": kind = "school"
        elif a == "place_of_worship": kind = "temple"
        elif sh == "convenience": kind = "convenience"
        elif sh in ("mall", "department_store", "supermarket"): kind = "mall"
        elif tour in ("hotel", "guest_house", "hostel", "motel", "apartment"): kind = "hotel"
        elif rw == "station": kind = "station"
        if kind:
            if e["type"] == "node":
                p = xy(e["lat"], e["lon"])
            elif "geometry" in e:
                g = [xy(q["lat"], q["lon"]) for q in e["geometry"]]
                p = (sum(q[0] for q in g) / len(g), sum(q[1] for q in g) / len(g))
            else:
                continue
            if inside(p):
                pois.append((kind, p))

    def lua_str(x):
        return '"' + x.replace("\\", "\\\\").replace('"', '\\"') + '"'

    with open(os.path.join(OUT, "Features.luau"), "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generated by tools/osm_to_map.py from OpenStreetMap data (c) OpenStreetMap contributors, ODbL.\n")
        f.write("-- Units: studs (1 stud = 0.28 m). Positions only; business names are not copied.\n")
        f.write("return {\n")
        f.write("\tnodeChunks = %d, edgeChunks = %d,\n" % (n_nodes, n_edges))
        f.write("\tbounds = { minX = %s, maxX = %s, minZ = %s, maxZ = %s },\n" % (s(BX1), s(BX2), s(BZ1), s(BZ2)))
        f.write("\tnames = {\n")
        for en, th in name_list:
            f.write("\t\t{ %s, %s },\n" % (lua_str(en), lua_str(th)))
        f.write("\t},\n")
        for label, polys in (("water", water), ("parks", parks)):
            f.write("\t%s = {\n" % label)
            for nm, poly in polys:
                f.write("\t\t{ name = %s, pts = { %s } },\n" % (lua_str(nm), ", ".join(s(x) + "," + s(z) for x, z in poly)))
            f.write("\t},\n")
        f.write("\trails = {\n")
        for run in rails:
            f.write("\t\t{ %s },\n" % ", ".join(s(x) + "," + s(z) for x, z in run))
        f.write("\t},\n")
        f.write("\tpois = {\n")
        for kind, p in pois:
            f.write('\t\t{ "%s", %s, %s },\n' % (kind, s(p[0]), s(p[1])))
        f.write("\t},\n}\n")

    total = sum(math.dist(node_out[a - 1], node_out[b - 1]) for a, b, _, _, _ in edge_out)
    by = defaultdict(float)
    for a, b, c, _, _ in edge_out:
        by[c] += math.dist(node_out[a - 1], node_out[b - 1])
    print("nodes %d edges %d  road km %.1f  (highway %.1f main %.1f street %.1f soi %.1f)" % (
        len(node_out), len(edge_out), total / 1000, by[1] / 1000, by[2] / 1000, by[3] / 1000, by[4] / 1000))
    print("water %d parks %d rails %d pois %d names %d  chunks nodes=%d edges=%d" % (
        len(water), len(parks), len(rails), len(pois), len(name_list), n_nodes, n_edges))
    kinds = defaultdict(int)
    for k, _ in pois:
        kinds[k] += 1
    print(dict(kinds))
    print("size studs: %d x %d" % ((BX2 - BX1) / STUD, (BZ2 - BZ1) / STUD))


if __name__ == "__main__":
    main()
