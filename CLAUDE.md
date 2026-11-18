# GoDash: rules for every Claude session

Speak Thai to the owner. Code, commits and docs may stay in English.

## We work on GitHub together (owner, 2026-11-18)

The owner: "จะแก้บน Git ด้วยกัน". The repo https://github.com/ppap2538/GoDash (public, branch `main`) is the shared
source of truth for the owner, the team and every Claude session.

- **Before you start:** `git checkout main && git pull`, so you build on the team's merged work.
- **The owner's own sessions:** commit and push each finished, verified batch to `main`. No need to ask first.
- **Team members:** one branch per topic (`fix/...`, `feat/...`) and a Pull Request into `main`, following
  [CONTRIBUTING.md](CONTRIBUTING.md). Never merge someone else's PR unasked; tell the owner it is waiting.
- **Before every push:** check for keys, cookies, passwords and personal paths (`C:\Users\...`, local promo folders).
  The repo is public.
- **Commit messages on Windows PowerShell:** write the message to a file and use `git commit -F <file>`. A `"` inside
  `-m` splits the argument and the commit fails.

## From GitHub to players (automatic since 2026-11-18)

Players get a change only after the owner publishes:

1. A PR is merged. GitHub Actions (`.github/workflows/luau-syntax.yml`) compiles every Luau file on each PR and push.
2. **Auto sync** on the owner's PC moves it into Studio by itself:
   - `tools/autosync.py` runs hidden from logon (`tools/autosync_start.ps1 -Install`; `-Uninstall` removes it).
     It fetches `origin/main` every 60 s, fast-forwards the local checkout when safe, and serves
     `http://127.0.0.1:8791`.
   - The Studio plugin `tools/studio_plugin/GoDashAutoSync.lua` (copied to `%LOCALAPPDATA%\Roblox\Plugins` on each
     start) polls every 15 s in Edit mode. It applies the scripts changed since the commit Studio last took
     (`tools/.synced/autosync.json`), then shows a panel saying "test and Publish".
   - A script edited in Studio as well is never overwritten silently. The panel asks: overwrite with GitHub's
     version, or skip.
3. The owner presses Play to check, then Publish.

Rules for Claude sessions with auto sync running:
- **Port 8791 belongs to autosync.py.** Don't start `python -m http.server 8791`: autosync already serves the project
  root there, so `tools/sync.luau` keeps working. Don't stop it either.
- **Only committed code on GitHub flows automatically.** Work in progress still goes in by hand:
  `sync_studio.py` + `sync.luau` + `--done`.
- **Pushing work you already synced by hand is safe.** The plugin sees Studio already has it and stays quiet.
- After changing the plugin file, run `tools/autosync_start.ps1` to copy it. Studio loads a new plugin file only after
  a restart.
- To change the place ids the plugin accepts (for example a dev copy), edit `PLACES` in the plugin.

## Never

- Publish the place, or spend Robux, without the owner.
- Touch live player data. Studio Play uses the `_Studio` data store.
- Move a player-owned plot in `data/sites.json`, or change the map origin LAT0/LON0.
- Leave `Qa*` workspace attributes set when saving the place.

The running checklist and test notes are in [docs/OVERHAUL.md](docs/OVERHAUL.md).
