"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");

const root = join(__dirname, "..");

function source(path) {
  return readFileSync(join(root, path), "utf8");
}

test("current release contract follows the authoritative operating identity", () => {
  const contract = JSON.parse(source("docs/releases/canonical/release-evidence.source.json"));
  const schema = JSON.parse(source("docs/releases/canonical/release-evidence.schema.json"));
  const policy = JSON.parse(source("SOURCE_AUTHORITY_POLICY.json"));
  const identity = source("docs/status/CURRENT_OPERATING_IDENTITY.md");
  const verifier = source("scripts/verify-canonical-release-evidence.mjs");
  const readme = source("docs/releases/canonical/README.md");

  assert.equal(contract.repository, policy.canonical.source_repository);
  assert.equal(contract.vercel.projectId, policy.canonical.vercel_project_id);
  assert.equal(contract.vercel.productionAlias, policy.canonical.production_origin);
  assert.equal(schema.properties.repository.const, policy.canonical.source_repository);
  assert.equal(
    schema.properties.vercel.properties.productionAlias.const,
    policy.canonical.production_origin,
  );

  assert.match(identity, /Production origin \| `https:\/\/mcpmaster\.vercel\.app`/);
  assert.match(verifier, /contract\.vercel\.productionAlias === "https:\/\/mcpmaster\.vercel\.app"/);
  assert.match(readme, /mcpmaster\.vercel\.app/);

  assert.notEqual(contract.vercel.productionAlias, "https://pandoras-box-system.vercel.app");
  assert.notEqual(
    schema.properties.vercel.properties.productionAlias.const,
    "https://pandoras-box-system.vercel.app",
  );
});

test("forward migration aligns live release functions to canonical production origin", () => {
  const migration = source("supabase/migrations/20260906180221_align_canonical_release_production_origin.sql");
  assert.match(migration, /capture_canonical_physical_android_receipt/);
  assert.match(migration, /capture_canonical_vercel_rehearsal_receipt/);
  assert.match(migration, /get_canonical_release_status_without_final_attestations/);
  assert.match(migration, /mcpmaster\.vercel\.app/);
  assert.match(migration, /legacy production origin remains/);
  assert.match(migration, /canonical production origin missing/);
  assert.doesNotMatch(migration, /\b(?:drop|truncate|delete\s+from)\b/i);
});
