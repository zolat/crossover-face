import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

// The geometry files sit in public/, so Vite serves them under fixed names, and GitHub
// Pages lets a browser keep any file for ten minutes. A deploy that changes their shape
// then hands a new page an old devices.json: Safari did, and the page asked for
// geometry/undefined.json and drew nothing. A hash of their contents goes on every
// fetch, so new code never reads a copy cached for old code.
const geometry = fileURLToPath(new URL("public/geometry/", import.meta.url));
const hash = createHash("sha256");
for (const name of readdirSync(geometry).sort()) hash.update(name).update(readFileSync(geometry + name));

// Relative base, so the built site works from any folder or static host.
export default defineConfig({
  base: "./",
  define: { __GEOMETRY_VERSION__: JSON.stringify(hash.digest("hex").slice(0, 12)) },
});
