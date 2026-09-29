"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const route = fs.readFileSync("api/growth/memory-context.ts", "utf8");
const router = fs.readFileSync("src/pandora-growth-memory-http.js", "utf8");

test("Vercel exposes the authenticated growth Memory router at its canonical API path", () => {
  assert.match(route, /createPandoraGrowthMemoryRouter/);
  assert.match(route, /\.\.\/\.\.\/src\/pandora-growth-memory-http\.js/);
  assert.match(route, /export default app/);
  assert.match(route, /maxDuration: 60/);
  assert.match(router, /router\.post\("\/api\/growth\/memory-context"/);
});

test("the route does not move workload identity into the client or request body", () => {
  assert.doesNotMatch(route, /x-pandora-vercel-oidc|VERCEL_OIDC|workloadToken/);
  assert.match(router, /resolveVercelWorkloadToken/);
  assert.match(router, /x-pandora-vercel-oidc/);
});
