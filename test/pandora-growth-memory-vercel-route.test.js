"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const route = fs.readFileSync("api/operations-memory.ts", "utf8");
const vercel = fs.readFileSync("vercel.json", "utf8");
const router = fs.readFileSync("src/pandora-growth-memory-http.js", "utf8");

test("Vercel exposes the authenticated growth Memory route without adding a thirteenth function", () => {
  assert.match(route, /createPandoraGrowthMemoryRouter/);
  assert.match(route, /req\.query\?\.growth/);
  assert.match(route, /req\.url='\/api\/growth\/memory-context'/);
  assert.match(vercel, /"source": "\/api\/growth\/memory-context"/);
  assert.match(vercel, /"destination": "\/api\/operations-memory\?growth=1"/);
  assert.equal(fs.existsSync("api/growth/memory-context.ts"), false);
  const rootFunctions = fs.readdirSync("api", {withFileTypes: true})
    .filter((entry) => entry.isFile() && /\.(?:ts|js)$/.test(entry.name));
  assert.ok(rootFunctions.length <= 12, `Hobby deployment function cap exceeded: ${rootFunctions.length}`);
  assert.match(router, /router\.post\("\/api\/growth\/memory-context"/);
});

test("the shared route keeps workload identity server-side", () => {
  assert.doesNotMatch(vercel, /x-pandora-vercel-oidc|VERCEL_OIDC|workloadToken/);
  assert.match(router, /resolveVercelWorkloadToken/);
  assert.match(router, /x-pandora-vercel-oidc/);
  assert.match(router, /owner_admin_required/);
  assert.match(router, /organization_access_required/);
  assert.match(router, /retrievalDoesNotGrantExecutionAuthority/);
  assert.match(router, /canAuthorizeSpend:\s*false/);
});
