"""Write tools/sync.json: every script whose source differs from what the Roblox place already has.

  python -I tools/sync_studio.py          # changed files since the last confirmed sync
  python -I tools/sync_studio.py --all    # everything
  python -I tools/sync_studio.py --done   # mark the current src/ as synced (run after Studio applied it)

Studio pulls the file over http://localhost:8791 (python -m http.server 8791 in the project root) and
sets each script's Source; see tools/sync.luau. Needs "localhost:8791" in the Assistant HTTP allowlist.
"""
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
SNAP = os.path.join(ROOT, "tools", ".synced", "src")
BASE = {
    "shared": "ReplicatedStorage.Shared",
    "server": "ServerScriptService.GoDash",
    "client": "StarterPlayer.StarterPlayerScripts.GoDash",
}


def scripts():
    for top, base in BASE.items():
        for d, _, files in os.walk(os.path.join(SRC, top)):
            for f in files:
                if not f.endswith(".luau"):
                    continue
                path = os.path.join(d, f)
                rel = os.path.relpath(path, os.path.join(SRC, top)).replace("\\", "/")
                parts = rel.split("/")
                name = parts[-1]
                cls = "ModuleScript"
                if name.endswith(".server.luau"):
                    cls, name = "Script", name[:-12]
                elif name.endswith(".client.luau"):
                    cls, name = "LocalScript", name[:-12]
                else:
                    name = name[:-5]
                yield path, ".".join([base] + parts[:-1] + [name]), cls


def read(p):
    with open(p, encoding="utf-8", newline="") as f:
        return f.read().replace("\r\n", "\n")


if "--done" in sys.argv:
    shutil.rmtree(SNAP, ignore_errors=True)
    shutil.copytree(SRC, SNAP)
    print("snapshot updated")
    sys.exit(0)

out = []
for path, target, cls in scripts():
    snap = os.path.join(SNAP, os.path.relpath(path, SRC))
    src = read(path)
    if "--all" in sys.argv or not os.path.exists(snap) or read(snap) != src:
        out.append({"path": target, "class": cls, "source": src})
with open(os.path.join(ROOT, "tools", "sync.json"), "w", encoding="utf-8", newline="\n") as f:
    json.dump(out, f, ensure_ascii=False)
print("%d script(s) to sync: %s" % (len(out), ", ".join(o["path"].split(".")[-1] for o in out)))
