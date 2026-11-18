"""GoDash auto sync: GitHub `main` -> the open Roblox Studio. The owner only tests and presses Publish.

Runs quietly on the owner's PC (tools/autosync_start.ps1 starts it hidden, also at logon):
  * every POLL seconds: `git fetch origin main`, and fast-forward the local checkout when that is safe
    (on branch main, no local commits, no local edits in the way);
  * serves http://127.0.0.1:8791 for the Studio plugin (tools/studio_plugin/GoDashAutoSync.lua):
      GET  /autosync/manifest  scripts that changed on origin/main since the commit Studio last took
      POST /autosync/done      {"commit": sha}: Studio applied that commit
      GET  /autosync/status
    Every other path is a static file from the project root, so the manual flow
    (tools/sync_studio.py + tools/sync.luau over localhost:8791) keeps working while this runs.

Only COMMITTED code on GitHub reaches Studio. Work in progress in the local tree never does.
State lives in tools/.synced/ (git-ignored): autosync.json (last commit Studio took) and autosync.log.

  python -I tools/autosync.py            run (one copy; a second copy exits because the port is taken)
  python -I tools/autosync.py --once     fetch + print the pending manifest summary, then exit
"""
import json
import os
import subprocess
import sys
import threading
import time
from datetime import datetime
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE_DIR = os.path.join(ROOT, "tools", ".synced")
STATE = os.path.join(STATE_DIR, "autosync.json")
LOG = os.path.join(STATE_DIR, "autosync.log")
SNAP = os.path.join(STATE_DIR, "src")  # same snapshot tools/sync_studio.py keeps
PORT = int(os.environ.get("AUTOSYNC_PORT", "8791"))
POLL = int(os.environ.get("AUTOSYNC_POLL", "60"))
BRANCH = os.environ.get("AUTOSYNC_BRANCH", "main")
# AUTOSYNC_REF=<local ref> + AUTOSYNC_NOFETCH=1: test against a local branch without touching GitHub
REF = os.environ.get("AUTOSYNC_REF") or ("origin/" + BRANCH)
NOFETCH = os.environ.get("AUTOSYNC_NOFETCH") == "1"
BASE = {
    "shared": "ReplicatedStorage.Shared",
    "server": "ServerScriptService.GoDash",
    "client": "StarterPlayer.StarterPlayerScripts.GoDash",
}

lock = threading.Lock()
status = {"fetched": None, "fetchError": None, "pull": None}


def log(msg):
    os.makedirs(STATE_DIR, exist_ok=True)
    try:
        if os.path.exists(LOG) and os.path.getsize(LOG) > 1_000_000:
            os.replace(LOG, LOG + ".old")
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("%s %s\n" % (datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg))
    except OSError:
        pass


def git(*args, check=True, raw=False):
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    p = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, env=env, timeout=120,
                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    if check and p.returncode != 0:
        raise RuntimeError("git %s: %s" % (args[0], p.stderr.decode("utf-8", "replace").strip()))
    return p.stdout if raw else p.stdout.decode("utf-8", "replace")


def succeeds(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, timeout=60,
                          creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)).returncode == 0


def target(path):
    """src/client/UI/HUD/Speedometer.luau -> ("StarterPlayer.StarterPlayerScripts.GoDash.UI.HUD.Speedometer", "ModuleScript")"""
    parts = path.split("/")
    if len(parts) < 3 or parts[0] != "src" or parts[1] not in BASE or not parts[-1].endswith(".luau"):
        return None
    name, cls = parts[-1], "ModuleScript"
    if name.endswith(".server.luau"):
        cls, name = "Script", name[:-12]
    elif name.endswith(".client.luau"):
        cls, name = "LocalScript", name[:-12]
    else:
        name = name[:-5]
    return ".".join([BASE[parts[1]]] + parts[2:-1] + [name]), cls


def show(commit, path):
    return git("show", "%s:%s" % (commit, path), raw=True).decode("utf-8").replace("\r\n", "\n")


def load_state():
    try:
        with open(STATE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(st):
    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(st, f, ensure_ascii=False, indent=1)
    os.replace(tmp, STATE)


def head():
    return git("rev-parse", REF).strip()


def changed(base, tip):
    """[(status, path)] for src/ between two commits; renames come as delete + add."""
    out = git("diff", "-z", "--no-renames", "--name-status", base, tip, "--", "src")
    bits = [b for b in out.split("\0") if b]
    return [(bits[i], bits[i + 1]) for i in range(0, len(bits) - 1, 2)]


def manifest():
    with lock:
        st = load_state()
        tip = head()
        base = st.get("commit")
        if not base:  # first run: Studio was synced by hand up to what GitHub has now
            st["commit"] = base = tip
            st["at"] = datetime.now().isoformat(timespec="seconds")
            save_state(st)
            log("first run: Studio assumed to match %s" % tip[:7])
        m = {"ok": True, "base": base, "commit": tip, "short": tip[:7], "files": [], "skipped": [], "commits": [],
             "fetched": status["fetched"], "fetchError": status["fetchError"], "pull": status["pull"]}
        if base == tip:
            return m
        if not succeeds("cat-file", "-e", base + "^{commit}") or not succeeds("merge-base", "--is-ancestor", base, tip):
            m["ok"] = False
            m["error"] = "history changed (force push?): last synced %s is not under %s; sync by hand" % (base[:7], tip[:7])
            return m
        m["commits"] = [l for l in git("log", "--no-merges", "--format=%h %an: %s", "%s..%s" % (base, tip)).splitlines() if l][:12]
        for code, path in changed(base, tip):
            t = target(path)
            if not t:
                m["skipped"].append(path)
                continue
            e = {"path": t[0], "class": t[1], "file": path}
            if code.startswith("D"):
                e["kind"] = "delete"
                e["old"] = show(base, path)
            else:
                e["kind"] = "create" if code.startswith("A") else "update"
                e["source"] = show(tip, path)
                if not code.startswith("A"):
                    e["old"] = show(base, path)
            m["files"].append(e)
        return m


def snapshot_update(base, tip):
    """Keep tools/.synced/src (tools/sync_studio.py's idea of what Studio has) in step."""
    for code, path in changed(base, tip):
        dest = os.path.join(SNAP, *path.split("/")[1:])
        if code.startswith("D"):
            if os.path.exists(dest):
                os.remove(dest)
        else:
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as f:
                f.write(git("show", "%s:%s" % (tip, path), raw=True))


def done(commit):
    with lock:
        st = load_state()
        base = st.get("commit")
        if not base:
            return {"ok": False, "error": "no state"}
        if not commit or not succeeds("merge-base", "--is-ancestor", commit, head()):
            return {"ok": False, "error": "unknown commit %s" % commit[:7]}
        if os.path.isdir(SNAP):
            snapshot_update(base, commit)
        st["commit"] = commit
        st["at"] = datetime.now().isoformat(timespec="seconds")
        save_state(st)
        log("Studio took %s (was %s)" % (commit[:7], base[:7]))
        return {"ok": True, "commit": commit}


def fast_forward():
    """Bring the local checkout up to origin/main when nothing local is in the way."""
    if git("rev-parse", "--abbrev-ref", "HEAD").strip() != BRANCH:
        return "local checkout is not on %s" % BRANCH
    here, tip = git("rev-parse", "HEAD").strip(), head()
    if here == tip:
        return "up to date"
    if not succeeds("merge-base", "--is-ancestor", here, tip):
        return "local commits not on GitHub yet: not pulled"
    p = subprocess.run(["git", "merge", "--ff-only", "-q", tip], cwd=ROOT, capture_output=True,
                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    if p.returncode != 0:
        return "local edits in the way: not pulled (%s)" % p.stderr.decode("utf-8", "replace").strip()[:160]
    log("pulled %s..%s" % (here[:7], tip[:7]))
    return "pulled to %s" % tip[:7]


def poller():
    while True:
        if not NOFETCH:
            try:
                git("fetch", "-q", "origin", BRANCH)
                status["fetched"] = datetime.now().isoformat(timespec="seconds")
                if status["fetchError"]:
                    log("fetch works again")
                status["fetchError"] = None
                status["pull"] = fast_forward()
            except Exception as ex:  # offline, credentials, ...
                if status["fetchError"] != str(ex):
                    log("fetch failed: %s" % ex)
                status["fetchError"] = str(ex)
        time.sleep(POLL)


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/autosync/manifest":
            try:
                return self.send_json(manifest())
            except Exception as ex:
                log("manifest failed: %s" % ex)
                return self.send_json({"ok": False, "error": str(ex)})
        if path == "/autosync/status":
            st = load_state()
            return self.send_json({"ok": True, "studio": st.get("commit"), "at": st.get("at"), "ref": REF,
                                   "fetched": status["fetched"], "fetchError": status["fetchError"],
                                   "pull": status["pull"]})
        return super().do_GET()

    def do_POST(self):
        if self.path.split("?")[0] != "/autosync/done":
            return self.send_json({"ok": False, "error": "not found"}, 404)
        try:
            n = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(n).decode("utf-8") or "{}")
            return self.send_json(done(str(body.get("commit", ""))))
        except Exception as ex:
            log("done failed: %s" % ex)
            return self.send_json({"ok": False, "error": str(ex)})


def main():
    if "--once" in sys.argv:
        if not NOFETCH:
            git("fetch", "-q", "origin", BRANCH)
        m = manifest()
        print(json.dumps({k: v for k, v in m.items() if k != "files"}, ensure_ascii=False, indent=1))
        for e in m["files"]:
            print("  %-6s %s" % (e["kind"], e["path"]))
        return
    try:
        server = ThreadingHTTPServer(("127.0.0.1", PORT), partial(Handler, directory=ROOT))
    except OSError:
        print("port %d is taken: auto sync (or another server) is already running" % PORT)
        return
    log("started: watching %s every %d s, serving 127.0.0.1:%d" % (REF, POLL, PORT))
    threading.Thread(target=poller, daemon=True).start()
    server.serve_forever()


if __name__ == "__main__":
    main()
