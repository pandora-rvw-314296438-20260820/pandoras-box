"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");

const root = join(__dirname, "..");
const currentRepository = "pandora-rvw-314296438-20260820/pandoras-box";
const currentOrigin = "https://pandoras-box-system.vercel.app";

function source(path) {
  return readFileSync(join(root, path), "utf8");
}

test("current release contract uses the operational repository and production origin", () => {
  const contract = JSON.parse(source("docs/releases/canonical/release-evidence.source.json"));
  const schema = JSON.parse(source("docs/releases/canonical/release-evidence.schema.json"));
  const verifier = source("scripts/verify-canonical-release-evidence.mjs");
  const readme = source("docs/releases/canonical/README.md");
  const mobileReadme = source("apps/pandora-mobile/README.md");

  assert.equal(contract.repository, currentRepository);
  assert.equal(contract.vercel.productionAlias, currentOrigin);
  assert.equal(schema.properties.repository.const, currentRepository);
  assert.equal(schema.properties.vercel.properties.productionAlias.const, currentOrigin);
  assert.match(verifier, /contract\.repository === "pandora-rvw-314296438-20260820\/pandoras-box"/);
  assert.match(verifier, /contract\.vercel\.productionAlias === "https:\/\/pandoras-box-system\.vercel\.app"/);
  assert.match(readme, /pandoras-box-system\.vercel\.app/);
  assert.match(mobileReadme, /pandora-rvw-314296438-20260820\/pandoras-box/);

  assert.notEqual(contract.repository, "banataosystems/Pandoras-box");
  assert.notEqual(contract.vercel.productionAlias, "https://mcpmaster.vercel.app");
  assert.notEqual(schema.properties.repository.const, "banataosystems/Pandoras-box");
  assert.notEqual(schema.properties.vercel.properties.productionAlias.const, "https://mcpmaster.vercel.app");
});

test("forward migration aligns live Vercel release checks without rewriting history", () => {
  const migration = source("supabase/migrations/20260906173325_align_canonical_release_current_identity.sql");
  assert.match(migration, /get_canonical_release_status_without_final_attestations/);
  assert.match(migration, /capture_canonical_vercel_rehearsal_receipt/);
  assert.match(migration, /pandora-rvw-314296438-20260820/);
  assert.match(migration, /legacy GitHub owner remains/);
  assert.match(migration, /current GitHub owner missing/);
  assert.doesNotMatch(migration, /\b(?:drop|truncate|delete\s+from)\b/i);
});
