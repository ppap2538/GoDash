// List / resolve Poly Haven assets (all CC0). Writes data/polyhaven_textures.json with direct 1k URLs.
//   node tools/polyhaven_pick.mjs search asphalt concrete ...   -> prints matching texture ids
//   node tools/polyhaven_pick.mjs resolve id1 id2 ...            -> resolves map URLs
import { writeFileSync, existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const cache = join(here, "..", "data", "polyhaven_index.json");
const UA = { "user-agent": "asset-fetch/1.0" };
const [mode, ...args] = process.argv.slice(2);
const type = process.env.PH_TYPE || "textures";

async function index() {
  const file = cache.replace(".json", "_" + type + ".json");
  if (existsSync(file)) return JSON.parse(readFileSync(file, "utf8"));
  const res = await fetch("https://api.polyhaven.com/assets?t=" + type, { headers: UA });
  const j = await res.json();
  writeFileSync(file, JSON.stringify(j));
  return j;
}

if (mode === "search") {
  const idx = await index();
  for (const term of args) {
    const hits = Object.entries(idx)
      .filter(([id, a]) => id.includes(term) || (a.categories || []).includes(term) || (a.tags || []).includes(term))
      .sort((a, b) => (b[1].download_count || 0) - (a[1].download_count || 0))
      .slice(0, Number(process.env.N || 14))
      .map(([id, a]) => id + (a.polycount ? "(" + a.polycount + ")" : ""));
    console.log(term + ": " + hits.join(", "));
  }
} else if (mode === "resolve") {
  const out = {};
  for (const id of args) {
    const res = await fetch("https://api.polyhaven.com/files/" + id, { headers: UA });
    if (!res.ok) { console.log("MISSING", id); continue; }
    const f = await res.json();
    const pick = (k) => f[k]?.["1k"]?.jpg?.url || f[k]?.["1k"]?.png?.url;
    out[id] = { color: pick("Diffuse"), normal: pick("nor_gl"), rough: pick("Rough"), metal: pick("Metal"), page: "https://polyhaven.com/a/" + id, license: "CC0" };
    console.log(id, Object.entries(out[id]).filter(([k, v]) => v && k !== "page" && k !== "license").map(([k]) => k).join("+"));
  }
  const file = join(here, "..", "data", "polyhaven_textures.json");
  const prev = existsSync(file) ? JSON.parse(readFileSync(file, "utf8")) : {};
  writeFileSync(file, JSON.stringify({ ...prev, ...out }, null, 1));
}
