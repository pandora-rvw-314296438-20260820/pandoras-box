import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL(
    "../supabase/migrations/20261001140843_pandora_ph_government_public_connections.sql",
    import.meta.url,
  ),
  "utf8",
);

test("registers four documented government API manifests", () => {
  for (const provider of [
    "ph.psa.openstat",
    "ph.psa.psgc",
    "ph.phivolcs.hazard_gis",
    "ph.namria.geoportal",
  ]) {
    assert.match(migration, new RegExp(`'${provider.replaceAll(".", "[.]")}'`, "g"));
  }
});

test("credentialless commit allowlist excludes token-gated PSGC", () => {
  assert.match(
    migration,
    /p_provider_key not in \('ph[.]psa[.]openstat','ph[.]phivolcs[.]hazard_gis','ph[.]namria[.]geoportal'\)/,
  );
  assert.doesNotMatch(
    migration,
    /p_provider_key not in \([^)]*ph[.]psa[.]psgc/,
  );
});

test("public safe-read commit is service-only and never returns a credential", () => {
  assert.match(
    migration,
    /revoke all on function public[.]pandora_connection_commit_public_safe_read_v1\([\s\S]*?\) from public, anon, authenticated;/,
  );
  assert.match(
    migration,
    /grant execute on function public[.]pandora_connection_commit_public_safe_read_v1\([\s\S]*?\) to service_role;/,
  );
  assert.match(migration, /'credentialReturned',false/);
  assert.doesNotMatch(migration, /'credential',v_/);
});

test("Connected requires exact tenant, identity, scope, health and probe readback", () => {
  for (const field of [
    "organizationId",
    "tenantId",
    "tenantKey",
    "providerIdentity",
    "verificationState",
    "grantedScopes",
    "bodySha256",
    "observedAt",
  ]) {
    assert.match(migration, new RegExp(field));
  }
  assert.match(migration, /pandora_control_plane_json_has_secret_keys/);
  assert.match(migration, /status='connected'/);
  assert.match(migration, /health_state='healthy'/);
  assert.match(migration, /connection[.]public_safe_read_connected/);
});
