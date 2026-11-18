// Download the map data for Tambon Nai Mueang, Khon Kaen, from OpenStreetMap (ODbL, © OpenStreetMap contributors).
//   node tools/osm_fetch.mjs            -> data/osm_tambon.json
// Then: python -I tools/plan_streets.py [preview.png] (it runs tools/osm_to_map.py first).
// 2026-11-18: the whole tambon (OSM relation 21404983) instead of a 2.5 x 3.8 km box (data/osm_raw.json,
// kept in backups/map_v1_2026-11-18), with the plain "service" alleys, land use and named public places.
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "..", "data", "osm_tambon.json");
// south, west, north, east: the tambon's box plus a hair
const B = process.env.BBOX || "16.3975,102.8020,16.4825,102.8785";
const q = `[out:json][timeout:180][maxsize:536870912];
(
  rel(21404983);
  way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link|pedestrian)$"](${B});
  way["natural"="water"](${B});
  relation["natural"="water"](${B});
  way["waterway"~"^(river|canal|stream)$"](${B});
  way["railway"~"^(rail|station|platform)$"](${B});
  node["railway"="station"](${B});
  way["leisure"~"^(park|stadium|sports_centre|pitch|golf_course)$"](${B});
  way["landuse"~"^(residential|commercial|retail|industrial|military|cemetery|religious|education|institutional|grass|farmland|meadow|orchard)$"](${B});
  nwr["amenity"](${B});
  nwr["office"~"^(government|administrative)$"](${B});
  nwr["government"](${B});
  nwr["shop"~"^(mall|supermarket|department_store|convenience|marketplace)$"](${B});
  nwr["tourism"](${B});
  nwr["historic"](${B});
);
out geom;`;

const servers = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://overpass.openstreetmap.fr/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
];
for (const url of servers) {
  try {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 240000);
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", "user-agent": "osm-fetch/1.0" },
      body: "data=" + encodeURIComponent(q),
      signal: ctl.signal,
    });
    clearTimeout(timer);
    const text = await res.text();
    if (!res.ok || !text.trim().startsWith("{")) {
      console.log("FAIL", url, res.status, text.slice(0, 120).replace(/\s+/g, " "));
      continue;
    }
    writeFileSync(out, text);
    const j = JSON.parse(text);
    console.log("OK", url, "MB", (text.length / 1e6).toFixed(1), "elements", j.elements.length);
    process.exit(0);
  } catch (e) {
    console.log("ERR", url, String(e.cause?.code || e.message));
  }
}
process.exit(1);
