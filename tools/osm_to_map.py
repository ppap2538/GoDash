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
# 2026-11-18 (owner: "the real town plan, the whole of Tambon Nai Mueang first"): the play area is the
# tambon's own boundary (OSM relation BOUNDARY_REL, + MARGIN metres), from data/osm_tambon.json
# (tools/osm_fetch.mjs). Until then it was a 2.5 x 3.8 km box from data/osm_raw.json, with two thirds of
# the streets invented by plan_streets.py; the old data is in backups/map_v1_2026-11-18.
RAW = os.environ.get("OSM_RAW") or os.path.join(ROOT, "data", "osm_tambon.json")
OUT = os.path.join(ROOT, "src", "shared", "Config", "Maps", "KhonKaenData")
SITES = os.path.join(ROOT, "data", "sites.json")

STUD = 0.28
LAT0, LON0 = 16.4225, 102.8310  # never change: every site, plot and saved position is relative to it
MX = 111320 * math.cos(math.radians(LAT0))
MZ = 110574
BOUNDARY_REL = 21404983  # ตำบลในเมือง, อำเภอเมืองขอนแก่น
MARGIN = 60.0
# play area in metres around the origin (x west..east, z north..south): set from the boundary in main()
BX1, BX2, BZ1, BZ2 = -1300.0, 1150.0, -2000.0, 1800.0
BOUNDARY = []  # [(x1, z1, x2, z2)] segments of the tambon outline, metres

CLASS = {
    "trunk": "highway", "primary": "highway",
    "secondary": "main", "tertiary": "street",
    "trunk_link": "street", "primary_link": "street", "secondary_link": "street", "tertiary_link": "street",
    "unclassified": "soi", "residential": "soi", "living_street": "soi",
    # the narrow lanes and alleys (ตรอก/ซอยย่อย) that OSM maps as plain "service" ways; not driveways,
    # car-park aisles or drive-throughs (SKIP_SERVICE)
    "service": "lane",
}
CLASS_ID = {"highway": 1, "main": 2, "street": 3, "soi": 4, "lane": 5}
SKIP_SERVICE = {"driveway", "parking_aisle", "drive-through", "emergency_access", "maintenance", "driveway;parking_aisle", "parking"}
MIN_SERVICE_M = 30.0  # a service way shorter than this is a driveway stub


def xy(lat, lon):
    return ((lon - LON0) * MX, -(lat - LAT0) * MZ)


def _in_poly(p):
    c = False
    x, z = p
    for x1, z1, x2, z2 in BOUNDARY:
        if (z1 > z) != (z2 > z):
            if x1 + (z - z1) * (x2 - x1) / (z2 - z1) > x:
                c = not c
    return c


def _near_edge(p, d):
    x, z = p
    for x1, z1, x2, z2 in BOUNDARY:
        dx, dz = x2 - x1, z2 - z1
        L2 = dx * dx + dz * dz or 1e-9
        t = max(0.0, min(1.0, ((x - x1) * dx + (z - z1) * dz) / L2))
        if (x - x1 - dx * t) ** 2 + (z - z1 - dz * t) ** 2 < d * d:
            return True
    return False


def inside(p):
    if not (BX1 <= p[0] <= BX2 and BZ1 <= p[1] <= BZ2):
        return False
    if not BOUNDARY:
        return True
    return _in_poly(p) or _near_edge(p, MARGIN)


def load_boundary(data):
    """The tambon outline from the extract; sets BOUNDARY and the bounds box."""
    global BX1, BX2, BZ1, BZ2
    BOUNDARY.clear()
    for e in data["elements"]:
        if e["type"] == "relation" and e["id"] == BOUNDARY_REL:
            for m in e.get("members", []):
                if m["type"] == "way" and m.get("role") == "outer" and m.get("geometry"):
                    pts = [xy(g["lat"], g["lon"]) for g in m["geometry"]]
                    for a, b in zip(pts, pts[1:]):
                        BOUNDARY.append((a[0], a[1], b[0], b[1]))
    if not BOUNDARY:
        print("no boundary relation in the extract: keeping the old box")
        return
    xs = [s[0] for s in BOUNDARY] + [s[2] for s in BOUNDARY]
    zs = [s[1] for s in BOUNDARY] + [s[3] for s in BOUNDARY]
    BX1, BX2 = min(xs) - MARGIN, max(xs) + MARGIN
    BZ1, BZ2 = min(zs) - MARGIN, max(zs) + MARGIN


def frozen_plots():
    """Plots players can own (data/sites.json, studs -> metres): no new lane may cross one."""
    try:
        with open(SITES, encoding="utf-8") as f:
            sites = json.load(f)["sites"]
    except (OSError, ValueError, KeyError):
        return []
    out = []
    for s in sites:
        if s.get("kind") in ("plot", "farm", "hub") and "x" in s:
            out.append((s["x"] * STUD, s["z"] * STUD, s["lx"], s["lz"], s["w"] * STUD / 2 + 4, s["d"] * STUD / 2 + 4))
    return out


# OSM land use -> the game's classes: "campus" (universities, schools, hospitals, government: big
# grounds, no invented lanes), "green" (fields, grass, cemeteries: open land), "commercial", "residential",
# "industrial", "military" (closed grounds)
LANDUSE = {
    "residential": "residential", "commercial": "commercial", "retail": "commercial", "industrial": "industrial",
    "military": "military", "cemetery": "green", "religious": "campus", "education": "campus", "institutional": "campus",
    "grass": "green", "farmland": "green", "meadow": "green", "orchard": "green",
}
LANDUSE_AMENITY = {"university": "campus", "college": "campus", "school": "campus", "hospital": "campus", "prison": "military", "townhall": "campus"}
LANDUSE_LEISURE = {"stadium": "campus", "golf_course": "green"}

# Real names are shown for public places only (government, public hospitals, schools, universities,
# municipal markets, the railway and bus stations, museums, the city gate). Shops, malls, private
# hospitals, banks, hotels and private markets keep the game's own names (no real brands).
PRIVATE_HOSPITAL = ("Bangkok", "กรุงเทพ", "ราม", "Ram ", "ราชพฤกษ์", "Ratchap")
PUBLIC_KINDS = {"government", "police", "fire", "post", "school", "university", "library", "museum", "citygate", "stadium", "station", "bus", "hospital", "market", "temple"}


def public_name(kind, t):
    th = (t.get("name") or "").strip()
    en = (t.get("name:en") or "").strip()
    if kind not in PUBLIC_KINDS or not th:
        return "", ""
    if kind == "hospital" and any(k in th or k in en for k in PRIVATE_HOSPITAL):
        return "", ""
    if kind == "market" and not ("เทศบาล" in th or "ถนนคนเดิน" in th):
        return "", ""
    if kind == "post" and not th.startswith("ไปรษณีย์"):
        return "", ""
    return en or th, th


def crosses_box(a, b, boxes):
    for cx, cz, lx, lz, hw, hd in boxes:
        rx, rz = -lz, lx
        for k in range(0, 11):
            t = k / 10
            x, z = a[0] + (b[0] - a[0]) * t - cx, a[1] + (b[1] - a[1]) * t - cz
            if abs(x * rx + z * rz) <= hw and abs(x * lx + z * lz) <= hd:
                return True
    return False


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


def dp_ring(points, tol):
    """Douglas-Peucker for a closed outline (first point == last point).

    dp() measures distance from the chord between the two ends; on a ring the ends are the same
    point, the chord has no length and every outline collapsed to that single point (until
    2026-11-16 the lake and every park were lost this way). Cut the ring at the point farthest
    from the start and simplify the two halves.
    """
    if len(points) < 4 or math.dist(points[0], points[-1]) > 1e-6:
        return dp(points, tol)
    far = max(range(len(points)), key=lambda i: math.dist(points[0], points[i]))
    first = dp(points[:far + 1], tol)
    second = [far + i for i in dp(points[far:], tol)]
    return first + second[1:-1]  # open ring: the Luau scanline closes it


def main():
    data = json.load(open(RAW, encoding="utf-8"))
    load_boundary(data)
    plots = frozen_plots()
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
        if t["highway"] == "service":
            if t.get("service") in SKIP_SERVICE or t.get("access") in ("private", "no"):
                continue
            L = sum(math.dist(xy(a["lat"], a["lon"]), xy(b["lat"], b["lon"])) for a, b in zip(geo, geo[1:]))
            if L < MIN_SERVICE_M:
                continue
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
                # an alley through a plot someone may own is left out (the plot never moves)
                if cls == "lane" and any(crosses_box(pts[a], pts[b], plots) for a, b in zip(keep, keep[1:])):
                    start = i
                    continue
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

    # features: water / parks (polygons), rail (lines), points of interest (positions; names only for
    # public places, see PUBLIC_NAME), land use (polygons, for the street planner and the builder)
    water, parks, rails, pois, landuse = [], [], [], [], []
    for e in data["elements"]:
        t = e.get("tags", {})
        # lakes mapped as multipolygon relations (Bueng Thung Sang...): their outer ways, one by one
        if e["type"] == "relation" and t.get("natural") == "water":
            for m in e.get("members", []):
                if m["type"] == "way" and m.get("role") == "outer" and m.get("geometry") and len(m["geometry"]) > 3:
                    pts = [xy(g["lat"], g["lon"]) for g in m["geometry"]]
                    cx = sum(p[0] for p in pts) / len(pts)
                    cz = sum(p[1] for p in pts) / len(pts)
                    if inside((cx, cz)):
                        idx = dp_ring(pts, 4.0)
                        if len(idx) >= 3:
                            water.append((t.get("name:en") or t.get("name") or "", [pts[i] for i in idx]))
        use = LANDUSE.get(t.get("landuse")) or LANDUSE_AMENITY.get(t.get("amenity")) or LANDUSE_LEISURE.get(t.get("leisure"))
        if use and e.get("geometry") and e["type"] == "way":
            pts = [xy(g["lat"], g["lon"]) for g in e["geometry"]]
            w = max(p[0] for p in pts) - min(p[0] for p in pts)
            h = max(p[1] for p in pts) - min(p[1] for p in pts)
            cx = sum(p[0] for p in pts) / len(pts)
            cz = sum(p[1] for p in pts) / len(pts)
            if max(w, h) >= 60 and inside((cx, cz)):
                idx = dp_ring(pts, 6.0)
                if len(idx) >= 3:
                    landuse.append((use, [pts[i] for i in idx]))
        elif use and e["type"] == "relation":
            for m in e.get("members", []):
                if m["type"] == "way" and m.get("role") == "outer" and m.get("geometry") and len(m["geometry"]) > 3:
                    pts = [xy(g["lat"], g["lon"]) for g in m["geometry"]]
                    cx = sum(p[0] for p in pts) / len(pts)
                    cz = sum(p[1] for p in pts) / len(pts)
                    if inside((cx, cz)):
                        idx = dp_ring(pts, 6.0)
                        if len(idx) >= 3:
                            landuse.append((use, [pts[i] for i in idx]))
        if e["type"] == "way" and "geometry" in e:
            pts = [xy(g["lat"], g["lon"]) for g in e["geometry"]]
            if t.get("natural") == "water" or t.get("leisure") == "park":
                cx = sum(p[0] for p in pts) / len(pts)
                cz = sum(p[1] for p in pts) / len(pts)
                w = max(p[0] for p in pts) - min(p[0] for p in pts)
                h = max(p[1] for p in pts) - min(p[1] for p in pts)
                if not inside((cx, cz)) or max(w, h) < 40:
                    continue
                idx = dp_ring(pts, 3.0)
                poly = [pts[i] for i in idx]
                if len(poly) < 3:
                    continue
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
        elif a == "school": kind = "school"
        elif a in ("university", "college"): kind = "university"
        elif a == "place_of_worship": kind = "temple"
        elif a == "townhall" or t.get("office") in ("government", "administrative") or t.get("government"): kind = "government"
        elif a == "fire_station": kind = "fire"
        elif a == "post_office": kind = "post"
        elif a == "library": kind = "library"
        elif tour == "museum": kind = "museum"
        elif t.get("historic") == "city_gate": kind = "citygate"
        elif t.get("leisure") == "stadium": kind = "stadium"
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
            elif e.get("bounds"):
                b = e["bounds"]
                p = xy((b["minlat"] + b["maxlat"]) / 2, (b["minlon"] + b["maxlon"]) / 2)
            else:
                continue
            if inside(p):
                en, th = public_name(kind, t)
                pois.append((kind, p, en, th))

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
        for kind, p, en, th in pois:
            if th:
                f.write('\t\t{ "%s", %s, %s, %s, %s },\n' % (kind, s(p[0]), s(p[1]), lua_str(en), lua_str(th)))
            else:
                f.write('\t\t{ "%s", %s, %s },\n' % (kind, s(p[0]), s(p[1])))
        f.write("\t},\n")
        # land use polygons (studs): { use, pts }
        f.write("\tlanduse = {\n")
        for use, poly in landuse:
            f.write('\t\t{ use = "%s", pts = { %s } },\n' % (use, ", ".join(s(x) + "," + s(z) for x, z in poly)))
        f.write("\t},\n")
        # the tambon outline (studs), for the map and the ground
        f.write("\tboundary = { %s },\n" % ", ".join(s(x1) + "," + s(z1) for x1, z1, _, _ in BOUNDARY))
        f.write("}\n")

    total = sum(math.dist(node_out[a - 1], node_out[b - 1]) for a, b, _, _, _ in edge_out)
    by = defaultdict(float)
    for a, b, c, _, _ in edge_out:
        by[c] += math.dist(node_out[a - 1], node_out[b - 1])
    print("nodes %d edges %d  road km %.1f  (highway %.1f main %.1f street %.1f soi %.1f)" % (
        len(node_out), len(edge_out), total / 1000, by[1] / 1000, by[2] / 1000, by[3] / 1000, by[4] / 1000))
    print("water %d parks %d rails %d pois %d (named %d) landuse %d names %d  chunks nodes=%d edges=%d  bounds m x %.0f..%.0f z %.0f..%.0f" % (
        len(water), len(parks), len(rails), len(pois), sum(1 for p in pois if p[3]), len(landuse), len(name_list), n_nodes, n_edges, BX1, BX2, BZ1, BZ2))
    print("lane (alley) km %.1f" % (by[5] / 1000))
    kinds = defaultdict(int)
    for p in pois:
        kinds[p[0]] += 1
    print(dict(kinds))
    print("size studs: %d x %d" % ((BX2 - BX1) / STUD, (BZ2 - BZ1) / STUD))
    # the folder was emptied above: write the real roundabouts again (World/RoadMarks builds their islands)
    import runpy
    runpy.run_path(os.path.join(ROOT, "tools", "osm_roundabouts.py"), run_name="__main__")


if __name__ == "__main__":
    main()
