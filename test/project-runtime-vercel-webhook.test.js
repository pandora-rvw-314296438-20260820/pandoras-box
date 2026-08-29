const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const migration = fs.readFileSync("supabase/migrations/20260829114500_pandora_worker_f_vercel_webhook_v1.sql", "utf8");
const edge = fs.readFileSync("supabase/functions/pandora-vercel-runtime-webhook/index.ts", "utf8");
const config = fs.readFileSync("supabase/config.toml", "utf8");

test("Vercel webhook endpoint authenticates provider signature instead of a Supabase user JWT", () => {
  assert.match(config, /\[functions\.pandora-vercel-runtime-webhook\]\s*\nverify_jwt = false/);
  assert.match(edge, /x-vercel-signature/);
  assert.match(edge, /await req\.text\(\)/);
  assert.match(edge, /pandora_worker_f_ingest_vercel_webhook_20260829/);
  assert.doesNotMatch(edge, /WEBHOOK_SECRET|PANDORA_VERCEL_TOKEN|VERCEL_TOKEN|Bearer\s+/);
});

test("webhook signature secret and Vercel provider token remain Vault-only", () => {
  assert.match(migration, /vault\.decrypted_secrets[\s\S]*name='pandora_vercel_runtime_webhook_signing'/);
  assert.match(migration, /vault\.decrypted_secrets[\s\S]*name='vercel'/);
  assert.match(migration, /vault\.create_secret\(v_signing_secret/);
  assert.match(migration, /vault\.update_secret\(v_secret_id,v_signing_secret/);
  assert.doesNotMatch(migration, /return\s+v_signing_secret/i);
  assert.doesNotMatch(migration, /jsonb_build_object\([^;]*['"]secret['"]/i);
});

test("signature check is raw-body HMAC-SHA1 with fixed-length comparison", () => {
  assert.match(migration, /extensions\.hmac\(convert_to\(p_raw_body,'utf8'\), convert_to\(v_secret,'utf8'\), 'sha1'\)/);
  assert.match(migration, /p_signature !~ '\^\[0-9A-Fa-f\]\{40\}\$'/);
  assert.match(migration, /for i in 0\.\.19 loop/);
  assert.match(migration, /get_byte\(p_expected, i\) # get_byte\(v_provided, i\)/);
  assert.match(migration, /return v_diff = 0/);
});

test("provider events are replay protected and never persist the raw provider payload", () => {
  assert.match(migration, /on conflict\(provider,provider_event_id\) do nothing/);
  assert.match(migration, /v_existing_sha is distinct from v_payload_sha/);
  assert.match(migration, /replayMismatch/);
  assert.match(migration, /payload_sha256/);
  assert.match(migration, /safe_summary/);
  assert.doesNotMatch(migration, /raw_payload|provider_payload\s*[,)]/);
});

test("only known Pandora Vercel project bindings are actionable", () => {
  assert.match(migration, /pandora_runtime_environments/);
  assert.match(migration, /provider='vercel' and provider_project_id=v_provider_project_id/);
  assert.match(migration, /v_mapping_count<>1/);
  assert.match(migration, /v_status := 'ignored'/);
  for (const event of ["deployment.created", "deployment.ready", "deployment.error", "deployment.promoted"]) assert.match(migration, new RegExp(event.replace(".", "\\.")));
});

test("webhook RPC and provisioning RPC are service-role only", () => {
  for (const name of ["pandora_worker_f_ingest_vercel_webhook_20260829", "pandora_worker_f_ensure_vercel_webhook_20260829"]) {
    assert.match(migration, new RegExp(`revoke all on function public\\.${name}[\\s\\S]*from public,anon,authenticated`, "i"));
    assert.match(migration, new RegExp(`grant execute on function public\\.${name}[\\s\\S]*to service_role`, "i"));
  }
});

test("provisioning is pinned to the Pandora Supabase webhook endpoint and stores only non-secret provider config", () => {
  assert.match(migration, /https:\/\/jcyqixttuebxqqfkjonq\.supabase\.co\/functions\/v1\/pandora-vercel-runtime-webhook/);
  assert.match(migration, /runtime_webhook_id/);
  assert.match(migration, /runtime_webhook_url/);
  assert.match(migration, /'POST'::extensions\.http_method/);
  assert.match(migration, /'DELETE'::extensions\.http_method/);
  assert.match(migration, /'GET'::extensions\.http_method/);
});
