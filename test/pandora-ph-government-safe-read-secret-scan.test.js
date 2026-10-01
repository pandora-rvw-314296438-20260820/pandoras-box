import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL(
    "../supabase/migrations/20261001150414_pandora_public_safe_read_secret_false_allowlist_v1.sql",
    import.meta.url,
  ),
  "utf8",
);

test("safe-read secret scan excludes only the required boolean sentinel", () => {
  assert.match(
    migration,
    /pandora_control_plane_json_has_secret_keys\(p_provider_readback - 'credentialReturned'\)/,
  );
  assert.doesNotMatch(
    migration,
    /pandora_control_plane_json_has_secret_keys\(p_provider_readback\) then/,
  );
});

test("credentialReturned must still be exactly false", () => {
  assert.match(
    migration,
    /coalesce\(p_provider_readback->'credentialReturned','true'::jsonb\) <> 'false'::jsonb/,
  );
});

test("service-only execute boundary is preserved", () => {
  assert.match(
    migration,
    /revoke all on function public[.]pandora_connection_commit_public_safe_read_v1\([\s\S]*?\) from public, anon, authenticated;/,
  );
  assert.match(
    migration,
    /grant execute on function public[.]pandora_connection_commit_public_safe_read_v1\([\s\S]*?\) to service_role;/,
  );
});

