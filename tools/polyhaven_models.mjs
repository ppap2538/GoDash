// Download Poly Haven models (CC0) as glTF + 1k textures into assets/models_src/<id>/.
//   node tools/polyhaven_models.mjs id1 id2 ...
import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "assets", "models_src");
const UA = { "user-agent": "asset-fetch/1.0" };

async function get(url, file) {
  if (existsSync(file)) return;
  const res = await fetch(url, { headers: UA });
  if (!res.ok) throw new Error(res.status + " " + url);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, Buffer.from(await res.arrayBuffer()));
}

for (const id of process.argv.slice(2)) {
  try {
    const res = await fetch("https://api.polyhaven.com/files/" + id, { headers: UA });
    if (!res.ok) { console.log("MISSING", id); continue; }
    const f = await res.json();
    const g = f.gltf?.["1k"]?.gltf;
    if (!g) { console.log("NO GLTF", id, Object.keys(f)); continue; }
    const dir = join(root, id);
    await get(g.url, join(dir, id + ".gltf"));
    let n = 1;
    for (const [rel, inc] of Object.entries(g.include || {})) {
      await get(inc.url, join(dir, rel));
      n++;
    }
    console.log("OK", id, n, "files");
  } catch (e) {
    console.log("FAIL", id, String(e.message));
  }
}
