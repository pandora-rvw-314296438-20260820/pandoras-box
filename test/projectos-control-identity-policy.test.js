"use strict";

const assert = require("node:assert/strict");
const { existsSync, readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");

const root = join(__dirname, "..");
const retiredRoot = join(root, "supabase", "functions", "projectos-control");

test("retired ProjectOS control Edge function remains absent", () => {
  assert.equal(existsSync(join(retiredRoot, "index.ts")), false);
  assert.equal(existsSync(join(retiredRoot, "identity-policy.mjs")), false);
});

test("Pandora owner API is the active governed owner control surface", () => {
  const ownerApi = readFileSync(
    join(root, "supabase", "functions", "pandora-owner-api", "index.ts"),
    "utf8",
  );
  assert.match(ownerApi, /CANONICAL_REPOSITORY/);
  assert.match(ownerApi, /reconcileOwnerWorkerCommand/);
  assert.doesNotMatch(ownerApi, /projectos-control/);
});
