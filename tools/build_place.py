"""Build GoDash.rbxlx from src/ (no Rojo needed).

  python -I tools/build_place.py

Mapping:
  src/shared -> ReplicatedStorage.Shared
  src/server -> ServerScriptService.GoDash
  src/client -> StarterPlayer.StarterPlayerScripts.GoDash
  *.server.luau -> Script, *.client.luau -> LocalScript, *.luau -> ModuleScript, dir -> Folder
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
OUT = os.path.join(ROOT, "GoDash.rbxlx")

_ref = [0]


def ref():
    _ref[0] += 1
    return "RBX%08d" % _ref[0]


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def cdata(s):
    return "<![CDATA[" + s.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def item(cls, name, props="", children=""):
    return '<Item class="%s" referent="%s"><Properties><string name="Name">%s</string>%s</Properties>%s</Item>\n' % (
        cls, ref(), esc(name), props, children)


def script(cls, name, path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        src = f.read().replace("\r\n", "\n")
    if len(src.encode("utf-8")) > 199000:
        raise SystemExit("Source too large (>199k): " + path)
    return item(cls, name, '<ProtectedString name="Source">%s</ProtectedString>' % cdata(src))


def walk(d):
    out = []
    count = 0
    for name in sorted(os.listdir(d)):
        p = os.path.join(d, name)
        if os.path.isdir(p):
            xml, n = walk(p)
            out.append(item("Folder", name, "", xml))
            count += n
        elif name.endswith(".server.luau"):
            out.append(script("Script", name[:-12], p)); count += 1
        elif name.endswith(".client.luau"):
            out.append(script("LocalScript", name[:-12], p)); count += 1
        elif name.endswith(".luau"):
            out.append(script("ModuleScript", name[:-5], p)); count += 1
    return "".join(out), count


MATERIAL_ENUM = {"Asphalt": 1376, "Pavement": 836, "Concrete": 816, "Slate": 800, "CorrodedMetal": 1040, "Brick": 848,
                 "Grass": 1280, "Metal": 1088, "Marble": 784}


def material_variants():
    """MaterialVariants from src/shared/Config/Materials.luau (game scripts cannot create them at runtime)."""
    import re
    path = os.path.join(SRC, "shared", "Config", "Materials.luau")
    text = open(path, encoding="utf-8").read()
    out = []
    for m in re.finditer(r"(GD_\w+) = \{ base = Enum\.Material\.(\w+), tile = ([\d.]+)(.*?)\}", text):
        name, base, tile, rest = m.groups()
        maps = dict(re.findall(r"(color|normal|rough|metal) = id\((\d+)\)", rest))
        props = '<token name="BaseMaterial">%d</token><float name="StudsPerTile">%s</float><token name="MaterialPattern">1</token>' % (
            MATERIAL_ENUM[base], tile)
        for key, prop in (("color", "ColorMap"), ("normal", "NormalMap"), ("rough", "RoughnessMap"), ("metal", "MetalnessMap")):
            if key in maps:
                props += '<Content name="%s"><url>rbxassetid://%s</url></Content>' % (prop, maps[key])
        out.append(item("MaterialVariant", name, props))
    return "".join(out), len(out)


def main():
    shared, n1 = walk(os.path.join(SRC, "shared"))
    server, n2 = walk(os.path.join(SRC, "server"))
    client, n3 = walk(os.path.join(SRC, "client"))
    variants, n_variants = material_variants()
    ws_props = (
        '<bool name="StreamingEnabled">true</bool>'
        '<int name="StreamingMinRadius">220</int>'
        '<int name="StreamingTargetRadius">700</int>'
    )
    parts = [
        '<roblox version="4">\n',
        item("Workspace", "Workspace", ws_props),
        item("Players", "Players", '<bool name="CharacterAutoLoads">false</bool><int name="MaxPlayers">12</int>'),
        item("Lighting", "Lighting", '<token name="Technology">3</token>'),  # 3 = ShadowMap (measured faster); 4 = Future for per-pixel lights
        item("ReplicatedStorage", "ReplicatedStorage", "", item("Folder", "Shared", "", shared)),
        item("ServerScriptService", "ServerScriptService", "", item("Folder", "GoDash", "", server)),
        item("ServerStorage", "ServerStorage"),
        item("StarterGui", "StarterGui"),
        item("StarterPlayer", "StarterPlayer", "",
             item("StarterPlayerScripts", "StarterPlayerScripts", "", item("Folder", "GoDash", "", client))),
        item("SoundService", "SoundService"),
        item("MaterialService", "MaterialService", "", variants),
        "</roblox>\n",
    ]
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("".join(parts))
    print("OK %s  scripts: shared=%d server=%d client=%d  materials=%d  bytes=%d" % (OUT, n1, n2, n3, n_variants, os.path.getsize(OUT)))


if __name__ == "__main__":
    main()
