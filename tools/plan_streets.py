"""Urban planner: cut oversized city blocks into real block sizes with lanes (ซอยย่อย).

  python -I tools/plan_streets.py [preview.png]

Why: the OpenStreetMap network only has the public streets. Real blocks in Khon Kaen are 100-200 m
across and their insides are reached by small lanes that are not in the data, so the builder could
only put one row of buildings along each street and the middle of every block was empty grass.

What it does:
  1. runs tools/osm_to_map.py (fresh street graph from data/osm_raw.json),
  2. rasterises streets, water, parks, railway and the authored sites (data/sites.json),
  3. finds every piece of free land (a block) and, by its density class, lays a grid of lanes in it,
     aligned with the block's main street, so no building land is far from a street,
  4. joins the lanes to the streets (splitting street edges at the new junctions), and
  5. rewrites KhonKaenData/Nodes*.luau, Edges*.luau (lanes = road type 5) and writes Plan.luau
     (sites + land use) for the world builder.

The GPS, AI traffic and the builder all read the same graph, so they pick the lanes up by themselves.
Needs numpy and Pillow.
"""
import importlib.util
import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "src", "shared", "Config", "Maps", "KhonKaenData")
SITES = os.path.join(ROOT, "data", "sites.json")

CELL = 8.0  # studs per raster cell (6 until 2026-11-18; the whole tambon is ~29k x 34k studs)
# carriageway width, sidewalk each side (must match Map.roadTypes in Config/Maps/KhonKaen.luau)
ROADS = {1: (44, 7), 2: (40, 7), 3: (30, 5), 4: (20, 0), 5: (14, 0)}
LANE = 5
# T = block depth between lanes (two rows of lots back to back), LB = block length between cross lanes.
# 2026-11-18 (owner: "the real town plan"): the real alleys now come from OSM (highway=service), so the
# planner only cuts the really big blocks, with much wider spacing (was T 100-120, LB 300-420, and two
# thirds of all street length was invented).
PARAMS = {
    "core": {"T": 200.0, "LB": 520.0, "skip": 0.0},
    "urban": {"T": 260.0, "LB": 700.0, "skip": 0.3},
    # suburbs and the countryside get no invented lanes at all: their fields and orchards stay open
}
MIN_LANE = 64.0
B_MIN = 9000000
B_PARK, B_WATER, B_RAIL, B_SITE = B_MIN + 1, B_MIN + 2, B_MIN + 3, B_MIN + 4


def run_osm():
    spec = importlib.util.spec_from_file_location("osm_to_map", os.path.join(ROOT, "tools", "osm_to_map.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.main()


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def load():
    feat = read(os.path.join(OUT, "Features.luau"))
    nc = int(re.search(r"nodeChunks = (\d+)", feat).group(1))
    ec = int(re.search(r"edgeChunks = (\d+)", feat).group(1))
    nodes, edges = [], []
    for i in range(1, nc + 1):
        t = read(os.path.join(OUT, "Nodes%d.luau" % i))
        for it in t[t.index('"') + 1:t.rindex('"')].split(";"):
            x, z = it.split(",")
            nodes.append([float(x), float(z)])
    for i in range(1, ec + 1):
        t = read(os.path.join(OUT, "Edges%d.luau" % i))
        for it in t[t.index('"') + 1:t.rindex('"')].split(";"):
            a, b, c, n, ow = map(int, it.split(","))
            edges.append([a - 1, b - 1, c, n, ow])
    b = re.search(r"bounds = \{ minX = (-?\d+), maxX = (-?\d+), minZ = (-?\d+), maxZ = (-?\d+) \}", feat)
    bounds = tuple(map(float, b.groups()))

    def polys(label):
        body = feat.split("\t%s = {" % label, 1)[1].split("\n\t},", 1)[0]
        out = []
        for m in re.finditer(r"pts = \{ (.*?) \}", body):
            v = list(map(float, re.findall(r"-?\d+", m.group(1))))
            out.append(list(zip(v[0::2], v[1::2])))
        return out

    body = feat.split("\trails = {", 1)[1].split("\n\t},", 1)[0]
    rails = []
    for line in body.strip().split("\n"):
        v = list(map(float, re.findall(r"-?\d+", line)))
        if len(v) >= 4:
            rails.append(list(zip(v[0::2], v[1::2])))
    return feat, nodes, edges, bounds, polys("water"), polys("parks"), rails


LU_POLYS = []  # [(use, rank, (minX, maxX, minZ, maxZ), pts)] from Features.luau "landuse" (OSM)
LU_RANK = {"campus": 1, "military": 1, "green": 2, "industrial": 3, "commercial": 4, "residential": 5}


def load_landuse(feat):
    LU_POLYS.clear()
    if "\tlanduse = {" not in feat:
        return
    body = feat.split("\tlanduse = {", 1)[1].split("\n\t},", 1)[0]
    for m in re.finditer(r'use = "(\w+)", pts = \{ (.*?) \}', body):
        v = list(map(float, re.findall(r"-?\d+", m.group(2))))
        pts = list(zip(v[0::2], v[1::2]))
        if len(pts) >= 3:
            xs, zs = [p[0] for p in pts], [p[1] for p in pts]
            LU_POLYS.append((m.group(1), LU_RANK.get(m.group(1), 9), (min(xs), max(xs), min(zs), max(zs)), pts))


def land_use_raw(x, z):
    best = None
    for use, rank, (x1, x2, z1, z2), pts in LU_POLYS:
        if x1 <= x <= x2 and z1 <= z <= z2 and (best is None or rank < best[1]) and point_in(x, z, pts):
            best = (use, rank)
    return best[0] if best else None


def land_use(cfg, x, z):
    """The same rule as Map.landUse in Config/Maps/KhonKaen.luau, except that university / hospital /
    government grounds ("campus"), fields ("green") and military land come back as such: the planner
    invents no lanes there."""
    cx, cz = cfg["center"]
    dc = (x - cx) ** 2 + (z - cz) ** 2
    raw = land_use_raw(x, z)
    if raw in ("campus", "green", "military"):
        return raw
    if raw == "industrial":
        return "suburb"
    if dc < cfg["coreRadius"] ** 2:
        return "core"
    if raw == "commercial":
        return "urban"
    for b in cfg["boxes"]:
        if b["x1"] <= x <= b["x2"] and b["z1"] <= z <= b["z2"]:
            return b["use"]
    if cfg.get("ruralRadius") and dc > cfg["ruralRadius"] ** 2:
        return "rural"
    if cfg.get("suburbRadius") and dc > cfg["suburbRadius"] ** 2:
        return "suburb"
    return "urban"


def site_corners(s, grow):
    lx, lz = s["lx"], s["lz"]
    rx, rz = -lz, lx  # across the front
    hw, hd = s["w"] / 2 + grow, s["d"] / 2 + grow
    return [(s["x"] + rx * a * hw + lx * b * hd, s["z"] + rz * a * hw + lz * b * hd) for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]


def label_free(free):
    """4-connected components of a boolean grid, by runs (no scipy needed)."""
    h, w = free.shape
    labels = np.zeros((h, w), np.int32)
    parent = [0]

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    prev = []
    for y in range(h):
        d = np.diff(np.concatenate(([0], free[y].view(np.int8), [0])))
        starts, ends = np.flatnonzero(d == 1), np.flatnonzero(d == -1)
        runs = []
        j = 0
        for s, e in zip(starts.tolist(), ends.tolist()):
            lab = 0
            while j < len(prev) and prev[j][1] <= s:
                j += 1
            k = j
            while k < len(prev) and prev[k][0] < e:
                pl = find(prev[k][2])
                if lab == 0:
                    lab = pl
                elif pl != lab:
                    parent[max(pl, lab)] = min(pl, lab)
                    lab = min(pl, lab)
                k += 1
            if lab == 0:
                parent.append(len(parent))
                lab = len(parent) - 1
            runs.append((s, e, lab))
            labels[y, s:e] = lab
        prev = runs
    lut = np.array([find(i) for i in range(len(parent))], np.int32)
    return lut[labels]


def far_share(occ, road_mask, reach):
    """Share of free land farther than `reach` cells (Chebyshev) from any road."""
    near = road_mask.copy()
    for _ in range(reach):
        grown = near.copy()
        grown[1:, :] |= near[:-1, :]
        grown[:-1, :] |= near[1:, :]
        grown[:, 1:] |= near[:, :-1]
        grown[:, :-1] |= near[:, 1:]
        grown[1:, 1:] |= near[:-1, :-1]
        grown[:-1, :-1] |= near[1:, 1:]
        grown[1:, :-1] |= near[:-1, 1:]
        grown[:-1, 1:] |= near[1:, :-1]
        near = grown
    free = occ == 0
    return float((free & ~near).sum()) / max(1.0, float(free.sum()))


def main():
    preview = sys.argv[1] if len(sys.argv) > 1 else None
    run_osm()
    feat, nodes, edges, bounds, water, parks, rails = load()
    load_landuse(feat)
    print("land use polygons:", len(LU_POLYS))
    cfg_all = json.loads(read(SITES))
    sites, cfg = cfg_all["sites"], cfg_all["landUse"]
    # a site with "auto": true has no position yet: the planner finds free land for it beside a
    # bigger street near "near" and freezes the result into data/sites.json (see auto_place)
    autos = [s for s in sites if s.get("auto")]
    sites = [s for s in sites if not s.get("auto")]
    minX, maxX, minZ, maxZ = bounds
    W, H = int(math.ceil((maxX - minX) / CELL)), int(math.ceil((maxZ - minZ) / CELL))

    def px(x, z):
        return ((x - minX) / CELL, (z - minZ) / CELL)

    deg = [0] * len(nodes)
    node_r = [0.0] * len(nodes)
    for a, b, c, _, _ in edges:
        for n in (a, b):
            deg[n] += 1
            node_r[n] = max(node_r[n], ROADS[c][0] / 2 + ROADS[c][1])

    def raster(with_lanes_from=None):
        img = Image.new("I", (W, H), 0)
        dr = ImageDraw.Draw(img)
        for poly in parks:
            dr.polygon([px(x, z) for x, z in poly], fill=B_PARK)
        for poly in water:
            dr.polygon([px(x, z) for x, z in poly], fill=B_WATER)
        for run in rails:
            dr.line([px(x, z) for x, z in run], fill=B_RAIL, width=int(math.ceil(22 / CELL)))
        for s in sites:
            dr.polygon([px(x, z) for x, z in site_corners(s, 3)], fill=B_SITE)
        elist = with_lanes_from or edges
        nlist = nodes
        for i, (a, b, c, _, _) in enumerate(elist):
            hw = ROADS[c][0] / 2 + ROADS[c][1] + 1.5
            dr.line([px(*nlist[a]), px(*nlist[b])], fill=i + 1, width=max(1, int(round(2 * hw / CELL))))
        return np.array(img, dtype=np.int32), dr

    occ, _ = raster()
    # junction discs (drawn after so they close the gaps thick lines leave at bends)
    img = Image.fromarray(occ, mode="I")
    dr = ImageDraw.Draw(img)
    first_edge = {}
    for i, (a, b, _, _, _) in enumerate(edges):
        first_edge.setdefault(a, i)
        first_edge.setdefault(b, i)
    for n, (x, z) in enumerate(nodes):
        if n in first_edge:
            r = (node_r[n] + 2) / CELL
            cx, cz = px(x, z)
            dr.ellipse([cx - r, cz - r, cx + r, cz + r], fill=first_edge[n] + 1)
    occ = np.array(img, dtype=np.int32)

    for s in autos:
        if auto_place(s, occ, nodes, edges, (minX, maxX, minZ, maxZ)):
            sites.append(s)
            print("placed %s at %.0f, %.0f (%d x %d)" % (s["id"], s["x"], s["z"], s["w"], s["d"]))
        else:
            print("NO ROOM for %s near %s" % (s["id"], s.get("near")))
    if autos:
        # (2026-11-18: an auto site with no room used to vanish from sites.json; keep it for the next run)
        cfg_all["sites"] = sites + [s for s in autos if s.get("auto")]
        save_sites(cfg_all)

    road_before = (occ > 0) & (occ < B_MIN)
    share_before = far_share(occ, road_before, 12)

    labels = label_free(occ == 0)
    ys, xs = np.nonzero(labels)
    labs = labels[ys, xs]
    order = np.argsort(labs, kind="stable")
    ys, xs, labs = ys[order], xs[order], labs[order]
    cut = np.flatnonzero(np.diff(labs)) + 1
    groups = np.split(np.arange(len(labs)), cut)

    def edge_dir(i):
        a, b = edges[i][0], edges[i][1]
        dx, dz = nodes[b][0] - nodes[a][0], nodes[b][1] - nodes[a][1]
        L = math.hypot(dx, dz) or 1e-9
        return dx / L, dz / L, L

    anchors = []  # every lane node-to-be
    lanes = []  # ordered anchor lists
    edge_att = {}  # edge index -> anchors on it
    stats = {"regions": 0, "planned": 0, "skipped_small": 0, "skipped_use": 0, "no_road": 0}

    def anchor(kind, **kw):
        a = {"kind": kind, "id": None}
        a.update(kw)
        anchors.append(a)
        return a

    def sample(x, z):
        ix, iz = int((x - minX) / CELL), int((z - minZ) / CELL)
        if ix < 0 or iz < 0 or ix >= W or iz >= H:
            return -1, -1
        return int(occ[iz, ix]), int(labels[iz, ix])

    for g in groups:
        rid = int(labs[g[0]])
        gx = minX + (xs[g] + 0.5) * CELL
        gz = minZ + (ys[g] + 0.5) * CELL
        area = len(g) * CELL * CELL
        stats["regions"] += 1
        cxm, czm = float(gx.mean()), float(gz.mean())
        use = land_use(cfg, cxm, czm)
        if use not in PARAMS:
            stats["skipped_use"] += 1
            continue
        P = PARAMS[use]
        if area < P["T"] * 1.3 * 150:
            stats["skipped_small"] += 1
            continue
        if P["skip"] > 0:
            hsh = (int(cxm) * 7919 + int(czm) * 104729) % 1000 / 1000.0
            if hsh < P["skip"]:
                stats["skipped_use"] += 1
                continue
        # roads touching this block, weighted by how much of its edge they make
        x0, x1 = int(xs[g].min()), int(xs[g].max())
        y0, y1 = int(ys[g].min()), int(ys[g].max())
        pad = 3
        sx0, sy0 = max(0, x0 - pad), max(0, y0 - pad)
        sub = labels[sy0:min(H, y1 + pad + 1), sx0:min(W, x1 + pad + 1)] == rid
        socc = occ[sy0:min(H, y1 + pad + 1), sx0:min(W, x1 + pad + 1)]
        dil = sub.copy()
        for _ in range(2):
            gnew = dil.copy()
            gnew[1:, :] |= dil[:-1, :]
            gnew[:-1, :] |= dil[1:, :]
            gnew[:, 1:] |= dil[:, :-1]
            gnew[:, :-1] |= dil[:, 1:]
            dil = gnew
        vals = socc[dil & ~sub]
        vals = vals[(vals > 0) & (vals < B_MIN)]
        if len(vals) == 0:
            stats["no_road"] += 1
            continue
        ids, cnt = np.unique(vals, return_counts=True)
        # principal axis of the block
        cov = np.cov(np.vstack((gx - cxm, gz - czm)))
        ev, evec = np.linalg.eigh(cov)
        pa = math.atan2(evec[1, 1], evec[0, 1])  # long axis
        # grid direction: the heaviest street direction, folded to 90 degrees
        bins = [0.0] * 18
        binbest = [(0, 0.0)] * 18
        for eid, c in zip(ids.tolist(), cnt.tolist()):
            dx, dz, _ = edge_dir(eid - 1)
            ang = math.atan2(dz, dx) % (math.pi / 2)
            k = int(ang / (math.pi / 2) * 18) % 18
            bins[k] += c
            if c > binbest[k][1]:
                binbest[k] = (ang, c)
        k = max(range(18), key=lambda i: bins[i] + 0.5 * bins[(i + 1) % 18] + 0.5 * bins[(i - 1) % 18])
        th = binbest[k][0] if binbest[k][1] > 0 else pa
        # choose th or th + 90 so that u is the long direction
        best = None
        for cand in (th, th + math.pi / 2):
            ux, uz = math.cos(cand), math.sin(cand)
            pu = (gx - cxm) * ux + (gz - czm) * uz
            pv = -(gx - cxm) * uz + (gz - czm) * ux
            L, Wd = float(pu.max() - pu.min()), float(pv.max() - pv.min())
            if best is None or L > best[0]:
                best = (L, Wd, ux, uz, float(pu.min()), float(pu.max()), float(pv.min()), float(pv.max()))
        L, Wd, ux, uz, umin, umax, vmin, vmax = best
        vx, vz = -uz, ux
        n = max(1, int(round(Wd / P["T"])))
        m = max(1, int(round(L / P["LB"])))
        if n == 1 and m == 1:
            continue
        stats["planned"] += 1

        def runs_on(ox, oz, dx, dz, t0, t1):
            """Lane pieces along the line o + t*d that lie inside this block."""
            step = CELL / 2
            ts = np.arange(t0 - step, t1 + step, step)
            qx, qz = ox + ts * dx, oz + ts * dz
            ix = np.floor((qx - minX) / CELL).astype(np.int64)
            iz = np.floor((qz - minZ) / CELL).astype(np.int64)
            ok = (ix >= 0) & (iz >= 0) & (ix < W) & (iz < H)
            inside = np.zeros(len(ts), bool)
            inside[ok] = labels[iz[ok], ix[ok]] == rid
            d = np.diff(np.concatenate(([0], inside.view(np.int8), [0])))
            out = []
            for s, e in zip(np.flatnonzero(d == 1).tolist(), np.flatnonzero(d == -1).tolist()):
                out.append((float(ts[s]), float(ts[e - 1])))
            return out

        def end_anchor(ox, oz, dx, dz, t, sign):
            """What the lane meets when it leaves the block at parameter t going `sign`."""
            step = CELL / 2
            tt = t
            for _ in range(int(70 / step)):
                tt += sign * step
                c, lab = sample(ox + tt * dx, oz + tt * dz)
                if lab == rid:
                    continue
                if 0 < c < B_MIN:
                    ei = c - 1
                    a, b = edges[ei][0], edges[ei][1]
                    ex, ez, EL = edge_dir(ei)
                    ax, az = nodes[a]
                    den = dx * ez - dz * ex
                    if abs(den) > 1e-6:
                        # o + T*d = A + S*e
                        T = ((ax - ox) * ez - (az - oz) * ex) / den
                        S = ((ax - ox) * dz - (az - oz) * dx) / den
                        if -1.0 <= S <= EL + 1.0 and abs(T - t) < 90:
                            if abs(dx * ex + dz * ez) > 0.84:  # too shallow a meeting: stop short instead
                                return anchor("dead", x=ox + (t - sign * 10) * dx, z=oz + (t - sign * 10) * dz), t - sign * 10
                            S = min(max(S, 0.0), EL)
                            an = anchor("edge", e=ei, s=S, x=ax + ex * S, z=az + ez * S)
                            edge_att.setdefault(ei, []).append(an)
                            return an, T
                    # passes the end of that street: join its nearer end node
                    qx, qz = ox + tt * dx, oz + tt * dz
                    da = math.hypot(nodes[a][0] - qx, nodes[a][1] - qz)
                    db = math.hypot(nodes[b][0] - qx, nodes[b][1] - qz)
                    nn = a if da <= db else b
                    if min(da, db) < 60:
                        Tn = (nodes[nn][0] - ox) * dx + (nodes[nn][1] - oz) * dz
                        return anchor("node", n=nn, x=nodes[nn][0], z=nodes[nn][1]), Tn
                    return anchor("dead", x=ox + (t - sign * 8) * dx, z=oz + (t - sign * 8) * dz), t - sign * 8
                # water, park, railway, a site, another block or the map edge: dead end with room to turn
                return anchor("dead", x=ox + (t - sign * 8) * dx, z=oz + (t - sign * 8) * dz), t - sign * 8
            return anchor("dead", x=ox + t * dx, z=oz + t * dz), t

        a_runs, b_runs = [], []  # (fixed coordinate, t0, t1, anchor0, anchor1, crossings)
        for k in range(1, n):
            vfix = vmin + Wd * k / n
            ox, oz = cxm + vx * vfix, czm + vz * vfix
            for t0, t1 in runs_on(ox, oz, ux, uz, umin, umax):
                if t1 - t0 < MIN_LANE * 0.6:
                    continue
                a0, T0 = end_anchor(ox, oz, ux, uz, t0, -1)
                a1, T1 = end_anchor(ox, oz, ux, uz, t1, 1)
                if T1 - T0 >= MIN_LANE:
                    a_runs.append({"fix": vfix, "t0": T0, "t1": T1, "a0": a0, "a1": a1, "cross": []})
        for k in range(1, m):
            ufix = umin + L * k / m
            ox, oz = cxm + ux * ufix, czm + uz * ufix
            for t0, t1 in runs_on(ox, oz, vx, vz, vmin, vmax):
                if t1 - t0 < MIN_LANE * 0.6:
                    continue
                a0, T0 = end_anchor(ox, oz, vx, vz, t0, -1)
                a1, T1 = end_anchor(ox, oz, vx, vz, t1, 1)
                if T1 - T0 >= MIN_LANE:
                    b_runs.append({"fix": ufix, "t0": T0, "t1": T1, "a0": a0, "a1": a1, "cross": []})
        for ra in a_runs:
            for rb in b_runs:
                if ra["t0"] + 6 < rb["fix"] < ra["t1"] - 6 and rb["t0"] + 6 < ra["fix"] < rb["t1"] - 6:
                    cx = cxm + ux * rb["fix"] + vx * ra["fix"]
                    cz = czm + uz * rb["fix"] + vz * ra["fix"]
                    an = anchor("new", x=cx, z=cz)
                    ra["cross"].append((rb["fix"], an))
                    rb["cross"].append((ra["fix"], an))
        for r in a_runs + b_runs:
            r["cross"].sort(key=lambda c: c[0])
            lanes.append([r["a0"]] + [c[1] for c in r["cross"]] + [r["a1"]])

    # ----- turn anchors into nodes -----
    n_old = len(nodes)
    for a in anchors:
        if a["kind"] == "node":
            a["id"] = a["n"]
    new_edges = []
    removed = set()
    for ei, atts in edge_att.items():
        a, b, c, nm, ow = edges[ei]
        ex, ez, EL = edge_dir(ei)
        atts.sort(key=lambda t: t["s"])
        chain = [a]
        last_pos, last_id = None, None
        for an in atts:
            s = an["s"]
            if s < 30:
                an["id"] = a
            elif s > EL - 30:
                an["id"] = b
            elif last_pos is not None and s - last_pos < 36:
                an["id"] = last_id
            else:
                nodes.append([nodes[a][0] + ex * s, nodes[a][1] + ez * s])
                an["id"] = len(nodes) - 1
                last_pos, last_id = s, an["id"]
                chain.append(an["id"])
        chain.append(b)
        if len(chain) > 2:
            removed.add(ei)
            for p, q in zip(chain, chain[1:]):
                new_edges.append([p, q, c, nm, ow])
    for a in anchors:
        if a["id"] is None:
            nodes.append([a["x"], a["z"]])
            a["id"] = len(nodes) - 1
    all_edges = [e for i, e in enumerate(edges) if i not in removed] + new_edges
    lane_edges = []
    for lane in lanes:
        for p, q in zip(lane, lane[1:]):
            if p["id"] != q["id"]:
                lane_edges.append([p["id"], q["id"], LANE, 0, 0])

    # ----- clean up: merge new nodes that landed on top of another node -----
    parent = list(range(len(nodes)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    cellsz = 32.0
    buckets = {}
    for i, (x, z) in enumerate(nodes):
        buckets.setdefault((int(x // cellsz), int(z // cellsz)), []).append(i)
    used = set()
    for e in all_edges + lane_edges:
        used.add(e[0])
        used.add(e[1])
    for i in range(n_old, len(nodes)):
        if i not in used:
            continue
        x, z = nodes[i]
        bx, bz = int(x // cellsz), int(z // cellsz)
        bestj, bestd = None, 15.0
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for j in buckets.get((bx + dx, bz + dz), ()):
                    if j != i and j in used and find(j) != find(i):
                        d = math.hypot(nodes[j][0] - x, nodes[j][1] - z)
                        if d < bestd and (j < n_old or j < i):
                            bestj, bestd = j, d
        if bestj is not None:
            parent[find(i)] = find(bestj)

    def norm(elist):
        seen, out = set(), []
        for a, b, c, nm, ow in elist:
            a, b = find(a), find(b)
            if a == b:
                continue
            k = (min(a, b), max(a, b))
            if k in seen:
                continue
            seen.add(k)
            out.append([a, b, c, nm, ow])
        return out, seen

    all_edges, seen = norm(all_edges)
    tmp = []
    for a, b, c, nm, ow in lane_edges:
        a, b = find(a), find(b)
        k = (min(a, b), max(a, b))
        if a != b and k not in seen:
            seen.add(k)
            tmp.append([a, b, c, nm, ow])
    lane_edges = tmp

    def length(e):
        return math.hypot(nodes[e[0]][0] - nodes[e[1]][0], nodes[e[0]][1] - nodes[e[1]][1])

    # prune short dead-end lane stubs, then lanes that do not reach the street network
    while True:
        d2 = {}
        for e in all_edges + lane_edges:
            d2[e[0]] = d2.get(e[0], 0) + 1
            d2[e[1]] = d2.get(e[1], 0) + 1
        keep = [e for e in lane_edges if not ((d2[e[0]] == 1 or d2[e[1]] == 1) and length(e) < 48)]
        if len(keep) == len(lane_edges):
            break
        lane_edges = keep
    adj = {}
    for e in all_edges + lane_edges:
        adj.setdefault(e[0], []).append(e[1])
        adj.setdefault(e[1], []).append(e[0])
    reach = set()
    stack = [all_edges[0][0]]
    reach.add(stack[0])
    while stack:
        u = stack.pop()
        for v in adj.get(u, ()):
            if v not in reach:
                reach.add(v)
                stack.append(v)
    lane_edges = [e for e in lane_edges if e[0] in reach and e[1] in reach]
    final = all_edges + lane_edges

    # ----- write -----
    index, node_out = {}, []
    for e in final:
        for n in (e[0], e[1]):
            if n not in index:
                index[n] = len(node_out) + 1
                node_out.append(nodes[n])
    edge_out = [(index[a], index[b], c, nm, ow) for a, b, c, nm, ow in final]

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

    for f in os.listdir(OUT):
        if re.match(r"(Nodes|Edges)\d+\.luau$", f):
            os.remove(os.path.join(OUT, f))
    nn = write_chunks("Nodes", ["%d,%d" % (round(x), round(z)) for x, z in node_out])
    ne = write_chunks("Edges", ["%d,%d,%d,%d,%d" % e for e in edge_out])
    feat = re.sub(r"nodeChunks = \d+, edgeChunks = \d+", "nodeChunks = %d, edgeChunks = %d" % (nn, ne), feat)
    feat = feat.replace("-- Generated by tools/osm_to_map.py", "-- Generated by tools/osm_to_map.py + tools/plan_streets.py (lanes = road type 5 are ours, not OSM)", 1)
    with open(os.path.join(OUT, "Features.luau"), "w", encoding="utf-8", newline="\n") as f:
        f.write(feat)
    with open(os.path.join(OUT, "Plan.luau"), "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generated by tools/plan_streets.py from data/sites.json. Do not edit here.\n")
        f.write("-- sites: lot centre (x, z) and the unit vector from the centre to its street front (lx, lz).\n")
        f.write("return {\n\tsites = {\n")
        for s in sites:
            f.write('\t\t["%s"] = { x = %s, z = %s, lx = %s, lz = %s, w = %s, d = %s },\n' % (s["id"], s["x"], s["z"], s["lx"], s["lz"], s["w"], s["d"]))
        f.write("\t},\n\tlandUse = {\n")
        f.write("\t\tcenter = { %s, %s }, coreRadius = %s, suburbRadius = %s, ruralRadius = %s,\n\t\tboxes = {\n" % (
            cfg["center"][0], cfg["center"][1], cfg["coreRadius"], cfg.get("suburbRadius", "nil"), cfg.get("ruralRadius", "nil")))
        for b in cfg["boxes"]:
            f.write('\t\t\t{ use = "%s", x1 = %s, z1 = %s, x2 = %s, z2 = %s },\n' % (b["use"], b["x1"], b["z1"], b["x2"], b["z2"]))
        f.write("\t\t},\n\t},\n}\n")

    # ----- report -----
    lane_len = sum(math.hypot(node_out[a - 1][0] - node_out[b - 1][0], node_out[a - 1][1] - node_out[b - 1][1]) for a, b, c, _, _ in edge_out if c == LANE)
    img = Image.fromarray(occ, mode="I")
    dr = ImageDraw.Draw(img)
    for a, b, c, _, _ in edge_out:
        if c == LANE:
            dr.line([px(*node_out[a - 1]), px(*node_out[b - 1])], fill=1, width=max(1, int(round((ROADS[LANE][0] + 3) / CELL))))
    occ2 = np.array(img, dtype=np.int32)
    share_after = far_share(occ2, (occ2 > 0) & (occ2 < B_MIN), 12)
    dd = {}
    for a, b, _, _, _ in edge_out:
        dd[a] = dd.get(a, 0) + 1
        dd[b] = dd.get(b, 0) + 1
    print("blocks %d: planned %d, already small %d, left open by land use %d, no street %d" % (
        stats["regions"], stats["planned"], stats["skipped_small"], stats["skipped_use"], stats["no_road"]))
    print("nodes %d -> %d   edges %d -> %d   lanes %d (%.1f km at 0.28 m/stud)   dead ends %d" % (
        n_old, len(node_out), len(edges), len(edge_out), sum(1 for e in edge_out if e[2] == LANE), lane_len * 0.28 / 1000,
        sum(1 for v in dd.values() if v == 1)))
    print("building land farther than %d studs from any street: %.1f%% -> %.1f%%" % (12 * CELL, share_before * 100, share_after * 100))
    print("chunks nodes=%d edges=%d" % (nn, ne))
    # sites standing in water or on a street are a planning error
    for s in sites:
        bad = set()
        for x, z in site_corners(s, -4) + [(s["x"], s["z"])]:
            ix, iz = int((x - minX) / CELL), int((z - minZ) / CELL)
            if 0 <= ix < W and 0 <= iz < H:
                poly_in = any(point_in(x, z, p) for p in water)
                if poly_in:
                    bad.add("water")
                if any(point_in(x, z, p) for p in parks):
                    bad.add("park")
            else:
                bad.add("outside the map")
        if bad:
            print("  site %s: %s" % (s["id"], ", ".join(sorted(bad))))

    if preview:
        rgb = np.zeros((H, W, 3), np.uint8)
        rgb[:] = (206, 200, 178)
        rgb[occ2 == B_PARK] = (150, 190, 120)
        rgb[occ2 == B_WATER] = (110, 160, 210)
        rgb[occ2 == B_RAIL] = (90, 80, 80)
        rgb[occ2 == B_SITE] = (220, 120, 200)
        rgb[(occ2 > 0) & (occ2 < B_MIN)] = (70, 70, 76)
        im = Image.fromarray(rgb)
        d2 = ImageDraw.Draw(im)
        for a, b, c, _, _ in edge_out:
            if c == LANE:
                d2.line([px(*node_out[a - 1]), px(*node_out[b - 1])], fill=(230, 120, 40), width=2)
        im.save(preview)
        print("preview:", preview)


def auto_place(s, occ, nodes, edges, bounds):
    """Find free land for site s beside a street (not a soi) near s["near"]; fills x, z, lx, lz, w, d."""
    minX, maxX, minZ, maxZ = bounds
    H, W = occ.shape
    tx, tz = s["near"]
    sizes = s.get("sizes") or [[s["w"], s["d"]]]
    cands = []
    maxc = s.get("maxClass", 3)  # 4 = a soi will do (inside a campus every road is small)
    for a, b, c, _, _ in edges:
        if c > maxc:
            continue
        ax, az = nodes[a]
        bx, bz = nodes[b]
        L = math.hypot(bx - ax, bz - az)
        if L < 40:
            continue
        d = math.hypot((ax + bx) / 2 - tx, (az + bz) / 2 - tz)
        if d < 3000:
            cands.append((d, ax, az, (bx - ax) / L, (bz - az) / L, L, c))
    cands.sort()
    for w, dep in sizes:
        us = np.arange(-w / 2 - 4, w / 2 + 4.01, 4.0)
        vs = np.arange(-dep / 2 - 2, dep / 2 + 4.01, 4.0)
        U, V = np.meshgrid(us, vs)
        for _, ax, az, dx, dz, L, c in cands:
            hw = ROADS[c][0] / 2 + ROADS[c][1]
            for t in np.arange(w / 2 + 10, L - w / 2 - 10 + 0.01, 24.0) if L > w + 20 else [L / 2]:
                for side in (1, -1):
                    nx, nz = -dz * side, dx * side
                    cx = ax + dx * t + nx * (hw + 4 + dep / 2)
                    cz = az + dz * t + nz * (hw + 4 + dep / 2)
                    X = cx + dx * U + nx * V
                    Z = cz + dz * U + nz * V
                    if X.min() < minX + 12 or X.max() > maxX - 12 or Z.min() < minZ + 12 or Z.max() > maxZ - 12:
                        continue
                    ix = ((X - minX) / CELL).astype(np.int64)
                    iz = ((Z - minZ) / CELL).astype(np.int64)
                    if occ[iz, ix].any():
                        continue
                    occ[iz, ix] = B_SITE
                    s["x"], s["z"] = round(float(cx), 3), round(float(cz), 3)
                    s["lx"], s["lz"] = round(float(-nx), 6), round(float(-nz), 6)
                    s["w"], s["d"] = w, dep
                    for k in ("auto", "near", "sizes"):
                        s.pop(k, None)
                    return True
    return False


def save_sites(cfg_all):
    lines = ["{", '  "_comment": %s,' % json.dumps(cfg_all.get("_comment", ""), ensure_ascii=False), '  "sites": [']
    lines.append(",\n".join("    " + json.dumps(s, ensure_ascii=False, separators=(",", ":")) for s in cfg_all["sites"]))
    lines.append("  ],")
    lines.append('  "landUse": ' + json.dumps(cfg_all["landUse"], ensure_ascii=False, indent=2).replace("\n", "\n  "))
    lines.append("}")
    with open(SITES, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def point_in(x, z, poly):
    inside = False
    n = len(poly)
    for i in range(n):
        x1, z1 = poly[i]
        x2, z2 = poly[(i + 1) % n]
        if (z1 <= z < z2) or (z2 <= z < z1):
            if x < x1 + (z - z1) / (z2 - z1) * (x2 - x1):
                inside = not inside
    return inside


if __name__ == "__main__":
    main()
