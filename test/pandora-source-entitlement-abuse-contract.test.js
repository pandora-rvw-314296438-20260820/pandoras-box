"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = process.cwd();
const entitlementMigration = fs.readFileSync(
  path.join(root, "supabase/migrations/20260902013000_pandora_source_entitlements_v1.sql"),
  "utf8",
);
const hardeningMigration = fs.readFileSync(
  path.join(root, "supabase/migrations/20260902070000_pandora_source_privilege_hardening_v1.sql"),
  "utf8",
);
const sourceFiles = fs.readFileSync(
  path.join(root, "supabase/functions/pandora-source-files/index.ts"),
  "utf8",
);

test("service_role cannot truncate paid-source authority or mutate append-only audit evidence", () => {
  assert.match(
    hardeningMigration,
    /revoke all on table public\.pandora_source_entitlements from service_role/i,
  );
  assert.match(
    hardeningMigration,
    /grant select,\s*insert,\s*update,\s*delete\s+on table public\.pandora_source_entitlements\s+to service_role/is,
  );
  assert.doesNotMatch(
    hardeningMigration,
    /grant[^;]*truncate[^;]*pandora_source_entitlements/is,
  );

  assert.match(
    hardeningMigration,
    /revoke all on table public\.pandora_source_access_audit from service_role/i,
  );
  assert.match(
    hardeningMigration,
    /grant select,\s*insert\s+on table public\.pandora_source_access_audit\s+to service_role/is,
  );
  assert.doesNotMatch(
    hardeningMigration,
    /grant[^;]*(?:update|delete|truncate|references|trigger)[^;]*pandora_source_access_audit/is,
  );

  assert.match(entitlementMigration, /source access audit is append-only/i);
  assert.match(
    entitlementMigration,
    /if tg_op='UPDATE' or tg_op='DELETE' then\s+raise exception 'source access audit is append-only'/is,
  );
});

test("entitlement authority fails closed for free, expired, revoked, and downgraded capability states", () => {
  for (const marker of [
    "NO_SOURCE_ENTITLEMENT",
    "SOURCE_ENTITLEMENT_EXPIRED",
    "SOURCE_ENTITLEMENT_REVOKED",
    "SOURCE_CAPABILITY_NOT_GRANTED",
    "SOURCE_ENTITLEMENT_ACTIVE",
    "private.is_org_member",
  ]) {
    assert.ok(
      entitlementMigration.includes(marker),
      `missing entitlement denial/authority marker: ${marker}`,
    );
  }

  assert.match(
    entitlementMigration,
    /revoke all on function public\.pandora_get_source_entitlement_v1\(uuid,text\) from public, anon/i,
  );
  assert.match(
    entitlementMigration,
    /grant execute on function public\.pandora_get_source_entitlement_v1\(uuid,text\) to authenticated/i,
  );
});

test("source API checks entitlement before exact version, storage, guessed path, or source bytes", () => {
  const entitlement = sourceFiles.indexOf("pandora_get_source_entitlement_v1");
  const exactVersion = sourceFiles.indexOf('.from("pandora_project_versions")');
  const storageRead = sourceFiles.indexOf(".storage.from(");
  const guessedPath = sourceFiles.indexOf("safePath(body.path)");

  assert.ok(entitlement > 0, "entitlement decision missing");
  assert.ok(exactVersion > entitlement, "exact-version lookup must follow entitlement decision");
  assert.ok(storageRead > entitlement, "artifact storage read must follow entitlement decision");
  assert.ok(guessedPath > entitlement, "caller-controlled source path must not be parsed before entitlement");

  assert.match(sourceFiles, /SOURCE_ENTITLEMENT_REQUIRED/);
  assert.match(sourceFiles, /EXACT_VERSION_REQUIRED/);
  assert.doesNotMatch(sourceFiles, /createSignedUrl|createSignedUrls|signedUrl|signedURL/);
});

test("source API binds every durable source operation to exact project and version identity", () => {
  assert.match(
    sourceFiles,
    /\.eq\("id", versionId\)\.eq\("organization_id", organizationId\)\.eq\("project_id", projectId\)/,
  );
  assert.match(
    sourceFiles,
    /text\(bundle\.projectVersionId\)\.toLowerCase\(\) !== versionId/,
  );
  assert.match(sourceFiles, /ARTIFACT_FILE_DIGEST_MISMATCH/);
  assert.match(sourceFiles, /ARTIFACT_BUNDLE_INVALID/);
});
