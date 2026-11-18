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

## From GitHub to players

Players get a change only after the owner publishes:

1. A PR is merged.
2. A Claude session pulls `main` and syncs `src/` into the open Studio (`python -I tools/sync_studio.py`, serve on
   :8791, run `tools/sync.luau`, then `sync_studio.py --done`).
3. It tests, saves the place and pushes any fixes.
4. The owner presses Publish.

Other people may also edit the live place in Team Create. Before syncing, compare Studio's scripts with git and ask
before overwriting edits made in Studio. Scripts are edited in git, not in Studio.

## Never

- Publish the place, or spend Robux, without the owner.
- Touch live player data. Studio Play uses the `_Studio` data store.
- Move a player-owned plot in `data/sites.json`, or change the map origin LAT0/LON0.
- Leave `Qa*` workspace attributes set when saving the place.

The running checklist and test notes are in [docs/OVERHAUL.md](docs/OVERHAUL.md).
