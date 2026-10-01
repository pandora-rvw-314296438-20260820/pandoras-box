"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const route = fs.readFileSync("api/operations-memory.ts", "utf8");
const mcp = fs.readFileSync("api/mcp.ts", "utf8");
const vercel = fs.readFileSync("vercel.json", "utf8");
const router = fs.readFileSync("src/pandora-growth-memory-http.js", "utf8");

test("Vercel exposes the authenticated growth Memory route within the Hobby function cap", () => {
  assert.match(route, /createPandoraGrowthMemoryRouter/);
  assert.match(route, /req\.query\?\.growth/);
  assert.match(route, /req\.url='\/api\/growth\/memory-context'/);
  assert.match(vercel, /"source": "\/api\/growth\/memory-context"/);
  assert.match(vercel, /"destination": "\/api\/operations-memory\?growth=1"/);
  assert.equal(fs.existsSync("api/growth/memory-context.ts"), false);
  const rootFunctions = fs.readdirSync("api", {withFileTypes: true})
    .filter((entry) => entry.isFile() && /\.(?:ts|js)$/.test(entry.name));
  assert.ok(rootFunctions.length <= 11, `Hobby deployment explicit-function budget exceeded: ${rootFunctions.length}`);
  assert.match(router, /router\.post\("\/api\/growth\/memory-context"/);
});

test("consumer Gemini shares the canonical MCP function instead of consuming another function slot", () => {
  assert.equal(fs.existsSync("api/gemini-consumer-mcp.ts"), false);
  assert.match(mcp, /createPandoraMcpHandler/);
  assert.match(mcp, /queryConsumer \|\| urlConsumer/);
  assert.match(mcp, /=== 'gemini'/);
  assert.match(mcp, /allowedMembershipRoles: new Set\(\['owner'\]\)/);
  assert.doesNotMatch(mcp, /'pandora_approve_plan'/);
  assert.match(vercel, /"destination": "\/api\/mcp\?consumer=gemini"/);
  assert.match(vercel, /consumer=gemini&metadata=gemini-consumer-mcp/);
});

test("operations Memory avoids CommonJS require of ESM runtime modules", () => {
  assert.doesNotMatch(route, /import \{createWorkloadOperationsMemory\} from '..\/packages\/pandora-operations-memory\/workload-rpc\.mjs'/);
  assert.doesNotMatch(route, /import \{createOwnerMemoryRead,OPERATIONS_MEMORY_MAPPING\} from '..\/packages\/pandora-operations-memory\/owner-read\.mjs'/);
  assert.match(route, /import\('\.\.\/packages\/pandora-operations-memory\/workload-rpc\.mjs'\)/);
  assert.match(route, /import\('\.\.\/packages\/pandora-operations-memory\/owner-read\.mjs'\)/);
  assert.match(route, /await loadOwnerMemoryModules\(\)/);
});

test("the shared growth route keeps workload identity server-side", () => {
  assert.doesNotMatch(vercel, /x-pandora-vercel-oidc|VERCEL_OIDC|workloadToken/);
  assert.match(router, /resolveVercelWorkloadToken/);
  assert.match(router, /x-pandora-vercel-oidc/);
  assert.match(router, /owner_admin_required/);
  assert.match(router, /organization_access_required/);
  assert.match(router, /retrievalDoesNotGrantExecutionAuthority/);
  assert.match(router, /canAuthorizeSpend:\s*false/);
});
