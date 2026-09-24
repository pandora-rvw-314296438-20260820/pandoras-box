const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");

const migration = readFileSync(
  join(
    __dirname,
    "..",
    "supabase",
    "migrations",
    "20260925035200_execution_audit_head_integrity_v1.sql",
  ),
  "utf8",
);
const ownerApi = readFileSync(
  join(__dirname, "..", "supabase", "functions", "pandora-owner-api", "index.ts"),
  "utf8",
);

test("runtime safety verification is constant-time and keeps the deep verifier separate", () => {
  assert.match(migration, /verify_execution_audit_head_v1/);
  assert.match(migration, /order by sequence desc\s+limit 1/i);
  assert.match(migration, /tail_event_hash_mismatch/);
  assert.match(
    migration,
    /grant execute on function public\.verify_execution_audit_head_v1\(uuid\)\s+to service_role/i,
  );
  assert.match(
    migration,
    /full historical verify_execution_audit_chain\(uuid\) verifier remains authoritative/i,
  );

  const safetyStart = ownerApi.indexOf("async function safety(");
  const safetyEnd = ownerApi.indexOf("const CONNECTED_SERVICES_OWNER_INTENT", safetyStart);
  assert.notEqual(safetyStart, -1);
  assert.notEqual(safetyEnd, -1);
  const safety = ownerApi.slice(safetyStart, safetyEnd);
  assert.match(safety, /verify_execution_audit_head_v1/);
  assert.doesNotMatch(safety, /verify_execution_audit_chain/);
});
