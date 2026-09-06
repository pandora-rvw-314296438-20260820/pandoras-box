"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");

const root = join(__dirname, "..");
const currentRepository = "pandora-rvw-314296438-20260820/pandoras-box";
const legacyRepository = "banataosystems/Pandoras-box";
const currentOrigin = "https://pandoras-box-system.vercel.app";

function source(path) {
  return readFileSync(join(root, path), "utf8");
}

test("current release contract uses the operational repository and production origin", () => {
  const contract = JSON.parse(source("docs/releases/canonical/release-evidence.source.json"));
  const schema = source("docs/releases/canonical/release-evidence.schema.json");
  const verifier = source("scripts/verify-canonical-release-evidence.mjs");
  const readme = source("docs/releases/canonical/README.md");
  const mobileReadme = source("apps/pandora-mobile/README.md");

  assert.equal(contract.repository, currentRepository);
  assert.equal(contract.vercel.productionAlias, currentOrigin);
  assert.ok(schema.includes(currentRepository));
  assert.ok(schema.includes(currentOrigin));
  assert.ok(verifier.includes(currentRepository));
  assert.ok(verifier.includes(currentOrigin));
  assert.ok(readme.includes("pandoras-box-system.vercel.app"));
  assert.ok(mobileReadme.includes(currentRepository));

  for (const active of [JSON.stringify(contract), schema, verifier, readme, mobileReadme]) {
    assert.equal(active.includes(legacyRepository), false);
  }
  assert.equal(schema.includes("https://github.com/banataosystems/Pandoras-box"), false);
  assert.equal(verifier.includes("https://mcpmaster.vercel.app"), false);
  assert.equal(readme.includes("https://mcpmaster.vercel.app"), false);
});

test("forward migration aligns live Vercel release checks without rewriting history", () => {
  const migration = source("supabase/migrations/20260906164100_align_canonical_release_current_identity.sql");
  assert.match(migration, /get_canonical_release_status_without_final_attestations/);
  assert.match(migration, /capture_canonical_vercel_rehearsal_receipt/);
  assert.match(migration, /pandora-rvw-314296438-20260820/);
  assert.match(migration, /legacy GitHub owner remains/);
  assert.match(migration, /current GitHub owner missing/);
  assert.doesNotMatch(migration, /\b(?:drop|truncate|delete\s+from)\b/i);
});
