"""Build the vegetation library: real branching trunks with leaf cards, palms, banana, shrubs, grass.

  blender --background --factory-startup -t 2 --python tools/blender_trees.py -- [--preview out.png] [name ...]

Reads the leaf cards from assets/textures/veg (tools/make_leaf_cards.py) and writes one GLB per
plant to assets/models/veg_<name>.glb: object "Trunk" (bark, opaque) and object "Leaves" (cards
with a transparent background, both sides modelled). 1 unit = 1 stud (0.28 m).
All shapes come from this script and a seed, so every variant is its own tree, not a rescaled copy.
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "assets", "textures", "veg")
OUT = os.path.join(ROOT, "assets", "models")
CARDS = json.load(open(os.path.join(TEX, "cards.json"), encoding="utf-8"))
UP = Vector((0, 0, 1))


def rand_unit(rnd):
    while True:
        v = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1)))
        if 0.05 < v.length < 1:
            return v.normalized()


def perp(d):
    a = d.cross(UP)
    if a.length < 1e-3:
        a = d.cross(Vector((1, 0, 0)))
    return a.normalized()


def deviate(d, angle, azimuth):
    """Direction `angle` away from d, at `azimuth` around it."""
    a = perp(d)
    b = d.cross(a).normalized()
    side = a * math.cos(azimuth) + b * math.sin(azimuth)
    return (d * math.cos(angle) + side * math.sin(angle)).normalized()


class Builder:
    def __init__(self, seed):
        self.rnd = random.Random(seed)
        self.trunk = bmesh.new()
        self.leaves = bmesh.new()
        self.uv_t = self.trunk.loops.layers.uv.new("UVMap")
        self.uv_l = self.leaves.loops.layers.uv.new("UVMap")
        self.card_pts = []

    # ---- wood ----
    def tube(self, pts, radii, sides, v_per_unit=1 / 7.0, u_span=(0.0, 1.0), cap=True):
        bm, uv = self.trunk, self.uv_t
        rings = []
        ref = None
        v = 0.0
        vs = []
        for i, p in enumerate(pts):
            d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            a = perp(d) if ref is None else (ref - d * ref.dot(d)).normalized()
            ref = a
            b = d.cross(a).normalized()
            ring = [bm.verts.new(p + (a * math.cos(k / sides * math.tau) + b * math.sin(k / sides * math.tau)) * radii[i]) for k in range(sides)]
            rings.append(ring)
            if i > 0:
                v += (p - pts[i - 1]).length * v_per_unit
            vs.append(v)
        for i in range(len(rings) - 1):
            for k in range(sides):
                k2 = (k + 1) % sides
                f = bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
                u0 = u_span[0] + (u_span[1] - u_span[0]) * k / sides
                u1 = u_span[0] + (u_span[1] - u_span[0]) * (k + 1) / sides
                for loop, (uu, vv) in zip(f.loops, ((u0, vs[i]), (u1, vs[i]), (u1, vs[i + 1]), (u0, vs[i + 1]))):
                    loop[uv].uv = (uu, vv)
                f.smooth = True
        if cap and radii[-1] > 0.05:
            tip = bm.verts.new(pts[-1] + (pts[-1] - pts[-2]).normalized() * radii[-1] * 0.6)
            for k in range(sides):
                f = bm.faces.new((rings[-1][k], rings[-1][(k + 1) % sides], tip))
                for loop in f.loops:
                    loop[uv].uv = (0.5, vs[-1])
                f.smooth = True

    # ---- leaves ----
    def quad(self, p0, p1, p2, p3, uvs):
        """One card, modelled on both sides (no reliance on double-sided rendering)."""
        bm, uv = self.leaves, self.uv_l
        for order in ((0, 1, 2, 3), (3, 2, 1, 0)):
            src = (p0, p1, p2, p3)
            vs = [bm.verts.new(src[i]) for i in order]
            f = bm.faces.new(vs)
            for loop, i in zip(f.loops, order):
                loop[uv].uv = uvs[i]
            f.smooth = True
        self.card_pts.extend((p0, p1, p2, p3))

    def card(self, base, up, size, box, roll=None, width=None):
        """A card growing from `base` along `up`; its image has the stem at the bottom centre."""
        up = up.normalized()
        side = perp(up)
        if roll is None:
            roll = self.rnd.uniform(0, math.tau)
        side = (Matrix.Rotation(roll, 3, up) @ side).normalized()
        w = (width or size) / 2
        x0, y0, x1, y1 = box
        self.quad(base - side * w, base + side * w, base + side * w + up * size, base - side * w + up * size,
                  ((x0, 1 - y1), (x1, 1 - y1), (x1, 1 - y0), (x0, 1 - y0)))

    def strip(self, pts, width, box, fold=0.35, lengthwise="u"):
        """A long leaf (palm frond, banana leaf) along a curved midrib, folded into a shallow V."""
        x0, y0, x1, y1 = box
        ym = (y0 + y1) / 2
        n = len(pts) - 1
        rows = []
        for i, p in enumerate(pts):
            d = (pts[min(i + 1, n)] - pts[max(i - 1, 0)]).normalized()
            s = perp(d)
            nrm = s.cross(d).normalized()
            if nrm.z < 0:
                nrm = -nrm
            lift = nrm * (width / 2) * math.sin(fold)
            out = s * (width / 2) * math.cos(fold)
            rows.append((p - out + lift, p, p + out + lift))
        for i in range(n):
            u0 = x0 + (x1 - x0) * i / n
            u1 = x0 + (x1 - x0) * (i + 1) / n
            a, b = rows[i], rows[i + 1]
            self.quad(a[0], a[1], b[1], b[0], ((u0, 1 - y0), (u0, 1 - ym), (u1, 1 - ym), (u1, 1 - y0)))
            self.quad(a[1], a[2], b[2], b[1], ((u0, 1 - ym), (u0, 1 - y1), (u1, 1 - y1), (u1, 1 - ym)))


def boxes(tex, kinds):
    return [c["uv"] for c in CARDS[tex] if c["kind"] in kinds]


def branching_tree(B, P):
    rnd = B.rnd

    def grow(start, d, length, r0, level):
        nseg = P["segs"][level]
        pts, radii = [start], [r0]
        for i in range(nseg):
            d = (d + rand_unit(rnd) * P["wander"][level] + UP * P["lift"][level]).normalized()
            if level > 0 and d.z < P.get("min_z", -0.25):
                d = Vector((d.x, d.y, P.get("min_z", -0.25))).normalized()
            pts.append(pts[-1] + d * length / nseg)
            radii.append(r0 * (1 - (1 - P["taper"]) * (i + 1) / nseg))
        B.tube(pts, radii, P["sides"][level])
        last = level >= P["levels"]

        def at(t):
            f = t * nseg
            i = min(int(f), nseg - 1)
            k = f - i
            return pts[i].lerp(pts[i + 1], k), (pts[i + 1] - pts[i]).normalized(), radii[i] + (radii[i + 1] - radii[i]) * k

        if not last:
            n = P["children"][level]
            az0 = rnd.uniform(0, math.tau)
            for k in range(n):
                t = P["first"][level] + (1 - P["first"][level]) * (k + rnd.uniform(0.2, 0.8)) / n
                p, dl, r = at(min(t, 0.98))
                cd = deviate(dl, P["angle"][level] * rnd.uniform(0.8, 1.2), az0 + k * 2.39996 + rnd.uniform(-0.3, 0.3))
                grow(p, cd, length * P["ratio"][level] * rnd.uniform(0.8, 1.15), max(0.12, r * P["thin"]), level + 1)
            if P.get("leader", True):
                p, dl, r = at(1.0)
                grow(p, (dl + rand_unit(rnd) * 0.25).normalized(), length * P["ratio"][level] * 0.8, max(0.12, r * 0.85), level + 1)
        if level >= P["leaf_level"]:
            cards = P["cards"]
            n = P["card_n"][min(level, len(P["card_n"]) - 1)]
            for k in range(n):
                t = 0.3 + 0.7 * (k + rnd.random()) / n
                p, dl, _ = at(min(t, 1.0))
                out = Vector((p.x, p.y, 0))
                out = out.normalized() if out.length > 0.5 else rand_unit(rnd)
                up = (dl * 0.5 + out * P["card_out"] + UP * P["card_up"] + rand_unit(rnd) * 0.45).normalized()
                size = P["card_size"] * rnd.uniform(0.8, 1.2)
                B.card(p, up, size, cards[rnd.randrange(len(cards))])
            p, dl, _ = at(1.0)
            B.card(p, (dl + UP * P["card_up"]).normalized(), P["card_size"] * 1.1, cards[rnd.randrange(len(cards))])

    lean = rand_unit(rnd) * P.get("lean", 0.08)
    grow(Vector((0, 0, -0.4)), (UP + Vector((lean.x, lean.y, 0))).normalized(), P["height"] * P["trunk"], P["radius"], 0)


def palm(B, P):
    rnd = B.rnd
    n = 10
    d = UP.copy()
    bend = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)).normalized() * P["bend"]
    pts, radii = [Vector((0, 0, -0.4))], [P["radius"] * 1.35]
    for i in range(n):
        d = (d + bend * (0.5 if i < n / 2 else -0.25) / n * 4).normalized()
        pts.append(pts[-1] + d * P["height"] / n)
        t = (i + 1) / n
        radii.append(P["radius"] * (1.0 - 0.3 * t) * (1 + P.get("bulge", 0) * math.sin(math.pi * min(1, t * 1.6))))
    B.tube(pts, radii, 8, v_per_unit=1 / 5.0)
    top = pts[-1]
    if P.get("shaft"):
        # smooth green crownshaft of a royal palm
        B.tube([top, top + d * P["shaft"]], [radii[-1] * 1.15, radii[-1] * 0.7], 8, u_span=(0.0, 1.0), v_per_unit=0.0)
        top = top + d * P["shaft"]
    fronds = boxes("veg_palm", ("frond",))
    count = P["fronds"]
    for i in range(count):
        az = i * 2.39996 + rnd.uniform(-0.2, 0.2)
        t = i / (count - 1)
        elev = math.radians(P["elev"][0] + (P["elev"][1] - P["elev"][0]) * t + rnd.uniform(-6, 6))
        fd = Vector((math.cos(az) * math.cos(elev), math.sin(az) * math.cos(elev), math.sin(elev)))
        L = P["frond"] * rnd.uniform(0.85, 1.1)
        seg = 5
        fp = [top]
        for k in range(seg):
            fd = (fd - UP * P["droop"] * (k + 1) / seg).normalized()
            fp.append(fp[-1] + fd * L / seg)
        B.strip(fp, P["frond_w"], fronds[i % len(fronds)])
    for _ in range(P.get("nuts", 0)):
        a = rnd.uniform(0, math.tau)
        c = top + Vector((math.cos(a), math.sin(a), -0.6)) * 1.0
        B.tube([c + UP * 0.7, c, c - UP * 0.7], [0.3, 0.75, 0.3], 6, u_span=(0.0, 1.0), v_per_unit=0.0, cap=False)


def banana(B, P):
    rnd = B.rnd
    leaf = boxes("veg_palm", ("banana",))[0]
    for s in range(P["stems"]):
        a = s * math.tau / P["stems"] + rnd.uniform(-0.4, 0.4)
        base = Vector((math.cos(a), math.sin(a), 0)) * (0 if s == 0 else rnd.uniform(1.2, 2.2))
        h = P["height"] * (1.0 if s == 0 else rnd.uniform(0.55, 0.8))
        lean = Vector((math.cos(a), math.sin(a), 0)) * (0 if s == 0 else 0.12)
        top = base + (UP + lean).normalized() * h
        B.tube([base - UP * 0.3, base.lerp(top, 0.5), top], [0.7, 0.55, 0.35], 7, v_per_unit=0.0)
        n = rnd.randint(6, 8)
        for i in range(n):
            az = i * 2.39996 + rnd.uniform(-0.3, 0.3)
            elev = math.radians(65 - 60 * i / (n - 1) + rnd.uniform(-8, 8))
            fd = Vector((math.cos(az) * math.cos(elev), math.sin(az) * math.cos(elev), math.sin(elev)))
            L = P["leaf"] * (h / P["height"]) * rnd.uniform(0.85, 1.1)
            fp = [top]
            for k in range(4):
                fd = (fd - UP * 0.42 * (k + 1) / 4).normalized()
                fp.append(fp[-1] + fd * L / 4)
            B.strip(fp, L * 0.32, leaf, fold=0.2)


def shrub(B, P):
    rnd = B.rnd
    cards = boxes("veg_shrub", P["kinds"])
    for i in range(P["n"]):
        az = i * 2.39996 + rnd.uniform(-0.3, 0.3)
        elev = math.radians(rnd.uniform(P["elev"][0], P["elev"][1]))
        d = Vector((math.cos(az) * math.cos(elev), math.sin(az) * math.cos(elev), math.sin(elev)))
        base = Vector((math.cos(az), math.sin(az), 0)) * rnd.uniform(0, P["spread"]) + UP * rnd.uniform(0, P["rise"])
        B.card(base, d, P["size"] * rnd.uniform(0.8, 1.15), cards[rnd.randrange(len(cards))])
    if P.get("stem"):
        B.tube([Vector((0, 0, -0.2)), Vector((0, 0, P["rise"] * 0.6))], [0.35, 0.2], 5)


BROAD = boxes("veg_broadleaf", ("broad",))
MANGO = boxes("veg_broadleaf", ("mango",))
FINE = boxes("veg_raintree", ("fine",))
KOON_LEAF = boxes("veg_goldenshower", ("leaf",))
KOON_ALL = boxes("veg_goldenshower", ("leaf", "flower", "flower"))
FRANGI = boxes("veg_frangipani", ("leaf", "flower"))

# height / radius in studs (1 stud = 0.28 m). levels = how many times branches fork.
RAIN = dict(height=44, trunk=0.36, radius=2.0, taper=0.62, levels=3, leaf_level=2, segs=[4, 5, 4, 3], sides=[9, 6, 5, 3],
            wander=[0.05, 0.14, 0.2, 0.22], lift=[0.3, 0.06, 0.05, 0.04], children=[5, 4, 3], first=[0.72, 0.4, 0.3],
            angle=[math.radians(58), math.radians(46), math.radians(45)], ratio=[1.05, 0.6, 0.55], thin=0.56, leader=False,
            cards=FINE, card_n=[0, 0, 4, 4], card_size=10.5, card_out=0.5, card_up=0.6, min_z=0.02)
MANGO_T = dict(height=32, trunk=0.42, radius=1.5, taper=0.6, levels=3, leaf_level=2, segs=[4, 4, 3, 3], sides=[8, 6, 5, 3],
               wander=[0.05, 0.15, 0.2, 0.25], lift=[0.3, 0.18, 0.12, 0.08], children=[4, 4, 3], first=[0.55, 0.35, 0.3],
               angle=[math.radians(48), math.radians(50), math.radians(50)], ratio=[0.85, 0.62, 0.55], thin=0.58,
               cards=MANGO, card_n=[0, 0, 3, 3], card_size=8.5, card_out=0.6, card_up=0.35)
SHADE = dict(MANGO_T, height=27, radius=1.2, cards=BROAD, card_size=7.5, children=[4, 3, 3])
KOON = dict(height=27, trunk=0.4, radius=1.0, taper=0.6, levels=3, leaf_level=2, segs=[4, 4, 4, 3], sides=[7, 5, 4, 3],
            wander=[0.07, 0.2, 0.25, 0.25], lift=[0.3, 0.1, -0.06, -0.12], children=[4, 3, 3], first=[0.6, 0.35, 0.3],
            angle=[math.radians(55), math.radians(52), math.radians(48)], ratio=[0.95, 0.65, 0.55], thin=0.56,
            cards=KOON_ALL, card_n=[0, 0, 3, 3], card_size=8.5, card_out=0.45, card_up=-0.15)
FRANGIPANI = dict(height=17, trunk=0.34, radius=0.95, taper=0.78, levels=2, leaf_level=2, segs=[3, 3, 2], sides=[7, 6, 5],
                  wander=[0.1, 0.12, 0.1], lift=[0.25, 0.25, 0.3], children=[3, 2], first=[0.85, 0.75],
                  angle=[math.radians(50), math.radians(42)], ratio=[0.9, 0.7], thin=0.78, leader=False,
                  cards=FRANGI, card_n=[0, 0, 1], card_size=7.5, card_out=0.3, card_up=0.8, lean=0.15)

PLANTS = {
    # name: (kind, params, seed, leaf texture, bark texture)
    "tree_rain_a": ("tree", RAIN, 101, "veg_raintree", "bark_tree"),
    "tree_rain_b": ("tree", dict(RAIN, height=38, children=[4, 4, 3]), 202, "veg_raintree", "bark_tree"),
    "tree_mango_a": ("tree", MANGO_T, 303, "veg_broadleaf", "bark_tree"),
    "tree_mango_b": ("tree", dict(MANGO_T, height=27, radius=1.25), 404, "veg_broadleaf", "bark_tree"),
    "tree_shade_a": ("tree", SHADE, 505, "veg_broadleaf", "bark_tree"),
    "tree_shade_b": ("tree", dict(SHADE, height=22, radius=1.0), 606, "veg_broadleaf", "bark_tree"),
    "tree_koon_a": ("tree", KOON, 707, "veg_goldenshower", "bark_tree"),
    "tree_koon_b": ("tree", dict(KOON, cards=KOON_LEAF, height=24), 808, "veg_goldenshower", "bark_tree"),
    "tree_frangipani_a": ("tree", FRANGIPANI, 909, "veg_frangipani", "bark_tree"),
    "palm_coconut_a": ("palm", dict(height=38, radius=0.9, bend=0.22, fronds=17, elev=(72, -28), frond=17, frond_w=4.6, droop=0.42, nuts=5), 111, "veg_palm", "bark_palm"),
    "palm_coconut_b": ("palm", dict(height=30, radius=0.85, bend=0.36, fronds=15, elev=(70, -32), frond=16, frond_w=4.4, droop=0.46, nuts=3), 222, "veg_palm", "bark_palm"),
    "palm_royal_a": ("palm", dict(height=34, radius=1.0, bend=0.02, bulge=0.28, shaft=5.0, fronds=14, elev=(74, -8), frond=14, frond_w=4.2, droop=0.36), 333, "veg_palm", "bark_palm"),
    "banana_a": ("banana", dict(height=9, stems=3, leaf=9.5), 444, "veg_palm", "bark_palm"),
    "shrub_hedge_a": ("shrub", dict(kinds=("hedge",), n=16, elev=(25, 85), spread=1.6, rise=1.2, size=4.2, stem=True), 555, "veg_shrub", "bark_tree"),
    "shrub_bougain_a": ("shrub", dict(kinds=("bougainvillea", "bougainvillea", "hedge"), n=18, elev=(15, 80), spread=2.0, rise=1.6, size=5.0, stem=True), 666, "veg_shrub", "bark_tree"),
    "grass_tuft_a": ("shrub", dict(kinds=("grass",), n=7, elev=(60, 88), spread=1.4, rise=0.0, size=3.2), 777, "veg_shrub", "bark_tree"),
}


def material(name, image_path, alpha):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(image_path, check_existing=True)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    if alpha:
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "DITHERED"
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
    return mat


def to_object(name, bm, mat, soften=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    if soften is not None:
        # foliage is lit as one rounded mass: normals lean away from the middle of the crown
        me.calc_loop_triangles()
        normals = []
        for loop in me.loops:
            v = me.vertices[loop.vertex_index].co
            n = (v - soften)
            n = n.normalized() if n.length > 1e-3 else UP
            n = (n * 0.75 + UP * 0.35).normalized()
            normals.append(n)
        me.normals_split_custom_set(normals)
    return obj


def build(name):
    kind, P, seed, leaf_tex, bark_tex = PLANTS[name]
    B = Builder(seed)
    {"tree": branching_tree, "palm": palm, "banana": banana, "shrub": shrub}[kind](B, P)
    centre = sum(B.card_pts, Vector()) / max(1, len(B.card_pts))
    bark_path = os.path.join(TEX, bark_tex + (".jpg" if os.path.exists(os.path.join(TEX, bark_tex + ".jpg")) else ".png"))
    objs = []
    if len(B.trunk.faces) > 0:
        objs.append(to_object("Trunk", B.trunk, material("bark_" + name, bark_path, False)))
    objs.append(to_object("Leaves", B.leaves, material("leaf_" + name, os.path.join(TEX, leaf_tex + ".png"), True), soften=centre))
    tris = 0
    for o in objs:
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
    return objs, tris


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    preview = None
    if "--preview" in argv:
        i = argv.index("--preview")
        preview = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    names = argv or list(PLANTS)
    os.makedirs(OUT, exist_ok=True)
    report = {}
    placed = []
    for idx, name in enumerate(names):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        objs, tris = build(name)
        size = [0, 0, 0]
        for o in objs:
            for i in range(3):
                size[i] = max(size[i], o.dimensions[i])
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        path = os.path.join(OUT, "veg_%s.glb" % name)
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True)
        report[name] = {"triangles": tris, "size": [round(v, 1) for v in size], "bytes": os.path.getsize(path)}
        print("VEG %-20s %5d tris  %5.1f x %5.1f x %5.1f  %d kB" % (name, tris, size[0], size[1], size[2], os.path.getsize(path) // 1024))
    with open(os.path.join(OUT, "veg_report.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(report, f, indent=1)

    if preview:
        # all plants in a row, one quick render, to look at before uploading anything
        bpy.ops.wm.read_factory_settings(use_empty=True)
        x = 0.0
        tallest = 1.0
        for name in names:
            objs, _ = build(name)
            w = max(o.dimensions.x for o in objs)
            x += w / 2 + 3
            for o in objs:
                o.location.x = x
            x += w / 2 + 3
            tallest = max(tallest, max(o.dimensions.z for o in objs))
        scene = bpy.context.scene
        scene.render.engine = "CYCLES"
        scene.cycles.samples = 12
        scene.cycles.use_denoising = False
        scene.render.threads_mode = "FIXED"
        scene.render.threads = 2
        scene.render.resolution_x = 1800
        scene.render.resolution_y = max(200, int(1800 * (tallest + 8) / (x + 8)))
        scene.render.film_transparent = False
        world = bpy.data.worlds.new("w")
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.7, 0.95, 1)
        world.node_tree.nodes["Background"].inputs[1].default_value = 1.1
        scene.world = world
        sun = bpy.data.lights.new("sun", "SUN")
        sun.energy = 3.5
        so = bpy.data.objects.new("sun", sun)
        so.rotation_euler = (math.radians(50), 0, math.radians(35))
        scene.collection.objects.link(so)
        bpy.ops.mesh.primitive_plane_add(size=2000, location=(x / 2, 0, -0.3))
        ground = bpy.context.active_object
        gm = bpy.data.materials.new("ground")
        gm.use_nodes = True
        gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.4, 0.34, 1)
        ground.data.materials.append(gm)
        cam = bpy.data.cameras.new("cam")
        cam.type = "ORTHO"
        cam.ortho_scale = x + 8
        co = bpy.data.objects.new("cam", cam)
        co.location = (x / 2, -220, (tallest + 8) / 2 - 3)
        co.rotation_euler = (math.radians(90), 0, 0)
        scene.collection.objects.link(co)
        scene.camera = co
        scene.render.filepath = preview
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", preview)


main()
