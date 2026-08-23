const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");

const root = join(__dirname, "..");
const ownerApi = readFileSync(
  join(root, "supabase/functions/pandora-owner-api/index.ts"),
  "utf8",
);
const migration = readFileSync(
  join(
    root,
    "supabase/migrations/20260813014555_remove_projectos_approval_aal2.sql",
  ),
  "utf8",
);

function between(source, start, end) {
  const startIndex = source.indexOf(start);
  assert.notEqual(startIndex, -1, `missing start marker: ${start}`);
  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notEqual(endIndex, -1, `missing end marker: ${end}`);
  return source.slice(startIndex, endIndex);
}

test("owner API ordinary approval has no AAL2 step-up and reports it accurately", () => {
  const decide = between(ownerApi, "async function decide(", "\nDeno.serve(");
  assert.doesNotMatch(decide, /context\.aal|aal2|AAL2_REQUIRED/i);
  assert.match(decide, /context\.isAnonymous/);
  assert.match(decide, /rpc\("decide_approval"/);
  assert.match(ownerApi, /mfaRequiredForApproval:\s*false/);
  assert.doesNotMatch(ownerApi, /currentAssuranceLevel/);
  const approvalSummary = between(
    ownerApi,
    "function approvalSummary(",
    "\nasync function home(",
  );
  assert.match(approvalSummary, /extraIdentityCheckRequired:\s*false/);
});

test("owner API keeps authenticated active-organization owner/admin authorization", () => {
  const authenticate = between(
    ownerApi,
    "async function authenticate(",
    "\nasync function enforceRateLimit(",
  );
  assert.match(authenticate, /Bearer\\s\+\\S\+/);
  assert.match(authenticate, /client\.auth\.getUser\(\)/);
  assert.match(authenticate, /\.from\("memberships"\)/);
  assert.match(authenticate, /\.eq\("status",\s*"active"\)/);
  assert.match(authenticate, /new Set\(\["owner",\s*"admin"\]\)/);
  assert.doesNotMatch(authenticate, /"operator"|"member"|"viewer"/);
});

test("owner API retains independent AAL2 gates for connection and destructive actions", () => {
  const connectionAction = between(
    ownerApi,
    "async function connectionAction(",
    "\nasync function approvals(",
  );
  assert.match(
    connectionAction,
    /action !== "test" && context\.aal !== "aal2"/,
  );
  assert.match(
    ownerApi,
    /action\.risk === "CRITICAL"[\s\S]*context\.aal !== "aal2"/,
  );
});

test("database approval function accepts AAL1 owner/admin while retaining all durable guards", () => {
  assert.doesNotMatch(migration, /auth\.jwt\(\)\s*->>\s*'aal'/);
  assert.doesNotMatch(migration, /auth\.sessions|auth\.aal_level|aal2 required/i);
  assert.match(migration, /current_user_id uuid := \(select auth\.uid\(\)\)/);
  assert.match(migration, /is_anonymous/);
  assert.match(
    migration,
    /array\['owner', 'admin'\]::public\.member_role\[\]/,
  );
  assert.doesNotMatch(migration, /array\[[^\]]*'operator'/);
  assert.match(migration, /for update/);
  assert.match(migration, /decision <> 'pending'/);
  assert.match(migration, /expires_at <= timezone\('utc', now\(\)\)/);
  assert.match(migration, /assigned_to <> current_user_id/);
  assert.match(migration, /step_risk in \('R3'.*'R4'/s);
  assert.match(migration, /requested_by = current_user_id/);
  assert.match(migration, /decision_by = current_user_id/);
  assert.match(migration, /private\.append_audit_event/);
  assert.match(migration, /'action_hash', approval_row\.action_hash/);
});

test("database approval function remains unavailable to public and anonymous roles", () => {
  assert.match(
    migration,
    /revoke execute on function public\.decide_approval\([\s\S]*\) from public, anon;/,
  );
  assert.match(
    migration,
    /grant execute on function public\.decide_approval\([\s\S]*\) to authenticated, service_role;/,
  );
});
