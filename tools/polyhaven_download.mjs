// Download the resolved Poly Haven maps into assets/textures (kept in the project as the asset library).
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
const here = dirname(fileURLToPath(import.meta.url));
const list = JSON.parse(readFileSync(join(here, "..", "data", "polyhaven_textures.json"), "utf8"));
const dir = join(here, "..", "assets", "textures");
mkdirSync(dir, { recursive: true });
let n = 0;
for (const [id, a] of Object.entries(list)) {
  for (const k of ["color", "normal", "rough", "metal"]) {
    if (!a[k]) continue;
    const ext = a[k].endsWith(".png") ? "png" : "jpg";
    const file = join(dir, `${id}_${k}.${ext}`);
    if (existsSync(file)) continue;
    const res = await fetch(a[k], { headers: { "user-agent": "asset-fetch/1.0" } });
    if (!res.ok) { console.log("FAIL", id, k, res.status); continue; }
    writeFileSync(file, Buffer.from(await res.arrayBuffer()));
    n++;
  }
}
console.log("downloaded", n);
