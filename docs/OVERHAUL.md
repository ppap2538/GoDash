# GoDash overhaul: working checklist

One list for the whole overhaul (the owner's "master prompt" of 2026-11-16 plus the urban-layout update of the same
day). Update it when a task changes state. States: **DONE** = built and checked in a Studio play test,
**PARTLY** = some of it done (the line says what is left), **TODO** = not started.

How to check anything here: sync `src/` into the Roblox place (`tools/sync_studio.py` + `tools/sync.luau`), press
Play, and use the Studio test hooks listed at the bottom.

## 1. City layout (the urban-planning update) — first pass DONE

Root causes found in the old city, and what replaced them:

| Problem | Cause | Fix |
|---|---|---|
| One row of buildings along each street, grass behind | OpenStreetMap only has the public streets; real blocks are 100-200 m across and the builder made lots 34 studs deep | `tools/plan_streets.py` lays lanes (ซอยย่อย, road type 5 `lane`) inside every oversized block, aligned with the block's main street. Building land farther than 72 studs from a street: **49.9 % -> 12.4 %** (what is left is farmland and the open suburb blocks). 1,991 street segments -> 7,169 |
| Towers and houses scattered on open ground | a "filler" pass dropped them on a 104-stud grid | removed. Every building now stands on a property that fronts a street |
| No buildings outside 2,000-2,600 studs of the centre (the dealer, the lake, the farm stood in an empty plain) | the server could only afford to build the centre | the whole map is planned at start-up (about 28,000 properties, 6-8 s) and drawn around the players a chunk at a time (`World/Streamer`). A fast car (90 studs/s) never outruns it in the play test |
| Bueng Kaen Nakhon and every park were missing | the outline simplifier collapsed closed rings to one point | fixed in `tools/osm_to_map.py` (`dp_ring`); the lake (about 620 x 1,380 m) and five parks are back |
| Gaps in the frontage opposite every side street | junction clearance was one number per junction | clearance is worked out per street side: a lane joining from the left opens a gap on the left only |
| People could walk straight across blocks | no property boundaries | every home, apartment, yard and car park has walls 8 studs high (a character jumps about 7) with a gate on the street |

What a lot becomes depends on the land use (`data/sites.json` -> `landUse`): **core** (within 1,500 studs of the
centre: shophouses, towers on the main streets, townhouses and apartments on the lanes), **urban**, **suburb**
(detached houses in compounds, some blocks left as orchards), **rural** (fields with crop rows, farmhouses on stilts).

Checked in play tests on 2026-11-16 (screenshots taken in Studio, not kept in the repository):
- top-down over the Rider Hub: blocks filled edge to edge, lanes between them, the diagonal street lined with shophouses
- lane at street level: walls, gates, townhouses, power poles with wires and lamps
- lakeside district: houses in compounds, apartments, park lawn
- farm district: fields, farmsteads, the Community Farm
- no server or client errors; the minimap and the Guide route work on the new streets

Still to do for the layout:
- [ ] TODO landmarks per district (lakeside promenade, a university district with a campus + Kangsadan strip, market hall, gateway signs) so each district is recognisable
- [x] DONE 2026-11-18 (§17) roundabouts / pedestrian crossings / road markings at lane mouths
- [x] DONE 2026-11-18 (§16c) AI traffic and pedestrians follow the player across the whole map (`Game.TRAFFIC_RADIUS = math.huge`)
- [x] DONE 2026-11-18 (§17) fields: bunds, sugar palms, dirt tracks, the gaps filled with farmland
- [x] DONE 2026-11-18 (§17) a far-distance backdrop (World/Skyline + client/Backdrop)
- [ ] TODO measure part count and frame time on a phone with several players in different districts

## 2. Master prompt sections

| # | Section | State | Notes |
|---|---|---|---|
| 2 | Audit of the existing project | DONE | see section 3 below |
| 3 | City environment rebuild | PARTLY | layout done (section 1). Building detail: new buildings (homes, townhouses, apartments, towers) are simple shapes with PBR walls; facades need windows, doors, balconies like the hero shophouses have |
| 4 | Trees, plants, ground | PARTLY | 16 plant models of 9 species with see-through leaf cards replace the clay trees (docs/ASSETS.md section 7), checked in Studio and in a play test. Left: hedges and flower beds along walls and in parks, grass tufts on verges, a second frangipani, leaf shadows review, triangle count on phones. Ground under the town is packed earth, not grass |
| 5 | Free asset acquisition | PARTLY | 8 Poly Haven props + 14 PBR materials are in (docs/ASSETS.md). Poly Haven's trees were checked: all are 0.3 - 17 million polygons, so the trees are our own. More needed: vehicles, street furniture |
| 6 | Street infrastructure / traffic lights | PARTLY | poles, wires and a lamp on every pole in the lanes; street lamps every 100 studs on alternating sides. Fixed: lamps in districts that loaded after dark never switched on (the light arrives after its lamp; `Env.applyLight` now waits for it), 387 of 387 lit in the play test. Traffic-light proportions not reviewed yet |
| 7 | Vehicles and driving | TODO (review) | existing system untouched |
| 8 | AI traffic, motorcycle riders | PARTLY | Root cause of the riderless motorbikes: traffic used the parked-showroom copy of each vehicle. `VehicleFactory.traffic` now seats a rider (helmet, hands on the bars) inside every AI two-wheeler model, so it cannot come off; play test: 16 of 16 two-wheelers carry a rider. 32 AI vehicles instead of 14. Left: the rider is a blocky figure (use the avatar models), drivers in cars, taxis / buses / delivery vans, lane keeping and pedestrian avoidance review, traffic that follows the player across the map |
| 9 | Living NPCs | TODO | |
| 10 | GPS and road navigation | PARTLY | routing already follows the road graph and now uses the lanes too; POI database, search app, turn-by-turn not reviewed |
| 11 | Needs recommendations | PARTLY | the Guide card already leads to food when hungry; energy / happiness / fuel / damage not reviewed |
| 12 | Home and dealership | TODO (review) | |
| 13 | Smartphone | TODO (review) | |
| 14 | Jobs | TODO (verify) | dispatcher now picks from every address on the map; a full delivery was not replayed after the rebuild |
| 15 | Housing | TODO (verify) | plots stand exactly where they did (data/sites.json) |
| 16 | Farming | TODO (review) | |
| 17 | Weather, day-night | PARTLY | Colour tone regraded to the owner's brief of 2026-11-16: cozy (soft warm light, low contrast, no glare), never dark enough to look scary, nights lit by street lamps and warm windows. Checked at noon and at 21:00 in a play test. Left: golden hour and rain looks, wet roads review |
| 18 | UX/UI | TODO | |
| 19 | Onboarding | TODO (review) | |
| 20 | Sound | TODO | |
| 21 | Performance | PARTLY | streaming city; phone measurements still to do |
| 22-23 | Play tests and screenshots | PARTLY | layout only so far |

## 3. Audit notes (2026-11-16)

- The place has no baked map: the server builds everything from `src/` at start-up. Code lives in `src/`, the cloud
  place gets it through `tools/sync_studio.py` + `tools/sync.luau` (HTTP on localhost:8791).
- Player data: `GoDash_Profiles_v1`. Nothing in this overhaul touches the profile format. Plot ids and positions are
  frozen in `data/sites.json`, so land that players own stays where it is.
- Working before the overhaul and kept: jobs (food + ride), vehicles and garage, shop / food, needs (hunger, energy,
  happiness), housing and furniture, farming allotments, bank, missions, daily reward, phone, GPS route on roads,
  minimap, radio, weather, day-night, Thai / English.
- Found broken: lake and parks missing (fixed), minimap had no colour for a new road type (fixed).

## 6. Owner feedback after the first publish (2026-11-16, played on the live game)

| # | What the owner said | State | What was done |
|---|---|---|---|
| 1 | The route line is ugly: it should run in the left lane and be better arrows | DONE | `GPS.luau`: a row of arrows (Beams with our `assets/textures/route_chevron.png`) flowing along the left lane, mitred round corners |
| 2 | The minimap should turn with the way you face | DONE | heading-up minimap (the turning part is a CanvasGroup so it stays clipped), N rides the edge, icons stay upright |
| 3-4 | Eating / drinking, taking an order and delivering need an animation and a cutscene, not a dry button | DONE (first pass) | `client/Cutscene.luau`: letterbox, the rider (a local copy) walks to the shop or customer, eats / drinks / takes the bag / hands it over and gives a wai; any key skips; the pay slip waits for the scene. Server sends `Notify "scene"` from Shop eatnow, Inventory eat and the food job steps. Replayed for real in Studio on 2026-11-16: bought a meal and a drink at a shop, then one whole food job (offer -> accept -> pick-up scene -> hand-over scene -> pay slip: fare 71, tip 28, 31 EXP, 5 stars). The pay slip comes up after the scene |
| 5 | A street-name sign stands in the middle of the road | DONE | signs go on the pavement corner between two of the streets, and only at junctions with a bigger road |
| 6 | NPCs run about at random; they should stroll along the streets and there should be many more; the town looks deserted | DONE (first pass) | `client/Peds.luau` rewritten: 34 people on PC / 18 on phones, moved along pavements and soi edges at walking pace (no physics), idle now and then; the avatars' arms hung 43 degrees out (A-pose), fixed at the shoulder joints |
| 7 | The lights are too bright (dusk and night were blown out on the live game) | DONE | the live client runs a higher graphics level than the Studio test did. Night exposure 0.2, lamps 1.2-1.5, bloom threshold 2.0, amber windows dimmer; checked at graphics level 21 |
| 8 | Cannot switch back to third person | DONE | `Drive.toggleView` pushes the zoom back out |
| 9 | Traffic jams, lots of cars, people crossing, so that finding a short cut matters; barking dogs in the small sois | DONE except the bark upload | `client/Street.luau`: besides the 30 route vehicles, every client runs **local traffic** on the big streets around its own player (22 on PC, 12 on phones; x1.4 and slower in the rush hours 07:00-09:30 and 16:30-19:30, x0.45 late at night). They queue at red lights and behind each other, brake for people, and stay out of the lanes, so the sois are the short cut. Play test: 13 vehicles queued within 70 studs at a light; 31 local vehicles + 34 pedestrians at 60 fps on the PC. 40 soi dogs. **Bark:** our own synthesised sound is ready (`tools/make_bark.py` -> `assets/sfx/dog_bark.wav`) and the dogs play it as soon as `Config/Sounds.dogBark` has an id; the upload was refused because `assets/sfx` is not an approved upload directory (see section 5) |
| 10 | A fatigue bar and a pop-up telling you to go and sleep; it must offer buying a house too | DONE | the bar is "Fatigue" now (fills as you tire); `client/Tired.luau` pops up at 30 and 12 energy left with one-tap routes to home / the nearest free rest spot, the nearest plot for sale (with its price) and a drink |

Checked on 2026-11-16 as well: the route arrows flow toward the destination (measured: a negative Beam.TextureSpeed moves
the texture toward Attachment0, in texture lengths per second), and the night look at graphics level 3 (readable, no glare).

Lighting note: always check dusk (18:45) and night (21:00) at `settings().Rendering.QualityLevel = Level21`, and wait
about ten seconds after the lamps come on before judging; the default Studio level shows a much darker picture than players get.

## 7. Polish pass before the owner's single play-through (2026-11-16: "make it beautiful, finish it, I will play once")

| What | State | Notes |
|---|---|---|
| AI riders were block figures | DONE | `shared/RiderPose.luau` seats one of the avatar models on every AI two-wheeler (hips on the saddle, hands on the bars, helmet). Fixed on the way: clients cloned the traffic kit before all of it had arrived, so some riders were only a helmet; the kit now carries its size and clients wait for it |
| Homes, townhouses, apartments and towers had blank fronts | DONE | facade tiles (`tools/make_facades.py`, `assets/textures/facade`): one part with a tiled picture per floor: doors, folding gates, louvred windows with grilles, balconies with railings, air-cons, curtain walls. The glass is cut out of the picture, so windows are dark by day and lit amber at night, floor by floor. Fewer parts than before |
| Night glare on walls beside lamps | DONE | lamps 1.0-1.15, night exposure 0.12; checked at graphics level 21 |
| Cutscene props | DONE | the bowl is held level; the rider stops an arm's length from the customer |

Still open after this pass: the dog bark upload (section 5), frame rate on phones (not measurable from Studio),
landmarks per district, a university district, the shop-interior and NPC-in-restaurant behaviours of the master
prompt, sound design, and a full UI / phone review.

## 8. Finishing pass and full test (2026-11-16: "finish it, test it to the end")

Built:

| What | Notes |
|---|---|
| University district | `Kaen Nakhon University` (our own name): gate, avenue, clock-tower hall, faculty blocks, 400 x 190 studs. The planner now places a site by itself (`"auto": true` in `data/sites.json`) and freezes the result. New zone "University District · Kangsadan" (north-west); houses there become student apartments 65 % of the time |
| District gateways | green sign gantries over the big roads where one district ends and the next begins (18 crossings, one every 800 studs at most) |
| Diners | people sit at the tables in front of restaurants (two each) and at some street tables (`Life.diners`, seated pose in `shared/RiderPose`) |
| Frame-rate governor | `client/Perf.luau`: below 27 fps pedestrians and local traffic are thinned in steps down to 30 %, restored above 48 fps |
| Dog bark | "Coyotes Gruff Barking 8 / 13 (SFX)" by Pro Sound Effects (the Roblox-licensed catalogue the other sounds use). No manual upload needed any more; our synthesised bark stays as a spare |
| Shophouse fronts away from the centre | simple terraces and the lighter main-street fronts use the facade tiles too (louvred windows, grilles, air-cons) |
| **Bug found by the test: nowhere to rest** | the hub benches and the lakeside sala were listed as free rest spots, the Guide and the tired pop-up sent players there, but no prompt was ever created. Fixed in `ShopService.start` |
| Tired pop-up | closes by itself when the player rests or recovers |
| Cutscene props | cup upright in the hand, bag hanging under it |

Test results (Studio play, test profile in the `_Studio` data store; live player data is a separate store and was not touched):

| Area | Result |
|---|---|
| Server start: whole city planned in 5.8 s, no warnings | PASS |
| Environment looked at: university, gateway, townhouse lane, apartment (day + night), detached houses, tower, diners, street trees | PASS |
| Rest at the hub bench (energy 44.9 -> 54.4), tired card closes while resting | PASS |
| Sleep in my own bed (energy 0 -> 36 in 6 s) | PASS |
| Eat at a shop (scene + hunger restored), drink (scene) | PASS |
| Shop screen through the real prompt (GoMart 24) | PASS |
| Buy a vehicle at KK Motors (money 400,588 -> 398,788), spawn, refuel, repair | PASS |
| Bank deposit / withdraw, daily reward | PASS |
| Buy land (S6: 398,788 -> 373,788), place a bed | PASS |
| Farm: till, buy seeds, plant lettuce, water | PASS |
| Food job: offer -> accept -> pick-up scene -> drop-off scene -> pay slip (earlier run: fare 71, tip 28, 31 EXP, 5 stars) | PASS |
| Orders pause while the rider is starving | PASS (by design) |
| Anti-cheat: a delivery finished by teleporting 4,723 studs in 37 s is not paid | PASS (by design) |
| GPS: route drawn to the customer (7 pieces); after leaving it by 370 studs it is redrawn from the rider (9 pieces, 11 studs away) | PASS |
| Phone: 16 screens opened in turn without an error; 1 error came from the test's own incomplete argument | PASS |
| AI traffic: 28 route vehicles + local traffic, every two-wheeler has a rider | PASS |
| Frame-rate governor: pedestrians 18 -> 5, local traffic 10 -> 3 at scale 0.3 | PASS |
| Dog bark sound loads (0.66 s) | PASS |
| Client and server logs at the end of the last run | no errors |

Added after the test, same day (owner: "a cutscene when resting too: sitting to rest, lying down to sleep"): `client/Cutscene.luau` `restScene`. Bench / sala: the server seats the rider on a real `Seat` (tag `RestSeat`, added to every `S.bench`) and the camera comes round to the front and moves in. Bed: a local copy of the rider lies on the mattress, head on the pillow, and the picture dims. Both show a caption and a rising 💤, and any key skips. Checked in a play test at the hub bench and on the test profile's bed; no errors.

NOT TESTED (cannot be done from Studio on this PC): frame rate and touch layout on a real phone; several players on
one server; other screen sizes.

## 9. Owner requests during play (2026-11-16, second round)

Built:

| Request (owner's words) | What was done |
|---|---|
| "Can I give passengers rides too, like Grab?" | **GoDash Ride** (no Grab name): the passenger waits at the kerb waving (pose `hail`), a boarding scene walks them to the vehicle, they sit behind the rider (pose `pillion`, no helmet) or in the car seat (welded to the chassis), and an alighting scene ends with a wai. `PassengerService`, `NPCService.figure / weldTo`, `client/Cutscene` `passengerScene` |
| "Cars stuck crossways in the middle of the road" | `client/Street.luau`: AI cars only queue behind traffic going their way; a junction lock lets one through at a time; 8 s held up by AI traffic = 3 s of ignoring it; a car still for 20 s out of view respawns elsewhere; spawns stay out of junctions |
| "KK Motors must give directions" | Phone vehicle screen and showroom: "🧭 navigate to KK Motors"; failed purchase / upgrade / repair messages route there by themselves |
| "Upbeat music so it never gets boring" | New first station **GoDash Beat** (15 APM / Distrokid tracks, see ASSETS.md), plays by itself 2.5 s after joining at volume 0.3, shuffled with no repeats; switch in Settings ("Background music", saved as `settings.bgm`) and the Radio app |
| "The coffee shop is not on the minimap; every place you can go must be on the map" | `GPS.places()`: all 55 shops (☕ cafés, 🏪 convenience stores, 🍜 restaurants), the landmarks, your home and allotment, on the minimap, the phone map, and the Places list with All / Food / Shops / Services filters |
| "Job search should start from the nearest area" | `DeliveryService`: orders come from the kitchen closest to the rider (restaurants, cafés, convenience stores, markets: 60 pick-up points); a declined one steps aside for the next closest. Rides pick the closest of 160 sampled doors |
| "Auto drive, for when it's far and I'm tired of pressing" | `client/AutoDrive.luau`: Q or the 🤖 button under the speedometer. Follows the GPS route in the left lane, keeps its distance from traffic, people and dogs, slows for corners, signals turns, stops at red (not for a left turn), creeps up to the door at the end, stops before a police checkpoint and hands over. Steering, pedals or handbrake take over at once |
| "Left turn always passes, why was I fined?" | `TrafficService`: entering on red is only marked; the fine comes when leaving the junction straight on, right or with a U-turn. A left turn shows "↰ ซ้ายผ่านตลอด ไม่โดนปรับ" |
| "Police checkpoints: drive into one and you pay, so you have to drive around them" | `PoliceService`: 12 checkpoints on main streets (cones, barriers, signs, tent with a flashing light bar, officers in khaki waving light batons); a motor vehicle through the gate pays ฿150 (bicycles free); 4 move every 5 minutes. 🚨 on the minimap and phone map, a warning 140 studs ahead |
| "A cutscene when fined or running a red light" | `client/Cutscene` `fineScene`: pulled over, an officer walks up (kerb side on a bike, the driver's window on a car) and holds out the ticket; the ticket card shows the charge, the fine and a "paid" stamp |
| "The green line disappeared" | `client/Guide.luau`: when the card says "follow the green line" and there is no GPS target any more (a waypoint clears itself 40 studs out), it is set again |
| "The bicycle is too slow, hard to start" | Bicycle top speed 27 -> 36, acceleration 10 -> 16, brake 26 -> 28 |

Test results (Studio play, `_Studio` data store):

| Area | Result |
|---|---|
| Ride job end to end: kerb wave, boarding scene, pillion welded on (17 welds), alighting wai, pay slip (fare 107, tip 34, 36 EXP, 5 stars) | PASS |
| Background music starts by itself after joining (GoDash Beat playing, loaded) | PASS (heard: NOT TESTED, the test is muted) |
| All 20 candidate tracks load (60 to 213 s) | PASS |
| Minimap shows the shops near the rider (8 🍜, 4 🏪, 1 ☕); phone map and Places list with filter chips, Thai names | PASS |
| First offers come from the 3 nearest kitchens (170 to 280 m), declining walks outwards | PASS |
| Auto drive: hub -> GoMart 24 (~480 studs), stops 8 studs from the door, G picks the order up | PASS |
| Auto drive stops 25 studs before a checkpoint and hands over; refuses to start right in front of one | PASS |
| Checkpoint gate fine ฿150 + cutscene + ticket card (screenshot checked) | PASS |
| Red light: left turn -> no fine, "ซ้ายผ่านตลอด" toast; straight on -> ฿100 fine | PASS |
| AI traffic within 400 studs: 6 cars, all moved within 25 s | PASS |
| KK Motors navigate button: route set, toast, phone closes | PASS |
| Client and server logs | no script errors |

NOT TESTED: the music heard out loud (tests run muted); touch layout of the new AUTO button on a real phone; the fine
cutscene on a car (tested on a motorbike); checkpoints moving after 5 minutes (code path only).

## 10. Vehicle sounds, crash cutscene, no corner falls (2026-11-17)

Owner: "realistic vehicle sounds when accelerating, braking or easing off", "realistic sound effects, and a
cutscene when you crash hard and fly off the vehicle, but take out the physics where you fall over in a corner".

| What | How |
|---|---|
| Engine model (`client/EngineSound.luau`) | revs and a gear from road speed and pedals. Geared bikes (4 or 6 gears) and cars (5 to 7-speed automatic) shift by themselves, revs drop at each change (a lever click on bikes, a short dip on cars). Scooters: CVT, revs jump up and hold. Profiles per vehicle style (idle and red-line revs, gear spread, pitch, grit) |
| Mix | three copies of one licensed loop: idle, on load (throttle open: louder, brighter, distortion on sport engines), off load (throttle shut: quieter, muffled, revs fall with speed = engine braking). Start-up blip, wind-down on getting off |
| Loops | bike "Go Kart Engine Constant 2", looped 8-22 s; car "1969 Chevrolet Chevelle 2", looped 1-13 s (the steady cruise; the rest of that take stops and switches off). Both regions measured with AudioAnalyzer (RMS and spectrum) |
| Other sounds | wind on bikes / tyre roar in cars by speed, brake squeal at the end of a hard stop, indicator tick-tock, car door on getting in and out, horn H (higher on bikes, a bell on the bicycle), bicycle pedals and freewheel ticks |
| Crash cutscene (`client/Cutscene` "crash") | Drive calls `Drive.onCrash` when one step loses more than 24 studs/s on two wheels or 38 in a car. White flash, slow motion, a copy of the rider flies on tumbling with arms flailing, bounces off walls, may bounce once on the ground, slides, lies with 💫; then the real rider stands where it came down, off the vehicle, dizzy for 3 s ("walk back and press F"). Vehicle damage as before (VehicleFall) |
| No corner falls | the cornering limit that knocked bikes down and rolled cars is gone from `client/Drive.luau`, with the fall torque |

Sounds added to `Config/Sounds.luau` (all ProSoundEffects, Roblox licence): roadCar, wind, brakeSqueal, carDoor, bell,
bikePedal, bodyHit, bodyFall, bodyFall2.

Test (Studio, muted):

| Check | Result |
|---|---|
| All 14 vehicle and crash sounds load | PASS |
| Moped, full throttle then coast then brake: idle 1,400 rpm, gears 1 to 4 with a rev drop at each shift, coasting revs fall with speed in 4th | PASS |
| Sedan (simulated): 5 gears, shifts at 4,000 to 5,200 rpm; scooter: CVT revs 5,200 to 7,500; sport bike: 6 gears to 11,000 rpm | PASS |
| Crash into a shophouse at speed: flash, flight, landing, stars; rider standing 6.7 studs from the bike, health 100, camera and HUD back | PASS (frames checked) |
| Hard swerve at 32 studs/s and 8 s full lock on open ground: stayed seated, no crash | PASS |

NOT TESTED: how it all sounds (tests run muted: the owner listens); cars in a real drive (no car in the test profile,
the car engine was run with simulated speeds); the crash scene from a car.

## 11. Thai street life and satire, faster vehicles, smaller HUD (2026-11-17)

Owner: "ideas that reflect Thai society, satire, funny", then "build all of them"; "every vehicle faster"; "UI that
is too big covers the screen". Satire guardrails: no royals, religion, real politicians, real people or real brands;
no gambling. All names are made up.

| Feature | Where |
|---|---|
| City Feed: a social-media phone app with posts and comments about the city and about you (crashes, fines, reviews, floods...) | `client/Feed.luau`, `Config/Feed.luau` |
| Order twists (45 % of jobs): wrong pin, late, customer not answering, add-on order, influencer passenger; choices with keys 1-3 | `server/Services/TwistService.luau`, `client/Choice.luau` |
| Street: potholes, floods in the rain (small bikes may stall), a live-streamer who wants a honk, a wrong-way rider, the mor lam party truck | `client/StreetLife.luau` |
| Roadworks, made-up election posters, motorbike-taxi stands (join by bringing the boss an iced coffee; outsiders lose part of the tip), municipal officers fining ฿100 for riding on the pavement, Songkran every 25-40 min for 5 min (+30 % fares) | `server/Services/StreetService.luau` |
| Instalments at KK Motors: 10 payments with a 35 % fee, missed payments bring calls and then the repo crew (a chase if you ride it, towed if parked) | `server/Services/FinanceService.luau`, `client/Finance.luau` |
| Driving licence test at the transport office (plank, slalom, box); riding without one costs ฿300 at a checkpoint | `server/Services/LicenseService.luau`, `client/License.luau` |
| The neighbour's nosy questions at home (5 questions, 3 answers) | `client/StreetLife.luau`, Social remote |
| Every vehicle faster: top speed x1.3, acceleration x1.35, brakes x1.15, grip x1.08; auto drive cruise 75 | `Config/Vehicles.luau`, `client/AutoDrive.luau` |
| HUD: layout base height 800 (compact 570), so everything is about 10 % smaller; the guide card slims to one line (62 px) while riding faster than 10 studs/s; at most 3 toasts, 3 s each | `client/UI/Core/Layout.luau`, `client/Guide.luau`, `client/Feedback.luau` |

Test (Studio, muted): every service starts without errors; party truck front and back; City Feed posts; twist
"no answer" played twice; instalment purchase, payment, level lock and refused-away-from-dealer; repo chase banner;
taxi-stand join on foot; bike licence (plank, slalom, box) passed with the card; neighbour question answered; pavement
fine ฿100 next to an officer; HUD smaller; guide card 59 px while riding (88 px standing); crash cutscene: PASS.
NOT TESTED: floods and stalling, pothole bump, Songkran soaking, streamer honk, the car licence, a real missed-payment
repo, how the new sounds and music sound.

## 12. Nothing walks through things, natural eating and pick-up, more walkers, brighter colours (2026-11-17)

Owner: "fix walking through assets, nothing may pass through, so it feels real"; "the eating and pick-up moves are
buggy, not real"; "too few people on the streets, and they run: I want them to walk normally"; "the colours look too
gloomy, I want it brighter".

| What | How |
|---|---|
| Solid city (`server/World/Solid.luau`) | street dressing drawn as decor (posts, poles, stall legs, counters, benches, fences, posters, roadworks) that stands in a walker's way gets its collision back (CanQuery stays off, so the camera and wheel rays ignore it). Mesh props (chairs, pot plants, hedges, parked bikes) and posed people get one invisible box. Runs on every chunk the Streamer finishes (spread at about 1.5 ms per frame) and on the places, street life and checkpoints at start; about 10,000 parts and 830 boxes around the hub |
| Driving unchanged | everything made solid is in the collision group "Props", which does not collide with "Vehicles"; vehicles and their riders are put in "Vehicles" (riders while seated). Riding into a chair still knocks it over. Banana trees got a trunk collider |
| Eating | the rider sits on a red plastic stool at a little steel table with a bowl of noodles and spoons it up at a human pace (scoop, lift, chew, down); turns three-quarters to a camera spot that has a clear view, so the face is in shot |
| Drinking | the cup tilts to the mouth while the head goes back, then comes down |
| Pick-up | the bag waits on a counter; one hand reaches, takes it, brings it to the side; a small nod |
| Delivery | one hand holds the bag out; when it is taken, a wai with a bow |
| Walkers (`client/Peds.luau`) | 60 on computers, 30 on phones (was 34 / 18) in a 60-300 stud ring (was 70-380). The walk is Roblox's current R15 walk played at the pace they really move (speed / (6.4 x height scale)); the old walk was sped up so the legs went about twice as fast as the body, which read as running. Cutscene walks use the same rule |
| Colours (`client/Env.luau`) | clear, slightly blue air instead of brown haze, saturation +0.14 by day, more exposure and brighter shadows, fewer clouds when sunny. Bloom only on real lights, nights unchanged in spirit (lamp-lit, readable) |

Test (Studio, muted):

| Check | Result |
|---|---|
| Walk into a pot plant: stops at its edge and slides round; parked scooter and lamp post block | PASS |
| Interaction prompts: none blocked (3 win-stand bosses have their prompt inside their own body; reachable from beside them) | PASS |
| Riding: rider group Vehicles while seated, Default after getting off | PASS |
| Eating, drinking, pick-up and delivery scenes | PASS (frames checked) |
| Walkers: walk animation playing at 0.44 x for 3.9 studs/s, natural stride | PASS (frames checked) |
| Solid pass on the busiest chunk: 11 ms in one go before spreading (was 46 ms in the first version) | PASS |

NOT TESTED: a long drive through new districts watching for hitches; phones (walker count and frame rate); the colours
at night and in rain on a real screen.

## 13. Growth plan (2026-11-17, owner: "do all of it for me")

Owner asked what would draw more players, then "ทำทั้งหมดให้ผมเลย". Already in the game before this: three daily
missions, a 7-day login reward (only in the phone), paint and upgrades. Order of work (tick as done):

| # | Item | State |
|---|---|---|
| A | Analytics (`server/Services/MetricsService.luau`): onboarding funnel for new riders (joined, got on a vehicle, went online, accepted, picked up, 1st/2nd/3rd job) and an economy event for every cash change ("Baht", source/sink, reason as SKU) | done, runs without errors; numbers appear in Creator Dashboard only after a publish |
| B | Daily reward card pops up once per session when waiting (`client/Board.luau`); weekly Top Riders (`server/Services/LeaderboardService.luau`): money, jobs, five stars, OrderedDataStore per board and week (Monday 00:00 Thai time), phone app "Top Riders" and a big board at the hub | done: card shown and claimed (+฿450 and 2 milk teas), board drawn, "board" op answers; NOT TESTED: a job landing on the board |
| C | Styling (`client/Styling.luau`, `VehicleFactory.style`, Garage op "style"): 8 underglow colours ฿1,500, own plate ฿800 (Thai/A-Z/digits, max 8, Roblox text filter, refused when filtered), 8 stickers ฿500, 5 horns ฿300; everyone gets a standard plate (traffic too) | done: all four fitted on the moped and seen on screen; a plate with "<>" refused |
| D | Ride along (`VehicleService` "RideAlong" prompt, Seat "PaxSeat"): other players press F on your vehicle; owner setting friends / anyone / nobody (Phone > Settings); not while a ride job's passenger is on; pillion pose in `client/Rider.luau`; ride jobs refuse when a friend fills the seat | built; checked only from the owner's side (prompt hidden for the owner, "Drive" only for the owner). NOT TESTED with a second player |
| E | Photo mode (`client/PhotoMode.luau`): P or the phone app; HUD and Roblox UI hidden, right-drag / buttons / wheel camera, 3 lenses, background blur, 6 filters, 4 poses, hide panel (H) | done: opens, vivid filter and wave pose work, P closes and restores everything |
| F | Phones | NOT TESTED: the MCP tools can't switch Studio's device emulator; check on a phone after publishing |
| G | Store page art and text: icon + 4 thumbnails (Kanit font, rider in a plain green GoDash shirt so no real brand shows), Thai + English description, title options, upload steps | done: in the owner's local promo folder `GoDash_หน้าร้าน_2026-11-17` (not in this repo; owner uploads: not in Open Cloud) |
| H | Marketing: 7-day TikTok/Reels plan with captions and hashtags for the existing vertical clips, list of new clips to record, ads advice | done, same folder; ads left to the owner (money) |

## 14. Tier-A plan (2026-11-17, owner: "do everything you recommended")

| # | Item | State |
|---|---|---|
| 1 | Robux (`StoreService`, `client/ShopApp`, Config/Store): passes VIP 2094188568 (299 R$: gold tag, VIP glow, gold plate frame, daily +20 %) and Neon Pro 2094392559 (149 R$: rainbow pulsing glow); products ฿5,000 3732707923 (49), ฿20,000 3732708044 (149), ฿60,000 3732708061 (399), Season premium 3732708078 (249); private servers 30 R$; receipts kept in d.receipts and the profile is saved before "granted" | done: all created on Roblox with Open Cloud; Shop app shows live prices; passes read (the creator owns them automatically). NOT TESTED: a real Robux purchase (Studio test purchases need the prompt clicked) |
| 2 | Codes SAWASDEE / GODASH / KHONKAEN / RIDER2026 (Shop app), group bonus (Store.GROUP_ID, +10 % daily), badges | codes done and tested (once per rider, unknown refused). Badges: the owner made the five on the dashboard (the Assistant key has no badge-creation scope even with every permission on); ids in StoreService Store.BADGES, all five read back enabled with BadgeService. Group: no group yet |
| 3 | Season pass (`SeasonService`, `client/SeasonApp`, Config/Season): season 1 from 2026-11-17, 50 tiers × 100 XP, XP from jobs 20 / five stars 10 / daily 25 / missions 30 / Rush Hour 15; exclusive glows, stickers, titles | done: XP counted from a real job (30), app shows tier, bar, rewards and locks |
| 4 | Ranks (Config/Store.RANKS, 7 ranks, tip bonus up to +12 %) with a name tag over the head (rank or season title, ⭐ VIP); rider company (`CompanyService`, `client/CompanyApp`) from the Rider rank: hire, better bikes, collect, half rate while away (3 h cap) | done: tag seen; company locked below the rank as designed. NOT TESTED: hiring (needs 30 jobs) |
| 5 | Rush Hour (`EventService`): every hour on the hour for 10 min in every server, pay +50 %, race, top 3 prizes ฿3,000/2,000/1,000 + season XP; chip with countdown (`client/LiveOps`) | done: QaRush started one, chip and offer bonus shown. NOT TESTED: the prize hand-out at the end with several riders |
| 6 | Phones | not testable with the MCP tools |
| 7 | Exhaust choice in Styling (stock / racing / quiet, ฿800) | done (sound not heard: tests muted). Tuk-tuk and new vehicle models: not done |
| 8 | "What's new" card once per Config/News.VERSION (skipped for brand-new riders); the Roblox player list hides while the phone is open | done: card shown and closed |

Fixed on the way: the Shop app first used the id "shop", which replaced the screen of the shops in town (buying food would have broken); now "store".

Store page uploaded with Open Cloud the same day (owner: "upload it, I'll only publish"): icon assets/71294166197784,
thumbnails 129928097741425 (ride), 88721529564534 (styling), 134806724985127 (eating), 118277502747835 (rewards, was
still in review), then the old one 110019363062518 kept last. Before: icon assets/92133389947584, previews
[110019363062518]. New Thai + English description on the root place. A new name ("GoDash: ไรเดอร์ขอนแก่น ...") was
refused by Roblox's text moderation, so the name stays "ชีวิตคนขับรถ GoDash ในประเทศไทย".

## 15. Realism pass + life systems (2026-11-18, owner: "as realistic as possible", then many additions)

Saved as place versions 95 and 97 (not published). Tests were Studio play tests with sound muted.

| Item | Where | State |
|---|---|---|
| Chase camera: spring follow, look-ahead, speed distance, bump spring, bike lean, collision, right-drag / stick orbit, wheel zoom | `client/ChaseCam` | PASS (seen while riding) |
| Drive effects: skid marks, tyre smoke and rain spray, exhaust, headlight beams, speed streaks | `client/DriveFx` | PASS for skid marks, spray in rain, exhaust; streaks and beams NOT SEEN (test bike too slow / daytime) |
| On foot: walk ramp, Shift / L3 / touch "วิ่ง" sprint with stamina, footsteps by floor, landing dip; the server sets `BaseWalk` | `client/OnFoot`, LifestyleService | PASS (16 -> 25.6 studs/s); footsteps NOT HEARD (muted) |
| Mount: walk to the seat side before sitting; get off on the seat side | VehicleService, `client/Drive` | PASS |
| Accident claims: hitting a pedestrian or another vehicle -> the person or the other driver walks up, orange "ใบเรียกค่าเสียหาย", angry line, City Feed; also on foot when a crash threw you off. Amounts sized to income (first build was too harsh): pedestrian 120 + 5/stud/s up to ฿450, vehicle 80 + 5 up to ฿600, never more than 25 % of cash | `client/Accident`, `AccidentService`, Cutscene fineScene | PASS (pedestrian ฿850 / car ฿2,160 at the old rates; scene screenshot); new rates NOT TESTED in a hit |
| NPC helmets (a ball on the head) removed (owner: "if it can't be done well, take it off") | `shared/RiderPose` HELMETS = false | done |
| Pedestrians step aside: look 4.5 studs ahead with a body-sized sphere, veer to the open side (shop side first), keep left for people coming the other way, boxed in -> wait, then turn back | `client/Peds` steer() | PASS (3/3 walkers kept 2.2-2.9 studs from a test post) |
| Speed bumps (ลูกระนาด): yellow-black, gaps at the kerbs, on sois and lanes, built around you; front axle lifts the vehicle, back axle drops the nose; bikes fall at speed (crash scene "ลูกระนาด! ซิ่งมาเต็มสปีด ปลิวข้ามแฮนด์") | `client/SpeedBumps`, Cutscene crash caption | PASS: 28 km/h bounce 0.5, 44 km/h lift 1.3 / 5°, 74 km/h fall + scene. Note: stacked Studio test bumps multiply the kick (test-only) |
| The "what to do now" card moved from the top middle to under the money panel and made smaller (owner: it hid the traffic lights) | `client/Guide`, HUD.topLeft | PASS |
| Injuries: falls add 8-35 (bike) or 3-15 (car); limp from 25, no running from 50, from 60 the card suggests the hospital, from 80 no new orders ("พักงาน: บาดเจ็บ") until treated; small knocks heal slowly | `HealthService`, `client/OnFoot`, Guide, JobService | PASS (card + route to Khon Kaen Hospital at 86) |
| Hospital: gold card ฿30 + medicine (about ฿180-220 at 70-86); scene: queue ticket A-xxx counting down, nurse in white, cleaning and bandaging, receipt; bandages stay 150 s | ShopService "heal", Cutscene treatScene | PASS (screenshots); receipt card NOT SEEN (scene ended during a slow tool call) |
| Down payment 0 / 25 / 50 % (fee 35 / 20 / 10 %), credit score 300-850, KK Bank personal loan (6 or 10 instalments, auto-debit cash then savings, late fee ฿50, 30 % of job pay while in arrears) | `Config/Credit`, FinanceService, EconomyService, `client/Finance` | PASS: ฿5,000 loan approved, instalment ฿904 auto-debited, score 650 -> 653. NOT TESTED: a missed instalment, a down-payment purchase |
| Customer reviews: the last 30 with stars, the customer's words from what happened (late, bumpy, crash, red light, hot food...), what to improve from the last 15 | JobService (d.reviews), `client/Reviews` | PASS (a real delivery: ★5.0 "ส่งไวทันใจ ... อาหารยังร้อนอยู่เลย", tip ฿87) |

Game name (2026-11-18, owner: "Thai and English, easy for search"): the root place is now
"GoDash 🛵 Thai Food Delivery & Driving Simulator". Roblox auto-translates it for Thai players; the Thai name
"GoDash 🛵 ไรเดอร์ส่งอาหาร ขับรถในเมืองไทย" must be typed in by the owner (Creator Dashboard -> the experience ->
Localization -> Thai -> Experience name): the game-internationalization API is not reachable with the Assistant's key.

Map (owner: "I'm from Khon Kaen and the layout isn't familiar"): the play area is lat 16.4062-16.4406, lon
102.8188-102.8418 (Bueng Kaen Nakhon in the south-east, Mittraphap in the west, Pracha Samoson in the north). 66 % of
the road length is lanes invented by `tools/plan_streets.py`; only 34 % is real OpenStreetMap. Picture:
`docs/map_khonkaen_real_vs_lanes.png`. Next batch: fewer invented lanes, real landmarks and government places.

New Studio hooks: `QaPedAhead = studs` (client: a walker stands in front of your vehicle), `QaBumpAhead = studs`
(client: a speed bump in front of you), `QaInjury = n` (server), `QaBankDue = true` (server: the bank instalment is due).

## 16. The real street plan: the whole of Tambon Nai Mueang (2026-11-18, owner: "ทำผังเมืองจริงเลย เอาเขตตำบลในเมืองทั้งหมดก่อน")

Saved as place version 99 (not published).

- Data: `node tools/osm_fetch.mjs` -> `data/osm_tambon.json` (OSM, 6.3 MB): the tambon boundary (relation 21404983,
  46 km², 8.1 x 9.3 km), every public road plus the plain `highway=service` alleys (driveways, car-park aisles and
  private ones left out), water (incl. multipolygon lakes such as Bueng Thung Sang), parks, rail, land use and places.
  The old 2.5 x 3.8 km data is in `backups/map_v1_2026-11-18/` (git-ignored).
- `tools/osm_to_map.py`: the play area is the tambon outline + 60 m (bounds 29.3k x 33.6k studs, same origin, so
  every site, plot and saved position is unchanged); alleys are road type 5; an alley through a frozen plot is
  dropped; Features.luau now also has `landuse` polygons (campus / green / military / industrial / commercial /
  residential), the `boundary`, and real names for public places only (government, police, public hospitals, schools,
  universities, municipal markets, stations, museums, the city gate). Shops, malls, private hospitals keep our names.
- `tools/plan_streets.py`: CELL 8; invented lanes only in core and urban blocks with much wider spacing, none in
  suburbs, fields or campus land; unplaced "auto" sites are kept in sites.json (they used to vanish); an auto site may
  set `maxClass: 4` to sit on a soi. Result: 668.5 km of OSM roads (137 km alleys) + ~105 km invented (was 117 km
  real + 224 km invented).
- Moved to their real places: Khon Kaen Hospital (โรงพยาบาลศูนย์ขอนแก่น, Si Chan east), Khon Kaen University (inside the
  real campus, real name), the municipal fresh market 1. Plots, the hub, farm, gas stations stay where they were (all
  of them already faced real OSM streets).
- Game: `Map.landUse` reads the OSM polygons first (`Map.landUseRaw`); zones = KKU, government centre, Bueng Thung
  Sang, northern outskirts, Mittraphap, Non Than, Bueng Kaen Nakhon, city centre, south; 70 restaurants / 28 shops /
  16 cafés requested (57 restaurants fit their spacing). Block insides: town = small houses on a footpath (plus a
  half-size pass for the gaps), campus = lawn, trees, Thai school blocks, a few pitches, fields = farmland.
  Ground tiles 1000 studs.
- Measured in Studio: server ready 16.0 s (was 10-13), 66,992 addresses (was 24,357), 75,103 lots, 6,651 chunks.
  Screenshots: city centre, Khon Kaen Wittayayon school grounds, a residential block, the KKU campus.
- NOT TESTED: phones (more memory: the road graph is 11k nodes / 14k edges), the phone city map with the bigger
  network, deliveries far out (KKU, Bueng Thung Sang). Server AI traffic, dogs, checkpoints still stay within
  Game.TRAFFIC_RADIUS of the centre.
- Next: landmark buildings with real names (Province Hall, district office, municipality, police, Srinagarind
  hospital, railway station, bus terminals, museums, city gate, markets, schools, temples as backdrop only).

### 16b. Landmarks with real names (2026-11-18, after the owner published v99: "publish this batch, then carry on")

Saved as place version 101 (not published). 20 public places added to `Map.pois` + `data/sites.json` (auto-placed by
the planner beside the street nearest their real OSM position, `maxClass: 4`):
government (`Places.government`, Thai two-tier roof, portico, flag, name wall): ศาลากลางจังหวัดขอนแก่น, ที่ว่าการอำเภอเมือง,
สำนักงานเทศบาลนครขอนแก่น, สำนักงานขนส่งจังหวัด, ตำรวจภูธรภาค 4; โรงพยาบาลศรีนครินทร์ (second hospital: treatment works at
both, the scene shows the right name); สถานีขนส่งแห่งที่ 2; พิพิธภัณฑสถานแห่งชาติขอนแก่น and โฮงมูนมังเมืองขอนแก่น
(`Places.museum`); ประตูเมืองขอนแก่น (`Places.citygate`); สนามกีฬากลางจังหวัด (`Places.stadium`, track, stands,
floodlights); ถนนคนเดินขอนแก่น (night-market style); schools and colleges (`Places.school`: teaching block, flag in the
yard, name arch): ขอนแก่นวิทยายน, แก่นนครวิทยาลัย, กัลยาณวัตร, อนุบาลขอนแก่น, เทศบาลวัดกลาง, วิทยาลัยเทคนิค,
วิทยาลัยอาชีวศึกษา, ราชมงคลอีสาน. Signs of the old hospital / university / bus terminal now use poi.thai / poi.name.
Map icons: 🏛 🏺 🚩 🏟 🏫. All 16 checked models built; screenshots of the Provincial Hall, Anuban school and the city gate.
NOT TESTED: the stadium, museums and walking street by eye; the phone place list with the new kinds (they fall under
"Services").

### 16c. Everything across the whole tambon (2026-11-18, owner: "ทำต่อให้จบ … เอาให้ครบ")

Saved in Team Create (scripts committed; save_place reported no unsaved changes). Not published.
- `Game.TRAFFIC_RADIUS = math.huge`: route traffic, soi dogs, checkpoints, roadworks and posters use the whole tambon.
  Measured: 69 route vehicles (55 beyond the old 730 m radius), 140 soi dogs (137 beyond), 24 checkpoints (21 beyond),
  20 roadworks, 48 posters, 312 signalled junctions. Local traffic and walkers already follow each player.
- Motorbike-taxi stands: 10 (fresh market, night market, station, KKU, both bus terminals, both hospitals, mall, walking
  street); the fresh-market stand had never appeared because the list asked for the id "market". Municipal officers: 6.
- "Hero" street detail (parked vehicles, kerb props, grates, patches, road-name signs, pavement life in front of shops)
  is now everywhere on core and urban land, not only within 1,200 studs of the old downtown.
- City gate v2: Thai-style gateway (cream pillars on brick plinths, stepped pinnacles with lotus-bud finials, two-tier
  tiled roof over the name beam, lamps).
- Checked by eye: city gate v2, provincial stadium, national museum (with street-name sign and walkers beyond the old
  radius). GetWorld now lists government 5, school 8, museum 2, hospital 2, bus 2, citygate, stadium (phone map/list).
  Client 59 fps in Studio, memory ~3.4 GB (Studio's own figure, includes the editor).
- Orders far out: online inside the KKU campus, an offer came in 3 s (restaurant 720 m away, drop-off 1.0 km).
- NOT TESTED: phones; driving a whole far-out delivery to the end (done in §17).

## 17. Smooth on phones, the far city, a living Khon Kaen (2026-11-18, owner: "ทำได้เลยที่แนะนำ"; then, mid-batch: "on the phone the road UI / the drop-off pin covers the road, and the vehicle is very hard to control")

Saved as place version 108 (Team Create). Not published.

| # | What | Where | Result |
|---|---|---|---|
| 1 | Graphics tiers low / medium / high (Phone > Settings > Graphics: Auto / Low / Medium / High, saved as `settings.quality`); auto: phones start at medium, any device steps down after ~10 s under 24 fps and up after ~30 s over 50 fps. The tier sets backdrop range, how far route cars are drawn, walkers, local traffic and driving particles. `StreamOutBehavior = Opportunistic` (clients let go of streamed streets behind them) | `client/Perf`, Phone settings, Main `Settings "quality"`, Street, Peds, DriveFx | PASS in Studio: QaTier 1 -> 202 backdrop parts, tier 3 -> 3,497 (then high trimmed to 2,300 studs). NOT TESTED on a real phone |
| 2 | A whole far-out delivery to the end | (test) | PASS: KKU campus, VIP order, auto drive 2.6k studs to the shop, pick-up, 4.1k studs to the customer, paid ฿264 (late −20 %), 2.2★. Found and fixed: auto drive did not slow for speed bumps (rider came off at 59 km/h); a vehicle stopped on a bump could not drive off (suspension rays caught on the curve: 0.4 studs in 2.5 s at 60 % throttle); someone walking down a narrow lane held auto drive up |
| 3 | The far city: the server sums every lot into a 128-stud skyline grid (56 KB string); each client draws plain blocks (lit window strips at night) and tree clumps from 760 studs out to the tier's range, plus ground to the horizon | `server/World/Skyline`, `client/Backdrop`, `GetSkyline` | PASS: A/B screenshots, the horizon shows town instead of haze/void |
| 4 | Real roundabouts from OSM (20 rings; islands where the graph has the ring: red-white kerb, lawn, flowers; a fountain and palms on big ones, a golden-shower tree on mid ones; an octagon reserved so nothing is built inside), zebra crossings at every signalled approach and in front of 11 schools / hospitals / KKU (give-way lines, yellow-white kerbs, blue crossing signs both ways, "เขตโรงเรียน ขับช้าๆ"), a stop line at every soi mouth. People cross at the school / hospital crossings when there is a gap; drive over one with someone on it: police ticket ฿100 ("ไม่หยุดให้คนข้ามทางม้าลาย") | `tools/osm_roundabouts.py` -> `KhonKaenData/Roundabouts.luau`, `server/World/RoadMarks`, Builder, `client/Peds`, `TrafficService "ZebraRun"`, Cutscene | PASS: Anuban school crossing by eye, 2-4 people waiting / crossing in the school run; fine + ticket scene fired. Roundabout at -1873,-1639 by eye (a building stood on the island: fixed with the octagon reservation, not re-shot) |
| 5 | Lake promenades on every big lake (red jogging path where the land is free, benches facing the water, shade trees), name signs on the named lakes; Bueng Kaen Nakhon and Bueng Thung Sang also get 6 evening food stalls, an outdoor gym and a pier with swan pedal boats. Joggers (people in sports kit) run the paths 5:18-8:12 and 16:18-19:42. The rim no longer draws a line across the water where a lake is mapped in pieces | `server/World/Lakeside`, `client/Peds` | PASS: signs at all 4 named lakes; stalls, gym, pier at both big ones; a jogger and the stalls at Kaen Nakhon at 17:00, 2 runners playing the run animation, pier + boats by eye. Sign flowers moved off the text (not re-shot) |
| 6 | Farmland: paddies get bunds on every side and a cross bund, 42 % have a sugar palm (ต้นตาล, part-built, fans edge-on) on a bund; other fields sometimes a dirt track; the ragged gaps between fields become small paddies, dirt yards with a track, sugar-palm clumps or grazing | Blocks.field, Scenery.sugarPalm, Builder STEP2 pass (rural) | PASS by eye (rural west); the first palm crown looked like stacked plates, reshaped (not re-shot) |
| 7 | Places sound like themselves: fresh market at dawn and afternoon, night market and walking street in the evening, school yard at bell / lunch / home time (bell at 8:00 and 15:30), university, mall, stadium in the evening, lake water and frogs by the lakes, crickets, frogs and roosters in the suburbs / countryside. ProSoundEffects ids (Roblox licence) in Config/Sounds | `client/Ambience` | PASS: emitter created and playing at the fresh market at 6:00, all ids load. NOT TESTED by ear (tests are muted) |
| 8 | People follow the hour: how many are out (busy at breakfast, lunch, after school; quiet at night), most gather where something is on at that hour (school gates, market, offices, hospitals, night market, mall), one in six in school uniform (only near schools / KKU in the day), one in six in sports kit (the joggers) | `client/Peds` | PASS (counts and roles in Studio) |
| 9 | Orders follow the hour: kitchens keep opening hours (late at night only GoMart 24, the night market and rest stops cook), lunch 11-13 and dinner 17:30-19:30 pay +15 %. Landmark jobs with their own hours: Urgent Documents (government offices -> Provincial Hall / police), Hospital Lunch Boxes, School Lunch Run, Match Day Snacks, Late-night Study Snacks (KKU dorms); rides: Student to the Bus Terminal, Hospital Appointment, Catch the Train, Museum Visit. The hospital is picked first, then a kitchen near it (max ~7k studs) | `server/Services/CivicJobs`, Config/Jobs, DeliveryService, PassengerService, JobService, OfferCard (bonus line translated part by part), Phone job list shows hours | PASS: offers "Urgent Documents: City Municipality -> Provincial Hall ฿375" and "Hospital Lunch Boxes -> Khon Kaen Hospital" with the lunch bonus |
| 10 | Phone feedback mid-batch: one analogue steering pad (slide: how far = how hard; centres on release) instead of ◀ ▶ full-lock buttons; Roblox's own thumbstick / jump hidden while driving; the drop-off pin's card smaller on touch, see-through, and only shown within 260 studs (520 on PC); world speech bubbles smaller on touch | `UI/HUD/TouchControls`, GPS beacon, Feedback.bubble | Built; NOT TESTED on a phone (the MCP tools cannot switch Studio's device emulator) |
| 11 | Speed bumps are not solid any more (their kick is scripted, LIFT_LOSS 1.0): checked 1.31 studs of lift at 40 km/h, rider stays on. Auto drive eases to 20 km/h for bumps on its route, and gives a polite toot so people step aside (`Peds.makeWay`; the rider's horn H does the same) | SpeedBumps, AutoDrive, Peds | PASS |

Server ready 16.5-18.8 s (world planned 12.6-14.3 s), 71k infill cells with the rural pass.

## 18. Fines with a daily limit, faster motorbikes, readable lights (2026-11-19, owner while playing: "โดนปรับเงินถี่เกิน ขับไม่คุ้ม", "มันต้องมี limit การปรับต่อวัน", "ปรับมอไซให้ไวกว่าเดิม เพราะจักรยานไวแล้ว", "ไฟแดงยังมั่วๆ อยู่ มันเป็นห้าแยก สับสน ควรจะมีสีหรือเตือน ... ชัดเจนกว่านี้")

| # | What | Where | Result |
|---|---|---|---|
| 1 | Daily limit on money taken for offences. Tickets (red light, zebra, pavement, police checkpoint): at most 2 per in-game day (16 real minutes) and at least 3 minutes apart. Accident bills: at most 2 per in-game day, 90 s apart. Both together: at most ฿600 per real day (Thai time, `daily.fines` in the profile). Past a limit: a warning toast only ("ตักเตือนครั้งนี้ (วันนี้โดนใบสั่งครบ 2 ใบแล้ว)", "คู่กรณีไม่เอาเรื่อง"), no money, no pulled-over scene. The trip's safety still counts the offence (`tele.red`: stars and tips). Ticket toasts and the ticket card say "ใบสั่งวันนี้ 1/2" | `server/Services/FineService` (new), TrafficService, StreetService, PoliceService, AccidentService, client Accident + Cutscene.ticketCard | PASS in Studio (QaFineGap 4): checkpoint 1 -> ฿150 "1/2", checkpoint 2 -> ฿150 "2/2", checkpoint 3 -> warning only, no money taken; `daily.fines` 150 -> 300 |
| 2 | Red light: 1.5 s of grace after the light turns red (that was a yellow you were committed to). Auto drive now goes on only if it reaches the junction before red (it used to go on any yellow it could not stop for and got the rider a ticket). Zebra fine only for someone near your path, not a person still on the far side of a wide road | Traffic.timing (new), TrafficService, AutoDrive, Peds.checkZebra | Built; the grace and auto drive change not separately play-tested |
| 3 | Motorbikes quicker, the small ones most (the bicycle stays 47 km/h): Rusty Dream 60->74 km/h, accel 16->27; Sabai 81->95 / 23->32; Zoomer 94->108 / 27->36; Raptor 127->142 / 40->49; Titan 166->182 / 54->62 | Config/Vehicles | Numbers only; job anti-cheat scales with topSpeed |
| 4 | "Your light": driving toward a signalled junction on one of its main roads, a panel at the top centre shows the light for YOUR road (3 lamps, the seconds left like a Thai countdown light, "ไฟแดง หยุดรอ" / "ไฟเขียว ไปได้" / "ไฟเหลือง ชะลอ", "⬅️ เลี้ยวซ้ายผ่านตลอดได้" on red, distance to the junction); your lane's stop line glows in that colour; a "▲ ไฟของคุณ" tag sits under your signal head; coming at a red too fast to stop calmly flashes the panel and beeps once. Sois have no light, so no panel there. Signal heads are bigger (black backboard with a yellow rim, 1.55 lamps, hoods) | `client/SignalAssist` (new), Scenery.trafficLight | PASS in Studio by eye: red 11 s panel, then green 9 s with the green lane glow at the stop line; bigger heads readable from 60 studs. The flash/beep path and the tag under the head NOT re-shot (RAM) |

Test hook: `QaFineGap = seconds` (Workspace attribute, Studio only) replaces the 3-minute / 90-second gap.

## 19. Fun + TikTok + 250 players plan (2026-11-18, owner: "ทำทั้งหมดที่เสนอมาได้เลย")

Goals (owner): the game is genuinely fun; plenty to play and post on TikTok to build hype; 250 highly engaged players
(Roblox's bar for under-16), then all ages. Loy Krathong is **Tue 24 Nov 2026**, so batch 1 aims to be ready ~21-22 Nov.

**Batch 1 (for Loy Krathong)**

| # | What | State |
|---|---|---|
| 1 | Controls: steering limited by sideways grip (`Drive.maxSteer`, 1.7 g × grip; was ~3 g at 40 km/h, ~6 g at top speed), keys ramp in (slower at speed) and centre fast, chase camera 15 studs back / 7 up and looking further ahead (Phone > Settings: Near/Normal/Far), phone: steer anywhere on the lower-left (floating pad), "auto gas" (tap GAS to cruise, BRAKE stops), lane assist `client/LaneAssist` (on for touch by default) | PASS: at 42 km/h full lock for 1 s turned 52° (was ~170°/s); camera measured 15.0 back / 7.0 up. NOT TESTED: phones (floating pad, auto gas), lane assist on a long drive |
| 2 | Traffic lights rebuilt (`shared/Traffic`): only junctions with a real OSM signal (`tools/osm_signals.py` -> `KhonKaenData/Signals.luau`, 86 points) -> 30 junctions (was 312 lit nodes); nodes of one junction merged into one controller; lights only on roads coming in (the exit carriageway of a divided road is dropped: keep-left rule); 3 phases at 5-way junctions (8 of 30); new head: pole on the left kerb, arm over the inbound lanes, flat lamps with hoods and a closed black back, a small pole head, LED countdown (`Count` SurfaceGui, client/Street); stop line across the inbound lanes only; red-light fine decided per junction (TrafficService); AutoDrive / Street / SignalAssist skip roads with no light | PASS in Studio: 30 junctions, heads read well at 21 m, countdown "5", panel "ไฟของคุณ 4 ไฟแดง หยุดรอ", AI car waited at red. Map note: `osm_to_map.py` keeps the one-way flag but not its direction |
| 3 | Store page: name EN "GoDash 🛵 Thai Rider Life" (Open Cloud), Thai-only description (no flag emoji), new icon (97841633896740) + previews loy 105822105345048, ride 78906189388680, styling 76079295322715, night radio 135989347837853, old rewards 118277502747835. New images must be granted open use first (`PATCH /asset-permissions-api/v1/assets/permissions`, subjectType All, action Use) or the icon/preview PATCH fails "must be open use" | done 2026-11-18. Owner: type the Thai name "GoDash 🛵 ไรเดอร์เมืองไทย" in Localization. Art in the owner's promo folder `GoDash_หน้าร้าน_2026-11-18` |
| 4 | Loy Krathong (`Config/Festival`, `server/FestivalService`, `client/Festival`): 20-30 Nov (QaFestival in Studio); lantern posts and bulb strings along ~700 studs of promenade each way from the pier, arch "ลอยกระทง บึงแก่นนคร", krathong stall, prompt at the pier end -> preset wish card -> krathong (first each day free + season XP + happiness, then ฿20) floats out along lanes that stay over water (the lake is several water parts: a test krathong once landed on the bank), clients drift them; quiet krathongs keep the lake lit; fireworks over the water every 150 s for 30 s at night (`FestivalSky`); chip only on foot | PASS: free first krathong, 15 s cooldown, krathongs drift over water, lantern line and arch seen at night, 4 fireworks bursts spawned. NOT TESTED: a fireworks screenshot (Studio stopped drawing, see below) |
| 5 | Invite friends (`client/Invite` phone app, `server/ReferralService`): Roblox invite card; a NEW friend (first join < 15 min, no job yet) joining through it gets ฿500, the inviter ฿1,000 (max 5 a day; offline inviters paid on next join from a DataStore queue) | built; NOT TESTED (needs two accounts) |
| 6 | Event alerts: Roblox opt-in card once after the 3rd job or a krathong (`alerts_asked`), and a button in the Invite app | built; NOT TESTED; sending needs the owner's notification template |
| 7 | Ghosts (`server/GhostService`, `client/Ghosts`): late (21:00-04:30) food deliveries to suburb/rural addresses may play the ghost-customer scene (money turns into leaves, she is gone, a short fright; +฿60); a figure under a big tree on dark roads (engine dies, she vanishes; +฿30); then "call the Haunted Night Radio 13.13?" -> on-air chat with DJ Pong built from the street name, a feeling choice, +฿100 + XP, City Feed post. Once per in-game night, 6 min apart. Phone > Settings turns ghost scenes off. Figure: `GoDashModels.GhostLady` (free Creator Store model, docs/ASSETS 5b) | PASS: roadside scene 6.4 s, +฿30, radio card with "แถวถนนรื่นจิตร", +฿100. NOT TESTED: the ghost-customer scene on a real late delivery; the GhostLady figure seen in a scene (only seen standing in Edit) |

Studio note (2026-11-18): after long Play sessions the Studio viewport turned white (also in Edit, also after a restart);
screen_capture returns white then. Probably the Studio window was minimised or covered. Store shots of fireworks and the
ghost scene are still to take.

**Batch 1b (2026-11-19, owner: "งั้นทำสิ่งที่แนะนำได้เลย": teaser tools + the look of the lake)**

| # | What | State |
|---|---|---|
| 8 | Owner-only codes, typed in the normal code box (`StoreService.ownerCode`, server-side only, owner user id 11934070066): `LOYPREVIEW` opens Loy Krathong on that server for 3 h and sets dusk, `LOYOFF`, `FIREWORKS` (75 s show now, `FireworksUntil`), `NIGHT` 20:00, `DUSK` 17:36, `DAY` 09:00 (`Time.set`). Anyone else gets "That code doesn't exist" | PASS in Studio (all six) |
| 9 | A code per TikTok clip: `LOY2569` (฿2,000 + 100 season XP, to 7 Dec), `PHEE` (฿1,313), `TIKTOK` (฿1,500 + 2 milk teas). Every use logs the custom event "Code <NAME>" (`Metrics.event`; Creator Dashboard > Analytics > Custom events) | PASS: LOY2569 once only, unknown code refused. Dashboard numbers NOT TESTED (live only) |
| 10 | Lakes are terrain water (`server/World/WaterSurface`): every lake and pond outline filled at 4-stud cells (centre ≥ 1 stud inside), surface at `Game.WATER_Y` = 1.2; the old "Water" parts are the dark lake bed (top 0.05) and keep collisions/raycasts (krathongs float at WATER_Y). 105 outlines, ~33 MB of voxels on the server | PASS: waves, sky and building reflections by day; lit windows reflected at night. An Edit test showed green specks where wave troughs met the ground tiles (top 0): the dark bed parts hide them |
| 11 | Night lights on the water (`client/Water`): lamps, lanterns and krathong candles near a lake get a shimmering streak at the mirror point toward the camera (max 6/14/24 by Perf tier); water colour eases to night blue | PASS in an Edit test scene; in game the streaks are subtle next to Roblox's own reflections |
| 12 | Backs that face a lake, the promenade or a park (`lot.view` from the planner's blocker, `Blocks.backDress`): windows on the back (lit at night), a drain pipe and air-cons, and on wide ones a lit rooftop billboard for a made-up local business | PASS: the far shore of Bueng Kaen Nakhon shows windows and boards instead of bare 30-50 stud walls |
| 13 | Fireworks: 4-stud sparks (were 1.6), 120 + 55 glitter, a flash, light range 120 | PASS: bursts read clearly from the pier |

**Batch 2a (2026-11-19)**

| # | What | State |
|---|---|---|
| 14 | Clip mode 9:16 (`client/ClipMode`, B or phone app "Clip"): pillarbox bars, controls on the bars (outside the crop), cameras Follow / Low chase / Side / Front / Drone / Roadside (N), HUD and Roblox menus hidden on computers (touch keeps the driving controls, drawn over the bars) | PASS on foot (Front). NOT TESTED: the moving cameras while driving, touch layout |
| 15 | Emotes (`client/Emotes` G or 😀, `server/EmoteService`): Roblox R15 wave / dance x3 / laugh / cheer; Thai poses wai, peace sign, selfie (server sets "Emote"/"EmoteAt", every client bends the joints in PreSimulation; ✌️ and "🙏 สวัสดีครับ" badges, a phone in the selfie hand). Stops on walk / jump / sit, 8 s max | PASS: menu, dance, wai (after flipping the arm Z sign), peace (badge moved toward the camera: it hid in the hand), selfie (phone held out, ✌️ on the other hand) |
| 16 | Turn-by-turn (`client/TurnHint`): only at junctions (graph nodes with 3+ roads), "อีก 130 ม. เลี้ยวขวา" + the road you turn into, orange in the last 40 m, "ถึงที่หมาย" at the end | PASS: card showed while driving a GPS route |

**Batch 2b (2026-11-19)**

| # | What | State |
|---|---|---|
| 17 | Adopt a soi dog (`Config/Pets`, `server/PetService`, `client/Pets`, prompt in `client/Dogs`): walk up (soi dogs now chase only bikes and runners, not calm walkers), ฿300, pick one of three preset names; it trots behind you on foot, sits in a wicker basket on bicycles / the Sabai / the old moped, stands on a scooter's floorboard, lies on a sport bike's tank; hidden in cars. Phone > Settings toggles taking it along. The stray's lane gets a new dog after 20 min | PASS: adopt "มะลิ", follows on foot, rides in the basket of a Sabai 110 (lowered 0.3 after the test). NOT TESTED: scooter / sport spots, the settings toggle |
| 18 | Swan pedal boats (`server/BoatService`, `client/Boats`): two per lakeside pier, free, E to sit, W/S/A/D or the thumbstick; LinearVelocity (speed + hold at WATER_Y) and AlignOrientation, owned by the rider; empty for 90 s -> back to the mooring. The tied-up decor swans are gone (they jammed the first test boat) | PASS: floats at 1.04, 11 studs/s. The new moorings (beside the deck, 21 out) NOT TESTED |
| 19 | Convoy bonus (JobService): other riders working within 160 studs when you finish add 12 % of the pay each (max 3) to your tip; "🛵🛵 ขบวนไรเดอร์" on the slip | NOT TESTED (needs two players) |
| 20 | Stunts (`client/Drive` + `client/Stunts`, `server/StuntService`): wheelie = R or the touch 🔥 button (body pivots ~24° on the rear axle), burnout = handbrake + gas standing still on a motorbike (rear wheel spins, smoke, the bike stays); timer chip, personal bests in d.stats; others see it through the vehicle's "Stunt" attribute | PASS: wheelie lifts the front (with the dog in the basket). NOT TESTED: burnout, the record toast (needs ≥ 1.5 s), others' view |
| 21 | Lake lap (`server/TimeTrialService`, `client/TimeTrial`): 6 gates on the big roads round Bueng Kaen Nakhon from the road graph, start/finish nearest the pier; chip near the start -> arches, GPS to the next gate, clock; the server checks the gates in order 10x/s, refuses laps under the believable minimum (86 s), keeps stats.bestLap and a weekly OrderedDataStore board shown on the sign at the start | PASS: chip, arming, START·FINISH arch, GPS ribbon. NOT TESTED: a whole lap (RAM ran out) |

**Batch 2c (2026-11-19)**

| # | What | State |
|---|---|---|
| 22 | Plates are picked, not typed (all ages: nobody types text others see): a word from `Vehicles.PLATE_WORDS` (ซิ่ง, แซ่บ, GO, KK, the Thai letter pairs...) + 1-999, lucky-number buttons; the server refuses typed plates (`{ w, n }` or "" only). Plates bought before stay | PASS: picked plate accepted, typed text refused. Phone UI NOT TESTED by eye |
| 23 | Customer memos (TwistService): a third of the jobs show a funny note from the customer when taken (12 food, 5 ride), jokes only | NOT TESTED (needs a job) |
| 24 | Two more horns in Styling: ตุ๊กตุ๊ก (three quick beeps) and แตรเพลง (our own 4-note tune) | NOT TESTED by ear |
| 25 | Night car meet (`server/CarMeetService`): 20:30-02:00 game time, 11 tuned display cars and bikes with underglow, stickers and lucky plates in the KK Plaza car park, a lit banner "มีตติ้งรถซิ่ง ทุกคืน" and a speaker stack; one toast a night to everyone | PASS: 11 cars, banner lit at 21:00. The banner then moved behind the cars (it stood in a bus stop): NOT TESTED there |

| 26 | Telling people about stunts (owner: "ยกล้อทำไงนะ ควรมีฟังชั่นบอกด้วย"): once a session, riding a bike fast for 3 s -> "hold R / the 🔥 button" toast (the touch button flashes), standing still on a motorbike 4 s -> the burnout keys; skipped for riders who already have a record. The key help (K) lists R, Space+W and B on a bike, G and B on foot. G no longer opens the emotes at a customer's door (G = deliver there) or in build mode | compiles; NOT TESTED in play (RAM 1.0 GB free) |

**Batch 2d (2026-11-19, owner while playing: "รถคุมยาก", "คนเดินไม่หลบรถ", "ต้นไม้ต่ำเกินบังจอ", then "คัทซีนตอนคู่กรณีไม่เอาเรื่อง, Replay
ให้ดูว่าเกิดอะไรขึ้นฟีลกล้องวงจรปิด, คนเจ็บลุกขึ้นมาเรียกค่าเสียหาย ตอนนี้มันวาปๆ, คัทซีนส่วนอื่นด้วย")**

| # | What | State |
|---|---|---|
| 27 | Steering (`client/Drive`, `client/LaneAssist`): grip budget 1.7 g -> 2.0 g (a sixth tighter at speed); the key ramps to full lock in ~0.3 s at speed (was ~0.55 s + smoothing, so turns came late and overshot); yaw follows the front wheel a little faster; lane assist waits 1.8 s after you last steered and leaves you alone in the other lane (it dragged lane changes back the moment you let go) | compiles; NOT TESTED by feel (needs the owner's hands) |
| 28 | Pedestrians watch the traffic (`client/Peds`): every 0.12 s the moving vehicles near the camera (physics speed, or how far a scripted AI car moved); someone in the strip a vehicle covers in the next 2.3 s notices it after 0.2-0.75 s (longer from behind / while standing), steps out to the open side (sprint at most 10 studs/s, a little jump when it is close, "เฮ้ย! ระวังหน่อย!" for your own vehicle) and watches it pass; people crossing a street look both ways and wait. A vehicle that turns up close can still catch someone | compiles; dodging NOT SEEN by eye (QaPedAhead pins its test target so the hit test still works) |
| 29 | Street trees (`World/Scenery`, `Config/Plants.crown`): the canopy of every street tree starts at 15.5 studs or more (crown heights measured from the leaf meshes); species that cannot get there (koon) are not planted along streets any more; a koon on a roundabout island stays inside the island. ChaseCam looks past thin things (trunks, posts) instead of jumping in | PASS: chase-cam shot under a shade tree on a 30-stud street, canopy above the picture |
| 30 | CCTV replay (`client/Replay`): the last 8 s of your vehicle, the people and the AI cars round it, 15 Hz; after an accident claim, a red light or the zebra fine the scene plays it back from a camera on a pole (grey, scan lines, REC, CAM nn, date and the town clock, choppy 15 fps, 0.3x slow motion and a flash at the moment). Your vehicle is anchored on your screen only for it and put back | PASS: replay of a pedestrian hit, slow motion at the impact |
| 31 | Claim scene (`client/Cutscene` fineScene, `client/Accident`): the person you hit is the one who comes over (borrowed from Peds: lies where they fell, gets up dazed, limps over, then walks on); the other driver gets out of the AI car you hit (a motorbike's rider climbs off it, the car keeps its hazards on); a long walk is shortened with a cut, never a warp. "They let it go" now has its own scene: "ไม่เป็นไรๆ ไม่เอาเรื่องหรอก…", a wave, a green card "คู่กรณีไม่เอาเรื่อง ฿0 · ยอมความ". AccidentService: a light bump (< 10 studs/s) is let go one time in three | PASS: the same pedestrian got up and came over (waived case). NOT TESTED: the card by eye, the car-driver variant |
| 32 | Police on a motorbike (fineScene): for a red light or the zebra crossing a traffic-kit motorbike in police colours (POLICE box, red-blue light bar) pulls up behind you, the officer climbs off and walks over. Checkpoints and the municipal officer keep the walk-up | compiles; NOT TESTED in play (RAM) |

**Still to do:** the first 10 minutes with gradual unlocks (needs a design pass with the owner: it changes what new riders
see first); random city events.

**Batch 3 (all ages):** plates from presets instead of typed text, content check (crash and injury = mild, ghosts =
mild fear), the maturity questionnaire, the refundable 1,000 R$ fee (ask the owner first), a full phone test.

**Owner steps:** type the Thai name and description in Localization; create the game's Roblox Community (free) and
send its id (turns on `Store.GROUP_ID`); add "ลอยกระทงบึงแก่นนคร 24 พ.ย." under Events; create a notification template.

## 4. Tools and test hooks

- `python -I tools/plan_streets.py [preview.png]` — regenerate the street graph with lanes and `KhonKaenData/Plan.luau`.
  Run it after changing `data/sites.json` (sites, land use) or `data/osm_raw.json`. Needs numpy + Pillow.
- Studio play test, **server side**: `game.ServerStorage.GoDashQa:Invoke("stats")`, `:Invoke("lots", x1, z1, x2, z2)`;
  `workspace:SetAttribute("QaFocus", Vector3.new(x, 5, z))` streams and builds the city around that point (nil = back to
  the character).
- Studio play test, **client side** (`src/client/Qa.luau`): `QaMute` (set it in Edit before pressing Play), `QaHud`,
  `QaView = "x,y,z,x2,y2,z2,fov"`, `QaClear` (no haze / clouds for aerial shots).
- More hooks (2026-11-16): `QaTarget = Vector3` (client: GPS waypoint, for auto drive), `QaSceneHold = true` (client:
  the fine scene keeps its ticket up 14 s), `QaNeeds = true` (server: full energy / hunger / happiness), `QaFastJobs`
  (server: the job anti-cheat lets teleport tests through). All are ignored on live servers.
- 2026-11-18: `QaTier = 1|2|3` (client: pin the graphics tier), `QaClock = hours` (server), `QaLevel`, `QaMoney` (server).
  A test vehicle: `Garage("buy", id)` only works near KK Motors; seat the player from the server with `seat:Sit(humanoid)`;
  drive it with the model attribute `QaThrottle` (client); auto drive = the Q key (user_keyboard_input). execute_luau puts
  the camera type back at the end of each run: release a `QaView` with `task.delay(1, ...)` setting `CameraType.Custom`.

## 5. Manual steps for the owner


- After pulling these changes: sync the scripts into the Roblox place, play-test, then **File -> Publish to Roblox**.
  Nothing reaches players until that publish.
- A new landmark or plot needs an entry in `data/sites.json` (lot centre + direction of its street front), then
  `tools/plan_streets.py`.
