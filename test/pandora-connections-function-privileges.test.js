import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL(
    "../supabase/migrations/20261001133930_pandora_connections_public_execute_hardening.sql",
    import.meta.url,
  ),
  "utf8",
)
  .replace(/--.*$/gm, "")
  .replace(/\s+/g, " ")
  .trim()
  .toLowerCase();

const expectedSignatures = [
  "public.pandora_connection_catalog_v1()",
  "public.pandora_connection_oauth_prepare_v1(uuid, text, text, text)",
  "public.pandora_connection_select_account_v1(uuid, uuid, text)",
  "public.pandora_connection_revoke_v1(uuid, uuid, text)",
  "public.pandora_connection_write_preview_v1(uuid, text, uuid, text, text, jsonb)",
  "public.pandora_connection_write_approve_v1(uuid, uuid, text, uuid, text, text)",
  "public.pandora_live_connections_v1(uuid)",
  "public.pandora_google_workspace_oauth_commit_v1(text, text, text, text, text, text[], text)",
];

test("connection SECURITY DEFINER RPCs revoke PUBLIC and anon execute", () => {
  const statements = migration
    .split(";")
    .map((statement) => statement.trim())
    .filter(Boolean);

  assert.equal(statements.length, expectedSignatures.length);
  assert.deepEqual(
    statements.sort(),
    expectedSignatures
      .map(
        (signature) =>
          `revoke execute on function ${signature} from public, anon`,
      )
      .sort(),
  );
});

test("hardening does not revoke intended authenticated or service roles", () => {
  assert.doesNotMatch(migration, /from[^;]*(authenticated|service_role)/);
  assert.doesNotMatch(migration, /grant execute[^;]*(public|anon)/);
});

test("OAuth hardening targets only the seven-argument callback", () => {
  assert.doesNotMatch(
    migration,
    /pandora_google_workspace_oauth_commit_v1\(text, text, text, text, text, text\)\s+from/,
  );
});
