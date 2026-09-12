import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const migration = fs.readFileSync(
  "supabase/migrations/20260913043000_pandora_owner_project_visibility_residual_v1.sql",
  "utf8",
);

test("recording 4998 residual internal projects are explicitly hidden", () => {
  for (const marker of [
    "pandora-rvw-314296438-20260820-76374545",
    "pandoras-box-and-pandoras-box-memory-4cc63040",
    "test-test-test-784ac0f8",
    "project_key = 'pandoras-box'",
    "ownerVisible",
  ]) {
    assert.ok(migration.includes(marker), `missing residual visibility marker: ${marker}`);
  }

  for (const legitimate of ["plp-boracay", "banataosystems/bok", "skysuites", "fxpass"]) {
    assert.ok(!migration.includes(legitimate), `legitimate project must not be targeted: ${legitimate}`);
  }
});
