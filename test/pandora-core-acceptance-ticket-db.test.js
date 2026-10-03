"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const { readFileSync } = require("node:fs"), { join } = require("node:path"), { createHash } = require("node:crypto");
const { PGlite } = require("@electric-sql/pglite"), { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");
const read = name => readFileSync(join(__dirname, "..", name), "utf8");
const fixture = JSON.parse(read("apps/pandora-mobile/test/fixtures/core_acceptance_profile_v1.json"));
const org = fixture.canonical.organizationId, source = fixture.canonical.sourceSha, digest = fixture.configSha256;
const sha = value => createHash("sha256").update(value).digest("hex");
const body = { messages: [{ role: "user", content: [{ text: "Synthetic SQL contract input" }] }], maxTokens: 64, stream: true };
let db;
const scalar = async (sql, params = []) => (await db.query(sql, params)).rows[0].r;
const issue = (overrides = {}) => scalar("select public.pandora_issue_core_acceptance_bedrock_chat_ticket_v1($1,$2,$3,$4,$5) r",
  [overrides.model ?? "fixture-stream", body, overrides.org ?? org, overrides.digest ?? digest, overrides.source ?? source]);
const claim = (ticket, overrides = {}) => scalar("select public.pandora_claim_core_acceptance_bedrock_chat_ticket_v1($1,$2,$3,$4) r",
  [sha(ticket), overrides.org ?? org, overrides.digest ?? digest, overrides.source ?? source]);
async function configure() {
  await db.query("insert into private.pandora_core_acceptance_runtime_config(singleton,supabase_project_ref,organization_id,source_sha,config_sha256,canonical_json) values(true,$1,$2,$3,$4,$5)",
    [fixture.canonical.supabaseProjectRef, org, source, digest, fixture.canonicalJson]);
}
test.before(async () => {
  db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(`create schema extensions; create extension pgcrypto with schema extensions;
    create schema private; create schema auth; create role anon; create role authenticated; create role service_role;
    create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
    create table public.organizations(id uuid primary key);
    create table private.pandora_bedrock_reasoning_catalog(model_id text primary key,model_name text,provider_name text,invocation_target text,input_modalities text[],routable boolean,conversational boolean,present_in_latest_sync boolean,runtime_verification_status text,lifecycle_status text,response_streaming_supported boolean);
    insert into private.pandora_bedrock_reasoning_catalog values('fixture-stream','Test only','Fixture','fixture-target',ARRAY['TEXT'],true,true,true,'passed','ACTIVE',true),('fixture-unverified','Test only','Fixture','fixture-target',ARRAY['TEXT'],false,true,true,'untested','ACTIVE',true);`);
  // Execute the actual base ticket table and claim, excluding its obsolete HTTP
  // bridge function, then the actual native issuer and the branch-only wrapper.
  const legacy = read("supabase/migrations/20261003033000_pandora_bedrock_chat_bridge_v1.sql");
  await db.exec(legacy.slice(0, legacy.indexOf("create or replace function private.pandora_bedrock_chat_api_v1")) + "commit;");
  await db.exec(read("supabase/migrations/20261003170100_pandora_chat_bedrock_native_stream_v2.sql"));
  await db.exec(read("supabase/acceptance/core_acceptance_ticket_binding_v1.sql"));
  await db.query("insert into public.organizations values($1)", [org]);
  await db.exec("select set_config('request.jwt.claim.role','service_role',false)");
});
test.after(async () => db?.close());

test("acceptance issuer fails closed without an installed target and creates no ticket", async () => {
  await assert.rejects(issue(), /CORE_RUNTIME_TARGET_MISMATCH/);
  assert.equal(await scalar("select count(*)::int r from private.pandora_bedrock_chat_tickets"), 0);
  await configure();
});

test("native request and durable scope survive the original one-time issue/claim engine", async () => {
  const issued = await issue();
  assert.match(issued.ticket, /^[0-9a-f]{64}$/);
  const result = await claim(issued.ticket);
  assert.equal(result.organizationId, org); assert.equal(result.configSha256, digest); assert.equal(result.sourceSha, source);
  assert.deepEqual(result.requestBody, body); assert.equal(result.modelId, "fixture-stream");
  await assert.rejects(claim(issued.ticket), /BEDROCK_CHAT_TICKET_DENIED/);
  assert.equal(await scalar("select count(*)::int r from private.pandora_core_acceptance_bedrock_ticket_bindings"), 0);
});

test("wrong issue organization/config/source never creates a ticket or a binding", async () => {
  for (const overrides of [{ org: "20000000-0000-4000-8000-000000000001" }, { digest: "b".repeat(64) }, { source: "b".repeat(40) }]) {
    await assert.rejects(issue(overrides), /CORE_RUNTIME_TARGET_MISMATCH/);
  }
  assert.equal(await scalar("select count(*)::int r from private.pandora_bedrock_chat_tickets"), 0);
});

test("wrong claim cannot consume or retarget the original ticket", async () => {
  const issued = await issue();
  for (const overrides of [{ org: "20000000-0000-4000-8000-000000000001" }, { digest: "b".repeat(64) }, { source: "b".repeat(40) }]) {
    await assert.rejects(claim(issued.ticket, overrides), /CORE_RUNTIME_TARGET_MISMATCH/);
  }
  assert.equal(await scalar("select count(*)::int r from private.pandora_bedrock_chat_tickets"), 1);
  assert.equal((await claim(issued.ticket)).organizationId, org);
});

test("unbound legacy ticket is denied by acceptance and remains valid for its unchanged legacy claim", async () => {
  const issued = await scalar("select public.pandora_issue_bedrock_chat_ticket_v1($1,$2) r", ["fixture-stream", body]);
  await assert.rejects(claim(issued.ticket), /BEDROCK_CHAT_TICKET_DENIED/);
  const result = await scalar("select public.pandora_claim_bedrock_chat_ticket_v1($1) r", [sha(issued.ticket)]);
  assert.equal(result.modelId, "fixture-stream"); assert.equal(result.organizationId, undefined);
});

test("configuration revocation prevents claim without silently consuming or replaying work", async () => {
  const issued = await issue();
  await db.exec("delete from private.pandora_core_acceptance_runtime_config");
  await assert.rejects(claim(issued.ticket), /CORE_RUNTIME_TARGET_MISMATCH/);
  assert.equal(await scalar("select count(*)::int r from private.pandora_bedrock_chat_tickets"), 1);
  await configure(); await claim(issued.ticket);
});

test("expiry and the original verified-catalog gate cannot be bypassed by binding metadata", async () => {
  await assert.rejects(issue({ model: "fixture-unverified" }), /BEDROCK_CHAT_MODEL_UNAVAILABLE/);
  const issued = await issue();
  await db.exec("update private.pandora_bedrock_chat_tickets set created_at=clock_timestamp()-interval '2 minutes',expires_at=clock_timestamp()-interval '1 minute'");
  await assert.rejects(claim(issued.ticket), /BEDROCK_CHAT_TICKET_DENIED/);
  await db.exec("delete from private.pandora_bedrock_chat_tickets");
});

test("customer roles cannot issue/claim tickets or rewrite protected configuration", async () => {
  await db.exec("set role authenticated");
  try {
    await assert.rejects(issue(), /permission denied/);
    await assert.rejects(claim("a".repeat(64)), /permission denied/);
    await assert.rejects(db.exec("delete from private.pandora_core_acceptance_runtime_config"), /permission denied/);
  } finally { await db.exec("reset role"); }
  await db.exec("select set_config('request.jwt.claim.role','authenticated',false)");
  try { await assert.rejects(issue(), /SERVICE_ROLE_REQUIRED/); }
  finally { await db.exec("select set_config('request.jwt.claim.role','service_role',false)"); }
});

test("configuration cannot target the canonical Core or Memory project", async () => {
  for (const ref of ["jcyqixttuebxqqfkjonq", "ivmvufhcsezyhczzondn"]) {
    await assert.rejects(db.query("update private.pandora_core_acceptance_runtime_config set supabase_project_ref=$1", [ref]), /check constraint/);
  }
  const malformed = JSON.stringify({});
  await assert.rejects(db.query("update private.pandora_core_acceptance_runtime_config set canonical_json=$1,config_sha256=$2", [malformed, sha(malformed)]), /check constraint/);
});
