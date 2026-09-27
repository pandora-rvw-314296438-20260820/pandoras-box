"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { once } = require("node:events");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const app = require("../vercel-entrypoint.js");

const root = path.resolve(__dirname, "..");

test("Meta privacy and deletion instructions resolve to public HTML instead of Pandora's web shell", async () => {
  const { rewrites } = JSON.parse(readFileSync(path.join(root, "vercel.json"), "utf8"));
  const map = new Map(rewrites.map(({ source, destination }) => [source, destination]));
  assert.equal(map.get("/privacy"), "/privacy.html");
  assert.equal(map.get("/privacy-policy"), "/privacy.html");
  assert.equal(map.get("/data-deletion"), "/data-deletion.html");

  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    const origin = `http://127.0.0.1:${server.address().port}`;
    for (const [route, heading] of [
      ["/privacy", "Privacy policy"],
      ["/data-deletion", "Data deletion instructions"],
    ]) {
      const response = await fetch(origin + route, { headers: { accept: "text/html" } });
      assert.equal(response.status, 200, route);
      assert.match(response.headers.get("content-type") || "", /^text\/html/i, route);
      const body = await response.text();
      assert.match(body, new RegExp(`<h1>${heading}<\\/h1>`), route);
      assert.match(body, /markjohnsonbanatao888@gmail\.com/, route);
      assert.doesNotMatch(body, /main\.dart\.js/, route);
    }
  } finally {
    server.close();
    await once(server, "close");
  }
});
