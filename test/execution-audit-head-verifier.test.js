const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");

const migration = readFileSync(
  join(
    __dirname,
    "..",
    "supabase/migrations/20260925031500_execution_audit_head_verifier_v1.sql",
  ),
  "utf8",
);

test("audit head verifier stays constant-time and re-hashes the current head", () => {
  assert.match(
    migration,
    /from private\.execution_audit_chain_state[\s\S]*where organization_id = p_organization_id/,
  );
  assert.match(
    migration,
    /sequence = chain\.last_sequence;/,
  );
  assert.match(
    migration,
    /sequence = chain\.last_sequence - 1;/,
  );
  assert.match(migration, /extensions\.digest\(/);
  assert.match(migration, /'scope', 'head'/);
  assert.doesNotMatch(migration, /for\s+\w+\s+in[\s\S]*execution_audit_events/i);
});

test("audit head verifier is service-role only and does not replace deep verification", () => {
  assert.match(
    migration,
    /perform private\.assert_control_service_role\(\)/,
  );
  assert.match(
    migration,
    /revoke all on function public\.verify_execution_audit_head\(uuid\)[\s\S]*from public, anon, authenticated/,
  );
  assert.match(
    migration,
    /grant execute on function public\.verify_execution_audit_head\(uuid\)[\s\S]*to service_role/,
  );
  assert.match(migration, /full verify_execution_audit_chain\(uuid\) forensic verifier remains unchanged/i);
});
