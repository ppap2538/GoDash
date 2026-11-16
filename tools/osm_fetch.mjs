// Download Khon Kaen city-centre data from OpenStreetMap (ODbL, © OpenStreetMap contributors).
//   node tools/osm_fetch.mjs
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "..", "data", "osm_raw.json");
// south, west, north, east
const BBOX = process.env.BBOX || "16.4030,102.8170,16.4420,102.8450";
const q = `[out:json][timeout:90];
(
  way["highway"~"^(trunk|primary|secondary|tertiary|unclassified|residential|living_street|trunk_link|primary_link|secondary_link|tertiary_link)$"](${BBOX});
  way["natural"="water"](${BBOX});
  relation["natural"="water"](${BBOX});
  way["railway"="rail"](${BBOX});
  way["leisure"="park"](${BBOX});
  node["amenity"~"^(restaurant|cafe|fast_food|fuel|hospital|police|bus_station|marketplace|university|school|place_of_worship|bank|pharmacy)$"](${BBOX});
  node["shop"~"^(mall|convenience|supermarket|department_store)$"](${BBOX});
  way["amenity"~"^(hospital|police|bus_station|marketplace|university|school|place_of_worship|fuel)$"](${BBOX});
  way["shop"~"^(mall|supermarket|department_store)$"](${BBOX});
  way["tourism"](${BBOX});
  node["tourism"](${BBOX});
  way["railway"="station"](${BBOX});
  node["railway"="station"](${BBOX});
);
out geom;`;

const servers = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
  "https://overpass.openstreetmap.fr/api/interpreter",
];
for (const url of servers) {
  try {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 120000);
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
    const kinds = {};
    for (const e of j.elements) {
      const k = e.type + ":" + (e.tags?.highway ? "highway" : e.tags?.natural || e.tags?.railway || e.tags?.amenity || e.tags?.shop || e.tags?.tourism || e.tags?.leisure || "?");
      kinds[k] = (kinds[k] || 0) + 1;
    }
    console.log("OK", url, "bytes", text.length, "elements", j.elements.length);
    console.log(JSON.stringify(kinds));
    process.exit(0);
  } catch (e) {
    console.log("ERR", url, String(e.cause?.code || e.message));
  }
}
process.exit(1);
