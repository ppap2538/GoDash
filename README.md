# GoDash: Thai Driver Life

Roblox life sim set in Khon Kaen city centre at 1:1 scale (1 stud = 0.28 m). Start on a bicycle, deliver food,
carry passengers, buy better vehicles, buy land, furnish a house, farm, eat and rest.

## Open and play

1. `powershell -ExecutionPolicy Bypass -File tools\reopen.ps1` — builds `GoDash.rbxlx` from `src/` and opens it in Roblox Studio.
   (Or run `python -I tools/build_place.py` and open `GoDash.rbxlx` yourself.)
2. Press **Play**. The server builds the city centre in about 5-8 s, then you spawn at the GoDash Rider Hub.
3. Get on your bike (**F**), press **J** to go online, accept an offer (**Y**) and follow the green route. The card at
   the top of the screen always says what to do next.

`GoDash.rbxlx` is generated: **edit the files in `src/`, not the place**. Anything changed inside Studio is lost on the next build.

### The place on Roblox

The game is also saved on Roblox as **GoDash Thai Driver Life** (public, 16+; place id 72947456721898). That copy is the one
that can load the imported mesh props and use real DataStores; the local `GoDash.rbxlx` falls back to simple props.
Script changes reach it through Studio (the assistant patches the scripts and saves), not through `reopen.ps1` —
running `reopen.ps1` closes that Studio window and opens the local file instead. `tools/sync_studio.py` lists which
scripts differ from the Roblox copy.

| Keys | |
|---|---|
| W / S, A / D | drive, steer |
| Space, Shift | handbrake, boost |
| F | get on the vehicle / headlights while driving |
| Z, C, X | indicators, hazards |
| E | interact, leave the vehicle |
| G | pick up / deliver while driving |
| Y | accept a job offer |
| J | go online / offline |
| K | show / hide the key help |
| M | phone |

## Working on it as a team

1. Make a branch, change files in `src/` (or `tools/`, `docs/`), open a pull request. One topic per PR.
2. Test locally: `python -I tools/build_place.py`, open `GoDash.rbxlx` in Roblox Studio, press Play. The local file
   uses simple stand-in props and keeps progress in memory only; that is expected.
3. Changes reach the live game only through the owner's Studio: after a PR is merged the owner syncs the scripts
   (`tools/sync_studio.py` + `tools/sync.luau`), tests, saves and presses **File -> Publish to Roblox**.

Not in this repository:
- `GoDash.rbxlx`: generated from `src/` by `tools/build_place.py`.
- `assets/models_src/`: Poly Haven glTF sources (one file is 199 MB). Re-download with `node tools/polyhaven_models.mjs <id>`.
- The models made with Studio's generator (vehicles, trees, pedestrians, the soi dog) live only in the Roblox place,
  under `ReplicatedStorage.GoDashModels`; see `docs/ASSETS.md` section 5.

Rules:
- New assets must be CC0 or carry an explicit commercial-use licence. Record each one in `docs/ASSETS.md`.
- Every player-visible text needs a Thai version. Add it to the tables in `src/client/Lang.luau`.
- No API keys, cookies or passwords in the repository. It is public.

## Layout

| Path | What |
|---|---|
| `src/shared/Config/*` | all tuning: vehicles, jobs, items, crops, housing, missions, sounds, materials, map |
| `src/shared/Config/Maps/KhonKaen*` | the province: real street graph (generated), places, plots |
| `src/shared/Net.luau` | every remote, with argument validation and per-player rate limits |
| `src/server/Services/*` | PlayerData, Economy, Inventory, Lifestyle, Time, Weather, Mission, NPC, Shop, Vehicle, Job, Delivery, Passenger, Farming, Housing |
| `src/server/World/*` | procedural city builder, shophouses, street life, landmarks, vehicles, furniture |
| `src/client/*` | Drive (vehicle physics), GPS, Phone, HUD, Env (lighting/weather), Build mode, Peds, Dogs, Street, Radio, Feedback |
| `src/client/Guide.luau` | the "what to do now" card at the top: next step, arrow + distance, action button; counts the first-delivery steps; J = online / offline |
| `src/client/Lang.luau` | Thai / English. Every GUI text is translated as it is set (exact strings, then patterns, then units); Thai text is drawn 20 % larger because Roblox's Thai fallback face is small. Add new strings to its tables |
| `src/client/Welcome.luau` | first-join card: pick a language, then three steps |
| `src/client/UI/*` | UI kit, theme, layout regions, layers, UI state, HUD widgets, interaction prompt |
| `tools/` | `build_place.py`, `reopen.ps1`, OpenStreetMap and Poly Haven fetchers |
| `docs/ASSETS.md` | every third-party asset with source and licence |

## Settings worth knowing (`src/shared/Config/Game.luau`)

- `DEV_RADIUS = 2000` — in Studio only the city within this many studs of the centre is built (fast Play). Live servers build the whole city. `nil` builds everything in Studio too (slow, heavy on RAM).
- `DATASTORE` — DataStore name. In an unpublished place the store is unavailable and progress is kept in memory for the session only.

## Studio-only test hooks (command bar, while playing, server side)

`workspace:SetAttribute("QaMoney", 100000)`, `("QaLevel", 12)`, `("QaClock", 20)`, `("QaWeather", "Storm")`.
On a vehicle model: `QaThrottle` / `QaSteer` attributes (client side) drive it without a keyboard.

## Adding another province

Add `Config/Maps/<Name>.luau` (+ its data folder from `tools/osm_fetch.mjs` with a new bounding box and `tools/osm_to_map.py`),
then set `Game.MAP`. Services read the map through the world registry, not through hard-coded places.

Map data © OpenStreetMap contributors (ODbL). Textures: Poly Haven (CC0).
