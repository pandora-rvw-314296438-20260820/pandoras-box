
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");

const ownerApi = readFileSync(
  join(__dirname, "..", "supabase/functions/pandora-owner-api/index.ts"),
  "utf8",
);

function between(source, start, end) {
  const from = source.indexOf(start);
  assert.notEqual(from, -1, "start anchor must exist");
  const to = source.indexOf(end, from + start.length);
  assert.notEqual(to, -1, "end anchor must exist");
  return source.slice(from, to);
}

test("safety health is scoped to the canonical Pandora project", () => {
  const resolver = between(
    ownerApi,
    "async function canonicalSafetyProjectId(",
    "async function safety(",
  );
  assert.match(resolver, /\.eq\("repository", CANONICAL_REPOSITORY\)/);
  assert.match(resolver, /\.neq\("status", "archived"\)/);

  const safety = between(
    ownerApi,
    "async function safety(",
    "const CONNECTED_SERVICES_OWNER_INTENT",
  );
  assert.match(
    safety,
    /const safetyProjectId = await canonicalSafetyProjectId\(context\)/,
  );
  assert.match(safety, /\.eq\("project_id", safetyProjectId\)/);
});

test("safety does not read historical integration health organization-wide", () => {
  const safety = between(
    ownerApi,
    "async function safety(",
    "const CONNECTED_SERVICES_OWNER_INTENT",
  );
  const integrationQuery = between(
    safety,
    'context.client.from("projectos_integration_health")',
    'admin.rpc("verify_execution_audit_chain"',
  );
  assert.match(
    integrationQuery,
    /\.eq\("organization_id", context\.organizationId\)/,
  );
  assert.match(integrationQuery, /\.eq\("project_id", safetyProjectId\)/);
});
