import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = (repoPath, workPath) => readFileSync(existsSync(repoPath) ? repoPath : workPath, "utf8");
const migration = read(
  "supabase/migrations/20261001130000_pandora_connections_lane_a_v1.sql",
  "work/20261001130000_pandora_connections_lane_a_v1.sql",
);
const broker = read(
  "supabase/functions/pandora-connections-broker/index.ts",
  "work/pandora-connections-broker-index.ts",
);
const google = read(
  "supabase/functions/pandora-google-workspace-oauth/index.ts",
  "work/pandora-google-workspace-oauth-index.ts",
);

test("P0 manifests carry all mandatory Connection Manifest controls", () => {
  for (const provider of ["google_workspace", "posthog", "meta", "openai", "gemini", "kimi", "supabase", "vercel"]) {
    assert.match(migration, new RegExp(`'${provider}','1\\.0\\.0'`));
  }
  for (const column of ["auth", "scopes", "callback", "health", "capabilities", "risk_class", "account_identity", "credential_policy", "write_authorization", "residency_policy"]) {
    assert.match(migration, new RegExp(`\\b${column}\\b`));
  }
  assert.match(migration, /serverSideOnly/);
  assert.match(migration, /selectionRequired/);
  assert.match(migration, /exact_target_preview_and_step_up/);
});

test("OAuth broker is PKCE S256 plus one-time state and nonce for web and mobile", () => {
  assert.match(migration, /pandora_connection_oauth_prepare_v1/);
  assert.match(migration, /pandora_connection_oauth_claim_v1/);
  assert.match(migration, /pandora_connection_oauth_consume_v1/);
  assert.match(migration, /codeChallengeMethod','S256/);
  assert.match(migration, /nonce_hash/);
  assert.match(migration, /secure_custom_tab/);
  assert.match(migration, /p_callback_mode not in \('web','mobile'\)/);
  assert.match(migration, /claimed_at is null and consumed_at is null/);
});

test("Live Connections is fail-closed and independent from catalog presence", () => {
  assert.match(migration, /pandora_live_connections_v1/);
  assert.match(migration, /live_connections_not_catalog/);
  assert.match(migration, /a\.health_state<>'healthy'/);
  assert.match(migration, /last_verified_at/);
  assert.match(migration, /required_scopes_v1\(c\.provider_key\)<@a\.granted_scopes/);
  assert.match(migration, /exists\(select 1 from vault\.secrets/);
  assert.match(migration, /credential_expires_at/);
  assert.match(migration, /revoked_at/);
});

test("Vault lifecycle and account selector never return credentials to clients", () => {
  assert.match(migration, /vault\.create_secret/);
  assert.match(migration, /vault\.update_secret/);
  assert.match(migration, /delete from vault\.secrets/);
  assert.match(migration, /pandora_connection_select_account_v1/);
  assert.match(migration, /connection\.account_selected/);
  assert.match(migration, /'credentialReturned',false/);
  assert.match(migration, /revoke all on function public\.pandora_connection_runtime_credential_v1/);
});

test("Google is read-first and validates provider OIDC nonce before commit", () => {
  assert.match(migration, /drive\.metadata\.readonly/);
  assert.match(migration, /spreadsheets\.readonly/);
  assert.doesNotMatch(migration, /'https:\/\/www\.googleapis\.com\/auth\/drive'/);
  assert.doesNotMatch(migration, /'https:\/\/www\.googleapis\.com\/auth\/spreadsheets'/);
  assert.match(google, /tokeninfo\?id_token=/);
  assert.match(google, /idTokenInfo\.nonce/);
  assert.match(google, /text\(idTokenInfo\.aud\) === clientId/);
  assert.match(google, /p_oidc_nonce: oidcNonce/);
});

test("PostHog and model cards require live readback; models require a test inference on connect", () => {
  assert.match(broker, /posthogHosts = new Set/);
  assert.match(broker, /\/api\/projects\/\$\{projectId\}\//);
  assert.match(broker, /https:\/\/api\.openai\.com\/v1\/models/);
  assert.match(broker, /https:\/\/generativelanguage\.googleapis\.com\/v1beta\/models/);
  assert.match(broker, /https:\/\/api\.moonshot\.ai\/v1\/models/);
  assert.match(broker, /TEST_INFERENCE_REQUIRED/);
  assert.match(broker, /responses/);
  assert.match(broker, /generateContent/);
  assert.match(broker, /chat\/completions/);
  assert.doesNotMatch(broker, /console\.(log|debug|info|warn|error)/);
});

test("Supabase and Vercel writes are exact-target, hash-bound, expiring, one-time approvals", () => {
  assert.match(migration, /pandora_connection_write_preview_v1/);
  assert.match(migration, /pandora_connection_write_approve_v1/);
  assert.match(migration, /pandora_connection_write_consume_v1/);
  assert.match(migration, /target_preview/);
  assert.match(migration, /target_hash/);
  assert.match(migration, /interval '10 minutes'/);
  assert.match(migration, /status='consumed'/);
  assert.match(migration, /write_preview_contains_secret_keys/);
});
