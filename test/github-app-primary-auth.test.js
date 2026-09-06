import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const ownerApi = readFileSync(
  new URL("../supabase/functions/pandora-owner-api/index.ts", import.meta.url),
  "utf8",
);
const migration = readFileSync(
  new URL(
    "../supabase/migrations/20260906193000_github_app_primary_runtime.sql",
    import.meta.url,
  ),
  "utf8",
);

test("owner GitHub connection verification is GitHub-App-primary", () => {
  assert.doesNotMatch(ownerApi, /from "node:crypto"/);
  assert.doesNotMatch(ownerApi, /from "node:buffer"/);
  assert.match(ownerApi, /crypto\.subtle\.importKey/);
  assert.match(ownerApi, /crypto\.subtle\.sign/);
  assert.match(ownerApi, /pandora_get_github_app_runtime_material/);
  assert.match(ownerApi, /appId !== 4785021/);
  assert.match(ownerApi, /installationId !== 158056492/);
  assert.match(
    ownerApi,
    /api\.github\.com\/app\/installations\/\$\{installationId\}\/access_tokens/,
  );
  assert.match(
    ownerApi,
    /api\.github\.com\/repos\/\$\{CANONICAL_REPOSITORY\}/,
  );

  const verifyStart = ownerApi.indexOf("async function verifyGithubConnection");
  const actionStart = ownerApi.indexOf("async function connectionAction", verifyStart);
  assert.notEqual(verifyStart, -1);
  assert.notEqual(actionStart, -1);
  const verifyBlock = ownerApi.slice(verifyStart, actionStart);
  assert.doesNotMatch(verifyBlock, /probe_github_connector/);
});

test("GitHub App runtime material remains service-role-only", () => {
  assert.match(migration, /pandora_get_github_app_runtime_material/);
  assert.match(
    migration,
    /revoke all on function public\.pandora_get_github_app_runtime_material\(\) from public, anon, authenticated;/,
  );
  assert.match(
    migration,
    /grant execute on function public\.pandora_get_github_app_runtime_material\(\) to service_role;/,
  );
});
