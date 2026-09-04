import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the colour field lab", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Colour Field Lab<\/title>/i);
  assert.match(html, /Colour Field Lab/);
  assert.match(html, /Activity/);
  assert.match(html, /Arcade/);
  assert.match(html, /Pulse/);
  assert.match(html, /Beacon/);
  assert.match(html, /Prototype only/);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/i);
});

test("keeps candidates marked as mockup-only", async () => {
  const source = await readFile(new URL("../app/palette-data.ts", import.meta.url), "utf8");
  assert.match(source, /activity:\s*\{[\s\S]*?status: "Shipping"/);
  for (const candidate of ["arcade", "pulse", "beacon"]) {
    assert.match(source, new RegExp(`${candidate}:\\s*\\{[\\s\\S]*?status: "Mockup only"`));
  }
  assert.match(source, /#FE4646[\s\S]*#6DC54F[\s\S]*#1F8FFE[\s\S]*#E59A0A/);
});
