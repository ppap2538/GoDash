"""Prepare Poly Haven glTF models for Roblox: decimate to a triangle budget, scale to studs, export GLB.

  blender --background --factory-startup -t 2 --python tools/blender_prepare.py

Reads assets/models_src/<id>/<id>.gltf, writes assets/models/<id>.glb and assets/models/report.json.
1 stud = 0.28 m, so models are scaled by 1/0.28 and arrive in Roblox at real size.
"""
import json
import os
import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "models_src")
OUT = os.path.join(ROOT, "assets", "models")
STUDS = 1 / 0.28

# triangle budget per model (whole model)
BUDGET = {
    "plastic_monobloc_chair_01": 3500, "utility_box_01": 4500, "potted_plant_04": 6200, "metal_trash_can": 7000,
    "street_lamp_02": 8000, "exterior_aircon_unit": 6000, "water_manhole_cover": 2000, "CoffeeCart_01": 10000,
    "shrub_03": 8000, "jacaranda_tree": 19000,
}


def tris(objs):
    n = 0
    for o in objs:
        o.data.calc_loop_triangles()
        n += len(o.data.loop_triangles)
    return n


os.makedirs(OUT, exist_ok=True)
report = {}
for name, budget in BUDGET.items():
    path = os.path.join(SRC, name, name + ".gltf")
    if not os.path.exists(path):
        print("SKIP", name)
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    before = tris(meshes)
    if before > budget:
        ratio = budget / before
        for o in meshes:
            bpy.context.view_layer.objects.active = o
            m = o.modifiers.new("dec", "DECIMATE")
            m.ratio = max(0.02, ratio)
            bpy.ops.object.modifier_apply(modifier=m.name)
    # one mesh per material keeps the part count low
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    # world-space size in metres before scaling
    bpy.context.view_layer.update()
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    size_m = mx - mn
    obj.scale = obj.scale * STUDS
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    after = tris([obj])
    out = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True, export_image_format="AUTO",
                              export_cameras=False, export_lights=False, export_yup=True)
    report[name] = {
        "tris_before": before, "tris_after": after, "materials": len(obj.data.materials),
        "size_m": [round(size_m.x, 3), round(size_m.z, 3), round(size_m.y, 3)],  # width, height, depth
        "height_studs": round(size_m.z * STUDS, 2), "mb": round(os.path.getsize(out) / 1e6, 2),
    }
    print("DONE", name, report[name])

with open(os.path.join(OUT, "report.json"), "w") as f:
    json.dump(report, f, indent=1)
